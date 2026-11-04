"""Create a read-only review index and contact sheets for the medal kiosk materials."""

from __future__ import annotations

import json
import re
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont
from pptx import Presentation


MATERIALS = Path(r"C:\Users\20251\Desktop\材料")
DECK = MATERIALS / "共和国勋章获得者人物志.pptx"
COPY = MATERIALS / "共和国勋章获得者人物志 - 副本"
OUT = Path(__file__).resolve().parents[1] / "materials_review"


def load_font(size: int) -> ImageFont.ImageFont:
    for candidate in (
        Path(r"C:\Windows\Fonts\msyh.ttc"),
        Path(r"C:\Windows\Fonts\simhei.ttf"),
    ):
        if candidate.exists():
            return ImageFont.truetype(str(candidate), size)
    return ImageFont.load_default()


def contact_sheet(paths: list[Path], out_path: Path, columns: int, cell_w: int, cell_h: int) -> None:
    rows = (len(paths) + columns - 1) // columns
    sheet = Image.new("RGB", (columns * cell_w, rows * cell_h), (28, 35, 51))
    draw = ImageDraw.Draw(sheet)
    font = load_font(18)
    for index, path in enumerate(paths):
        image = Image.open(path).convert("RGB")
        image.thumbnail((cell_w - 16, cell_h - 42), Image.Resampling.LANCZOS)
        x = (index % columns) * cell_w + (cell_w - image.width) // 2
        y = (index // columns) * cell_h + 4 + (cell_h - 42 - image.height) // 2
        sheet.paste(image, (x, y))
        draw.text(((index % columns) * cell_w + 8, (index // columns) * cell_h + cell_h - 32),
                  path.stem, font=font, fill=(245, 239, 220))
    sheet.save(out_path)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    prs = Presentation(DECK)
    slides = []
    for index, slide in enumerate(prs.slides, start=1):
        texts = []
        for shape in slide.shapes:
            if getattr(shape, "has_text_frame", False) and shape.text.strip():
                texts.append({
                    "text": shape.text.strip(),
                    "x": round(shape.left / prs.slide_width, 5),
                    "y": round(shape.top / prs.slide_height, 5),
                    "w": round(shape.width / prs.slide_width, 5),
                    "h": round(shape.height / prs.slide_height, 5),
                })
        slides.append({"slide": index, "texts": texts})

    copied_slides = sorted(COPY.glob("幻灯片*.png"), key=lambda p: int(p.stem.replace("幻灯片", "")))
    home_background = COPY / "幻灯片1背景.jpg"
    portraits = sorted(MATERIALS.glob("图片*"), key=lambda p: int(p.stem.replace("图片", "")))
    portrait_meta = []
    for path in portraits:
        with Image.open(path) as image:
            portrait_meta.append({"file": path.name, "width": image.width, "height": image.height, "mode": image.mode})
    bg_meta = []
    all_backgrounds = ([home_background] if home_background.exists() else []) + copied_slides
    for path in all_backgrounds:
        with Image.open(path) as image:
            slide_id = 1 if path == home_background else int(path.stem.replace("幻灯片", ""))
            bg_meta.append({"slide": slide_id, "file": path.name,
                            "width": image.width, "height": image.height, "mode": image.mode})

    index_doc = {
        "deck": DECK.name,
        "slide_count": len(prs.slides),
        "slide_inches": [prs.slide_width / 914400, prs.slide_height / 914400],
        "background_folder": COPY.name,
        "slides": slides,
        "background_images": bg_meta,
        "portraits": portrait_meta,
    }
    (OUT / "ppt_text_and_asset_index.json").write_text(
        json.dumps(index_doc, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    if portraits:
        contact_sheet(portraits, OUT / "portraits_contact_sheet.png", 4, 250, 210)
    if all_backgrounds:
        contact_sheet(all_backgrounds, OUT / "slides_contact_sheet.png", 4, 360, 230)

    # The source deck uses one home page followed by four pages for each person:
    # intro, life timeline, main contributions, and representative deeds.
    people = []
    for person_index in range(13):
        base = 2 + person_index * 4
        intro = slides[base - 1]
        name = next((item["text"].splitlines()[0].strip() for item in intro["texts"]
                     if item["text"].strip() and not re.fullmatch(r"\d+", item["text"].strip())),
                    f"人物{person_index + 1}")
        pages = {}
        for role, slide_id in (("intro", base), ("life", base + 1),
                               ("contribution", base + 2), ("deeds", base + 3)):
            pages[role] = {
                "slide": slide_id,
                "background": f"幻灯片{slide_id}.png",
                "texts": slides[slide_id - 1]["texts"],
            }
        people.append({
            "index": person_index,
            "name": name,
            "portrait": f"图片{person_index + 1}.{portraits[person_index].suffix.lstrip('.')}",
            "pages": pages,
        })
    nav_map = {
        "home": {"background": home_background.name if home_background.exists() else None,
                 "slide": 1, "portrait_order": [p["portrait"] for p in people]},
        "people": people,
        "navigation": {
            "KEY1": "next person / next reveal item",
            "KEY2": "previous person / previous reveal item",
            "KEY3": "back one level",
            "KEY4": "enter / reveal the next subtitle",
            "SW3": "autoplay intro, life, contribution and deeds; skip quiz as previously agreed",
        },
        "quiz_note": "The source PPT has no quiz slides. Keep the existing interactive quiz flow and author questions from the slide facts after content review.",
    }
    (OUT / "medal_navigation_map.json").write_text(
        json.dumps(nav_map, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    print(f"indexed {len(slides)} slides, {len(all_backgrounds)} background images, {len(portraits)} portraits")
    print(f"output: {OUT}")


if __name__ == "__main__":
    main()
