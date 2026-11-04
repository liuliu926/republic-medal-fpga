"""Verify package file hashes and local project dependencies; never access a board."""
from pathlib import Path
import hashlib,json,sys,xml.etree.ElementTree as ET

ROOT=Path(__file__).resolve().parent
def digest(p):
    h=hashlib.sha256()
    with p.open('rb') as f:
        for block in iter(lambda:f.read(1024*1024),b''):h.update(block)
    return h.hexdigest()

def main():
    failures=[];count=0
    for line in (ROOT/'MANIFEST.sha256').read_text(encoding='utf-8').splitlines():
        expected,name=line.split('  ',1)
        path=(ROOT/name).resolve()
        if not path.is_relative_to(ROOT.resolve()) or not path.is_file() or digest(path)!=expected:
            failures.append(name)
        count+=1
    prj=ROOT/'fpga/run/medal_kiosk_720p.prj'
    refs=[]
    for item in ET.parse(prj).iter('File'):
        if not item.get('Path'):continue
        p=(prj.parent/item.get('Path')).resolve()
        if not p.is_relative_to((ROOT/'fpga').resolve()) or not p.is_file():failures.append(item.get('Path'))
        refs.append(item.get('Path'))
    assets=json.loads((ROOT/'tf_manifest.json').read_text(encoding='utf-8'))['files']
    for row in assets:
        p=ROOT/'tf_card'/row['file']
        if not p.is_file() or p.stat().st_size!=row['bytes'] or digest(p)!=row['sha256']:
            failures.append('TF:'+row['file'])
    print(json.dumps({'ok':not failures,'files_checked':count,'project_references':len(refs),'tf_files':len(assets),'failures':failures},ensure_ascii=False,indent=2))
    return 1 if failures else 0
if __name__=='__main__':raise SystemExit(main())
