import pathlib,hashlib,json,unicodedata,sys
root=pathlib.Path(sys.argv[1]).resolve(); manifest=json.loads((root/'HANDOFF-SHA256.json').read_text('utf8'))
normalize=lambda s:unicodedata.normalize('NFC',s)
files=[x for x in root.rglob('*') if x.is_file() and x.name!='HANDOFF-SHA256.json' and '__pycache__' not in x.parts]
actual={}; aliases=[]; failures=[]
for f in files:
 key=normalize(f.relative_to(root).as_posix())
 if key in actual:raise ValueError('Unicode collision: '+key)
 actual[key]=f
for rel,want in manifest.items():
 f=actual.get(normalize(rel))
 if f is None:failures.append({'file':rel,'reason':'missing'});continue
 with f.open('rb') as stream:got=hashlib.file_digest(stream,'sha256').hexdigest()
 if got!=want:failures.append({'file':rel,'reason':'hash mismatch'})
 if f.relative_to(root).as_posix()!=rel:aliases.append({'manifest_path':rel,'physical_path':f.relative_to(root).as_posix(),'sha256':got})
extra=set(actual)-{normalize(x) for x in manifest}
failures += [{'file':x,'reason':'extra'} for x in sorted(extra)]
result={'status':'FAIL' if failures else 'PASS_WITH_UNICODE_NAME_ALIASES','expected_files':len(manifest),'actual_files':len(files),'normalization':'NFC alias lookup only; original files not modified','aliases':aliases,'failures':failures,'handoff_manifest_sha256':hashlib.sha256((root/'HANDOFF-SHA256.json').read_bytes()).hexdigest()}
print(json.dumps(result,ensure_ascii=False,indent=2));sys.exit(bool(failures))
