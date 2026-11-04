"""Render the Yu Min deeds text from PPT slide 5 into a TF subtitle atlas."""
import json
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

root = Path(__file__).resolve().parents[1]
items = [x['text'] for x in json.loads((root / 'materials_review/ppt_text_and_asset_index.json').read_text(encoding='utf-8-sig'))['slides'][4]['texts']]
assert items[6] == '1961' and items[9] == '1966' and items[12] == '1967'
image = Image.new('RGB', (768, 320), 'black')
draw = ImageDraw.Draw(image)
font = 'C:/Windows/Fonts/msyh.ttc'
draw.text((3, 0), items[0], font=ImageFont.truetype(font, 21), fill='white')
draw.text((3, 27), items[1], font=ImageFont.truetype(font, 30), fill='white')
for i in range(3):
    year, heading, description = items[6+i*3:9+i*3]
    y = (i+1)*64
    draw.text((3, y+19), year, font=ImageFont.truetype(font, 24), fill='white')
    draw.text((130, y+1), heading, font=ImageFont.truetype(font, 24), fill='white')
    for size in range(23, 12, -1):
        face = ImageFont.truetype(font, size)
        if draw.textsize(description, font=face)[0] <= 630:
            break
    draw.text((130, y+32), description, font=face, fill='white')
image = image.convert('L').point(lambda x: 255 if x >= 128 else 0).convert('RGB')
out = root / 'assets_720p/article_pilot/ART05C.BMP'
out.parent.mkdir(parents=True, exist_ok=True)
image.save(out)
print(out)
