"""CLI-only targeted share regression using the frozen 5A driver and XCTest."""

import json
import os
from pathlib import Path
import pty
import signal
import subprocess
import sys
import threading
import time

ROOT = Path(__file__).resolve().parents[2]
OUT = Path(__file__).resolve().parent
SIMULATOR = 'E3B49F40-CB5C-4CDC-A04D-35E0284103A8'
DART = ROOT / '.fvm/flutter_sdk/bin/dart'
PACKAGES = ROOT / '.fvm/flutter_sdk/packages/flutter_tools/.dart_tool/package_config.json'
HARNESS = Path((OUT / 'harness-path.txt').read_text().strip())
MAGNET = json.loads((ROOT / 'artifacts/ios-step5a-20261001/fixture-manifest.json').read_text())['magnet']


def wait_ready(process, log):
    deadline = time.monotonic() + 150
    while time.monotonic() < deadline:
        if 'STEP5A_READY' in log.read_text(errors='replace'):
            return
        if process.poll() is not None:
            raise RuntimeError(f'Flutter exited before readiness: {process.returncode}')
        time.sleep(0.2)
    raise TimeoutError('Flutter readiness')


def drive(log, label, command):
    output = OUT / f'{label}-{command}.json'
    with (OUT / f'{label}-driver.log').open('ab') as stream:
        subprocess.run([
            str(DART), f'--packages={PACKAGES}', 'tool/ios_baseline_driver.dart',
            str(log), command, str(output),
        ], cwd=ROOT, stdout=stream, stderr=subprocess.STDOUT, check=True, timeout=90)
    return json.loads(output.read_text())


def run_round(number):
    label = f'simulator-{number}'
    log = OUT / f'{label}.log'
    log.touch()
    master, slave = pty.openpty()
    process = subprocess.Popen([
        str(ROOT / 'scripts/ios_dev.sh'), 'run', '--debug', '-d', SIMULATOR,
        '-t', 'tool/ios_baseline_probe.dart',
        '--use-application-binary=build/ios/iphonesimulator/fehviewer.app',
    ], cwd=ROOT, stdin=slave, stdout=slave, stderr=subprocess.STDOUT, start_new_session=True)
    os.close(slave)

    def pump():
        with log.open('wb', buffering=0) as stream:
            try:
                while True:
                    data = os.read(master, 8192)
                    if not data:
                        break
                    stream.write(data)
            except OSError:
                pass  # PTY returns EIO once its slave has closed.

    thread = threading.Thread(target=pump, daemon=True)
    thread.start()
    result = {'round': number, 'status': 'FAIL'}
    try:
        wait_ready(process, log)
        print(f'{label}: ready; driving frozen gallery/torrent/magnet', flush=True)
        drive(log, label, 'gallery')
        drive(log, label, 'torrent')
        sentinel = f'EROS_SHARE_CHECK_SENTINEL_{number}'
        subprocess.run(['xcrun', 'simctl', 'pbcopy', SIMULATOR], input=sentinel.encode(), check=True)
        share = drive(log, label, 'share')
        assertions = [event for event in share['events']
                      if event.get('case') == 'system_share_visible_and_usable']
        assert assertions[-1]['status'] == 'NEEDS_NATIVE_OBSERVATION', assertions[-1]
        subprocess.run(['xcrun', 'simctl', 'io', SIMULATOR, 'screenshot',
                        str(OUT / f'{label}-share.png')], check=True, capture_output=True)
        bundle = HARNESS / f'{label}.xcresult'
        with (OUT / f'{label}-native.log').open('wb') as stream:
            native = subprocess.run([
                'python3', str(HARNESS / 'scripts/ios_lock.py'), '--',
                'xcodebuild', '-project', str(HARNESS / 'ShareMenuChecks.xcodeproj'),
                '-scheme', 'ShareMenuChecks', '-configuration', 'Debug',
                '-destination', f'platform=iOS Simulator,id={SIMULATOR}',
                '-derivedDataPath', str(HARNESS / 'DerivedData'),
                '-resultBundlePath', str(bundle), '-parallel-testing-enabled', 'NO',
                'test-without-building', 'CODE_SIGNING_ALLOWED=NO',
            ], stdout=stream, stderr=subprocess.STDOUT, timeout=180)
        result['nativeExitCode'] = native.returncode
        if bundle.exists():
            summary = subprocess.check_output([
                'xcrun', 'xcresulttool', 'get', 'test-results', 'summary', '--path', str(bundle),
            ])
            (OUT / f'{label}-native-summary.json').write_bytes(summary)
            subprocess.run([
                'xcrun', 'xcresulttool', 'export', 'attachments', '--path', str(bundle),
                '--output-path', str(OUT / f'{label}-native-attachments'),
            ], check=True, capture_output=True)
        assert native.returncode == 0, f'Native UI check failed; see {label}-native.log'
        clipboard = subprocess.check_output(['xcrun', 'simctl', 'pbpaste', SIMULATOR]).decode()
        result['clipboardBefore'] = sentinel
        result['clipboardAfter'] = clipboard
        result['expectedMagnet'] = MAGNET
        assert clipboard == MAGNET, repr(clipboard)
        drive(log, label, 'snapshot')
        result.update({'status': 'PASS', 'systemMenuVisible': True,
                       'copyHittableAndTapped': True, 'menuDismissed': True,
                       'copiedMagnetMatches': True, 'xcresultPath': str(bundle)})
        print(f'{label}: native menu + actual Copy + exact clipboard PASS', flush=True)
    except Exception as error:
        result['error'] = repr(error)
        raise
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
        (OUT / f'{label}-result.json').write_text(json.dumps(result, indent=2) + '\n')
    assert process.returncode == 0, process.returncode
    return result


if __name__ == '__main__':
    results = [run_round(number) for number in range(1, 4)]
    (OUT / 'share-results.json').write_text(json.dumps(results, indent=2) + '\n')
    print('All three targeted simulator share rounds PASS.', flush=True)
