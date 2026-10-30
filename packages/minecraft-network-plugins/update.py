#!/usr/bin/env python3
"""Discover upstream changes for review. Only this entry point discovers releases."""
import argparse
import hashlib
import json
from pathlib import Path
import tempfile
from upstream import GITHUB, PROJECT, MAX_JAR_SIZE, open_url, read_json, require, matches, validate_pin, load_pin, load_env, velocity_state, MAVEN, read_bytes, parse_floodgate, newer_floodgate, newer_velocity, acquire_floodgate


def dev_commit(read=read_json):
    obj = read(f'{GITHUB}/git/ref/tags/dev-build')['object']
    for _ in range(5):
        require(matches(r'[0-9a-f]{40}', obj.get('sha')), 'Invalid full dev-build SHA')
        if obj.get('type') == 'commit':
            return obj['sha']
        require(obj.get('type') == 'tag', 'dev-build must resolve to a commit')
        obj = read(f"{GITHUB}/git/tags/{obj['sha']}")['object']
    raise ValueError('Too many annotated tag indirections')


def limbo_state(commit, release, previous, hash_asset=None):
    require(release.get('tag_name') == 'dev-build' and release.get('draft') is False,
            'Invalid LimboAPI release')
    require(matches(r'[0-9a-f]{40}', commit), 'Full source commit required')
    require(isinstance(release.get('assets'), list) and all(isinstance(a, dict) for a in release['assets']),
            'Invalid release assets')
    assets = [a for a in release['assets'] if matches(r'limboapi-[0-9][A-Za-z0-9.+-]*\.jar', a.get('name'))]
    require(len(assets) == 1, 'Missing or ambiguous LimboAPI plugin asset')
    asset = assets[0]
    require(asset.get('state') == 'uploaded', 'LimboAPI asset is not uploaded')
    digest = asset.get('digest')
    if digest is not None:
        require(matches(r'sha256:[0-9a-f]{64}', digest), 'Invalid GitHub SHA-256 digest')
        digest = digest[7:]
    else:
        require(hash_asset is not None, 'Asset without upstream digest must be hashed')
        digest = hash_asset(asset)
    state = dict(repository='Elytrium/LimboAPI', release_tag='dev-build', source_commit=commit,
                 release_id=release['id'], release_name=release['name'], asset_id=asset['id'],
                 filename=asset['name'], version=asset['name'][9:-4], published_at=release['published_at'],
                 size=asset['size'], sha256=digest, url=asset['url'], license=previous['license'],
                 compatibility=previous['compatibility'] if commit == previous['source_commit'] else
                 'Requires review: Minecraft 26.3 compatibility has not been confirmed for this commit')
    return validate_pin(state, 'limboapi')


def hash_limbo_asset(asset):
    require(type(asset.get('id')) is int and asset['id'] > 0, 'Invalid asset ID')
    require(asset.get('url') == f"{GITHUB}/releases/assets/{asset['id']}", 'Untrusted asset URL')
    require(type(asset.get('size')) is int and 0 < asset['size'] <= MAX_JAR_SIZE, 'Invalid asset size')
    digest, size = hashlib.sha256(), 0
    with open_url(asset['url'], binary=True) as response:
        while chunk := response.read(1024 * 1024):
            size += len(chunk)
            require(size <= asset['size'], 'Asset size mismatch')
            digest.update(chunk)
    require(size == asset['size'], 'Asset size mismatch')
    return digest.hexdigest()


def stable_velocity(version, builds):
    require(isinstance(builds, list) and all(isinstance(b, dict) for b in builds), 'Invalid Fill builds')
    stable = [b for b in builds if b.get('channel') == 'STABLE']
    if not stable:
        return None
    require(all(type(b.get('id')) is int and b['id'] > 0 for b in stable), 'Invalid Fill build ID')
    build = max(stable, key=lambda b: b['id'])
    return velocity_state(version, build)


def discover_velocity(read=read_json):
    project = read(PROJECT)
    require(project.get('project', {}).get('id') == 'velocity', 'Unexpected PaperMC project')
    groups = project.get('versions')
    require(isinstance(groups, dict) and groups, 'Missing Fill version groups')
    candidates = []
    for versions in groups.values():
        require(isinstance(versions, list), 'Invalid Fill versions')
        for version in versions:
            require(matches(r'[0-9][A-Za-z0-9.+-]{0,79}', version), 'Invalid Fill version')
            # Snapshot and prerelease versions cannot be stable compile inputs.
            if matches(r'[0-9]+(?:\.[0-9]+){1,3}', version):
                candidates.append(version)
    for version in sorted(set(candidates), key=lambda v: tuple(map(int, v.split('.'))), reverse=True):
        state = stable_velocity(version, read(f'{PROJECT}/versions/{version}/builds'))
        if state is not None:
            return state
    raise ValueError('No STABLE Velocity build found')


def changed(previous, candidate):
    return previous != candidate


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory', type=Path, default=Path(__file__).parent)
    parser.add_argument('--summary', type=Path, required=True)
    args = parser.parse_args()
    env = load_env(args.directory)
    old_limbo = load_pin(args.directory, 'limboapi')
    commit = dev_commit()
    new_limbo = limbo_state(commit, read_json(f'{GITHUB}/releases/tags/dev-build'), old_limbo, hash_limbo_asset)
    velocity = discover_velocity()
    floodgate = parse_floodgate(read_bytes(MAVEN + 'maven-metadata.xml'))
    with tempfile.TemporaryDirectory() as work:
        acquire_floodgate(floodgate, Path(work) / 'floodgate-api.jar')
    require(commit == dev_commit(), 'dev-build changed during discovery; retry later')
    require(new_limbo == limbo_state(commit, read_json(f'{GITHUB}/releases/tags/dev-build'),
                                    old_limbo, hash_limbo_asset), 'Release changed during discovery')
    replacements = {}
    lines = ['Review Minecraft Network dependency updates before merging.', '']
    if changed(old_limbo, new_limbo):
        lines += [f"LimboAPI `{old_limbo['source_commit']}` -> `{new_limbo['source_commit']}`", '']
    if newer_velocity(env['VELOCITY_VERSION'], env['VELOCITY_BUILD'], velocity):
        replacements.update(VELOCITY_VERSION=velocity['version'], VELOCITY_BUILD=str(velocity['build']))
        lines += [f"Velocity {env['VELOCITY_VERSION']} build {env['VELOCITY_BUILD']} -> Velocity {velocity['version']} build {velocity['build']}", '']
    if newer_floodgate(env['FLOODGATE_API_VERSION'], floodgate):
        replacements['FLOODGATE_API_VERSION'] = floodgate
        lines += [f"Floodgate API {env['FLOODGATE_API_VERSION']} -> Floodgate API {floodgate}", '']
    # All discovery/validation completes before changing either permitted state file.
    if changed(old_limbo, new_limbo):
        (args.directory / 'limboapi-update.json').write_text(json.dumps(new_limbo, indent=2) + '\n')
    if replacements:
        path = args.directory / 'package.env'
        path.write_text('\n'.join(
            line.split('=', 1)[0] + '=' + replacements[line.split('=', 1)[0]]
            if line.split('=', 1)[0] in replacements else line
            for line in path.read_text().splitlines()) + '\n')
    args.summary.write_text('\n'.join(lines) + '\n')
    print('Upstream state changed' if replacements or changed(old_limbo, new_limbo) else 'Upstream state unchanged')


if __name__ == '__main__':
    main()
