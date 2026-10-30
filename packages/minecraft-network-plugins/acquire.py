#!/usr/bin/env python3
"""Acquire reviewed inputs; only exact Velocity build metadata is queried."""
import argparse
import json
from pathlib import Path
from upstream import download, load_pin, load_env, exact_velocity, acquire_floodgate


def acquire(output):
    directory = Path(__file__).parent
    env = load_env(directory)
    output.mkdir(parents=True, exist_ok=True)
    pins = {'limboapi': load_pin(directory, 'limboapi'),
            'velocity': exact_velocity(env['VELOCITY_VERSION'], int(env['VELOCITY_BUILD']))}
    for kind, pin in pins.items():
        download(pin, kind, output / f'{kind}.jar')
        (output / f'{kind}-release.json').write_text(json.dumps(pin, indent=2) + '\n')
    floodgate = acquire_floodgate(env['FLOODGATE_API_VERSION'], output / 'floodgate-api.jar')
    (output / 'floodgate-release.json').write_text(json.dumps(floodgate, indent=2) + '\n')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    acquire(parser.parse_args().output)
