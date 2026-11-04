"""Build the 13 right-to-left vertical contribution pages.

Only the contribution BMPs and their subtitle masks change. PCM assets, other
sections, and the accepted release are left untouched.
"""
import hashlib
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets_720p" / "contribution_vertical_candidate_v2"
WALLPAPER = ROOT / "materials_review" / "red_gold_wallpaper.jpg"
MANIFEST = ROOT / "assets_720p" / "audio_article_batch" / "manifest.json"
OLD_ATLAS = ROOT / "assets_720p" / "article_pilot"
FONT = "C:/Windows/Fonts/msyh.ttc"
GOLD = (231, 180, 48)
WHITE = (255, 255, 255)
# Each atlas band still uses 64 pixels, but the FPGA spaces its three text
# columns apart on screen. That gives the gold heading its own visual area.
RULES = (1005, 790, 575, 360)
BODY_TOP = 150
BODY_PITCH = 32
BODY_COL_CAPACITY = 16


def vertical_text(draw, x, top, value, font, fill, max_chars=16):
    assert len(value) <= max_chars, value
    for idx, char in enumerate(value):
        draw.text((x, top + idx * BODY_PITCH), char, font=font, fill=fill,
                  stroke_width=0)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8-sig"))
    wallpaper = Image.open(WALLPAPER).convert("RGB").resize((1280, 720), Image.LANCZOS)
    title_font = ImageFont.truetype(FONT, 24)
    body_font = ImageFont.truetype(FONT, 20)
    number_font = ImageFont.truetype(FONT, 19)
    report = []

    for person in range(13):
        rows = sorted((item for item in manifest if item["person_index"] == person
                       and item["section"] == "contribution"), key=lambda x: x["row"])
        assert len(rows) == 4 and [r["row"] for r in rows] == [1, 2, 3, 4]
        slide = 4 + 4 * person

        # Keep the red/gold wallpaper and four gold rules, without any old box.
        bg = wallpaper.copy()
        bd = ImageDraw.Draw(bg)
        for x in RULES:
            bd.rectangle((x - 2, 163, x + 3, 393), fill=GOLD, outline=(67, 56, 45), width=1)
        bd.rectangle((56, 48, 61, 145), fill=GOLD, outline=(67, 56, 45), width=1)
        bd.line((56, 154, 173, 154), fill=(59, 56, 45), width=2)
        for index in range(4):
            x = 1150
            y = 56 + index * 24
            bd.ellipse((x - 4, y - 4, x + 4, y + 4), outline=GOLD, width=2)
        bg_path = OUT / f"BG{slide:03d}.BMP"
        bg.save(bg_path)

        atlas = Image.new("RGB", (768, 320), "black")
        ad = ImageDraw.Draw(atlas)
        ad.text((2, 0), "共和国勋章 · 人物志", font=ImageFont.truetype(FONT, 21), fill=WHITE)
        ad.text((2, 24), rows[0]["person"] + "  |  主要贡献",
                font=ImageFont.truetype(FONT, 34), fill=WHITE)
        for index, item in enumerate(rows):
            body = item["subtitle"]
            assert len(body) <= 32, (person, index, body)
            # A 64 x 720 screen-space group is transposed into one 768 x 64
            # atlas band. RTL transposes it back with no scaler or extra RAM.
            group = Image.new("RGB", (64, 720), "black")
            gd = ImageDraw.Draw(group)
            gd.text((40, BODY_TOP), item["marker"], font=number_font, fill=WHITE)
            vertical_text(gd, 40, BODY_TOP + 55, item["title"], title_font, WHITE)
            vertical_text(gd, 20, BODY_TOP, body[:BODY_COL_CAPACITY], body_font, WHITE)
            vertical_text(gd, 0, BODY_TOP, body[BODY_COL_CAPACITY:], body_font, WHITE)
            atlas.paste(group.transpose(Image.TRANSPOSE), (0, 64 * (index + 1)))
        atlas = atlas.convert("L").point(lambda x: 255 if x >= 128 else 0).convert("RGB")
        atlas_path = OUT / f"ART{slide:02d}C.BMP"
        atlas.save(atlas_path)
        report.append({"person": rows[0]["person"], "slide": slide,
                       "background": bg_path.name, "atlas": atlas_path.name,
                       "body_lengths": [len(item["subtitle"]) for item in rows],
                       "pcm": [item["sfn"] for item in rows],
                       "background_sha256": hashlib.sha256(bg_path.read_bytes()).hexdigest(),
                       "atlas_sha256": hashlib.sha256(atlas_path.read_bytes()).hexdigest()})

    (OUT / "manifest.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"Prepared {len(report)} backgrounds and {len(report)} vertical subtitle atlases in {OUT}")


if __name__ == "__main__":
    main()
