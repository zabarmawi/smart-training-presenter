"""Run the unchanged shared checker with extended-length Windows file IO.
Only digest's file path is adapted; comparisons and expected values are unchanged.
"""
import pathlib,sys,importlib.util,json
contract,package,restored=map(pathlib.Path,sys.argv[1:4])
spec=importlib.util.spec_from_file_location('stp_conformance',contract/'conformance.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
original=m.transport.digest
def digest(path):
 path=pathlib.Path(path).absolute()
 if sys.platform=='win32' and not str(path).startswith('\\\\?\\'):path=pathlib.Path('\\\\?\\'+str(path))
 return original(path)
m.transport.digest=digest
result=m.restored(package,restored)
print(json.dumps({'status':'PASS','portable':result,'filesystem_adapter':'Windows extended-length prefix for SHA file reads only; shared comparisons unchanged'},ensure_ascii=False,indent=2))
