"""Prepare PPT article subtitle atlases for persons 3 through 13."""
import json
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
root=Path(__file__).resolve().parents[1]
slides=json.loads((root/'materials_review/ppt_text_and_asset_index.json').read_text(encoding='utf-8-sig'))['slides']
out=root/'assets_720p/article_pilot'
font='C:/Windows/Fonts/msyh.ttc'
for person in range(2,13):
    for section in range(3):
        page=3+person*4+section
        t=[v['text'] for v in slides[page-1]['texts']]
        img=Image.new('RGB',(768,320),'black'); d=ImageDraw.Draw(img)
        def put(x,y,s,size,width):
            for n in range(size,12,-1):
                f=ImageFont.truetype(font,n)
                if d.textsize(s,font=f)[0] <= width:
                    d.text((x,y),s,font=f,fill='white'); return
            raise ValueError('Page %s text too wide: %s' % (page,s))
        put(3,0,t[0],21,590); put(3,27,t[1],30,590)
        if section == 0:
            assert len(t)==17
            for s,y,size in zip(t[6:9],(0,27,46),(25,17,15)): put(604,y,s,size,160)
            for i in range(4):
                year,desc=t[9+2*i:11+2*i]; y=(i+1)*64
                put(2,y+14,year,31,124); put(183,y+17,desc,25,577)
        elif section == 1:
            assert len(t)==18
            for i in range(4):
                number,title,desc=t[6+3*i:9+3*i]; y=(i+1)*64
                put(2,y+2,number+'  '+title,23,495); put(2,y+32,desc,23,495)
        else:
            assert len(t)==15
            for i in range(3):
                year,title,desc=t[6+3*i:9+3*i]; y=(i+1)*64
                put(3,y+19,year,24,120); put(130,y+1,title,24,630); put(130,y+32,desc,23,630)
        img.convert('L').point(lambda x:255 if x>=128 else 0).convert('RGB').save(out/('ART%02dC.BMP'%page))
print('Prepared 33 article atlases.')
