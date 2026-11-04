"""Build compact 768x320 1-bit text atlases for the Yu Min life pilot.

The FPGA keeps this atlas in the existing subtitle BRAM. Its five 64-pixel
strips are placed independently over BG003.BMP at HDMI scanout; KEY1/KEY2
select how many timeline strips are visible. The wording is checked against
the extracted PPT text index, so a source change cannot silently diverge.
"""

import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
INDEX = ROOT / "materials_review" / "ppt_text_and_asset_index.json"
OUT = ROOT / "assets_720p" / "article_pilot"
FONT = Path("C:/Windows/Fonts/msyh.ttc")
WIDTH, HEIGHT = 768, 320

ZH_ROWS = [
    ("1926", "生于天津宁河，少年时代立志科学报国"),
    ("1949", "毕业于北京大学物理系，留校从事原子核理论研究"),
    ("1961", "奉命转向氢弹理论预研，从此隐姓埋名"),
    ("1967", "参与我国第一颗氢弹试验，理论方案获得验证"),
]
EN_ROWS = [
    ("1926", "Born in Ninghe, Tianjin; resolved to serve the nation through science."),
    ("1949", "Graduated from Peking University and studied nuclear theory."),
    ("1961", "Began confidential research on hydrogen bomb theory."),
    ("1967", "Helped validate the theory in China's first hydrogen bomb test."),
]


def check_source():
    data = json.loads(INDEX.read_text(encoding="utf-8-sig"))
    texts = {item["text"] for item in data["slides"][2]["texts"]}
    if "于敏　|　生平" not in texts:
        raise ValueError("PPT slide 3 is no longer the Yu Min life page")
    for year, description in ZH_ROWS:
        if year not in texts or description not in texts:
            raise ValueError("PPT text mismatch: {} {}".format(year, description))


def fitted_font(draw, value, max_width, initial_size):
    for size in range(initial_size, 13, -1):
        face = ImageFont.truetype(str(FONT), size)
        if draw.textsize(value, font=face)[0] <= max_width:
            return face
    raise ValueError("Text does not fit in atlas: " + value)


def make_atlas(language, rows):
    image = Image.new("RGB", (WIDTH, HEIGHT), (0, 0, 0))
    draw = ImageDraw.Draw(image)
    title1 = "共和国勋章 · 人物志" if language == "C" else "REPUBLIC MEDAL · PROFILES"
    title2 = "于敏  |  生平" if language == "C" else "YU MIN  |  LIFE"
    draw.text((3, 0), title1, font=fitted_font(draw, title1, 590, 21), fill="white")
    draw.text((3, 27), title2, font=fitted_font(draw, title2, 590, 31), fill="white")
    side = ("于敏", "1926—2019", "氢弹理论") if language == "C" else ("YU MIN", "1926—2019", "THEORY")
    for value, top, size in zip(side, (0, 27, 46), (25, 17, 15)):
        draw.text((604, top), value,
                  font=fitted_font(draw, value, 160, size), fill="white")
    for index, (year, description) in enumerate(rows):
        y = (index + 1) * 64
        draw.text((2, y + 14), year,
                  font=fitted_font(draw, year, 124, 31), fill="white")
        draw.text((183, y + 17), description,
                  font=fitted_font(draw, description, 577, 25), fill="white")
    # The loader consumes BMP pixels bottom-up; threshold antialiasing before
    # output because the on-chip cache stores one bit per pixel.
    image = image.convert("L").point(lambda value: 255 if value >= 128 else 0).convert("RGB")
    OUT.mkdir(parents=True, exist_ok=True)
    destination = OUT / "ART03{}.BMP".format(language)
    image.save(destination, format="BMP")
    if language == "C":
        background = Image.open(ROOT / "prepared_resource_catalog" / "files" / "BG003.BMP").convert("RGB")
        strips = [(74, 40), (342, 180), (342, 298), (342, 412), (342, 534)]
        for index, (x, y) in enumerate(strips):
            left = 600 if index == 0 else 768
            mask = image.crop((0, index * 64, left, (index + 1) * 64)).convert("L")
            tint = Image.new("RGB", (left, 64), (255, 241, 205))
            background.paste(tint, (x, y), mask)
        side_mask = image.crop((600, 0, 768, 44)).convert("L")
        background.paste(Image.new("RGB", (168, 44), (255, 241, 205)), (55, 380), side_mask)
        label_mask = image.crop((600, 45, 728, 63)).convert("L")
        background.paste(Image.new("RGB", (128, 18), (255, 241, 205)), (100, 449), label_mask)
        background.save(OUT / "preview_ART03C_step4.png")
    return destination


if __name__ == "__main__":
    check_source()
    print(make_atlas("C", ZH_ROWS))
    print(make_atlas("E", EN_ROWS))
