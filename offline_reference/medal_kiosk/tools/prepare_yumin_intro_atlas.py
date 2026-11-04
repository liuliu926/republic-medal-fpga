"""Pack six PPT text strips into the existing 768x320 one-bit atlas format."""
import json
from pathlib import Path
from PIL import Image

root = Path(__file__).resolve().parents[1]
folder = root / 'assets_ppt_720p/text_zh'
index = json.loads((folder / 'layer_index.json').read_text(encoding='utf-8'))
layer = index['pages'][1]['layers'][0]
source = Image.open(folder / layer['preview']).convert('RGBA')
screen = Image.new('RGBA', (1280, 720), (0, 0, 0, 0))
screen.paste(source, (layer['x'], layer['y']))
atlas = Image.new('RGB', (768, 320), (0, 0, 0))
for strip, y in enumerate((160, 260, 316, 367, 478, 561)):
    tile = screen.crop((457, y, 1225, y + 48))
    atlas.paste(tile.convert('RGB'), (0, strip * 48), tile.getchannel('A'))
atlas = atlas.convert('L').point(lambda n: 255 if n >= 110 else 0).convert('RGB')
out = root / 'assets_720p' / 'YMTEXT.BMP'
atlas.save(out, 'BMP')
preview = Image.open(root / 'assets_ppt_720p/BG002.BMP').convert('RGB')
for strip, y in enumerate((160, 260, 316, 367, 478, 561)):
    tile = atlas.crop((0, strip * 48, 768, strip * 48 + 48))
    preview.paste((255, 241, 205), (457, y, 1225, y + 48), tile.convert('L'))
preview.save(root / 'materials_review/preview_yumin_text_atlas.png')
print('Created YMTEXT.BMP and preview from PPT slide 2')
