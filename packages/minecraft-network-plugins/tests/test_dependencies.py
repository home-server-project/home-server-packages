import copy
import hashlib
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

PACKAGE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PACKAGE))
import upstream as u
import update
import acquire
import validate


def velocity(build=45, version='4.3.1', channel='STABLE'):
    digest = 'a' * 64
    name = f'velocity-{version}-{build}.jar'
    return dict(id=build, channel=channel, downloads={'server:default':
        dict(name=name, size=20, checksums={'sha256': digest},
             url=f'https://fill-data.papermc.io/v1/objects/{digest}/{name}')})


class LimboTests(unittest.TestCase):
    def setUp(self):
        self.old = u.load_pin(PACKAGE, 'limboapi')
        p = self.old
        self.commit = 'cd34c9c3b2951f040c840de00dd9215b37138655'
        self.release = dict(id=p['release_id'] + 1, name='1.2.0', tag_name='1.2.0', draft=False,
                            prerelease=False, published_at=p['published_at'],
                            assets=[dict(id=p['asset_id'], name='limboapi-1.2.0.jar', size=3341235,
                            url=p['url'], state='uploaded',
                            digest='sha256:25582ebf5567fec1c20a03ad2c6e01fa05911a76749c67e7b0192acf508f7d31')])

    def test_legacy_pin_still_validates(self):
        self.assertEqual(self.old['release_tag'], 'dev-build')
        self.assertEqual(u.validate_pin(self.old, 'limboapi'), self.old)

    def test_stable_candidate_and_migration(self):
        candidate = update.limbo_state(self.commit, self.release, self.old)
        self.assertEqual(u.validate_pin(candidate, 'limboapi'), candidate)
        self.assertEqual((candidate['release_tag'], candidate['source_commit'],
                          candidate['version'], candidate['filename']),
                         ('1.2.0', self.commit, '1.2.0', 'limboapi-1.2.0.jar'))
        self.assertTrue(update.changed(self.old, candidate))
        self.assertIn('Requires review', candidate['compatibility'])
        for field, value in [('release_tag', '1.2.1'), ('version', '1.2.1'),
                             ('filename', 'limboapi-1.2.1.jar')]:
            pin = dict(candidate, **{field: value})
            with self.subTest(field=field), self.assertRaises(ValueError):
                u.validate_pin(pin, 'limboapi')

    def test_unchanged_full_commit(self):
        candidate = update.limbo_state(self.old['source_commit'], self.release, self.old)
        self.assertEqual(candidate['compatibility'], self.old['compatibility'])
        self.assertFalse(update.changed(candidate,
            update.limbo_state(candidate['source_commit'], self.release, candidate)))

    def test_changed_commit_even_with_same_short_prefix(self):
        commit = self.old['source_commit'][:7] + 'a' * 33
        candidate = update.limbo_state(commit, self.release, self.old)
        self.assertTrue(update.changed(self.old, candidate))
        self.assertEqual(candidate['source_commit'], commit)
        self.assertIn('Requires review', candidate['compatibility'])

    def test_bad_metadata_and_sha_rejected(self):
        for field, value in [('size', 0), ('size', True), ('size', u.MAX_JAR_SIZE + 1),
                             ('url', 'https://evil.example/a'), ('id', -1), ('id', True),
                             ('name', '../limboapi.jar'), ('name', 'limboapi-1.2.1.jar'),
                             ('state', 'new'), ('digest', 'sha256:bad'),
                             ('digest', 'sha256:' + 'z' * 64)]:
            with self.subTest(field=field, value=value):
                release = copy.deepcopy(self.release)
                release['assets'][0][field] = value
                with self.assertRaises(ValueError):
                    update.limbo_state(self.old['source_commit'], release, self.old)
        for commit in ['bfef579', 'x' * 40]:
            with self.assertRaises(ValueError):
                update.limbo_state(commit, self.release, self.old)
        for field, value in [('id', 0), ('id', True), ('id', '123'), ('name', None),
                             ('name', ''), ('published_at', None), ('assets', None),
                             ('assets', [None]), ('assets', []),
                             ('assets', self.release['assets'] * 2)]:
            with self.subTest(field=field, value=value), self.assertRaises(ValueError):
                update.limbo_state(self.commit, dict(self.release, **{field: value}), self.old)
        for release in [None, [], 'release']:
            with self.assertRaises(ValueError):
                update.limbo_state(self.commit, release, self.old)

    def test_draft_and_prerelease_rejected(self):
        for field in ('draft', 'prerelease'):
            for value in (True, None, 0, 'false'):
                with self.subTest(field=field, value=value), self.assertRaises(ValueError):
                    update.limbo_state(self.commit, dict(self.release, **{field: value}), self.old)

    def test_invalid_tags_rejected_before_tag_url_construction(self):
        for tag in ['dev-build', '../1.2.0', '1.2.0/evil', '1.2.0?query', '1.2.0#fragment',
                    '1.2.0%2f..', '1.2.0\n', '1.2.0-rc1', '1.2.0+build', 'v1.2.0',
                    '01.2.0', '1.2', '', None]:
            with self.subTest(tag=tag):
                with self.assertRaises(ValueError):
                    update.tag_commit(tag, lambda url: self.fail('Invalid tag requested'))
                urls = []
                def read(url):
                    urls.append(url)
                    return dict(self.release, tag_name=tag)
                with self.assertRaises(ValueError):
                    update.discover_limbo(self.old, read)
                self.assertEqual(urls, [u.GITHUB + '/releases/latest'])
                with self.assertRaises(ValueError):
                    update.limbo_state(self.commit, dict(self.release, tag_name=tag), self.old)

    def test_latest_release_discovery_resolves_exact_tag(self):
        urls = []
        responses = {u.GITHUB + '/releases/latest': self.release,
                     u.GITHUB + '/git/ref/tags/1.2.0':
                         {'object': {'type': 'commit', 'sha': self.commit}}}
        def read(url):
            urls.append(url)
            return responses[url]
        state = update.discover_limbo(self.old, read)
        self.assertEqual(state['source_commit'], self.commit)
        self.assertEqual(urls, list(responses))

    def test_annotated_tag_and_full_sha_validation(self):
        responses = [{'object': {'type': 'tag', 'sha': 'a'*40}},
                     {'object': {'type': 'commit', 'sha': self.commit}}]
        urls = []
        def read(url):
            urls.append(url)
            return responses.pop(0)
        self.assertEqual(update.tag_commit('1.2.0', read), self.commit)
        self.assertEqual(urls, [u.GITHUB + '/git/ref/tags/1.2.0', u.GITHUB + '/git/tags/' + 'a'*40])
        for obj in [{'type': 'commit', 'sha': 'abc'}, {'type': 'tag', 'sha': 'abc'},
                    {'type': 'tree', 'sha': 'a'*40}, {'type': 'commit', 'sha': 'z'*40}, None]:
            with self.subTest(obj=obj), self.assertRaises(ValueError):
                update.tag_commit('1.2.0', lambda url: {'object': obj})
        urls = []
        def loop(url):
            urls.append(url)
            return {'object': {'type': 'tag', 'sha': 'a'*40}}
        with self.assertRaisesRegex(ValueError, 'Too many annotated tag'):
            update.tag_commit('1.2.0', loop)
        self.assertEqual(len(urls), 6)

    def test_verified_hashing_fallback(self):
        release = copy.deepcopy(self.release)
        asset = release['assets'][0]
        del asset['digest']
        data = b'jar contents'
        asset['size'] = len(data)
        with patch.object(update, 'open_url', return_value=io.BytesIO(data)) as opened:
            state = update.limbo_state(self.commit, release, self.old, update.hash_limbo_asset)
        self.assertEqual(state['sha256'], hashlib.sha256(data).hexdigest())
        opened.assert_called_once_with(asset['url'], binary=True)
        for data in [b'', b'x' * (asset['size'] + 1)]:
            with patch.object(update, 'open_url', return_value=io.BytesIO(data)):
                with self.assertRaisesRegex(ValueError, 'size mismatch'):
                    update.limbo_state(self.commit, release, self.old, update.hash_limbo_asset)
        asset['url'] = 'https://evil.example/a'
        with self.assertRaises(ValueError):
            update.limbo_state(self.commit, release, self.old,
                               lambda asset: self.fail('Unvalidated download'))


class VelocityTests(unittest.TestCase):
    def test_version_comes_from_request_context(self):
        item = velocity()
        self.assertNotIn('version', item)
        result = u.velocity_state('4.3.1', item)
        self.assertEqual((result['version'], result['build']), ('4.3.1', 45))

    def test_safe_filename_need_not_encode_version_and_build(self):
        item = velocity()
        artifact = item['downloads']['server:default']
        artifact['name'] = 'velocity-4.3.1+release.jar'
        artifact['url'] = f"https://fill-data.papermc.io/v1/objects/{artifact['checksums']['sha256']}/{artifact['name']}"
        self.assertEqual(u.velocity_state('4.3.1', item)['filename'], artifact['name'])

    def test_select_only_newest_stable(self):
        builds = [velocity(99, channel='EXPERIMENTAL'), velocity(45), velocity(46)]
        result = update.stable_velocity('4.3.1', builds)
        self.assertEqual(result['build'], 46)
        self.assertIsNone(update.stable_velocity('4.3.1', [velocity(channel='ALPHA')]))
        self.assertFalse(u.newer_velocity('4.3.1', 46, result))
        self.assertTrue(u.newer_velocity('4.3.1', 45, result))
        self.assertTrue(u.newer_velocity('4.3.0', 100, result))
        self.assertFalse(u.newer_velocity('4.4.0', 1, result))

    def test_discovery_selects_newest_version_with_stable_build(self):
        responses = {u.PROJECT: {'project': {'id': 'velocity'}, 'versions': {'4': ['4.4.0', '4.3.1']}},
                     u.PROJECT+'/versions/4.4.0/builds': [velocity(1, '4.4.0', 'ALPHA')],
                     u.PROJECT+'/versions/4.3.1/builds': [velocity(45), velocity(46)]}
        result = update.discover_velocity(responses.__getitem__)
        self.assertEqual((result['version'], result['build']), ('4.3.1', 46))
        responses[u.PROJECT+'/versions/4.4.0/builds'].extend([velocity(2, '4.4.0'), velocity(3, '4.4.0')])
        result = update.discover_velocity(responses.__getitem__)
        self.assertEqual((result['version'], result['build']), ('4.4.0', 3))

    def test_exact_selection_checks_identity_and_channel(self):
        urls = []
        def read(url):
            urls.append(url)
            return [velocity(46), velocity(), velocity(44)]
        env = u.load_env(PACKAGE)
        self.assertEqual((env['VELOCITY_VERSION'], env['VELOCITY_BUILD']), ('4.3.1', '45'))
        self.assertEqual(u.exact_velocity(env['VELOCITY_VERSION'], int(env['VELOCITY_BUILD']), read)['build'], 45)
        self.assertEqual(urls, [u.PROJECT+'/versions/4.3.1/builds'])
        missing_id = velocity()
        del missing_id['id']
        for builds in [[], [velocity(46)], [missing_id], [velocity('45')],
                       [velocity(), velocity()], [velocity(channel='BETA')],
                       {}, [None], [velocity(), None]]:
            with self.subTest(builds=builds), self.assertRaises(ValueError):
                u.exact_velocity('4.3.1', 45, lambda url: builds)

    def test_invalid_version_context_and_build_ids(self):
        for version in ['../4.3.1', '4.3.1/evil', '4.3.1?query', '4.3.1-SNAPSHOT']:
            with self.subTest(version=version), self.assertRaises(ValueError):
                u.exact_velocity(version, 45, lambda url: self.fail('Invalid request'))
        for build in [None, 0, -1, True, 45.0, '45']:
            with self.subTest(build=build), self.assertRaises(ValueError):
                u.velocity_state('4.3.1', velocity(build))
            with self.subTest(build=build), self.assertRaises(ValueError):
                u.exact_velocity('4.3.1', build, lambda url: self.fail('Invalid request'))

    def test_bad_artifact_metadata(self):
        for key, value in [('name', '../velocity.jar'), ('name', 'velocity-.jar'),
                           ('name', 'velocity-test.jar/evil'), ('name', 'velocity-test.jar\n'),
                           ('size', 0), ('size', True), ('size', -1), ('size', 20.0),
                           ('size', u.MAX_JAR_SIZE + 1), ('size', None),
                           ('checksums', None), ('checksums', {}),
                           ('checksums', {'sha256': 'bad'}), ('checksums', {'sha256': 'A'*64}),
                           ('checksums', {'sha256': 'z'*64}), ('url', 'https://evil.example/a'),
                           ('url', 'https://fill-data.papermc.io.evil.example/a'),
                           ('url', 'http://fill-data.papermc.io/a')]:
            item = velocity()
            item['downloads']['server:default'][key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                u.velocity_state('4.3.1', item)
        for downloads in [None, [], {}, {'server:default': None}]:
            item = velocity()
            item['downloads'] = downloads
            with self.subTest(downloads=downloads), self.assertRaises(ValueError):
                u.velocity_state('4.3.1', item)

    def test_url_manipulation_rejected(self):
        official = velocity()['downloads']['server:default']['url']
        for url in [official+'?query=1', official+'#fragment', official+'?', official+'#',
                    official.replace('/v1/objects/', '/v1/objects/../objects/'),
                    official.replace('/v1/objects/', '/v1/%6fbjects/'),
                    official.replace('a'*64, 'b'*64), official.replace('.jar', '-other.jar'),
                    official.replace('fill-data.papermc.io', 'fill-data.papermc.io:443'),
                    official.replace('fill-data.papermc.io', 'user@fill-data.papermc.io'),
                    '\n'+official, official+'\t', official+'é', None]:
            item = velocity()
            item['downloads']['server:default']['url'] = url
            with self.subTest(url=url), self.assertRaises(ValueError):
                u.velocity_state('4.3.1', item)

    def test_download_verifies_size_and_checksum(self):
        pin = u.velocity_state('4.3.1', velocity())
        pin['sha256'] = hashlib.sha256(b'j'*20).hexdigest()
        pin['url'] = f"https://fill-data.papermc.io/v1/objects/{pin['sha256']}/{pin['filename']}"
        for data, valid in [(b'j'*20, True), (b'j'*19, False), (b'x'*20, False), (b'j'*21, False)]:
            response = io.BytesIO(data)
            response.geturl = lambda: pin['url']
            with tempfile.TemporaryDirectory() as directory, patch.object(u, 'open_url', return_value=response):
                dest = Path(directory)/'velocity.jar'
                if valid:
                    u.download(pin, 'velocity', dest)
                    self.assertEqual(dest.read_bytes(), data)
                else:
                    with self.assertRaises(ValueError):
                        u.download(pin, 'velocity', dest)
                    self.assertFalse(dest.exists())
                self.assertFalse(dest.with_suffix('.part').exists())

    def test_download_rejects_untrusted_final_host(self):
        pin = u.velocity_state('4.3.1', velocity())
        response = io.BytesIO(b'j'*20)
        response.geturl = lambda: 'https://evil.example/velocity.jar'
        with tempfile.TemporaryDirectory() as directory, patch.object(u, 'open_url', return_value=response) as opened:
            dest = Path(directory)/'velocity.jar'
            with self.assertRaisesRegex(ValueError, 'final artifact host'):
                u.download(pin, 'velocity', dest)
            opened.assert_called_once_with(pin['url'], binary=True)
            self.assertFalse(dest.exists())
            self.assertFalse(dest.with_suffix('.part').exists())


class FloodgateTests(unittest.TestCase):
    def setUp(self):
        self.xml = (PACKAGE/'tests/fixtures/floodgate.xml').read_bytes()
        self.current = '2.2.5-20260917.145236-21'

    def test_parse_and_compare(self):
        result = u.parse_floodgate(self.xml)
        self.assertEqual(result, self.current)
        self.assertFalse(u.newer_floodgate(self.current, result))
        newer = u.parse_floodgate(self.xml.replace(b'20260917.145236-21', b'20260918.145236-22'))
        self.assertTrue(u.newer_floodgate(self.current, newer))

    def test_malformed_metadata(self):
        from xml.etree.ElementTree import ParseError
        for data in [b'<broken', b'<metadata/>', self.xml.replace(b'<artifactId>api', b'<artifactId>evil'),
                     self.xml.replace(b'2.2.5-20260917.145236-21', b'2.2.5-SNAPSHOT')]:
            with self.assertRaises((ValueError, ParseError)):
                u.parse_floodgate(data)

    def test_path_is_confined_and_mutable_coordinate_rejected(self):
        self.assertEqual(u.floodgate_url(self.current), u.MAVEN+'api-'+self.current+'.jar')
        for version in ['2.2.5-SNAPSHOT', '../api.jar', '2.3.0-20260917.145236-21', self.current+'/../evil']:
            with self.assertRaises(ValueError):
                u.floodgate_url(version)
        with self.assertRaises(ValueError):
            u.floodgate_url(self.current, '../evil')
        self.assertNotIn('api:2.2.5-SNAPSHOT', (PACKAGE/'velocity-lobby/build.gradle.kts').read_text())

    def test_checksum_from_official_repository(self):
        data = b'api jar'
        digest = hashlib.sha256(data).hexdigest().encode()
        with tempfile.TemporaryDirectory() as directory:
            for checksum, valid in [(digest, True), (b'bad', False), (b'a'*64, False)]:
                calls = []
                def read(url):
                    calls.append(url)
                    return checksum if url.endswith('.sha256') else data
                with patch.object(u, 'read_bytes', side_effect=read):
                    if valid:
                        u.acquire_floodgate(self.current, Path(directory)/'api.jar')
                        self.assertEqual(calls, [u.floodgate_url(self.current)+'.sha256', u.floodgate_url(self.current)])
                    else:
                        with self.assertRaises(ValueError):
                            u.acquire_floodgate(self.current, Path(directory)/'api.jar')


class UpdaterWritesTests(unittest.TestCase):
    def setUp(self):
        LimboTests.setUp(self)
        self.stable = update.limbo_state(self.commit, self.release, self.old)

    def test_migration_writes_only_state_and_races_write_nothing(self):
        import shutil
        discover = update.discover_limbo
        for race in (None, 'release', 'tag'):
            with self.subTest(race=race), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)/'package'
                shutil.copytree(PACKAGE, root)
                before = {p.relative_to(root): p.read_bytes() for p in root.rglob('*') if p.is_file()}
                summary = Path(directory)/'summary.md'
                args = ['update.py', '--directory', str(root), '--summary', str(summary)]
                calls = []
                def read(url):
                    calls.append(url)
                    if url == u.GITHUB + '/releases/latest':
                        release = copy.deepcopy(self.release)
                        if race == 'release' and len(calls) > 2:
                            release['id'] += 1
                        return release
                    self.assertEqual(url, u.GITHUB + '/git/ref/tags/1.2.0')
                    commit = 'b'*40 if race == 'tag' and len(calls) > 2 else self.commit
                    return {'object': {'type': 'commit', 'sha': commit}}
                xml = (PACKAGE/'tests/fixtures/floodgate.xml').read_bytes().replace(
                    b'20260917.145236-21', b'20260918.145236-22')
                with patch.object(sys, 'argv', args), \
                        patch.object(update, 'discover_limbo', side_effect=lambda previous: discover(previous, read)), \
                        patch.object(update, 'discover_velocity', return_value=u.velocity_state('4.3.1', velocity(46))), \
                        patch.object(update, 'read_bytes', return_value=xml), \
                        patch.object(update, 'acquire_floodgate'):
                    if race:
                        with self.assertRaisesRegex(ValueError, 'changed during discovery'):
                            update.main()
                    else:
                        update.main()
                after = {p.relative_to(root): p.read_bytes() for p in root.rglob('*') if p.is_file()}
                self.assertEqual(before.keys(), after.keys())
                changed = {str(name) for name in before if before[name] != after[name]}
                self.assertEqual(changed, set() if race else {'limboapi-update.json', 'package.env'})
                self.assertEqual(summary.exists(), race is None)
                self.assertEqual(calls, [u.GITHUB + '/releases/latest',
                                        u.GITHUB + '/git/ref/tags/1.2.0'] * 2)
                if not race:
                    self.assertEqual(u.load_pin(root, 'limboapi'), self.stable)
                    self.assertIn(self.old['source_commit'], summary.read_text())
                    self.assertIn(self.commit, summary.read_text())

    def test_unchanged_upstreams_do_not_rewrite_state(self):
        import shutil
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name in ('package.env', 'limboapi-update.json'):
                shutil.copyfile(PACKAGE/name, root/name)
            (root/'limboapi-update.json').write_text(json.dumps(self.stable))
            before = {p.name: p.read_bytes() for p in root.iterdir()}
            args = ['update.py', '--directory', str(root), '--summary', str(root/'summary.md')]
            with patch.object(sys, 'argv', args), \
                    patch.object(update, 'discover_limbo', return_value=self.stable), \
                    patch.object(update, 'discover_velocity', return_value=u.velocity_state('4.3.1', velocity())), \
                    patch.object(update, 'read_bytes', return_value=(PACKAGE/'tests/fixtures/floodgate.xml').read_bytes()), \
                    patch.object(update, 'acquire_floodgate'):
                update.main()
            self.assertEqual(before, {name: (root/name).read_bytes() for name in before})

    def test_newer_velocity_and_floodgate_change_only_reviewed_fields(self):
        import shutil
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name in ('package.env', 'limboapi-update.json'):
                shutil.copyfile(PACKAGE/name, root/name)
            (root/'limboapi-update.json').write_text(json.dumps(self.stable))
            limbo_before = (root/'limboapi-update.json').read_bytes()
            before = u.load_env(root)
            args = ['update.py', '--directory', str(root), '--summary', str(root/'summary.md')]
            xml = (PACKAGE/'tests/fixtures/floodgate.xml').read_bytes().replace(
                b'20260917.145236-21', b'20260918.145236-22')
            with patch.object(sys, 'argv', args), \
                    patch.object(update, 'discover_limbo', return_value=self.stable), \
                    patch.object(update, 'discover_velocity', return_value=u.velocity_state('4.3.1', velocity(46))), \
                    patch.object(update, 'read_bytes', return_value=xml), \
                    patch.object(update, 'acquire_floodgate'):
                update.main()
            after = u.load_env(root)
            self.assertEqual({key for key in before if before[key] != after[key]},
                             {'VELOCITY_BUILD', 'FLOODGATE_API_VERSION'})
            self.assertEqual((root/'limboapi-update.json').read_bytes(), limbo_before)
            summary = (root/'summary.md').read_text()
            self.assertIn('Velocity 4.3.1 build 45 -> Velocity 4.3.1 build 46', summary)
            self.assertIn('Floodgate API 2.2.5-20260917.145236-21 -> Floodgate API 2.2.5-20260918.145236-22', summary)


class PayloadTests(unittest.TestCase):
    def test_checksum_coverage_and_integrity(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name in ('artifacts', 'metadata', 'source', 'licenses'):
                (root/name).mkdir()
            for name in ('limboapi', 'justvoxel-lobby'):
                with zipfile.ZipFile(root/'artifacts'/f'{name}.jar', 'w') as jar:
                    jar.writestr('velocity-plugin.json', json.dumps({'id': name}))
            (root/'source/source.txt').write_text('source')
            (root/'licenses/license.txt').write_text('license')
            sums = root/'metadata/SHA256SUMS'
            files = sorted(p for p in root.rglob('*') if p.is_file())
            sums.write_text(''.join(f'{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.relative_to(root)}\n' for p in files))
            validate.validate(root)
            (root/'source/extra.txt').write_text('uncovered')
            with self.assertRaisesRegex(ValueError, 'coverage'):
                validate.validate(root)
            (root/'source/extra.txt').unlink()
            (root/'source/source.txt').write_text('tampered')
            with self.assertRaisesRegex(ValueError, 'Checksum mismatch'):
                validate.validate(root)

    def test_plugin_id_zip_and_bundling_contract(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)/'plugin.jar'
            for identity, extra, valid in [('justvoxel-lobby', 'org/example/Main.class', True),
                    ('wrong', '', False), ('justvoxel-lobby', 'net/elytrium/Foo.class', False),
                    ('justvoxel-lobby', 'com/velocitypowered/Foo.class', False),
                    ('justvoxel-lobby', 'org/geysermc/Foo.class', False)]:
                with zipfile.ZipFile(path, 'w') as jar:
                    jar.writestr('velocity-plugin.json', json.dumps({'id': identity}))
                    if extra:
                        jar.writestr(extra, b'class')
                if valid:
                    validate.validate_jar(path, 'justvoxel-lobby')
                else:
                    with self.assertRaises(ValueError):
                        validate.validate_jar(path, 'justvoxel-lobby')
            path.write_bytes(b'bad zip')
            with self.assertRaises(zipfile.BadZipFile):
                validate.validate_jar(path, 'limboapi')


if __name__ == '__main__':
    unittest.main()
