#!/usr/bin/env python3
"""Check the pinned iOS runtime or select and boot a checkout's simulator."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent


def simctl(*arguments, json_output=False):
    result = subprocess.run(['xcrun', 'simctl', *arguments], capture_output=True, text=True)
    if result.stderr:
        print(result.stderr, file=sys.stderr, end='')
    if result.returncode:
        sys.exit(f'simctl {" ".join(arguments)} failed with exit status {result.returncode}')
    return json.loads(result.stdout) if json_output else result.stdout.strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('device', nargs='?', default='auto')
    parser.add_argument('--check', action='store_true', help='list available devices without booting')
    args = parser.parse_args()
    config = json.loads(Path(__file__).with_name('ios_toolchain.json').read_text())
    version = config['simulator_runtime_version']
    architecture = config['simulator_architecture']
    runtime_id = 'com.apple.CoreSimulator.SimRuntime.iOS-' + version.replace('.', '-')
    runtimes = simctl('list', 'runtimes', '-j', json_output=True)['runtimes']
    runtime = next((r for r in runtimes if r.get('identifier') == runtime_id
                    and r.get('version') == version and r.get('isAvailable') is True
                    and architecture in r.get('supportedArchitectures', [])), None)
    if runtime is None:
        parser.error(f'available {architecture} iOS {version} runtime required ({runtime_id})')
    devices = simctl('list', 'devices', 'available', '-j', json_output=True)['devices'].get(runtime_id, [])
    if args.check:
        print(runtime_id, runtime.get('buildversion', 'unknown'), ', '.join(runtime['supportedArchitectures']))
        if not devices:
            parser.error(f'no available simulator devices for iOS {version}; create one in Xcode Device Hub')
        for device in devices:
            print(f"  {device['name']} ({device['udid']}) ({device['state']})")
        return

    name = 'Eros-FE-' + hashlib.sha256(str(ROOT).encode()).hexdigest()[:10]
    if args.device != 'auto':
        device = next((d for d in devices if d['udid'] == args.device), None)
        if device is None:
            parser.error(f'requested simulator is not available on iOS {version}')
    else:
        device = next((d for d in devices if d['name'] == name), None)
        if device is None:
            types = runtime.get('supportedDeviceTypes', [])
            target = next((t for t in types if t['name'] == 'iPad Pro 11-inch (M5)'), None)
            if target is None:
                target = next((t for t in types if t.get('productFamily') == 'iPad'), None)
            if target is None:
                parser.error('runtime does not provide a supported iPad simulator type')
            udid = simctl('create', name, target['identifier'], runtime_id)
            device = {'udid': udid, 'state': 'Shutdown'}
    if device['state'] != 'Booted':
        simctl('boot', device['udid'])
    print(simctl('bootstatus', device['udid'], '-b'), file=sys.stderr)
    print(device['udid'])


if __name__ == '__main__':
    main()
