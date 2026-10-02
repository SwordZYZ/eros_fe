"""Host CLI wrapper; preserves the frozen 5A Debug driver and real UI actions."""
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
OUT = Path(__file__).resolve().parent
DEVICE = '00008132-000278923E99001C'
label, action, *parameters = sys.argv[1:]
if action == 'capture':
    name = parameters[0]
    command = ['xcrun', 'devicectl', 'device', 'capture', 'screenshot',
               '--device', DEVICE, '--destination', str(OUT / f'{label}-{name}.png'), '--timeout', '20']
    with (OUT / 'capture.log').open('ab') as stream:
        subprocess.run(command, stdout=stream, stderr=subprocess.STDOUT, check=True, timeout=35)
    print(f'{label}: screenshot {name} saved')
elif action == 'export':
    command = ['xcrun', 'devicectl', 'device', 'copy', 'from', '--device', DEVICE,
               '--source', 'Documents/step5a-events.json', '--destination', str(OUT / f'{label}-app-events.json'),
               '--domain-type', 'appDataContainer', '--domain-identifier', 'com.fuhua.erosfe.step5a', '--timeout', '20']
    with (OUT / 'export.log').open('ab') as stream:
        subprocess.run(command, stdout=stream, stderr=subprocess.STDOUT, check=True, timeout=35)
    print(f'{label}: App events exported')
else:
    # Distinct file names preserve both privacy states and each lifecycle phase.
    suffix = '-' + '-'.join(p.replace('=', '-') for p in parameters) if parameters else ''
    result = OUT / f'{label}-{action}{suffix}.json'
    command = [str(ROOT / '.fvm/flutter_sdk/bin/dart'),
               f'--packages={ROOT / ".fvm/flutter_sdk/packages/flutter_tools/.dart_tool/package_config.json"}',
               'tool/ios_baseline_driver.dart', str(OUT / f'{label}.log'), action, str(result), *parameters]
    with (OUT / 'driver.log').open('ab') as stream:
        subprocess.run(command, cwd=ROOT, stdout=stream, stderr=subprocess.STDOUT, check=True, timeout=90)
    data = json.loads(result.read_text())
    print(json.dumps({'round': label, 'action': action,
        'route': data.get('route'), 'privacy': data.get('privacy'),
        'results': [{k: e[k] for k in ('case', 'status')} for e in data['events'] if e.get('kind') == 'result'],
        'errorCount': sum(e.get('kind') == 'error' for e in data['events'])}, ensure_ascii=False))
