"""Preserve and inspect TF metadata without modifying the volume."""
import json,struct,hashlib
from pathlib import Path
out=Path(__file__).resolve().parents[1]/'releases/tf_diagnostics_20261101';out.mkdir(exist_ok=True)
with open(r'\\.\E:','rb',buffering=0) as f:
    raw=f.read(512*16384)
(out/'volume_first_8MiB.bin').write_bytes(raw)
report={'bytes_saved':len(raw),'sha256':hashlib.sha256(raw).hexdigest(),'valid_boot_candidates':[]}
for sector in range(min(len(raw)//512,128)):
    b=raw[sector*512:(sector+1)*512]
    if b[510:512]==b'\x55\xaa':
        rec={'sector':sector,'bps':struct.unpack_from('<H',b,11)[0], 'spc':b[13], 'type':repr(b[82:90])}
        report['valid_boot_candidates'].append(rec)
for sector in [0,1,6,7]:
    b=raw[sector*512:(sector+1)*512]
    report[str(sector)]={'signature':b[510:512].hex(),'first64':b[:64].hex()}
(out/'boot_report.json').write_text(json.dumps(report,indent=2))
print(json.dumps(report,indent=2))
