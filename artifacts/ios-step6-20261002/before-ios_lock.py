#!/usr/bin/env python3
"""Hold a checkout-local lock for an entire command and its child process group."""

import argparse
import errno
import fcntl
import json
import os
from pathlib import Path
import signal
import stat
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parent.parent
LOCK_PATH = ROOT / '.ios-development.lock'
FD_ENV = 'EROS_IOS_LOCK_FD'
ROOT_ENV = 'EROS_IOS_LOCK_ROOT'
BUSY_EXIT = 75
INTERRUPT_GRACE = 2.0


def inherited_lock_fd():
    """Verify the inherited descriptor, rather than trusting an environment flag."""
    if os.environ.get(ROOT_ENV) != str(ROOT):
        return None
    try:
        fd = int(os.environ[FD_ENV])
        if fd < 3:
            return None
        opened = os.fstat(fd)
        current = LOCK_PATH.stat()
        if not stat.S_ISREG(opened.st_mode):
            return None
        if (opened.st_dev, opened.st_ino) != (current.st_dev, current.st_ino):
            return None
        # Reacquiring through the same inherited open-file description is safe.
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        return fd
    except (KeyError, ValueError, OSError):
        return None


def group_exists(pgid):
    """Return whether cleanup must keep waiting for this process group."""
    try:
        os.killpg(pgid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        # Darwin can return EPERM for a group containing only zombies. Those
        # processes have exited and cannot access Pods, but EPERM alone cannot
        # distinguish them from live processes we are not allowed to signal.
        try:
            snapshot = subprocess.run(
                ['/bin/ps', '-axo', 'pgid=,stat='],
                capture_output=True, text=True, check=True, timeout=2,
            )
            rows = snapshot.stdout.splitlines()
            if not rows:
                raise ValueError('empty process snapshot')
            for row in rows:
                group, state = row.split()
                if int(group) == pgid and not state.startswith('Z'):
                    return True
        except (OSError, subprocess.SubprocessError, ValueError) as error:
            print(f'[iOS lock] Cannot verify process group {pgid}: {error}; '
                  'keeping the lock until cleanup can be confirmed.', file=sys.stderr)
            return True
        print(f'[iOS lock] Process group {pgid} has no live members after EPERM.',
              file=sys.stderr)
        return False


def signal_group(pgid, signum):
    try:
        os.killpg(pgid, signum)
    except ProcessLookupError:
        pass
    except PermissionError:
        # The group may have become zombie-only between checking and signalling.
        # If any live member remains (or inspection fails), finish_group keeps
        # waiting with the lock held rather than crashing and releasing it.
        if group_exists(pgid):
            print(f'[iOS lock] Cannot send signal {signum} to process group {pgid}; '
                  'keeping the lock while its live members remain.', file=sys.stderr)


def finish_group(child):
    """Do not unlock while a surviving build/link child can still access Pods."""
    pgid = child.pid
    child.poll()  # Reap the immediate child, including exceptional exit paths.
    if not group_exists(pgid):
        return
    print('[iOS lock] Stopping remaining child processes before unlocking.', file=sys.stderr)
    signal_group(pgid, signal.SIGTERM)
    deadline = time.monotonic() + INTERRUPT_GRACE
    while group_exists(pgid) and time.monotonic() < deadline:
        child.poll()
        time.sleep(0.05)
    if group_exists(pgid):
        signal_group(pgid, signal.SIGKILL)
        # Keep the lock until no live member remains, including delayed termination.
        while group_exists(pgid):
            child.poll()
            time.sleep(0.05)


def holder_description(fd):
    try:
        holder = json.loads(os.pread(fd, 4096, 0))
        return f"PID {holder['pid']} ({holder['command']})"
    except (ValueError, KeyError, TypeError, OSError):
        return 'another iOS operation'


def run_locked(command, no_wait):
    inherited = inherited_lock_fd()
    if inherited is not None:
        os.set_inheritable(inherited, True)
        try:
            os.execvp(command[0], command)
        except OSError as error:
            print(f'[iOS lock] Cannot start command: {error}', file=sys.stderr)
            return 127

    child = None
    interrupted = None
    interrupt_time = None

    def on_signal(signum, _frame):
        nonlocal interrupted, interrupt_time
        if interrupted is None:
            interrupted = signum
            interrupt_time = time.monotonic()
        if child is not None:
            signal_group(child.pid, signum)

    previous_handlers = {}
    for signum in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
        previous_handlers[signum] = signal.signal(signum, on_signal)

    fd = None
    try:
        fd = os.open(LOCK_PATH, os.O_RDWR | os.O_CREAT, 0o600)
        if fd < 3:  # Keep the lock separate even when a caller closed stdin/out/err.
            original_fd = fd
            fd = fcntl.fcntl(original_fd, fcntl.F_DUPFD_CLOEXEC, 3)
            os.close(original_fd)
        announced_wait = False
        while True:
            if interrupted is not None:
                return 128 + interrupted
            try:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except OSError as error:
                if error.errno not in (errno.EACCES, errno.EAGAIN):
                    raise
                holder = holder_description(fd)
                if no_wait:
                    print(f'[iOS lock] Checkout busy: {holder}; command not started.', file=sys.stderr)
                    return BUSY_EXIT
                if not announced_wait:
                    print(f'[iOS lock] Checkout busy: {holder}; waiting. Ctrl-C cancels.', file=sys.stderr)
                    announced_wait = True
                time.sleep(0.1)

        metadata = json.dumps({'pid': os.getpid(), 'command': Path(command[0]).name}).encode()
        os.ftruncate(fd, 0)
        os.pwrite(fd, metadata + b'\n', 0)
        print(f'[iOS lock] Acquired {LOCK_PATH}; held until this command/session ends.', file=sys.stderr)
        if interrupted is not None:
            return 128 + interrupted
        environment = os.environ.copy()
        environment[FD_ENV] = str(fd)
        environment[ROOT_ENV] = str(ROOT)
        child = subprocess.Popen(
            command, env=environment, pass_fds=(fd,), start_new_session=True,
        )
        if interrupted is not None:
            signal_group(child.pid, interrupted)
        while child.poll() is None:
            if interrupted is not None and time.monotonic() - interrupt_time >= INTERRUPT_GRACE:
                signal_group(child.pid, signal.SIGKILL)
            try:
                child.wait(timeout=0.1)
            except subprocess.TimeoutExpired:
                pass
        result = child.returncode
        return 128 + interrupted if interrupted is not None else (128 - result if result < 0 else result)
    except OSError as error:
        print(f'[iOS lock] Cannot start or lock operation: {error}', file=sys.stderr)
        return 127
    finally:
        if child is not None:
            finish_group(child)
        if fd is not None:
            os.close(fd)
        for signum, handler in previous_handlers.items():
            signal.signal(signum, handler)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true', help='silently verify an inherited lock')
    parser.add_argument('--no-wait', action='store_true', help='exit 75 if this checkout is busy')
    parser.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    if args.check:
        return 0 if inherited_lock_fd() is not None else 1
    command = args.command
    if command and command[0] == '--':
        command = command[1:]
    if not command:
        parser.error('specify a command after --')
    return run_locked(command, args.no_wait)


if __name__ == '__main__':
    sys.exit(main())
