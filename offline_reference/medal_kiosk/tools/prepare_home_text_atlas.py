"""Create a 1-bit home-text atlas stored as a 24-bit BMP for the TF pilot."""
import json
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
lang = 'zh'
folder = ROOT / 'assets_ppt_720p' / f'text_{lang}'
index = json.loads((folder / 'layer_index.json').read_text(encoding='utf-8'))
home = index['pages'][0]['layers'][0]
rgba = Image.open(folder / home['preview']).convert('RGBA')
screen = Image.new('RGBA', (1280, 720), (0, 0, 0, 0))
screen.paste(rgba, (home['x'], home['y']))

atlas = Image.new('RGB', (768, 320), (0, 0, 0))
locations = []
for index in range(13):
    row, col = divmod(index, 4)
    sx, sy = 151 + col * 296, 180 + row * 133
    tile = screen.crop((sx, sy, sx + 192, sy + 64))
    atlas.paste(tile.convert('RGB'), (col * 192, row * 64), tile.getchannel('A'))
    locations.append([sx, sy, col * 192, row * 64])

# Title crop: preserve its PPT location and leave unused atlas area black.
title = screen.crop((320, 18, 320 + 512, 18 + 64))
atlas.paste(title.convert('RGB'), (0, 256), title.getchannel('A'))
# The FPGA stores one bit per pixel; use a deterministic threshold.
atlas = atlas.convert('L').point(lambda x: 255 if x >= 110 else 0).convert('RGB')
out = ROOT / 'assets_720p' / 'HOMETXT.BMP'
atlas.save(out, format='BMP')
preview = Image.open(ROOT / 'assets_ppt_720p/BG001.BMP').convert('RGB')
for sx, sy, ax, ay in locations:
    tile = atlas.crop((ax, ay, ax + 192, ay + 64))
    preview.paste((255, 241, 205), (sx, sy, sx + 192, sy + 64), tile.convert('L'))
tile = atlas.crop((0, 256, 512, 320))
preview.paste((255, 241, 205), (320, 18, 832, 82), tile.convert('L'))
preview.save(ROOT / 'materials_review/preview_home_text_atlas.png')
print(f'Created {out}, 768x320, 24-bit BMP; screen preview ready')
