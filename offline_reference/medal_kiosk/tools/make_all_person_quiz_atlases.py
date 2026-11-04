"""Draft 12 quizzes directly from the supplied PPT contribution headings."""
import json
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
root=Path(__file__).resolve().parents[1]
slides=json.loads((root/'materials_review/ppt_text_and_asset_index.json').read_text(encoding='utf-8-sig'))['slides']
people=[]
for i in range(13):
    texts=[v['text'] for v in slides[3+i*4]['texts']]
    idx=7 if i==1 else 6
    assert texts[idx]=='01'
    people.append((texts[1].split('　|　')[0].strip(),texts[idx+1]))
out=root/'assets_720p/article_pilot'; out.mkdir(parents=True,exist_ok=True)
records=[]
for i in range(1,13):
    name,answer=people[i]
    # Use distinct fields for distractors; avoid overlapping military or
    # medical achievements being incorrectly presented as exclusive.
    anchors=[people[1][1], people[5][1], people[7][1]]
    other=[value for value in anchors if value != answer][:2]
    choices=other[:]; choices.insert(i%3,answer)
    if len(set(choices)) != 3: raise ValueError(name+' duplicate options')
    img=Image.new('RGB',(768,320),'black'); d=ImageDraw.Draw(img)
    def put(x,y,s,size,width):
        for n in range(size,12,-1):
            f=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',n)
            if d.textsize(s,font=f)[0] <= width:
                d.text((x,y),s,font=f,fill='white'); return
        raise ValueError(name+' text too wide: '+s)
    put(3,0,'共和国勋章 · 人物志',21,400)
    put(3,27,name+'  |  互动问答',30,400)
    put(480,3,'回答正确',24,130); put(620,3,'再试一次',24,130)
    put(2,76,'以下哪一项是'+name+'的主要贡献？',28,670)
    for n,s in enumerate(choices): put(2,143+n*64,chr(65+n)+'. '+s,26,670)
    img.convert('L').point(lambda x:255 if x>=128 else 0).convert('RGB').save(out/('QUIZ%02dC.BMP'%(i+1)))
    records.append({'person':name,'question':'以下哪一项是'+name+'的主要贡献？','choices':choices,'correct':i%3,'ppt_page':4+i*4})
(out/'quiz_draft_manifest.json').write_text(json.dumps(records,ensure_ascii=False,indent=2),encoding='utf-8')
print('Prepared 12 quiz drafts.')
