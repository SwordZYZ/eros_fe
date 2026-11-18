"""Runtime regression checks for checkout locking; fixtures never touch real Pods."""
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
import unittest

SOURCE = Path(__file__).resolve().parents[2] / 'scripts' / 'ios_lock.py'


def wait_for(predicate, timeout=8):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if predicate():
            return
        time.sleep(0.03)
    raise TimeoutError('fixture did not become ready')


def orphan_fixture(directory):
    directory = Path(directory)
    # Exactly the observed failure shape: an independently grouped console
    # outlives the command. close_fds=False exercises accidental inheritance.
    child = subprocess.Popen(
        ['/bin/sleep', '60'], start_new_session=True, close_fds=False,
        stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    lock = (directory / '.ios-development.lock').stat()
    retained = False
    for fd in range(3, 256):
        try:
            opened = os.fstat(fd)
            retained |= (opened.st_dev, opened.st_ino) == (lock.st_dev, lock.st_ino)
        except OSError:
            pass
    (directory / 'orphan.json').write_text(json.dumps({
        'pid': child.pid, 'pgid': os.getpgid(child.pid), 'retained_fd': retained,
        'parent_group': os.getpgrp(),
    }))
    return 23


class LockChecks(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='eros-lock-test-')
        self.root = Path(self.temporary.name)
        (self.root / 'scripts').mkdir()
        self.lock = self.root / 'scripts' / 'ios_lock.py'
        shutil.copyfile(os.environ.get('IOS_LOCK_SCRIPT', SOURCE), self.lock)
        self.children = []
        self.handles = []

    def tearDown(self):
        for child in self.children:
            if child.poll() is None:
                child.terminate()
                try:
                    child.wait(timeout=8)
                except subprocess.TimeoutExpired:
                    child.kill()
                    child.wait(timeout=5)
        orphan = self.root / 'orphan.json'
        if orphan.exists():
            try:
                os.kill(json.loads(orphan.read_text())['pid'], signal.SIGKILL)
            except ProcessLookupError:
                pass
        for handle in self.handles:
            handle.close()
        self.temporary.cleanup()

    def start(self, payload, *, no_wait=False, env=None):
        logfile = self.root / f'log-{len(self.children)}.txt'
        handle = logfile.open('w')
        self.handles.append(handle)
        command = [sys.executable, str(self.lock)]
        if no_wait:
            command.append('--no-wait')
        child = subprocess.Popen(command + ['--'] + payload, env=env,
                                 stdout=handle, stderr=handle)
        self.children.append(child)
        return child, logfile

    def hold(self):
        marker = self.root / 'ready'
        child, log = self.start([sys.executable, '-c',
            f"from pathlib import Path; import time; Path({str(marker)!r}).touch(); time.sleep(60)"])
        wait_for(marker.exists)
        return child, log

    def test_busy_refuses_then_releases_on_termination(self):
        owner, _ = self.hold()
        contender, log = self.start([sys.executable, '-c', 'raise SystemExit(0)'], no_wait=True)
        self.assertEqual(contender.wait(timeout=5), 75, log.read_text())
        owner.terminate()
        self.assertEqual(owner.wait(timeout=8), 143)
        contender, log = self.start([sys.executable, '-c', 'raise SystemExit(0)'], no_wait=True)
        self.assertEqual(contender.wait(timeout=5), 0, log.read_text())

    def test_waiting_task_does_not_start_before_owner_exits(self):
        owner, _ = self.hold()
        marker = self.root / 'contender-ready'
        contender, log = self.start([sys.executable, '-c',
            f"from pathlib import Path; Path({str(marker)!r}).touch()"])
        wait_for(lambda: 'waiting' in log.read_text())
        self.assertFalse(marker.exists())
        owner.terminate()
        owner.wait(timeout=8)
        self.assertEqual(contender.wait(timeout=5), 0)
        self.assertTrue(marker.exists())

    def test_waiting_task_can_be_cancelled(self):
        self.hold()
        contender, log = self.start([sys.executable, '-c', 'raise SystemExit(0)'])
        wait_for(lambda: 'waiting' in log.read_text())
        contender.send_signal(signal.SIGINT)
        self.assertEqual(contender.wait(timeout=5), 130)

    def test_failure_keeps_exit_code_and_releases(self):
        child, _ = self.start([sys.executable, '-c', 'raise SystemExit(29)'])
        self.assertEqual(child.wait(timeout=5), 29)
        next_child, _ = self.start([sys.executable, '-c', 'raise SystemExit(0)'], no_wait=True)
        self.assertEqual(next_child.wait(timeout=5), 0)

    def test_nested_wrapper_reuses_live_owner(self):
        child, log = self.start([sys.executable, str(self.lock), '--', sys.executable,
                                 '-c', 'raise SystemExit(17)'])
        self.assertEqual(child.wait(timeout=8), 17, log.read_text())
        self.assertEqual(log.read_text().count('Acquired'), 1)

    def test_stale_session_cannot_bypass_new_lock(self):
        saved = self.root / 'session.json'
        child, _ = self.start([sys.executable, '-c',
            f"import json,os; from pathlib import Path; Path({str(saved)!r}).write_text(json.dumps(dict(os.environ)))"])
        self.assertEqual(child.wait(timeout=5), 0)
        environment = json.loads(saved.read_text())
        self.hold()
        contender, log = self.start([sys.executable, '-c', 'raise SystemExit(0)'],
                                    no_wait=True, env=environment)
        self.assertEqual(contender.wait(timeout=5), 75, log.read_text())

    def test_escaped_console_never_inherits_lock(self):
        child, log = self.start([sys.executable, str(Path(__file__).resolve()),
                                 '--orphan', str(self.root)])
        self.assertEqual(child.wait(timeout=8), 23, log.read_text())
        orphan = json.loads((self.root / 'orphan.json').read_text())
        self.assertNotEqual(orphan['pgid'], orphan['parent_group'])
        os.kill(orphan['pid'], 0)  # Still alive when the next operation starts.
        contender, log = self.start([sys.executable, '-c', 'raise SystemExit(0)'], no_wait=True)
        self.assertEqual(contender.wait(timeout=5), 0, log.read_text())
        self.assertFalse(orphan['retained_fd'])

    def test_other_checkout_is_independent(self):
        self.hold()
        other = self.root / 'other' / 'scripts'
        other.mkdir(parents=True)
        shutil.copyfile(self.lock, other / 'ios_lock.py')
        result = subprocess.run([sys.executable, str(other / 'ios_lock.py'), '--no-wait',
                                 '--', sys.executable, '-c', 'raise SystemExit(0)'],
                                capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == '__main__':
    if len(sys.argv) > 1 and sys.argv[1] == '--orphan':
        sys.exit(orphan_fixture(sys.argv[2]))
    unittest.main()
