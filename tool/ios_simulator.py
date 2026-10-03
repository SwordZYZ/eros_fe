#!/usr/bin/env python3
"""Select/boot an arm64 iOS 27.0 simulator dedicated to this checkout."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent


def simctl(*arguments, json_output=False):
    result = subprocess.run(['xcrun', 'simctl', *arguments], capture_output=True, text=True, check=True)
    if result.stderr:
        print(result.stderr, file=sys.stderr, end='')
    return json.loads(result.stdout) if json_output else result.stdout.strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('device', nargs='?', default='auto')
    args = parser.parse_args()
    runtime = next((r for r in simctl('list', 'runtimes', '-j', json_output=True)['runtimes']
                    if r.get('version') == '27.0' and r.get('isAvailable')
                    and 'arm64' in r.get('supportedArchitectures', [])), None)
    if runtime is None:
        parser.error('available arm64 iOS 27.0 runtime required; no fallback to another version')
    devices = simctl('list', 'devices', 'available', '-j', json_output=True)['devices'].get(runtime['identifier'], [])
    name = 'Eros-FE-' + hashlib.sha256(str(ROOT).encode()).hexdigest()[:10]
    if args.device != 'auto':
        device = next((d for d in devices if d['udid'] == args.device), None)
        if device is None:
            parser.error('requested simulator is not available on iOS 27.0')
    else:
        device = next((d for d in devices if d['name'] == name), None)
        if device is None:
            types = runtime.get('supportedDeviceTypes', [])
            target = next((t for t in types if t['name'] == 'iPad Pro 11-inch (M5)'), None)
            if target is None:
                target = next((t for t in types if t.get('productFamily') == 'iPad'), None)
            if target is None:
                parser.error('runtime does not provide a supported iPad simulator type')
            udid = simctl('create', name, target['identifier'], runtime['identifier'])
            device = {'udid': udid, 'state': 'Shutdown'}
    if device['state'] != 'Booted':
        simctl('boot', device['udid'])
    print(simctl('bootstatus', device['udid'], '-b'), file=sys.stderr)
    print(device['udid'])


if __name__ == '__main__':
    main()
