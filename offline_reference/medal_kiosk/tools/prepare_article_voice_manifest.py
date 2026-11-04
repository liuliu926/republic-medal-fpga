"""Build contribution and deeds narration from the provided PPT text."""
import json
import re
from pathlib import Path

root = Path(__file__).resolve().parents[1]
nav = json.loads((root / 'materials_review/medal_navigation_map.json').read_text(encoding='utf-8'))
out = root / 'assets_720p/audio_article_batch'
out.mkdir(parents=True, exist_ok=True)
digits = dict(zip('0123456789', '零一二三四五六七八九'))
manifest = []
for person in nav['people']:
    for section, count, code in [('contribution', 4, 'C'), ('deeds', 3, 'D')]:
        texts = [item['text'] for item in person['pages'][section]['texts']]
        rows = texts[-count * 3:]
        for row_no in range(count):
            marker, title, description = rows[row_no * 3:row_no * 3 + 3]
            if not title or not description or len(description) > 100:
                raise ValueError(f"{person['name']} {section} row {row_no + 1}: bad text")
            if section == 'contribution' and marker != f'{row_no + 1:02d}':
                raise ValueError(f"{person['name']} contribution row {row_no + 1}: bad marker {marker}")
            if section == 'deeds' and not re.fullmatch(r'(?:18|19|20)\d\d', marker):
                raise ValueError(f"{person['name']} deeds row {row_no + 1}: bad year {marker}")
            spoken_marker = ''.join(digits[c] for c in marker) + '年，' if section == 'deeds' else ''
            speech = spoken_marker + title + '。' + description
            stem = f"P{person['index']+1:02d}{code}{row_no+1:02d}"
            manifest.append({
                'person_index': person['index'], 'person': person['name'],
                'section': section, 'row': row_no + 1, 'marker': marker,
                'title': title, 'subtitle': description, 'speech': speech,
                'sfn': stem + '.PCM', 'wav': stem + '.WAV',
            })
assert len(manifest) == 91
path = out / 'manifest.json'
path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding='utf-8')
print(f'{path}: {len(manifest)} clips')
