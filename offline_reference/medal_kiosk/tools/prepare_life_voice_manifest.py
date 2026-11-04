"""Build a machine-checkable list of the 12 remaining life-page narrations."""
import json
import re
from pathlib import Path

root = Path(__file__).resolve().parents[1]
nav = json.loads((root / 'materials_review/medal_navigation_map.json').read_text(encoding='utf-8'))
out = root / 'assets_720p/audio_life_batch'
out.mkdir(parents=True, exist_ok=True)
digits = dict(zip('0123456789', '零一二三四五六七八九'))
manifest = []
for person in nav['people'][1:]:
    texts = [item['text'] for item in person['pages']['life']['texts']]
    rows = []
    for idx, value in enumerate(texts[:-1]):
        if re.fullmatch(r'(?:18|19|20)\d\d', value):
            rows.append((value, texts[idx + 1]))
    if len(rows) != 4:
        raise ValueError(f"{person['name']}: expected four year/event rows, found {rows}")
    for row_no, (year, event) in enumerate(rows, 1):
        if not event or len(event) > 60:
            raise ValueError(f"{person['name']} {year}: invalid event text")
        speech = ''.join(digits[c] for c in year) + '年，' + event
        stem = f"P{person['index']+1:02d}L{row_no:02d}"
        manifest.append({
            'person_index': person['index'], 'person': person['name'],
            'section': 'life', 'row': row_no, 'year': year,
            'subtitle': event, 'speech': speech,
            'sfn': stem + '.PCM', 'wav': stem + '.WAV',
        })
assert len(manifest) == 48
path = out / 'manifest.json'
path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding='utf-8')
print(f'{path}: {len(manifest)} clips')
