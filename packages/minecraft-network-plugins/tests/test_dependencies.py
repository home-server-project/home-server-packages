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
    return dict(id=build, version={'id': version}, channel=channel, downloads={'server:default':
        dict(name=name, size=20, checksums={'sha256': digest},
             url=f'https://fill-data.papermc.io/v1/objects/{digest}/{name}')})


class LimboTests(unittest.TestCase):
    def setUp(self):
        self.old = u.load_pin(PACKAGE, 'limboapi')
        p = self.old
        self.release = dict(id=p['release_id'], name=p['release_name'], tag_name='dev-build', draft=False,
                            published_at=p['published_at'], assets=[dict(id=p['asset_id'], name=p['filename'],
                            size=p['size'], url=p['url'], state='uploaded', digest='sha256:' + p['sha256'])])

    def test_unchanged_full_commit(self):
        candidate = update.limbo_state(self.old['source_commit'], self.release, self.old)
        self.assertFalse(update.changed(self.old, candidate))

    def test_changed_commit_even_with_same_short_prefix(self):
        commit = self.old['source_commit'][:7] + 'a' * 33
        candidate = update.limbo_state(commit, self.release, self.old)
        self.assertTrue(update.changed(self.old, candidate))
        self.assertEqual(candidate['source_commit'], commit)
        self.assertIn('Requires review', candidate['compatibility'])

    def test_bad_metadata_and_sha_rejected(self):
        for field, value in [('size', 0), ('size', True), ('url', 'https://evil.example/a'),
                             ('id', -1), ('name', '../limboapi.jar'), ('digest', 'sha256:bad'),
                             ('digest', 'sha256:' + 'z' * 64)]:
            with self.subTest(field=field):
                release = copy.deepcopy(self.release)
                release['assets'][0][field] = value
                with self.assertRaises(ValueError):
                    update.limbo_state(self.old['source_commit'], release, self.old)
        for commit in ['bfef579', 'x' * 40]:
            with self.assertRaises(ValueError):
                update.limbo_state(commit, self.release, self.old)

    def test_annotated_tag_and_full_sha_validation(self):
        responses = [{'object': {'type': 'tag', 'sha': 'a'*40}},
                     {'object': {'type': 'commit', 'sha': self.old['source_commit']}}]
        self.assertEqual(update.dev_commit(lambda url: responses.pop(0)), self.old['source_commit'])
        with self.assertRaises(ValueError):
            update.dev_commit(lambda url: {'object': {'type': 'commit', 'sha': 'abc'}})


class VelocityTests(unittest.TestCase):
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
        self.assertEqual(update.discover_velocity(responses.__getitem__)['build'], 46)

    def test_exact_selection_checks_identity_and_channel(self):
        urls = []
        def read(url):
            urls.append(url)
            return velocity()
        self.assertEqual(u.exact_velocity('4.3.1', 45, read)['build'], 45)
        self.assertEqual(urls, [u.PROJECT+'/versions/4.3.1/builds/45'])
        for item in [velocity(46), velocity(version='4.3.2'), velocity(channel='BETA')]:
            with self.assertRaises(ValueError):
                u.exact_velocity('4.3.1', 45, lambda url: item)

    def test_bad_artifact_metadata(self):
        for key, value in [('name', '../velocity.jar'), ('size', 0), ('size', True),
                           ('checksums', {'sha256': 'bad'}), ('url', 'https://evil.example/a'),
                           ('url', 'https://fill-data.papermc.io.evil.example/a'),
                           ('url', 'http://fill-data.papermc.io/a')]:
            item = velocity()
            item['downloads']['server:default'][key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                u.velocity_state('4.3.1', item)
        with self.assertRaises(ValueError):
            u.velocity_state('4.3.1', dict(id=45, version='4.3.1', channel='STABLE', downloads={}))

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
    setUp = LimboTests.setUp

    def test_unchanged_upstreams_do_not_rewrite_state(self):
        import shutil
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name in ('package.env', 'limboapi-update.json'):
                shutil.copyfile(PACKAGE/name, root/name)
            before = {p.name: p.read_bytes() for p in root.iterdir()}
            args = ['update.py', '--directory', str(root), '--summary', str(root/'summary.md')]
            with patch.object(sys, 'argv', args), \
                    patch.object(update, 'dev_commit', return_value=self.old['source_commit']), \
                    patch.object(update, 'read_json', return_value=self.release), \
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
            before = u.load_env(root)
            args = ['update.py', '--directory', str(root), '--summary', str(root/'summary.md')]
            xml = (PACKAGE/'tests/fixtures/floodgate.xml').read_bytes().replace(
                b'20260917.145236-21', b'20260918.145236-22')
            with patch.object(sys, 'argv', args), \
                    patch.object(update, 'dev_commit', return_value=self.old['source_commit']), \
                    patch.object(update, 'read_json', return_value=self.release), \
                    patch.object(update, 'discover_velocity', return_value=u.velocity_state('4.3.1', velocity(46))), \
                    patch.object(update, 'read_bytes', return_value=xml), \
                    patch.object(update, 'acquire_floodgate'):
                update.main()
            after = u.load_env(root)
            self.assertEqual({key for key in before if before[key] != after[key]},
                             {'VELOCITY_BUILD', 'FLOODGATE_API_VERSION'})
            self.assertEqual((root/'limboapi-update.json').read_bytes(), (PACKAGE/'limboapi-update.json').read_bytes())
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
