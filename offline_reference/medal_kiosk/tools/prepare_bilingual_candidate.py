"""Build English TF atlases and isolate bilingual RTL from the accepted release."""
import csv, json, hashlib, re
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
R=Path(__file__).resolve().parents[1]
OUT=R/'assets_720p/bilingual_candidate'; OUT.mkdir(exist_ok=True)
slides=json.loads((R/'materials_review/ppt_text_and_asset_index.json').read_text(encoding='utf-8-sig'))['slides']
tr=json.loads((R/'materials_review/english_translations.json').read_text(encoding='utf-8'))
inv=list(csv.DictReader((R/'materials_review/english_translation_inventory.csv').open(encoding='utf-8-sig')))
norm=lambda s: re.sub(r'[\s。；，、·“”「」—–:：|｜]', '',s)
translations={norm(x['Chinese']):tr[x['id']] for x in inv}
translations[norm('于敏')]='Yu Min'
def en(s):
    if not re.search('[\u4e00-\u9fff]',s): return s.replace('—','–')
    key=norm(s)
    if key not in translations: raise ValueError('Missing translation: '+s)
    return translations[key]
def txt(n): return [x['text'] for x in slides[n-1]['texts']]
def new(): return Image.new('RGB',(768,320),'black')
def put(im,text,x,y,w,h,size=24):
    d=ImageDraw.Draw(im)
    for sz in range(size,10,-1):
        f=ImageFont.truetype('C:/Windows/Fonts/arial.ttf',sz); lines=[]; line=''
        for word in text.split():
            cand=(line+' '+word).strip()
            if line and d.textsize(cand,font=f)[0]>w: lines.append(line); line=word
            else: line=cand
        if line: lines.append(line)
        if len(lines)*(sz+3)<=h and all(d.textsize(a,font=f)[0]<=w for a in lines): break
    else: raise ValueError('Text cannot fit: '+text)
    for j,line in enumerate(lines): d.text((x,y+j*(sz+3)-2),line,font=f,fill='white')
def save(im,name):
    im.convert('L').point(lambda a:255 if a>=110 else 0).convert('RGB').save(OUT/name)
names=[en(txt(1)[1+2*i]) for i in range(13)]
im=new()
for p in range(13):
    row,col=divmod(p,4); x=col*192; y=row*64
    put(im,names[p],x,y,190,30,23); put(im,en(txt(1)[2+2*p]),x,y+33,190,28,18)
put(im,'Medal of the Republic',0,256,512,64,37); save(im,'HOMEENG.BMP')
quiz=json.loads((R/'assets_720p/article_pilot/quiz_draft_manifest.json').read_text(encoding='utf-8'))
sections=['Life','Contributions','Key Events','Interactive Quiz']
for p in range(13):
    t=txt(2+p*4); start=1 if p==1 else 0; im=new()
    for i,st in enumerate([names[p],en(t[start+1]),en(t[start+2]),en(t[start+3])]):
        put(im,st,0,i*48,768,48,32 if i==0 else 25)
    for j,label in enumerate(sections):
        put(im,f'{j+1:02d}  '+label,16+(j%2)*346,192+(j//2)*48,312,48,25)
    save(im,f'ITX{p+1:02d}E.BMP')
    for sec in range(3):
        slide=3+p*4+sec; t=txt(slide); im=new()
        put(im,'Medal of the Republic · Profiles',2,0,590,26,20)
        put(im,names[p]+' | '+sections[sec],2,27,590,36,29)
        if sec==0:
            side=7 if p==1 else 6
            tags=['Nuclear Theory','Equal Pay','Space Science','Korean War','Veteran','Hybrid Rice','Nuclear Submarines','Artemisinin','Respiratory Medicine','Space Engineering','Hematology','Wheat Breeding','War Veteran']
            for j,st in enumerate(t[side:side+3]): put(im,tags[p] if j==2 else en(st),604,[0,27,46][j],160,[27,19,18][j],22 if j==0 else 14)
            rows=t[side+3:]
            for j in range(4):
                put(im,rows[j*2],2,(j+1)*64+14,124,48,30)
                put(im,en(rows[j*2+1]),183,(j+1)*64+2,577,62,23)
        else:
            offset=7 if p==1 else 6
            rows=t[offset:]
            for j in range(4 if sec==1 else 3):
                marker,title,body=rows[j*3:j*3+3]; y=(j+1)*64
                if sec==1:
                    put(im,marker+'  '+en(title),2,y,768,31,24)
                    put(im,en(body),2,y+32,768,32,21)
                else:
                    put(im,marker,2,y+14,124,48,24)
                    put(im,en(title),130,y,630,31,24); put(im,en(body),130,y+32,630,32,20)
        save(im,f'ART{slide:02d}E.BMP')
    im=new(); put(im,'Medal of the Republic · Profiles',3,0,400,26,18)
    put(im,names[p]+' | Quiz',3,27,400,35,28)
    put(im,'Correct!',480,3,130,30,23); put(im,'Try again',620,3,130,30,23)
    if p==0: question="In which year did China's first hydrogen bomb test succeed?"; choices=['1964','1967','1970']
    else:
        q=quiz[p-1]; question='Which is a major contribution of '+names[p]+'?'; choices=[en(x) for x in q['choices']]
    put(im,question,2,70,680,58,27)
    for j,c in enumerate(choices): put(im,chr(65+j)+'. '+c,2,138+j*64,680,54,25)
    save(im,'QUIZ3E.BMP' if p==0 else f'QUIZ{p+1:02d}E.BMP')
wallpaper=Image.open(R/'materials_review/red_gold_wallpaper.jpg').convert('RGB').resize((1280,720),Image.LANCZOS)
for p in range(13):
    wallpaper.save(OUT/f'BE{4+4*p:03d}.BMP')
manifest=[{'file':p.name,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in sorted(OUT.glob('*.BMP'))]
(OUT/'manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
print('Created',len(manifest),'English atlases')


