#!/usr/bin/env python3
"""Validate the exact standalone OCI payload, including complete checksum coverage."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import zipfile


def validate_jar(path, identity):
    if not path.is_file() or not path.stat().st_size:
        raise ValueError('Missing or empty JAR')
    with zipfile.ZipFile(path) as jar:
        if jar.testzip() is not None or json.loads(jar.read('velocity-plugin.json'))['id'] != identity:
            raise ValueError('Invalid plugin JAR')
        if identity == 'justvoxel-lobby' and any(
                name.startswith(('net/elytrium/', 'com/velocitypowered/', 'org/geysermc/'))
                for name in jar.namelist()):
            raise ValueError('Compile dependency bundled in lobby')


def validate(root):
    expected = {'limboapi.jar', 'justvoxel-lobby.jar'}
    if {p.name for p in (root / 'artifacts').iterdir()} != expected:
        raise ValueError('Unexpected runtime payload')
    for name in ('source', 'licenses', 'metadata'):
        if not (root / name).is_dir() or not any((root / name).iterdir()):
            raise ValueError(f'Missing {name}')
    checked = set()
    for line in (root / 'metadata/SHA256SUMS').read_text().splitlines():
        digest, name = line.split('  ', 1)
        path = Path(name)
        if (not re.fullmatch('[0-9a-f]{64}', digest) or path.is_absolute()
                or '..' in path.parts or name in checked or (root / path).is_symlink()):
            raise ValueError('Invalid checksum entry')
        if hashlib.sha256((root / path).read_bytes()).hexdigest() != digest:
            raise ValueError(f'Checksum mismatch: {name}')
        checked.add(name)
    files = {str(p.relative_to(root)) for p in root.rglob('*') if p.is_file()}
    if checked != files - {'metadata/SHA256SUMS'}:
        raise ValueError('Incomplete checksum coverage')
    for name in expected:
        validate_jar(root / 'artifacts' / name, name[:-4])


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('root', type=Path)
    validate(parser.parse_args().root)
