"""Align TF menu artwork to the existing, verified FPGA selection geometry."""
from pathlib import Path
import hashlib,json
from PIL import Image,ImageDraw
R=Path(__file__).resolve().parents[1];OUT=R/'assets_720p/bilingual_layout_v2'
OLD=[(471,463,798,530),(818,463,1144,530),(471,548,798,614),(818,548,1144,614)]
NEW=[(469,461,799,532),(815,461,1145,532),(469,545,799,616),(815,545,1145,616)]
def erase_h(im,left,right,y):
    # Reconstruct a narrow baked stroke from the adjacent background pixels.
    px=im.load()
    for x in range(left-4,right+5):
        a,b=px[x,y-5],px[x,y+5]
        for dy in range(-3,4):
            t=(dy+5)/10
            px[x,y+dy]=tuple(round(v*(1-t)+w*t) for v,w in zip(a,b))
def erase_v(im,top,bottom,x):
    px=im.load()
    for y in range(top-4,bottom+5):
        a,b=px[x-5,y],px[x+5,y]
        for dx in range(-3,4):
            t=(dx+5)/10
            px[x+dx,y]=tuple(round(v*(1-t)+w*t) for v,w in zip(a,b))
for person in range(13):
    name=f'BG{2+4*person:03d}.BMP';im=Image.open(R/'assets_ppt_720p'/name).convert('RGB')
    for left,top,right,bottom in OLD:
        erase_h(im,left,right,top);erase_h(im,left,right,bottom)
        erase_v(im,top,bottom,left);erase_v(im,top,bottom,right)
    d=ImageDraw.Draw(im)
    for rect in NEW:d.rectangle(rect,outline=(201,159,100),width=2)
    im.save(OUT/name)

def overlay_atlas(im,atlas,regions):
    for box,(x,y) in regions:
        tile=atlas.crop(box);im.paste((255,241,205),(x,y,x+tile.width,y+tile.height),tile.convert('L'))
for person in [0,5,12]:
    b=Image.open(OUT/f'BG{2+4*person:03d}.BMP').convert('RGB')
    photo=Image.open(R/f'assets_ppt_720p/POR{person+1:02d}.BMP').convert('RGB')
    b.paste(photo,(100,160))
    a=Image.open(OUT/f'ITX{person+1:02d}E.BMP')
    overlay_atlas(b,a,[((0,i*48,768,(i+1)*48),(457,y)) for i,y in enumerate([160,260,316,367,478,561])])
    ImageDraw.Draw(b).rectangle(NEW[0],outline=(255,226,124),width=3)
    b.save(OUT/f'preview_intro_{person+1:02d}.png')
    b=Image.open(OUT/f'BE{4+4*person:03d}.BMP').convert('RGB');a=Image.open(OUT/f'ART{4+4*person:02d}E.BMP')
    overlay_atlas(b,a,[((0,0,600,64),(74,40))]+[((0,(i+1)*64,768,(i+2)*64),(342,y)) for i,y in enumerate([180,298,412,534])])
    b.save(OUT/f'preview_contribution_{person+1:02d}.png')
manifest=[{'file':p.name,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in sorted(OUT.glob('*.BMP'))]
(OUT/'manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
print('Aligned 13 backgrounds; prepared',len(manifest),'total layout assets and 6 previews')
