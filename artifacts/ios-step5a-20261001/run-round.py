import json,subprocess,sys,time
from pathlib import Path
root=Path.cwd(); out=root/'artifacts/ios-step5a-20261001'; label=sys.argv[1]; do_lifecycle=len(sys.argv)>2
log=out/f'{label}.log'; dart=root/'.fvm/flutter_sdk/bin/dart'; config=root/'.fvm/flutter_sdk/packages/flutter_tools/.dart_tool/package_config.json'
sim='E3B49F40-CB5C-4CDC-A04D-35E0284103A8'; device='00008132-000278923E99001C'; physical=label.startswith('ipad'); bundle='com.fuhua.erosfe.step5a'
def wait_log(text, start=0):
 deadline=time.monotonic()+55
 while time.monotonic()<deadline:
  if log.exists() and text in log.read_text(errors='replace')[start:]: return
  time.sleep(.2)
 raise RuntimeError(f'{label}: missing log event {text}')
def call(command,**args):
 result=out/f'{label}-{command}.json'
 with (out/'driver-console.log').open('a') as stream:
  subprocess.run([str(dart),f'--packages={config}','tool/ios_baseline_driver.dart',str(log),command,str(result)]+[f'{k}={v}' for k,v in args.items()],stdout=stream,stderr=subprocess.STDOUT,check=True)
 return json.loads(result.read_text())
def capture(name):
 path=out/f'{label}-{name}.png'
 cmd=['xcrun','devicectl','device','capture','screenshot','--device',device,'--destination',str(path),'--timeout','20'] if physical else ['xcrun','simctl','io',sim,'screenshot',str(path)]
 with (out/'capture.log').open('a') as stream: subprocess.run(cmd,stdout=stream,stderr=subprocess.STDOUT,check=True)
def launch(app):
 cmd=['xcrun','devicectl','device','process','launch','--device',device,app] if physical else ['xcrun','simctl','launch',sim,app]
 with (out/f'{label}-lifecycle-process.log').open('a') as stream: subprocess.run(cmd,stdout=stream,stderr=subprocess.STDOUT,check=True)
wait_log('STEP5A_READY')
for command in ('gallery','torrent','share','smoke'):
 r=call(command)
 if command in ('gallery','torrent','share'): capture(command)
if do_lifecycle:
 call('lifecycle_begin',label='background_foreground')
 offset=len(log.read_text(errors="replace"))
 launch('com.apple.Preferences');wait_log('"state":"paused"',offset)
 launch(bundle)
 r=call('lifecycle_end',label='background_foreground');capture('resumed')
print(json.dumps({'run':label,'results':[e for e in r['events'] if e['kind']=='result']},ensure_ascii=False))
