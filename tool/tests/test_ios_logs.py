"""CoreDevice directory export must receive an existing destination."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

SOURCE = Path(__file__).resolve().parents[1] / 'ios_logs.py'


class LogsChecks(unittest.TestCase):
    def test_device_log_destination_exists_before_copy(self):
        with tempfile.TemporaryDirectory(prefix='eros-log-test-') as temporary:
            root = Path(temporary)
            (root / 'tool').mkdir()
            (root / 'bin').mkdir()
            shutil.copyfile(SOURCE, root / 'tool/ios_logs.py')
            fake = root / 'bin/xcrun'
            fake.write_text(
                '#!/usr/bin/env python3\n'
                'import json,os,sys\nfrom pathlib import Path\n'
                'args=sys.argv[1:]\n'
                "if '--json-output' in args:\n"
                "    Path(args[args.index('--json-output')+1]).write_text(json.dumps({'result':{'files':[]}}))\n"
                "if 'copy' in args:\n"
                "    target=Path(args[args.index('--destination')+1])\n"
                "    if not target.is_dir(): sys.exit(44)\n"
                "    if os.environ['FIXTURE_EMPTY']=='0': (target/'fixture.log').write_text('captured App log')\n"
            )
            fake.chmod(0o755)
            for empty in ('0', '1'):
                output = root / ('output-' + empty)
                result = subprocess.run(
                    [sys.executable, str(root / 'tool/ios_logs.py'), 'device',
                     'fixture-UDID', 'com.example.fixture', '--output', str(output)],
                    env=os.environ | {'PATH': str(root / 'bin') + os.pathsep + os.environ['PATH'],
                                      'FIXTURE_EMPTY': empty},
                    capture_output=True, text=True, timeout=8,
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                folder = next(output.glob('diagnostics-*'))
                manifest = json.loads((folder / 'collection.json').read_text())
                copy = next(r for r in manifest['results'] if r['label'] == 'app-log')
                self.assertEqual(copy['exit_code'], 0, manifest)
                self.assertTrue((folder / 'app-log').is_dir())
                self.assertEqual((folder / 'app-log/fixture.log').exists(), empty == '0')


if __name__ == '__main__':
    unittest.main()
