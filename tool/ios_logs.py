#!/usr/bin/env python3
"""Collect bounded simulator/device diagnostics without a GUI or shared output."""
import argparse
import datetime
import json
from pathlib import Path
import shutil
import subprocess
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('kind', choices=('simulator', 'device'))
    parser.add_argument('device')
    parser.add_argument('bundle')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    if args.kind == 'simulator' and args.device == 'auto':
        args.device = subprocess.check_output(
            [sys.executable, str(root / 'tool/ios_simulator.py')], text=True).strip()
    timestamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ')
    output = args.output / ('diagnostics-' + timestamp + '-' + args.kind)
    output.mkdir(parents=True, exist_ok=False)
    results = []

    def execute(label, command):
        try:
            result = subprocess.run(command, capture_output=True, timeout=45)
            (output / (label + '.log')).write_bytes(result.stdout + result.stderr)
            results.append({'label': label, 'command': command, 'exit_code': result.returncode})
            return result.returncode == 0, result.stdout
        except (OSError, subprocess.TimeoutExpired) as error:
            results.append({'label': label, 'command': command, 'error': str(error)})
            return False, b''

    if args.kind == 'simulator':
        execute('runtimes', ['xcrun', 'simctl', 'list', 'runtimes', '-j'])
        execute('devices', ['xcrun', 'simctl', 'list', 'devices', '-j'])
        execute('native-console', ['xcrun', 'simctl', 'spawn', args.device, 'log', 'show',
                '--last', '10m', '--style', 'compact', '--predicate', 'process == "fehviewer"'])
        execute('screenshot', ['xcrun', 'simctl', 'io', args.device, 'screenshot', str(output / 'screen.png')])
        ok, data = execute('app-container', ['xcrun', 'simctl', 'get_app_container', args.device, args.bundle, 'data'])
        if ok:
            container = Path(data.decode().strip())
            for source in ('Documents/log', 'Documents/step5a-events.json'):
                path = container / source
                destination = output / path.name
                if path.is_dir():
                    shutil.copytree(path, destination)
                elif path.is_file():
                    shutil.copy2(path, destination)
                else:
                    results.append({'label': source, 'status': 'ABSENT'})
        for path in (Path.home() / 'Library/Logs/DiagnosticReports').glob('fehviewer*.ips'):
            try:
                header = json.loads(path.read_text().splitlines()[0])
                if header.get('bundleID') == args.bundle:
                    shutil.copy2(path, output / path.name)
            except (OSError, ValueError):
                results.append({'label': str(path), 'status': 'UNREADABLE'})
    else:
        base = ['xcrun', 'devicectl', 'device']
        execute('device-details', base + ['info', 'details', '--device', args.device,
                '--json-output', str(output / 'device-details.json'), '--timeout', '20'])
        execute('app-files', base + ['info', 'files', '--device', args.device,
                '--domain-type', 'appDataContainer', '--domain-identifier', args.bundle,
                '--subdirectory', 'Documents/log', '--json-output', str(output / 'app-files.json'), '--timeout', '20'])
        # CoreDevice copies directory contents into an existing destination.
        # An empty App log directory is valid and should remain exportable.
        (output / 'app-log').mkdir()
        execute('app-log', base + ['copy', 'from', '--device', args.device, '--source', 'Documents/log',
                '--destination', str(output / 'app-log'), '--domain-type', 'appDataContainer',
                '--domain-identifier', args.bundle, '--timeout', '20'])
        listing = output / 'crash-files.json'
        ok, _ = execute('crash-files', base + ['info', 'files', '--device', args.device,
                '--domain-type', 'systemCrashLogs', '--search', 'fehviewer',
                '--json-output', str(listing), '--timeout', '20'])
        if ok:
            paths = set()

            def visit(value):
                if isinstance(value, dict):
                    path = value.get('relativePath')
                    if path and Path(path).name.startswith('fehviewer') and path.endswith('.ips'):
                        paths.add(path)
                    for child in value.values():
                        visit(child)
                elif isinstance(value, list):
                    for child in value:
                        visit(child)

            visit(json.loads(listing.read_text()))
            for path in sorted(paths):
                destination = output / Path(path).name
                ok, _ = execute('crash-' + destination.stem, base + ['copy', 'from', '--device', args.device,
                        '--domain-type', 'systemCrashLogs', '--source', path,
                        '--destination', str(destination), '--timeout', '20'])
                if ok:
                    try:
                        header = json.loads(destination.read_text().splitlines()[0])
                        if header.get('bundleID') != args.bundle:
                            destination.unlink()
                    except (OSError, ValueError):
                        results.append({'label': path, 'status': 'UNREADABLE'})
    (output / 'collection.json').write_text(json.dumps({
        'kind': args.kind, 'device_id': args.device, 'bundle_id': args.bundle,
        'collected_utc': timestamp, 'results': results,
        'note': 'Diagnostic capture is not an application acceptance result.',
    }, indent=2) + '\n')
    print(output)
    # Missing app log files are a recorded diagnostic state; console logs from
    # build/run/smoke remain the primary source. Command failures stay visible.
    return 0


if __name__ == '__main__':
    sys.exit(main())
