"""Render the three Shen Jilan article atlases using the supplied PPT text."""
import json
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

root = Path(__file__).resolve().parents[1]
slides = json.loads((root / 'materials_review/ppt_text_and_asset_index.json').read_text(encoding='utf-8-sig'))['slides']
out = root / 'assets_720p/article_pilot'
out.mkdir(parents=True, exist_ok=True)
font = 'C:/Windows/Fonts/msyh.ttc'

def render(index):
    text = [x['text'] for x in slides[index-1]['texts']]
    assert text[1].startswith('申纪兰')
    img = Image.new('RGB', (768, 320), 'black')
    d = ImageDraw.Draw(img)
    def put(x,y,s,size,width):
        for n in range(size, 12, -1):
            f=ImageFont.truetype(font,n)
            if d.textsize(s,font=f)[0] <= width:
                d.text((x,y),s,font=f,fill='white')
                return
        raise ValueError('Text too wide: '+s)
    put(3,0,text[0],21,590)
    put(3,27,text[1],30,590)
    if index == 7:
        assert text[10] == '1929' and text[16] == '2020'
        for s,y,size in zip(text[7:10],(0,27,46),(25,17,15)):
            put(604,y,s,size,160)
        for i in range(4):
            year, description = text[10+2*i:12+2*i]
            y=(i+1)*64
            put(2,y+14,year,31,124)
            put(183,y+17,description,25,577)
    elif index == 8:
        for i in range(4):
            number,title,description=text[7+3*i:10+3*i]
            y=(i+1)*64
            put(2,y+2,number+'  '+title,23,495)
            put(2,y+32,description,23,495)
    else:
        for i in range(3):
            year,title,description=text[7+3*i:10+3*i]
            y=(i+1)*64
            put(3,y+19,year,24,120)
            put(130,y+1,title,24,630)
            put(130,y+32,description,23,630)
    img.convert('L').point(lambda x: 255 if x >= 128 else 0).convert('RGB').save(out / ('ART%02dC.BMP' % index))

for page in (7,8,9):
    render(page)
print('Prepared ART07C.BMP, ART08C.BMP, ART09C.BMP')
