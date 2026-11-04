"""Render UI mockups using the exported clean PPT backgrounds and TF portraits."""

from __future__ import print_function

import json
import re
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont, ImageOps


ROOT = Path(__file__).resolve().parents[1]
MATERIALS = Path(r"C:\Users\20251\Desktop\材料")
REVIEW = ROOT / "materials_review"
BACKGROUNDS = REVIEW / "clean_template_png"
NAV = json.loads((REVIEW / "medal_navigation_map.json").read_text(encoding="utf-8"))
TEXT = json.loads((REVIEW / "ppt_text_and_asset_index.json").read_text(encoding="utf-8-sig"))
OUT = REVIEW
W, H = 1280, 720
FONT_PATH = r"C:\Windows\Fonts\msyh.ttc"
LANCZOS = getattr(getattr(Image, "Resampling", Image), "LANCZOS")


def font(px):
    return ImageFont.truetype(FONT_PATH, px)


def rounded_portrait(index, size):
    person = NAV["people"][index]
    path = MATERIALS / person["portrait"]
    image = Image.open(str(path)).convert("RGB")
    image = ImageOps.fit(image, size, method=LANCZOS)
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).rectangle((0, 0, size[0] - 1, size[1] - 1), fill=255)
    return image, mask


def text(draw, xy, value, size, color, anchor=None):
    draw.text(xy, value, font=font(size), fill=color, anchor=anchor,
              stroke_width=0)


def render_home():
    bg = Image.open(str(BACKGROUNDS / "slide_001.png")).convert("RGBA")
    layer = Image.new("RGBA", bg.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    text(d, (640, 40), "共和国勋章获得者", 42, (255, 245, 220, 255), anchor="mt")
    text(d, (640, 96), "选择一位人物，了解他们的奋斗与贡献", 20,
         (255, 218, 126, 255), anchor="mt")
    xs = [57, 353, 649, 945]
    ys = [163, 296, 429, 562]
    index = 0
    for row, y in enumerate(ys):
        for col, x in enumerate(xs):
            if index >= len(NAV["people"]):
                break
            p = NAV["people"][index]
            photo, mask = rounded_portrait(index, (64, 96))
            layer.paste(photo, (x + 10, y + 9), mask)
            d.rectangle((x + 82, y + 7, x + 264, y + 107), fill=(62, 8, 13, 95))
            text(d, (x + 96, y + 26), p["name"], 27, (255, 247, 228, 255))
            intro_slide = int(p["pages"]["intro"]["slide"])
            year_texts = TEXT["slides"][intro_slide - 1]["texts"]
            years = next((t["text"] for t in year_texts if re.search(r"\d{4}.*\d{4}", t["text"])), "")
            years = years.replace("2019 获", "")
            text(d, (x + 96, y + 67), years[:20], 17, (255, 220, 145, 255))
            if index == 0:
                d.rectangle((x + 3, y + 2, x + 274, y + 111),
                            outline=(255, 216, 95, 255), width=4)
            index += 1
    text(d, (640, 684), "KEY1 / KEY2 选择    KEY4 进入    KEY3 返回", 18,
         (255, 245, 220, 255), anchor="mm")
    bg.alpha_composite(layer)
    bg.convert("RGB").save(str(OUT / "preview_ppt_home_720p.png"), optimize=True)


def render_intro(person_index=0):
    person = NAV["people"][person_index]
    slide = int(person["pages"]["intro"]["slide"])
    bg = Image.open(str(BACKGROUNDS / "slide_{:03d}.png".format(slide))).convert("RGBA")
    photo, mask = rounded_portrait(person_index, (296, 382))
    bg.paste(photo, (112, 171), mask)
    d = ImageDraw.Draw(bg, "RGBA")
    d.rectangle((91, 150, 429, 572), outline=(247, 198, 66, 255), width=4)
    items = TEXT["slides"][slide - 1]["texts"]
    for i, item in enumerate(items):
        value = item["text"]
        if i == 0:
            value = person["name"]
        elif i == 1:
            value = next((t["text"] for t in items if re.search(r"\d{4}.*\d{4}", t["text"])), value)
        elif i in (4, 5, 6, 7, 8, 9, 10, 11):
            # Keep the template's selectable category labels; make their active
            # highlight explicit in the mockup.
            pass
        size = 52 if item["h"] > 0.12 else (28 if item["h"] > 0.075 else 22)
        color = (255, 247, 225, 255) if i < 4 else (255, 220, 143, 255)
        x = int(item["x"] * W)
        y = int(item["y"] * H)
        if i in (4, 5):
            d.rectangle((x - 10, y - 10, x + int(item["w"] * W) + 5,
                         y + int(item["h"] * H) + 5),
                        fill=(94, 14, 19, 135), outline=(255, 210, 86, 210), width=2)
        text(d, (x + 2, y + 2), value, size, color)
    d.rectangle((470, 636, 1160, 691),
                fill=(45, 10, 20, 220), outline=(231, 183, 64, 255), width=2)
    text(d, (500, 650), "KEY1 / KEY2 选择栏目　　KEY4 逐条显现　　KEY3 返回", 19,
         (255, 244, 218, 255))
    bg.convert("RGB").save(str(OUT / "preview_ppt_intro_yumin_720p.png"), optimize=True)


def main():
    render_home()
    render_intro()
    print("Rendered PPT-backed home and person-intro mockups at 1280x720.")


if __name__ == "__main__":
    main()
