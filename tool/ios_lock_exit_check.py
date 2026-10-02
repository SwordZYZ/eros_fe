#!/usr/bin/env python3
"""Check the macOS lock cleanup path using disposable processes, without Pods."""

import argparse
import errno
import importlib.util
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import time
from unittest import mock


def wait_for(predicate, timeout=10):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if predicate():
            return
        time.sleep(0.05)
    raise TimeoutError('Timed out waiting for fixture state')


def fixture(directory, mode):
    """Retain a zombie outside the supervised group until the check releases it."""
    directory = Path(directory)
    group = os.getpgrp()
    reaper = os.fork()
    if reaper == 0:
        os.setpgid(0, 0)
        # Only the supervisor should keep the lock during cleanup in this check.
        os.close(int(os.environ['EROS_IOS_LOCK_FD']))
        worker = os.fork()
        if worker == 0:
            os.setpgid(0, group)
            if mode != 'term':
                signal.signal(signal.SIGTERM, signal.SIG_IGN)
            (directory / 'worker.json').write_text(json.dumps({
                'pid': os.getpid(), 'pgid': group, 'reaper': os.getppid(),
            }))
            while True:
                signal.pause()
        try:
            wait_for(lambda: (directory / 'reap').exists(), timeout=20)
        finally:
            try:
                os.kill(worker, signal.SIGKILL)
            except ProcessLookupError:
                pass
            os.waitpid(worker, 0)
        os._exit(0)
    wait_for(lambda: (directory / 'worker.json').exists())
    if mode == 'interrupt':
        while True:
            signal.pause()
    os._exit(23)


def process_state(pid):
    result = subprocess.run(
        ['/bin/ps', '-p', str(pid), '-o', 'stat='],
        capture_output=True, text=True, check=False, timeout=2,
    )
    if result.returncode not in (0, 1):
        raise RuntimeError(result.stderr)
    return result.stdout.strip()


def runtime_case(lock_script, mode, expect_regression):
    with tempfile.TemporaryDirectory(prefix='eros-lock-exit-') as temporary:
        directory = Path(temporary)
        scripts = directory / 'scripts'
        scripts.mkdir()
        copied = scripts / 'ios_lock.py'
        shutil.copyfile(lock_script, copied)
        stderr_path = directory / 'supervisor.stderr'
        child = None
        worker = None
        observation = {'case': mode}
        with stderr_path.open('w') as stderr:
            child = subprocess.Popen([
                sys.executable, str(copied), '--', sys.executable,
                str(Path(__file__).resolve()), '--fixture', str(directory), mode,
            ], stdout=subprocess.DEVNULL, stderr=stderr)
            try:
                wait_for(lambda: (directory / 'worker.json').exists())
                worker = json.loads((directory / 'worker.json').read_text())
                observation['fixture'] = worker
                if mode != 'term':
                    if mode == 'interrupt':
                        child.send_signal(signal.SIGTERM)
                    wait_for(lambda: 'Stopping remaining child' in stderr_path.read_text())
                    competing = subprocess.run([
                        sys.executable, str(copied), '--no-wait', '--',
                        sys.executable, '-c', 'raise SystemExit(0)',
                    ], capture_output=True, text=True, timeout=5)
                    observation['during_cleanup_exit'] = competing.returncode
                    assert competing.returncode == 75, competing.stderr
                    assert not process_state(worker['pid']).startswith('Z')
                child.wait(timeout=10)
                observation['exit_code'] = child.returncode
                observation['stderr'] = stderr_path.read_text()
                observation['worker_state_after_exit'] = process_state(worker['pid'])
                assert observation['worker_state_after_exit'].startswith('Z'), observation
                try:
                    os.killpg(worker['pgid'], 0)
                except PermissionError as error:
                    observation['zombie_group_probe_errno'] = error.errno
                else:
                    raise AssertionError('Fixture did not produce macOS EPERM')
                assert observation['zombie_group_probe_errno'] == errno.EPERM
                if expect_regression:
                    assert child.returncode != 23 and 'PermissionError' in observation['stderr']
                    observation['status'] = 'REPRODUCED'
                else:
                    expected = 143 if mode == 'interrupt' else 23
                    assert child.returncode == expected, observation
                    assert 'Traceback' not in observation['stderr'], observation
                    competing = subprocess.run([
                        sys.executable, str(copied), '--no-wait', '--',
                        sys.executable, '-c', 'raise SystemExit(0)',
                    ], capture_output=True, text=True, timeout=5)
                    observation['after_cleanup_exit'] = competing.returncode
                    assert competing.returncode == 0, competing.stderr
                    observation['status'] = 'PASS'
            finally:
                # Release only this fixture's reaper; never target existing groups.
                (directory / 'reap').touch()
                if child.poll() is None:
                    child.send_signal(signal.SIGTERM)
                    child.wait(timeout=10)
                if worker is not None:
                    wait_for(lambda: not process_state(worker['reaper']) or
                             process_state(worker['reaper']).startswith('Z'))
        return observation


def boundary_cases(lock_script):
    spec = importlib.util.spec_from_file_location('ios_lock_under_check', lock_script)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    results = []
    denied = PermissionError(errno.EPERM, 'controlled permission denial')
    for label, snapshot, expected in (
        ('zombie_only', '123 Z\n123 Z+\n', False),
        ('live_and_zombie', '123 Z\n123 S\n', True),
        ('group_disappeared', '999 S\n', False),
        ('snapshot_empty', '', True),
        ('snapshot_malformed', 'not-a-group Z\n', True),
    ):
        with mock.patch.object(module.os, 'killpg', side_effect=denied), \
                mock.patch.object(module.subprocess, 'run', return_value=
                                  subprocess.CompletedProcess([], 0, snapshot, '')):
            assert module.group_exists(123) is expected, label
            module.signal_group(123, signal.SIGTERM)
        results.append({'case': label, 'status': 'PASS', 'group_exists': expected})
    for label, failure in (
        ('snapshot_denied', PermissionError(errno.EPERM, 'ps denied')),
        ('snapshot_timeout', subprocess.TimeoutExpired('ps', 2)),
        ('snapshot_failed', subprocess.CalledProcessError(1, 'ps')),
    ):
        with mock.patch.object(module.os, 'killpg', side_effect=denied), \
                mock.patch.object(module.subprocess, 'run', side_effect=failure):
            assert module.group_exists(123) is True, label
            module.signal_group(123, signal.SIGTERM)
        results.append({'case': label, 'status': 'PASS', 'group_exists': True})
    return results


def main():
    if len(sys.argv) > 1 and sys.argv[1] == '--fixture':
        fixture(sys.argv[2], sys.argv[3])
        return
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--lock-script', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--expect-regression', action='store_true')
    args = parser.parse_args()
    if sys.platform != 'darwin':
        parser.error('This check exercises the macOS zombie/EPERM path')
    modes = ['term'] if args.expect_regression else ['term', 'kill', 'interrupt']
    results = [runtime_case(args.lock_script, mode, args.expect_regression) for mode in modes]
    if not args.expect_regression:
        results.extend(boundary_cases(args.lock_script))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(results, indent=2) + '\n')
    for result in results:
        print(result['case'], result['status'])


if __name__ == '__main__':
    main()
