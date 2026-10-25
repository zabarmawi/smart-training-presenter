#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP="${1:-$PWD/dist/V0.6.0-mac-intel/Smart Training Presenter.app}"
OUT="${PRESENTER_TEST_OUTPUT:-$(mktemp -d "$PWD/build/privacy-acceptance.XXXXXX")}"
python3 - "$APP" "$OUT" "$PWD" <<'PYTEST'
import os,pathlib,shutil,subprocess,sys,json,time,hashlib
app,out,root=map(pathlib.Path,sys.argv[1:]);summary={}
user=pathlib.Path.home()/'Library/Application Support/SmartTrainingPresenter'
modes=[('privacy','--privacy-acceptance','تجربة العرض.stpresenter')]
if os.environ.get('PRESENTER_SKIP_POWERPOINT')!='1':modes.append(('powerpoint','--powerpoint-acceptance','editable-arabic.pptx'))
for name,mode,fixture in modes:
 folder=out/name;folder.mkdir(parents=True,exist_ok=True)
 if (folder/'results.txt').exists():raise RuntimeError('Use a fresh test output directory')
 if not (folder/'Library').exists():shutil.copytree(user/'Library',folder/'Library')
 legacy=user/'RemoteWorkspace-v05.json'
 if legacy.exists() and not (folder/legacy.name).exists():shutil.copy2(legacy,folder/legacy.name)
 env=os.environ.copy();env.update(PRESENTER_CACHE=str(folder/'cache'),PRESENTER_DISABLE_OCR='1',PRESENTER_CONVERSION_LOG=str(folder/'conversion.log'))
 samples=[];deadline=time.monotonic()+300
 with (folder/'launch.log').open('w') as log:
  process=subprocess.Popen([str(app/'Contents/MacOS/SmartTrainingPresenter'),mode,str(folder),str(root/'Fixtures'/fixture)],env=env,stdout=log,stderr=log)
  while process.poll() is None:
   result=subprocess.run(['/usr/sbin/lsof','-nP','-a','-p',str(process.pid),'-iTCP','-sTCP:LISTEN','-Fn'],capture_output=True,text=True,timeout=6)
   samples.append({'pid':process.pid,'returncode':result.returncode,'listeners':result.stdout.strip(),'error':result.stderr.strip()})
   if time.monotonic()>deadline:
    process.terminate()
    try:process.wait(timeout=3)
    except subprocess.TimeoutExpired:process.kill();process.wait()
    break
   try:process.wait(timeout=2)
   except subprocess.TimeoutExpired:pass
 files=[folder/'results.txt']+([folder/'powerpoint-results.txt'] if name=='powerpoint' else [])
 lines=[line for file in files if file.exists() for line in file.read_text().splitlines()]
 check={'exit':process.returncode,'pass':sum(x.startswith('PASS:') for x in lines),'fail':[x for x in lines if x.startswith('FAIL:')],'notes':[x for x in lines if x.startswith('NOT TESTED:')],'listener_samples':len(samples),'no_tcp_listeners':bool(samples) and all(x['returncode']==1 and not x['listeners'] and not x['error'] for x in samples)}
 if name=='powerpoint' and not any('PASS: PowerPoint confirmed closed' in x for x in lines):check['notes'].append('Cold start was not confirmed')
 (folder/'listener-samples.json').write_text(json.dumps(samples,indent=2));summary[name]=check;print(name,check,flush=True)
summary['binary_sha256']=hashlib.sha256((app/'Contents/MacOS/SmartTrainingPresenter').read_bytes()).hexdigest()
(out/'summary.json').write_text(json.dumps(summary,indent=2,ensure_ascii=False));print('Evidence:',out,flush=True)
if any(v['exit'] or v['fail'] or not v['pass'] or not v['no_tcp_listeners'] for v in summary.values() if isinstance(v,dict)):sys.exit(1)
PYTEST
