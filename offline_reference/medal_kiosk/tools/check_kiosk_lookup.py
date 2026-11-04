"""Check generated lookup table contents and the intended routing contract.

This inspects generated source against the independent catalog. It is not an
HDL simulator and does not validate a synthesized or physical device.
"""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
catalog = json.loads((ROOT / 'prepared_resource_catalog/catalog.json').read_text(encoding='utf-8'))
rtl = (ROOT / 'fpga/user_source_720p/hdl_source/kiosk_resource_lookup.v').read_text(encoding='ascii')

def short(name):
    stem, ext = name.split('.')
    return stem.ljust(8) + ext

page_rows = re.findall(r'6\'d(\d+): begin background_sfn = "(.{11})"; layer_count = 3\'d(\d+); end', rtl)
portrait_rows = re.findall(r'5\'d(\d+): portrait_sfn = "(.{11})";', rtl)
layer_rows = re.findall(
    r'\{6\'d(\d+), 3\'d(\d+)\}: begin layer_valid = 1; '
    r'layer_sfn = language_en \? "(.{11})" : "(.{11})"; '
    r'layer_x = 11\'d(\d+); layer_y = 10\'d(\d+); '
    r'layer_width = 11\'d(\d+); layer_height = 10\'d(\d+); reveal_step = 3\'d(\d+); end', rtl)
assert len(page_rows) == 53 and len(portrait_rows) == 13 and len(layer_rows) == 198
by_page = {int(n): (name, int(count)) for n, name, count in page_rows}
by_portrait = {int(n): name for n, name in portrait_rows}
by_layer = {(int(r[0]), int(r[1])): r[2:] for r in layer_rows}
assert len(by_page) == 53 and len(by_portrait) == 13 and len(by_layer) == 198
for index, p in enumerate(catalog['portrait_order']):
    assert by_portrait[index] == short(p['file'])
    for offset, section in enumerate(('intro', 'life', 'contribution', 'deeds')):
        slide = 2 + index * 4 + offset
        page = catalog['pages'][slide - 1]
        assert page['person'] == p['person'] and page['page'] == section
for page in catalog['pages']:
    slide = page['slide']
    assert by_page[slide] == (short(page['background']), len(page['layers']))
    for i, layer in enumerate(page['layers']):
        expected = (short(layer['files']['en']), short(layer['files']['zh']),
                    str(layer['x']), str(layer['y']), str(layer['width']),
                    str(layer['height']), str(layer['key4_reveal_step']))
        assert by_layer[(slide, i)] == expected, (slide, i)
assert 'section_index == 3) quiz_page = 1' in rtl
print('PASS: 53 page backgrounds, 13 portraits and 198 bilingual layer records match catalog')
print('PASS: 13 people x intro/life/contribution/deeds route to expected slides')
print('Scope: source-table validation only; no HDL simulation or board test')
