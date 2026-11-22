#!/usr/bin/env python3
"""Capture a command's output and status without retaining orphan console pipes."""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import selectors
import signal
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parent.parent


def git(*arguments):
    result = subprocess.run(['git', '-C', str(ROOT), *arguments], capture_output=True)
    return result.stdout.decode(errors='replace').strip() if result.returncode == 0 else None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--label', required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--device')
    parser.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ['--'] else args.command
    if not command:
        parser.error('command required after --')
    args.output.mkdir(parents=True, exist_ok=True)
    started = datetime.datetime.now(datetime.timezone.utc)
    prefix = started.strftime('%Y%m%dT%H%M%S') + '-' + args.label + '-' + str(os.getpid())
    manifest_path = args.output / (prefix + '.json')
    log_path = args.output / (prefix + '.log')
    patch = subprocess.run(['git', '-C', str(ROOT), 'diff', 'HEAD', '--binary'], capture_output=True)
    manifest = {
        'operation': args.label, 'started_utc': started.isoformat(),
        'checkout': str(ROOT), 'commit': git('rev-parse', 'HEAD'),
        'working_tree': git('status', '--porcelain'),
        'tracked_diff_sha256': hashlib.sha256(patch.stdout).hexdigest(),
        'command': command, 'device_id': args.device, 'host_arch': os.uname().machine,
        'log': log_path.name, 'status': 'RUNNING',
    }
    for flag in ('-d', '--device-id'):
        if not manifest['device_id'] and flag in command:
            index = command.index(flag) + 1
            if index < len(command):
                manifest['device_id'] = command[index]
    # Includes new entry/test sources, which are absent from git diff until staged.
    sources = [ROOT / 'pubspec.yaml', ROOT / 'pubspec.lock', ROOT / 'ios/Podfile.lock',
               ROOT / 'Gemfile.lock']
    for directory in ('scripts', 'tool', 'integration_test', 'lib'):
        sources.extend(p for p in (ROOT / directory).rglob('*')
                       if p.is_file() and p.suffix in ('.sh', '.py', '.dart'))
    manifest['source_sha256'] = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
                                for p in sources if p.is_file()}
    manifest_path.write_text(json.dumps(manifest, indent=2) + '\n')
    interrupted = None
    interrupt_time = None

    def on_signal(signum, _frame):
        nonlocal interrupted, interrupt_time
        if interrupted is None:
            interrupted, interrupt_time = signum, time.monotonic()

    for signum in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
        signal.signal(signum, on_signal)
    result = 127
    try:
        with log_path.open('wb') as log, selectors.DefaultSelector() as ready:
            if args.label == 'smoke':
                timestamp = datetime.datetime.now(datetime.timezone.utc).isoformat()
                message = f'[iOS smoke] {timestamp} Starting flutter test command\n'
                log.write(message.encode())
                log.flush()
                print(message, end='', flush=True)
            child = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            os.set_blocking(child.stdout.fileno(), False)
            ready.register(child.stdout, selectors.EVENT_READ)
            while True:
                if interrupted is not None and child.poll() is None:
                    child.send_signal(interrupted if time.monotonic() - interrupt_time < 1 else signal.SIGKILL)
                events = ready.select(0.1)
                for key, _ in events:
                    chunk = os.read(key.fd, 65536)
                    if chunk:
                        log.write(chunk)
                        log.flush()
                        sys.stdout.buffer.write(chunk)
                        sys.stdout.buffer.flush()
                    else:
                        ready.unregister(key.fileobj)
                if child.poll() is not None:
                    # Drain available data, but do not wait for EOF from escaped
                    # devicectl processes that inherited the console pipe.
                    while True:
                        try:
                            chunk = os.read(child.stdout.fileno(), 65536)
                        except BlockingIOError:
                            break
                        if not chunk:
                            break
                        log.write(chunk)
                        sys.stdout.buffer.write(chunk)
                    break
            child.stdout.close()
            result = child.wait()
            result = 128 - result if result < 0 else result
            if interrupted is not None:
                result = 128 + interrupted
    except OSError as error:
        manifest['error'] = str(error)
        print(error, file=sys.stderr)
    finally:
        manifest.update(ended_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),
                        exit_code=result, status='PASS' if result == 0 else 'FAIL')
        manifest_path.write_text(json.dumps(manifest, indent=2) + '\n')
        print(f'[iOS evidence] {manifest_path}', file=sys.stderr)
    return result


if __name__ == '__main__':
    sys.exit(main())
