"""Prepare a draft subtitle atlas for PPT slide 4; not yet wired into RTL."""
import json
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

root = Path(__file__).resolve().parents[1]
slide = json.loads((root / 'materials_review/ppt_text_and_asset_index.json').read_text(encoding='utf-8-sig'))['slides'][3]
items = [entry['text'] for entry in slide['texts']]
assert items[6:7] == ['01'] and items[9:10] == ['02'] and items[12:13] == ['03'] and items[15:16] == ['04']
image = Image.new('RGB', (768, 320), 'black')
draw = ImageDraw.Draw(image)
font_path = 'C:/Windows/Fonts/msyh.ttc'
draw.text((3, 0), items[0], font=ImageFont.truetype(font_path, 21), fill='white')
draw.text((3, 27), items[1], font=ImageFont.truetype(font_path, 30), fill='white')
for i in range(4):
    number, title, description = items[6+i*3:9+i*3]
    y = 64*(i+1)
    draw.text((2, y+2), number+'  '+title, font=ImageFont.truetype(font_path, 23), fill='white')
    for size in range(23, 12, -1):
        face = ImageFont.truetype(font_path, size)
        if draw.textsize(description, font=face)[0] <= 495:
            break
    draw.text((2, y+32), description, font=face, fill='white')
image = image.convert('L').point(lambda x: 255 if x >= 128 else 0).convert('RGB')
out = root / 'assets_720p/article_pilot'
out.mkdir(parents=True, exist_ok=True)
image.save(out / 'ART04C.BMP')
print(out / 'ART04C.BMP')
