#!/usr/bin/env python3
"""Run on either OS; compares target output with frozen Swift goldens. Not a Windows application."""
import argparse,copy,json,pathlib,shutil,tempfile,sys,importlib.util
sys.dont_write_bytecode=True
ROOT=pathlib.Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('portable_library',ROOT/'portable_library.py');transport=importlib.util.module_from_spec(spec);spec.loader.exec_module(transport)
def same(a,b,path='root'):
 if isinstance(a,(int,float)) and not isinstance(a,bool):
  if not isinstance(b,(int,float)) or abs(a-b)>0.000001:raise AssertionError(path+': numeric mismatch')
 elif isinstance(a,dict):
  if not isinstance(b,dict) or set(a)!=set(b):raise AssertionError(path+': keys mismatch')
  for k in a:same(a[k],b[k],path+'/'+k)
 elif isinstance(a,list):
  if not isinstance(b,list) or len(a)!=len(b):raise AssertionError(path+': length mismatch')
  for i,(x,y) in enumerate(zip(a,b)):same(x,y,path+'/'+str(i))
 elif a!=b:raise AssertionError(path+': value mismatch')
def restored(package,user):
 result=transport.verify(package);m=transport.read(package/'manifest.json')
 for f,h in m['project_semantic_sha256'].items():
  p=transport.read(user/f)
  if transport.semantic_hash(p)!=h:raise AssertionError('Restored semantic decisions differ: '+f)
  for material in p['materials']:
   if transport.digest(pathlib.Path(material['path']))!=material['hash']:raise AssertionError('Restored material changed')
  for a in p['activities']:
   mids={v['id']:v for v in p['materials']}
   for e in a.get('evidence',[]):
    if e['fileID'] not in mids or not 1<=e['page']<=mids[e['fileID']]['pages']:raise AssertionError('Restored evidence lost')
 return result

def self_test():
 good=ROOT/'fixtures/synthetic-portable';transport.verify(good);count=1
 # Each attack must be rejected without writing to the real approved dataset.
 for label,change in [
  ('approval',lambda p:p['activities'][0].update(approved=False)),
  ('duration',lambda p:p['activities'][0].update(duration=1)),
  ('activity ID',lambda p:p['activities'][0].update(id='different')),
  ('source ID',lambda p:p['activities'][0]['evidence'][0].update(fileID='missing')),
  ('source page',lambda p:p['activities'][0]['evidence'][0].update(page=100)),
  ('material path escape',lambda p:p['materials'][0].update(path='../outside'))]:
  with tempfile.TemporaryDirectory(prefix='stp-contract-') as tmp:
   folder=pathlib.Path(tmp)/'case';shutil.copytree(good,folder);f=folder/'Library/Projects/synthetic-bag.stpresenter';p=transport.read(f);change(p);transport.write(f,p)
   manifest=transport.read(folder/'manifest.json');manifest['files_sha256']['Library/Projects/synthetic-bag.stpresenter']=transport.digest(f);transport.write(folder/'manifest.json',manifest)
   try:transport.verify(folder)
   except (ValueError,KeyError):count+=1
   else:raise AssertionError('Accepted corrupt '+label)
 with tempfile.TemporaryDirectory(prefix='stp-contract-') as tmp:
  restored(good,pathlib.Path(transport.restore(good,pathlib.Path(tmp)/'restored')['restored_to']));count+=1
  try:transport.restore(good,pathlib.Path(tmp)/'restored')
  except ValueError:count+=1
  else:raise AssertionError('Overwrote existing destination')
 for invalid in ['../escape','C:/absolute','/absolute','folder\\escape']:
  try:transport.safe(good,invalid)
  except ValueError:count+=1
  else:raise AssertionError('Accepted unsafe path')
 return {'status':'PASS','checks':count,'method':'synthetic-only negative transport tests; no user data modified'}

if __name__=='__main__':
 ap=argparse.ArgumentParser();ap.add_argument('--portable',type=pathlib.Path);ap.add_argument('--restored',type=pathlib.Path);ap.add_argument('--timer-results',type=pathlib.Path);ap.add_argument('--self-test',action='store_true');a=ap.parse_args();results={}
 try:
  if a.self_test:results['self_test']=self_test()
  if a.portable:results['portable']=restored(a.portable,a.restored) if a.restored else transport.verify(a.portable)
  if a.timer_results:
   same(transport.read(ROOT/'timer-expected.json'),transport.read(a.timer_results));results['timer']={'status':'PASS','scenarios':len(transport.read(a.timer_results))}
  if not results:raise ValueError('Choose a test')
  print(json.dumps(results,ensure_ascii=False,indent=2))
 except Exception as e:print('FAIL: '+str(e),file=sys.stderr);sys.exit(1)
