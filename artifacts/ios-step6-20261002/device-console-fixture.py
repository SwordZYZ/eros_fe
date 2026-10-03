"""Launch the installed test App suspended; leave a real console in a new group."""
import json
import pathlib
import subprocess
import sys
import time

root = pathlib.Path(sys.argv[1])
output = pathlib.Path(sys.argv[2])
output.mkdir(parents=True, exist_ok=True)
command = ['xcrun', 'devicectl', 'device', 'process', 'launch', '--device',
           '00008132-000278923E99001C', '--start-stopped', '--console',
           '--terminate-existing', 'com.fuhua.erosfe.step6']
with (output / 'console.log').open('w') as log:
    child = subprocess.Popen(command, stdin=subprocess.DEVNULL, stdout=log,
                             stderr=subprocess.STDOUT, close_fds=False,
                             start_new_session=True)
    for _ in range(300):
        if child.poll() is not None:
            raise SystemExit('console failed: ' + (output / 'console.log').read_text())
        if 'Waiting for the application to terminate' in (output / 'console.log').read_text():
            break
        time.sleep(0.1)
    else:
        child.terminate()
        raise SystemExit('console readiness timeout')
    (output / 'console.json').write_text(json.dumps({'pid': child.pid,
        'command': command, 'lock_root': str(root)}, indent=2) + '\n')
raise SystemExit(23)
