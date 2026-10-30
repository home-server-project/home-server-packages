"""Shared strict pin validation and verified acquisition; no release discovery."""
import hashlib
import json
import os
from pathlib import Path
import re
import urllib.parse
import urllib.request

PROJECT = 'https://fill.papermc.io/v3/projects/velocity'
GITHUB = 'https://api.github.com/repos/Elytrium/LimboAPI'
USER_AGENT = 'Home-Server-Packages/1.0 (https://github.com/home-server-project/home-server-packages)'
GITHUB_HOSTS = {'api.github.com', 'release-assets.githubusercontent.com', 'objects.githubusercontent.com'}
MAVEN = 'https://repo.opencollab.dev/main/org/geysermc/floodgate/api/2.2.5-SNAPSHOT/'
MAX_JAR_SIZE = 128 * 1024 * 1024


def require(condition, message):
    if not condition:
        raise ValueError(message)


def matches(pattern, value):
    return isinstance(value, str) and re.fullmatch(pattern, value) is not None


def validate_pin(pin, kind):
    require(isinstance(pin, dict), 'Pin must be an object')
    require(type(pin.get('size')) is int and 0 < pin['size'] <= MAX_JAR_SIZE, 'Invalid asset size')
    require(matches(r'[0-9a-f]{64}', pin.get('sha256')), 'Missing SHA-256')
    if kind == 'limboapi':
        require(pin.get('repository') == 'Elytrium/LimboAPI' and pin.get('release_tag') == 'dev-build',
                'Unexpected LimboAPI upstream')
        require(matches(r'[0-9a-f]{40}', pin.get('source_commit')), 'Full source commit required')
        require(all(type(pin.get(k)) is int and pin[k] > 0 for k in ('release_id', 'asset_id')),
                'Invalid GitHub release/asset identity')
        require(matches(r'limboapi-[0-9][A-Za-z0-9.+-]*\.jar', pin.get('filename')), 'Invalid LimboAPI filename')
        require(pin.get('version') == pin['filename'][9:-4], 'LimboAPI version mismatch')
        require(matches(r'\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ', pin.get('published_at')), 'Missing publication time')
        require(pin.get('url') == f"{GITHUB}/releases/assets/{pin['asset_id']}", 'Untrusted GitHub asset URL')
        require(pin.get('license') == 'AGPL-3.0-only', 'Unexpected LimboAPI license')
        require(isinstance(pin.get('compatibility'), str) and pin['compatibility'], 'Missing compatibility note')
    elif kind == 'velocity':
        require(pin.get('project') == 'velocity' and pin.get('channel') == 'STABLE', 'Only STABLE Velocity is allowed')
        require(matches(r'[0-9]+(?:\.[0-9]+){1,3}', pin.get('version')), 'Invalid stable Velocity version')
        require(type(pin.get('build')) is int and pin['build'] > 0, 'Invalid Velocity build')
        require(matches(r'velocity-[A-Za-z0-9.+-]+\.jar', pin.get('filename')), 'Invalid Velocity filename')
        url = pin.get('url')
        require(isinstance(url, str) and all(32 < ord(c) < 127 for c in url), 'Invalid Velocity download URL')
        require(pin.get('url') == f"https://fill-data.papermc.io/v1/objects/{pin['sha256']}/{pin['filename']}",
                'Untrusted PaperMC download metadata')
        require(pin.get('metadata_url') == f"{PROJECT}/versions/{pin['version']}/builds/{pin['build']}",
                'Untrusted PaperMC build identity')
    else:
        raise ValueError('Unknown upstream')
    return pin


class TrustedRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        parsed = urllib.parse.urlsplit(newurl)
        require(parsed.scheme == 'https' and parsed.netloc in GITHUB_HOSTS and urllib.parse.urlsplit(req.full_url).netloc in GITHUB_HOSTS,
                'Untrusted GitHub redirect')
        redirected = super().redirect_request(req, fp, code, msg, headers, newurl)
        if parsed.netloc != 'api.github.com':
            redirected.remove_header('Authorization')
        return redirected


def open_url(url, binary=False):
    parsed = urllib.parse.urlsplit(url)
    require(parsed.scheme == 'https' and parsed.netloc in GITHUB_HOSTS | {'fill.papermc.io', 'fill-data.papermc.io', 'repo.opencollab.dev'},
            'Untrusted upstream host')
    headers = {'User-Agent': USER_AGENT, 'Accept': 'application/octet-stream' if binary else 'application/json'}
    if parsed.netloc == 'api.github.com' and os.environ.get('GH_TOKEN'):
        headers['Authorization'] = 'Bearer ' + os.environ['GH_TOKEN']
    return urllib.request.build_opener(TrustedRedirect()).open(urllib.request.Request(url, headers=headers), timeout=60)


def read_json(url):
    with open_url(url) as response:
        data = response.read(16 * 1024 * 1024 + 1)
    require(len(data) <= 16 * 1024 * 1024, 'Upstream metadata too large')
    return json.loads(data)


def download(pin, kind, destination):
    validate_pin(pin, kind)
    destination = Path(destination)
    temporary = destination.with_suffix('.part')
    digest, size = hashlib.sha256(), 0
    try:
        with open_url(pin['url'], binary=True) as response, temporary.open('wb') as output:
            parsed = urllib.parse.urlsplit(response.geturl())
            hosts = GITHUB_HOSTS if kind == 'limboapi' else {'fill-data.papermc.io'}
            require(parsed.scheme == 'https' and parsed.netloc in hosts, 'Untrusted final artifact host')
            while chunk := response.read(1024 * 1024):
                size += len(chunk)
                require(size <= pin['size'], 'Asset size mismatch')
                digest.update(chunk)
                output.write(chunk)
        require(size == pin['size'], 'Asset size mismatch')
        require(digest.hexdigest() == pin['sha256'], 'Asset SHA-256 mismatch')
        temporary.replace(destination)
    finally:
        temporary.unlink(missing_ok=True)


def load_pin(directory, kind):
    return validate_pin(json.loads((Path(directory) / f'{kind}-update.json').read_text()), kind)


def read_bytes(url):
    with open_url(url) as response:
        data = response.read(16 * 1024 * 1024 + 1)
    require(len(data) <= 16 * 1024 * 1024, 'Metadata too large')
    return data


def load_env(directory):
    values = {}
    for line in (Path(directory) / 'package.env').read_text().splitlines():
        if line and not line.startswith('#'):
            key, value = line.split('=', 1)
            require(matches(r'[A-Z_][A-Z_0-9]*', key) and matches(r'[A-Za-z0-9.+-]+', value), 'Invalid package state')
            values[key] = value
    require(matches(r'[0-9]+(?:\.[0-9]+){1,3}', values.get('VELOCITY_VERSION')), 'Invalid Velocity version')
    require(matches(r'[1-9][0-9]*', values.get('VELOCITY_BUILD')), 'Invalid Velocity build')
    require(values.get('FLOODGATE_API_BASE_VERSION') == '2.2.5-SNAPSHOT', 'Unexpected Floodgate family')
    floodgate_url(values['FLOODGATE_API_VERSION'])
    return values


def velocity_state(version, build):
    require(isinstance(build, dict), 'Invalid Fill build')
    # The version comes from the requested builds collection, not the build object.
    require(build.get('channel') == 'STABLE', 'Velocity must be STABLE')
    downloads = build.get('downloads')
    require(isinstance(downloads, dict), 'Missing Velocity downloads')
    artifact = downloads.get('server:default')
    require(isinstance(artifact, dict), 'Missing server:default artifact')
    checksums = artifact.get('checksums')
    require(isinstance(checksums, dict), 'Missing Velocity checksums')
    return validate_pin(dict(project='velocity', version=version, build=build.get('id'), channel='STABLE',
                             filename=artifact.get('name'), size=artifact.get('size'),
                             sha256=checksums.get('sha256'), url=artifact.get('url'),
                             metadata_url=f"{PROJECT}/versions/{version}/builds/{build.get('id')}"), 'velocity')


def exact_velocity(version, build, read=read_json):
    require(matches(r'[0-9]+(?:\.[0-9]+){1,3}', version), 'Invalid stable Velocity version')
    require(type(build) is int and build > 0, 'Invalid Velocity build')
    builds = read(f'{PROJECT}/versions/{version}/builds')
    require(isinstance(builds, list) and all(isinstance(b, dict) for b in builds), 'Invalid Fill builds')
    selected = [b for b in builds if b.get('id') == build]
    require(len(selected) == 1, 'Missing or ambiguous Velocity build')
    state = velocity_state(version, selected[0])
    require(state['build'] == build, 'Velocity build mismatch')
    return state


def floodgate_url(version, extension='jar'):
    require(matches(r'2\.2\.5-\d{8}\.\d{6}-[1-9][0-9]*', version), 'Exact Floodgate snapshot required')
    from datetime import datetime
    datetime.strptime(version[6:21], '%Y%m%d.%H%M%S')
    require(extension in ('jar', 'pom'), 'Invalid Floodgate artifact extension')
    return f'{MAVEN}api-{version}.{extension}'


def parse_floodgate(data):
    import xml.etree.ElementTree as ET
    root = ET.fromstring(data)
    require(root.tag == 'metadata' and root.findtext('groupId') == 'org.geysermc.floodgate'
            and root.findtext('artifactId') == 'api' and root.findtext('version') == '2.2.5-SNAPSHOT',
            'Unexpected Maven metadata identity')
    versions = []
    for item in root.findall('./versioning/snapshotVersions/snapshotVersion'):
        if item.findtext('extension') != 'jar' or item.findtext('classifier'):
            continue
        version = item.findtext('value')
        # Other snapshot families are not candidates.
        if isinstance(version, str) and not version.startswith('2.2.5-'):
            continue
        floodgate_url(version)
        versions.append(version)
    require(versions, 'Missing timestamped Floodgate API snapshot')
    return max(versions, key=floodgate_key)


def floodgate_key(version):
    floodgate_url(version)
    timestamp, build = version[6:].rsplit('-', 1)
    return timestamp, int(build)


def acquire_floodgate(version, destination):
    url = floodgate_url(version)
    # OpenCollab provides SHA-256 sidecars. Fail closed if unavailable or malformed.
    digest = read_bytes(url + '.sha256').decode('ascii').strip()
    require(matches(r'[0-9a-f]{64}', digest), 'Invalid official Floodgate SHA-256')
    data = read_bytes(url)
    require(data and hashlib.sha256(data).hexdigest() == digest, 'Floodgate checksum mismatch')
    Path(destination).write_bytes(data)
    return dict(version=version, url=url, sha256=digest, size=len(data))


def newer_velocity(current_version, current_build, candidate):
    return (tuple(map(int, candidate['version'].split('.'))), candidate['build']) > (
        tuple(map(int, current_version.split('.'))), int(current_build))


def newer_floodgate(current, candidate):
    return floodgate_key(candidate) > floodgate_key(current)
