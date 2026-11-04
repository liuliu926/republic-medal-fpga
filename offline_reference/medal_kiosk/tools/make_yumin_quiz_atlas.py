from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
root = Path(__file__).resolve().parents[1]
image = Image.new('RGB', (768, 320), 'black')
draw = ImageDraw.Draw(image)
font = 'C:/Windows/Fonts/msyh.ttc'
for x,y,text,size in [(3,0,'共和国勋章 · 人物志',21),(3,27,'于敏  |  互动问答',30),(3,78,'我国第一颗氢弹试验成功是在哪一年？',25),(3,143,'A. 1964 年',26),(3,207,'B. 1967 年',26),(3,270,'回答正确',26),(384,270,'再试一次',26)]:
    draw.text((x,y), text, font=ImageFont.truetype(font,size), fill='white')
image.convert('L').point(lambda x: 255 if x >= 128 else 0).convert('RGB').save(root / 'assets_720p/article_pilot/QUIZ01C.BMP')
