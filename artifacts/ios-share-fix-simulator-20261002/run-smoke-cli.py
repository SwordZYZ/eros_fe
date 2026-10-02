"""Compare the simulator smoke cases with 5A using its unchanged CLI driver."""
import importlib.util
import json
import os
from pathlib import Path
import pty
import signal
import subprocess
import threading
import time

OUT = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('share_cli', OUT / 'run-simulator-check.py')
cli = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cli)
LOG = OUT / 'simulator-smoke.log'
LOG.touch()


def command(name, **parameters):
    output = OUT / f'simulator-smoke-{name}.json'
    with (OUT / 'simulator-smoke-driver.log').open('ab') as stream:
        subprocess.run([
            str(cli.DART), f'--packages={cli.PACKAGES}', 'tool/ios_baseline_driver.dart',
            str(LOG), name, str(output),
        ] + [f'{key}={value}' for key, value in parameters.items()],
            cwd=cli.ROOT, stdout=stream, stderr=subprocess.STDOUT, check=True, timeout=90)
    return json.loads(output.read_text())


def wait_paused(offset):
    deadline = time.monotonic() + 30
    while time.monotonic() < deadline:
        if '"state":"paused"' in LOG.read_text(errors='replace')[offset:]:
            return
        time.sleep(0.1)
    raise TimeoutError('Actual simulator background transition')


master, slave = pty.openpty()
process = subprocess.Popen([
    str(cli.ROOT / 'scripts/ios_dev.sh'), 'run', '--debug', '-d', cli.SIMULATOR,
    '-t', 'tool/ios_baseline_probe.dart',
    '--use-application-binary=build/ios/iphonesimulator/fehviewer.app',
], cwd=cli.ROOT, stdin=slave, stdout=slave, stderr=subprocess.STDOUT, start_new_session=True)
os.close(slave)


def pump():
    with LOG.open('wb', buffering=0) as stream:
        try:
            while data := os.read(master, 8192):
                stream.write(data)
        except OSError:
            pass


thread = threading.Thread(target=pump, daemon=True)
thread.start()
result = {'status': 'INCOMPLETE'}
try:
    cli.wait_ready(process, LOG)
    command('gallery')
    command('torrent')
    command('smoke')
    command('lifecycle_begin', label='background_foreground')
    offset = len(LOG.read_text(errors='replace'))  # Character offset, not bytes.
    with (OUT / 'simulator-smoke-os.log').open('ab') as stream:
        subprocess.run(['xcrun', 'simctl', 'launch', cli.SIMULATOR, 'com.apple.Preferences'],
                       stdout=stream, stderr=subprocess.STDOUT, check=True)
        wait_paused(offset)
        subprocess.run(['xcrun', 'simctl', 'launch', cli.SIMULATOR, 'com.fuhua.erosfe.step5a'],
                       stdout=stream, stderr=subprocess.STDOUT, check=True)
    final = command('lifecycle_end', label='background_foreground')
    result.update({'status': 'BASELINE_RECORDED',
                   'results': [event for event in final['events'] if event.get('kind') == 'result'],
                   'errors': [event for event in final['events'] if event.get('kind') == 'error']})
    subprocess.run(['xcrun', 'simctl', 'io', cli.SIMULATOR, 'screenshot',
                    str(OUT / 'simulator-smoke-restored.png')], check=True, capture_output=True)
finally:
    if process.poll() is None:
        os.write(master, b'q')
        try:
            process.wait(timeout=40)
        except subprocess.TimeoutExpired:
            process.send_signal(signal.SIGTERM)
            process.wait(timeout=15)
    thread.join(timeout=5)
    os.close(master)
    result['flutterExitCode'] = process.returncode
    (OUT / 'simulator-smoke-result.json').write_text(json.dumps(result, indent=2) + '\n')
assert process.returncode == 0, process.returncode
print('Simulator smoke baseline recorded; existing errors are retained separately.')
