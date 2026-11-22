"""Exercise CI orchestration and failure propagation without an SDK or device."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class CIEntryChecks(unittest.TestCase):
    def exercise(self, test_status, *, release=False):
        with tempfile.TemporaryDirectory(prefix='eros-ci-entry-') as temporary:
            root = Path(temporary)
            for name in ('scripts', 'tool', 'tool/tests', 'ios', 'bin'):
                (root / name).mkdir(parents=True, exist_ok=True)
            (root / 'tool/tests/test_fixture.py').write_text(
                'import unittest\nclass Fixture(unittest.TestCase):\n'
                '    def test_ready(self): self.assertTrue(True)\n')
            for name in ('scripts/ios_dev.sh', 'scripts/ios_common.sh', 'scripts/ios_lock.py', 'tool/ios_evidence.py'):
                shutil.copyfile(ROOT / name, root / name)
            for name in ('pubspec.lock', 'Gemfile.lock', 'ios/Podfile.lock'):
                (root / name).write_text('fixed fixture lock\n')
            for name, stage in (('scripts/ios_prepare.sh', 'prepare'), ('scripts/ios_env_check.sh', 'check')):
                (root / name).write_text('printf "' + stage + '\\n" >> "$STAGES"\n')
            (root / 'tool/ios_simulator.py').write_text("print('fixture-UDID')\n")
            flutter = root / 'bin/flutter'
            flutter.write_text('#!/usr/bin/env python3\nimport os,sys\n'
                              "if sys.argv[1] == '--version': print('Flutter 3.47.3'); sys.exit(0)\n"
                              "with open(os.environ['STAGES'],'a') as f: f.write(sys.argv[1]+'\\n')\n"
                              "sys.exit(int(os.environ['TEST_STATUS']) if sys.argv[1]=='test' else 0)\n")
            flutter.chmod(0o755)
            bundle = root / 'bin/bundle'
            bundle.write_text('#!/bin/bash\nshift\nexec "$@"\n')
            bundle.chmod(0o755)
            stages = root / 'stages'
            env = os.environ | {'PATH': str(root / 'bin') + os.pathsep + os.environ['PATH'],
                                'IOS_FLUTTER_BIN': str(flutter), 'STAGES': str(stages),
                                'TEST_STATUS': str(test_status), 'IOS_LOG_DIR': str(root / 'output')}
            command = ['bash', str(root / 'scripts/ios_dev.sh'), 'ci']
            if release:
                command.append('--release')
            result = subprocess.run(command,
                                    cwd=root, env=env, capture_output=True, text=True, timeout=20)
            self.assertEqual(result.returncode, test_status, result.stdout + result.stderr)
            expected_stages = ['prepare', 'check']
            if release:
                expected_stages.append('build')
            expected_stages.append('test')
            self.assertEqual(stages.read_text().splitlines(), expected_stages)
            manifests = [json.loads(p.read_text()) for p in (root / 'output').glob('*.json')]
            smoke = next(m for m in manifests if m['operation'] == 'smoke')
            self.assertEqual(smoke['exit_code'], test_status)
            self.assertEqual(smoke['status'], 'FAIL' if test_status else 'PASS')
            self.assertIn('Starting flutter test command', (root / 'output' / smoke['log']).read_text())

    def test_ci_builds_only_the_smoke_app(self):
        self.exercise(0)

    def test_release_ci_also_builds_the_production_entry_point(self):
        self.exercise(0, release=True)

    def test_failing_smoke_fails_ci(self):
        self.exercise(42)


if __name__ == '__main__':
    unittest.main()
