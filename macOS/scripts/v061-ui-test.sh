#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 - "$1" "$2" "$PWD" <<'PY'
import os,pathlib,shutil,subprocess,sys,time,json
app,out,root=map(pathlib.Path,sys.argv[1:]);out.mkdir(parents=True,exist_ok=False)
shutil.copytree(root/'build/v061/before/User/Library',out/'Library')
env=os.environ.copy();env.update(PRESENTER_CACHE=str(out/'cache'),PRESENTER_DISABLE_OCR='1')
binary=app/'Contents/MacOS/SmartTrainingPresenter'
samples=[]
with (out/'launch.log').open('w') as log:
 p=subprocess.Popen([str(binary),'--v061-acceptance',str(out),str(root/'Fixtures/تجربة العرض.stpresenter')],env=env,stdout=log,stderr=log)
 deadline=time.monotonic()+240
 while p.poll() is None:
  r=subprocess.run(['/usr/sbin/lsof','-nP','-a','-p',str(p.pid),'-iTCP','-Fn'],capture_output=True,text=True,timeout=5)
  samples.append({'status':r.returncode,'connections':r.stdout.strip(),'error':r.stderr.strip()})
  if time.monotonic()>deadline:
   p.terminate()
   try:p.wait(timeout=3)
   except subprocess.TimeoutExpired:p.kill();p.wait()
   break
  try:p.wait(timeout=2)
  except subprocess.TimeoutExpired:pass
result=p.returncode
with (out/'restart.log').open('w') as log:
 p=subprocess.run([str(binary),'--v061-theme-restore',str(out/'theme-restore.txt')],env=env,stdout=log,stderr=log,timeout=30)
lines=(out/'results.txt').read_text().splitlines() if (out/'results.txt').exists() else []
if (out/'theme-restore.txt').exists():lines+=(out/'theme-restore.txt').read_text().splitlines()
summary={'exit':result,'restart_exit':p.returncode,'pass':sum(x.startswith('PASS:') for x in lines),'fail':[x for x in lines if x.startswith('FAIL:')],'notes':[x for x in lines if x.startswith('NOT TESTED:')],'network_samples':len(samples),'no_tcp':bool(samples) and all(x['status']==1 and not x['connections'] and not x['error'] for x in samples)}
(out/'network.json').write_text(json.dumps(samples,indent=2));(out/'summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2));print(summary)
if result or p.returncode or summary['fail'] or not summary['no_tcp']:sys.exit(1)
PY
