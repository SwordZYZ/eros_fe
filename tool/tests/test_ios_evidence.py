"""Evidence collection must return the command status even with orphaned pipes."""
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import unittest

SOURCE = Path(__file__).resolve().parents[1] / 'ios_evidence.py'


class EvidenceChecks(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='eros-evidence-')
        self.root = Path(self.temporary.name)
        (self.root / 'tool').mkdir()
        self.capture = self.root / 'tool/ios_evidence.py'
        shutil.copyfile(SOURCE, self.capture)

    def tearDown(self):
        pidfile = self.root / 'orphan.pid'
        if pidfile.exists():
            try:
                os.kill(int(pidfile.read_text()), signal.SIGKILL)
            except ProcessLookupError:
                pass
        self.temporary.cleanup()

    def invoke(self, command):
        result = subprocess.run([sys.executable, str(self.capture), '--label', 'check',
                                 '--output', str(self.root / 'output'), '--'] + command,
                                capture_output=True, text=True, timeout=8)
        manifest = json.loads(next((self.root / 'output').glob('*.json')).read_text())
        return result, manifest

    def test_failure_is_recorded_and_propagated(self):
        result, manifest = self.invoke([sys.executable, '-c',
                                        "import sys; print('assertion failed'); sys.exit(42)"])
        self.assertEqual(result.returncode, 42)
        self.assertEqual(manifest['exit_code'], 42)
        self.assertEqual(manifest['status'], 'FAIL')
        self.assertIn('assertion failed', result.stdout)

    def test_missing_command_is_recorded(self):
        result, manifest = self.invoke(['/no-such-eros-command'])
        self.assertEqual(result.returncode, 127)
        self.assertEqual(manifest['status'], 'FAIL')

    def test_escaped_console_pipe_does_not_hold_capture_open(self):
        payload = ("import subprocess; from pathlib import Path; "
                   "p=subprocess.Popen(['/bin/sleep','60'],start_new_session=True); "
                   f"Path({str(self.root / 'orphan.pid')!r}).write_text(str(p.pid)); "
                   "print('main command returned',flush=True)")
        result, manifest = self.invoke([sys.executable, '-c', payload])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(manifest['status'], 'PASS')
        os.kill(int((self.root / 'orphan.pid').read_text()), 0)


if __name__ == '__main__':
    unittest.main()
