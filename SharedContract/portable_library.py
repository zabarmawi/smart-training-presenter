#!/usr/bin/env python3
"""Data transport only. No analysis, approval logic or platform app implementation."""
import argparse,copy,hashlib,json,pathlib,shutil,sys
P=pathlib.Path

def digest(p):
 h=hashlib.sha256()
 with p.open('rb') as f:
  for b in iter(lambda:f.read(1024*1024),b''):h.update(b)
 return h.hexdigest()
def read(p):return json.loads(p.read_text(encoding='utf-8'))
def write(p,x):
 p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(x,ensure_ascii=False,indent=2),encoding='utf-8')
def semantic(project):
 p=copy.deepcopy(project)
 for m in p['materials']:
  m.pop('path',None);m.pop('renderedPath',None)
 return p

def semantic_hash(p):return hashlib.sha256(json.dumps(semantic(p),ensure_ascii=False,sort_keys=True,separators=(',',':'),allow_nan=False).encode()).hexdigest()
def safe(root,relative):
 if not isinstance(relative,str) or not relative or '\\' in relative or ':' in relative:raise ValueError('Unsafe relative path')
 pure=pathlib.PurePosixPath(relative)
 if pure.is_absolute() or '..' in pure.parts:raise ValueError('Unsafe relative path')
 current=root.resolve()
 for part in pure.parts:
  current=current/part
  if current.is_symlink():raise ValueError('Symlink not allowed')
 if not current.resolve().is_relative_to(root.resolve()):raise ValueError('Path escapes package')
 return current

def empty_target(path):
 if path.exists() and (not path.is_dir() or any(path.iterdir())):raise ValueError('Destination must be absent or empty; existing user data is never overwritten')
 path.mkdir(parents=True,exist_ok=True)
def export(user,out):
 empty_target(out);index=read(user/'Library/index.json');mapping={};physical={}
 for bag in index['bags']:
  p=read(user/'Library/Projects'/(bag['id']+'.stpresenter'))
  for m in p['materials']:
   src=P(m['path']);h=digest(src)
   if h!=m['hash']:raise ValueError('Source version changed: '+src.name)
   rel='Materials/'+h+'/'+src.name
   safe(out,rel)
   if h not in physical:
    destination=safe(out,rel);destination.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(src,destination)
   else:rel=physical[h]
   physical[h]=rel;mapping[str(src)]=rel
   rendered=m.get('renderedPath')
   if rendered and rendered!=str(src):
    rp=P(rendered);rh=digest(rp);rrel='Previews/'+rh+'.pdf';safe(out,rrel).parent.mkdir(exist_ok=True);shutil.copy2(rp,safe(out,rrel));mapping[rendered]=rrel
 def relocate(p):
  p=copy.deepcopy(p)
  for m in p['materials']:
   old=m['path'];m['path']=mapping.get(old) or physical[m['hash']]
   if m.get('renderedPath'):m['renderedPath']=mapping.get(m['renderedPath']) or (m['path'] if m['renderedPath']==old else None)
   if m.get('renderedPath') is None and 'renderedPath' in m:raise ValueError('Unresolved rendered source')
  return p
 project_hashes={};approvals=items=evidence=activities=breaks=0
 for bag in index['bags']:
  f='Library/Projects/'+bag['id']+'.stpresenter';p=read(user/f);q=relocate(p);assert semantic(p)==semantic(q);write(out/f,q);project_hashes[f]=semantic_hash(p)
  for a in p['activities']:
   items+=1;approvals+=bool(a['approved']);activities+=a['kind']=='نشاط';breaks+=a['kind']=='استراحة';evidence+=len(a.get('evidence',[]))
  for f in bag['files']:
   f['relativePath']=physical[f['hash']]
 index['root']='.';write(out/'Library/index.json',index)
 if (user/'Recovery.stpresenter').exists():
  p=read(user/'Recovery.stpresenter');q=relocate(p);assert semantic(p)==semantic(q);write(out/'Recovery.stpresenter',q);project_hashes['Recovery.stpresenter']=semantic_hash(p)
 for name in ['SharingPreferences.json','UIAppearance.json']:
  if (user/name).exists():shutil.copy2(user/name,out/name)
 files={str(f.relative_to(out)).replace('\\','/'):digest(f) for f in sorted(out.rglob('*')) if f.is_file()}
 manifest={'format':'stp-portable-library','version':1,'baseline':'0.6.1-build12','root_resolution':'index.root is relative to package root; restore converts paths only','counts':{'bags':len(index['bags']),'time_items':items,'activities':activities,'breaks':breaks,'approvals':approvals,'evidence':evidence},'project_semantic_sha256':project_hashes,'files_sha256':files,'private':True,'publish_to_github':False}
 write(out/'manifest.json',manifest);return verify(out)

def verify(root):
 manifest=read(root/'manifest.json')
 if manifest.get('format')!='stp-portable-library' or manifest.get('version')!=1:raise ValueError('Unknown package format')
 expected=manifest['files_sha256'];actual={str(f.relative_to(root)).replace('\\','/') for f in root.rglob('*') if f.is_file() and f.name!='manifest.json'}
 if actual!=set(expected):raise ValueError('Missing or unexpected files')
 for f,h in expected.items():
  if digest(safe(root,f))!=h:raise ValueError('SHA mismatch: '+f)
 index=read(root/'Library/index.json');items=approvals=evidence=activities=breaks=0;material_ids=set()
 for bag in index['bags']:
  f='Library/Projects/'+bag['id']+'.stpresenter';p=read(root/f)
  if semantic_hash(p)!=manifest['project_semantic_sha256'][f]:raise ValueError('Decision/project mismatch: '+f)
  if p.get('libraryBagID')!=bag['id']:raise ValueError('Bag identity mismatch')
  mids={m['id']:m for m in p['materials']};aids=[a['id'] for a in p['activities']]
  if len(mids)!=len(p['materials']) or len(aids)!=len(set(aids)):raise ValueError('Duplicate identity')
  for m in mids.values():
   if digest(safe(root,m['path']))!=m['hash']:raise ValueError('Original changed')
   if m.get('renderedPath') and not safe(root,m['renderedPath']).is_file():raise ValueError('Missing rendered source')
  for a in p['activities']:
   items+=1;approvals+=bool(a['approved']);activities+=a['kind']=='نشاط';breaks+=a['kind']=='استراحة';evidence+=len(a.get('evidence',[]))
   if a.get('presentationID') and a['presentationID'] not in mids:raise ValueError('Missing presentation ID')
   for e in a.get('evidence',[]):
    if e['fileID'] not in mids or not 1<=e['page']<=mids[e['fileID']]['pages']:raise ValueError('Unresolved evidence')
  for f in bag['files']:
   if digest(safe(root,f['relativePath']))!=f['hash']:raise ValueError('Library original changed')
 if 'Recovery.stpresenter' in manifest['project_semantic_sha256'] and semantic_hash(read(root/'Recovery.stpresenter'))!=manifest['project_semantic_sha256']['Recovery.stpresenter']:raise ValueError('Recovery decisions changed')
 counts={'bags':len(index['bags']),'time_items':items,'activities':activities,'breaks':breaks,'approvals':approvals,'evidence':evidence}
 if counts!=manifest['counts']:raise ValueError('Counts changed')
 return {'status':'PASS','counts':counts,'files':len(expected),'project_semantics_preserved':True}

def restore(source,target):
 result=verify(source);empty_target(target)
 for folder in ['Materials','Previews','Library']:
  if (source/folder).exists():shutil.copytree(source/folder,target/folder)
 index=read(target/'Library/index.json');index['root']=str(target.resolve());write(target/'Library/index.json',index)
 for f,expected in read(source/'manifest.json')['project_semantic_sha256'].items():
  p=read(source/f)
  for m in p['materials']:
   m['path']=str(safe(target,m['path']))
   if m.get('renderedPath'):m['renderedPath']=str(safe(target,m['renderedPath']))
  assert semantic_hash(p)==expected;write(target/f,p)
 for name in ['SharingPreferences.json','UIAppearance.json']:
  if (source/name).exists():shutil.copy2(source/name,target/name)
 return dict(result,restored_to=str(target.resolve()),mode='paths only; no approvals, durations or identifiers changed')

if __name__=='__main__':
 parser=argparse.ArgumentParser(description=__doc__);sub=parser.add_subparsers(dest='mode',required=True)
 for name in ['export','restore']:
  c=sub.add_parser(name);c.add_argument('source',type=P);c.add_argument('target',type=P)
 sub.add_parser('verify').add_argument('source',type=P);a=parser.parse_args()
 try:result=verify(a.source) if a.mode=='verify' else (export(a.source,a.target) if a.mode=='export' else restore(a.source,a.target));print(json.dumps(result,ensure_ascii=False,indent=2))
 except Exception as error:print('FAIL: '+str(error),file=sys.stderr);sys.exit(1)
