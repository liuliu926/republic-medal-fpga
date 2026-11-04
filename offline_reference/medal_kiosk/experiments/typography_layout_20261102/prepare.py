"""Isolated typography candidate; never overwrite accepted sources or assets."""
from pathlib import Path
import json, hashlib, shutil
from PIL import Image, ImageDraw, ImageFont

E=Path(__file__).resolve().parent
R=E.parent.parent
B=R/'releases/english_step_display_accepted_20261102'
OUT=E/'assets';OUT.mkdir(parents=True,exist_ok=True)
PRE=E/'previews';PRE.mkdir(exist_ok=True)
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
canonical={x['file']:x for x in json.loads((R/'releases/bilingual_layout_v2_20261101/card_asset_manifest.json').read_text())}
slides=json.loads((R/'materials_review/ppt_text_and_asset_index.json').read_text(encoding='utf-8-sig'))['slides']
def texts(slide):return [x['text'] for x in slides[slide-1]['texts']]
records=[]
fontpath={'C':'C:/Windows/Fonts/msyh.ttc','E':'C:/Windows/Fonts/arial.ttf'}
def put(im,s,box,size,lang,center=False):
    d=ImageDraw.Draw(im);x,y,w,h=box
    for n in range(size,9,-1):
        f=ImageFont.truetype(fontpath[lang],n);bb=d.textbbox((0,0),s,font=f)
        tw,th=bb[2]-bb[0],bb[3]-bb[1]
        if tw<=w and th<=h:break
    else:raise ValueError(s)
    px=x+(w-tw)//2 if center else x
    py=y+(h-th)//2 if center else y
    d.text((px-bb[0],py-bb[1]),s,font=f,fill='white')
    records.append(dict(text=s,lang=lang,font_px=n,box=box,ink_box=[px,py,px+tw,py+th]))

def src(name):
    p=Path(canonical[name]['source']);assert sha(p)==canonical[name]['sha256'],name
    return Image.open(p).convert('RGB')
def save(im,name):
    im.convert('L').point(lambda v:255 if v>=128 else 0).convert('RGB').save(OUT/name)

import csv,re
norm=lambda s:re.sub(r'[\s。；，、·“”「」—–:：|｜]','',s)
tr=json.loads((R/'materials_review/english_translations.json').read_text(encoding='utf-8'))
inv=list(csv.DictReader((R/'materials_review/english_translation_inventory.csv').open(encoding='utf-8-sig')))
trans={norm(x['Chinese']):tr[x['id']] for x in inv};trans[norm('于敏')]='Yu Min'
def en(s):return trans[norm(s)] if re.search('[\u4e00-\u9fff]',s) else s.replace('—','–')
tags=['Nuclear Theory','Equal Pay','Space Science','Korean War','Veteran','Hybrid Rice','Nuclear Submarines','Artemisinin','Respiratory Medicine','Space Engineering','Hematology','Wheat Breeding','War Veteran']

for p in range(13):
    intro=texts(2+4*p);life=texts(3+4*p);deeds=texts(5+4*p)
    name=intro[1 if p==1 else 0];side=7 if p==1 else 6
    for lang in ['C','E']:
        im=src(f'ITX{p+1:02d}{lang}.BMP');ImageDraw.Draw(im).rectangle((0,0,767,47),fill='black')
        put(im,name if lang=='C' else en(name),(6,2,756,44),40,lang)
        save(im,f'ITX{p+1:02d}{lang}.BMP')
        im=src(f'ART{3+4*p:02d}{lang}.BMP');ImageDraw.Draw(im).rectangle((600,0,767,63),fill='black')
        # First crop maps atlas x600 to screen x55; its visual center x160 is atlas705.
        for value,box,size in [
            (life[side] if lang=='C' else en(life[side]),(642,0,126,26),26 if lang=='C' else 20),
            (life[side+1] if lang=='C' else en(life[side+1]),(642,29,126,15),16),
            (life[side+2] if lang=='C' else tags[p],(604,46,112,17),16 if lang=='C' else 14)]:
            put(im,value,box,size,lang,True)
        save(im,f'ART{3+4*p:02d}{lang}.BMP')
        im=src(f'ART{5+4*p:02d}{lang}.BMP')
        # Keep the accepted English word wrapping and type sizes. Long English
        # paragraphs already use both body lines; Chinese gets the larger gap.
        ImageDraw.Draw(im).rectangle((0,64,767 if lang=='C' else 129,319),fill='black')
        for j in range(3):
            marker,heading,body=deeds[side+3*j:side+3*j+3];y=(j+1)*64
            # Screen row top211/362/513; center local34 => circle center245/396/547.
            put(im,marker,(0,y+21,100,26),26,lang,True)
            if lang=='C':
                put(im,heading,(130,y+1,630,29),28,lang)
                put(im,body,(130,y+40,630,24),22,lang)
        save(im,f'ART{5+4*p:02d}{lang}.BMP')

for directory in ['source','user_source']:
    dest=E/directory
    if not dest.exists():shutil.copytree(B/directory,dest)
mask=E/'source/hdl_source/home_text_mask_title_candidate.v'
s=(B/'source/hdl_source/home_text_mask_title_candidate.v').read_text(encoding='utf-8');original=s
for old,new in [('in_y64(y, 10\'d187)','in_y64(y, 10\'d211)'),
                ('y_bias=9\'d389','y_bias=9\'d365'),
                ('in_y64(y, 10\'d338)','in_y64(y, 10\'d362)'),
                ('y_bias=9\'d302','y_bias=9\'d278'),
                ('in_y64(y, 10\'d489)','in_y64(y, 10\'d513)'),
                ('y_bias=9\'d215','y_bias=9\'d191'),
                ('y >= 10\'d449 && y < 10\'d467','y >= 10\'d457 && y < 10\'d475'),
                ('y_bias=9\'d108','y_bias=9\'d100')]:
    assert s.count(old)==1,(old,s.count(old));s=s.replace(old,new)
mask.write_text(s,encoding='utf-8')
shutil.copy2(B/'source/hdl_source/home_text_mask_bilingual.v',E/'source/hdl_source/home_text_mask_bilingual.v')
run=E/'run';run.mkdir(exist_ok=True)
prj=(B/'run/medal_kiosk_720p.prj').read_text(encoding='utf-8').replace(B.as_posix(),E.as_posix())
(run/'medal_kiosk_720p.prj').write_text(prj,encoding='utf-8')
for p in (B/'run').glob('*.hex'):shutil.copy2(p,run/p.name)
build=(B/'build.tcl').read_text().replace('medal_720p_resource_opt.bit','medal_typography_layout.bit').replace('RESOURCE_OPT_BUILD_COMPLETE','TYPOGRAPHY_BUILD_COMPLETE')
(E/'build.tcl').write_text(build)
manifest=[dict(file=p.name,source=str(p),size=p.stat().st_size,sha256=sha(p),previous=canonical[p.name]) for p in sorted(OUT.glob('*.BMP'))]
(E/'asset_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
(E/'typography_report.json').write_text(json.dumps(records,ensure_ascii=False,indent=2),encoding='utf-8')
(E/'changes.json').write_text(json.dumps(dict(baseline=str(B),baseline_bit_sha256=sha(B/'run/medal_720p_resource_opt.bit'),assets=len(manifest),hardware_status='not tested',timing_closed=False,changes=['intro name ink up to40px','life name and dates centered at x160; label centered in pill','deeds dates centered at circle centers; heading up to28px; body starts40px into row','only deeds row windows shifted24px; reveal bands unchanged'],tf_written=False),ensure_ascii=False,indent=2),encoding='utf-8')

def overlay(bg,atlas,regions):
    for box,xy in regions:
        tile=atlas.crop(box);bg.paste((255,241,205),(*xy,xy[0]+tile.width,xy[1]+tile.height),tile.convert('L'))
for p in [0,1,5,12]:
    for lang in ['C','E']:
        bg=src(f'BG{2+4*p:03d}.BMP');photo=Image.open(R/f'assets_ppt_720p/POR{p+1:02d}.BMP');bg.paste(photo,(100,160))
        a=Image.open(OUT/f'ITX{p+1:02d}{lang}.BMP')
        overlay(bg,a,[((0,i*48,768,(i+1)*48),(457,y)) for i,y in enumerate([160,260,316,367,478,561])]);bg.save(PRE/f'intro_{p+1:02d}{lang}.png')
        bg=src(f'BG{3+4*p:03d}.BMP');a=Image.open(OUT/f'ART{3+4*p:02d}{lang}.BMP')
        overlay(bg,a,[((0,0,600,64),(74,40)),((600,0,768,44),(55,380)),((600,45,728,63),(100,457))]+[((0,(j+1)*64,768,(j+2)*64),(342,y)) for j,y in enumerate([180,298,412,534])]);bg.save(PRE/f'life_{p+1:02d}{lang}.png')
        bg=src(f'BG{5+4*p:03d}.BMP');a=Image.open(OUT/f'ART{5+4*p:02d}{lang}.BMP')
        overlay(bg,a,[((0,0,600,64),(80,46))]+[((0,(j+1)*64,768,(j+2)*64),(64,y)) for j,y in enumerate([211,362,513])]);bg.save(PRE/f'deeds_{p+1:02d}{lang}.png')
print(json.dumps(dict(assets=len(manifest),previews=len(list(PRE.glob('*.png'))),experiment=str(E))))
