"""Render Chinese PPT text as independently addressable, cropped TF layers."""

from __future__ import print_function

import csv
import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
REVIEW = ROOT / "materials_review"
LANG = sys.argv[1].lower() if len(sys.argv) > 1 else "zh"
if LANG not in ("zh", "en"):
    raise SystemExit("Usage: python render_all_zh_text_layers.py [zh|en]")
OUT = ROOT / "assets_ppt_720p" / ("text_zh" if LANG == "zh" else "text_en")
INDEX = json.loads((REVIEW / "ppt_text_and_asset_index.json").read_text(encoding="utf-8-sig"))
NAV = json.loads((REVIEW / "medal_navigation_map.json").read_text(encoding="utf-8"))
FONT_PATH = r"C:\Windows\Fonts\msyh.ttc" if LANG == "zh" else r"C:\Windows\Fonts\arial.ttf"
ENGLISH_MAP = json.loads((REVIEW / "english_translations.json").read_text(encoding="utf-8")) if LANG == "en" else {}
if LANG == "en":
    with (REVIEW / "english_translation_inventory.csv").open(encoding="utf-8-sig", newline="") as stream:
        _inventory = list(csv.DictReader(stream))
    TRANSLATIONS = {row["Chinese"]: ENGLISH_MAP[row["id"]] for row in _inventory if row["id"] in ENGLISH_MAP}
    missing_ids = [row["id"] for row in _inventory if row["id"] not in ENGLISH_MAP]
    if missing_ids:
        raise SystemExit("Missing English translations: " + ", ".join(missing_ids))
else:
    TRANSLATIONS = {}
W, H = 1280, 720
KEY = (255, 0, 255)
IVORY = (255, 247, 225, 255)
GOLD = (255, 211, 104, 255)


def font(px):
    return ImageFont.truetype(FONT_PATH, px)


def wrap(draw, text, face, width):
    if LANG == "en":
        lines, line = [], ""
        for word in text.split():
            candidate = word if not line else line + " " + word
            if line and draw.textsize(candidate, font=face)[0] > width:
                lines.append(line)
                line = word
            else:
                line = candidate
        if line:
            lines.append(line)
        return lines
    lines, line = [], ""
    for char in text:
        candidate = line + char
        if line and draw.textsize(candidate, font=face)[0] > width:
            lines.append(line)
            line = char
        else:
            line = candidate
    if line:
        lines.append(line)
    return lines


def fitted(draw, value, box, preferred):
    x, y, width, height = box
    for size in range(preferred, 10, -1):
        face = font(size)
        lines = wrap(draw, value, face, width)
        line_height = size + max(2, size // 5)
        if len(lines) * line_height <= height:
            return face, lines, line_height
    face = font(10)
    return face, wrap(draw, value, face, width), 12


def page_metadata():
    result = {1: {"person": "", "page": "home"}}
    names_en = {
        "于敏": "Yumin", "申纪兰": "Shen Jilan", "孙家栋": "Sun Jiadong",
        "李延年": "Li Yannian", "张富清": "Zhang Fuqing", "袁隆平": "Yuan Longping",
        "黄旭华": "Huang Xuhua", "屠呦呦": "Tu Youyou", "钟南山": "Zhong Nanshan",
        "王永志": "Wang Yongzhi", "王振义": "Wang Zhenyi", "李振声": "Li Zhensheng",
        "黄宗德": "Huang Zongde",
    }
    for person in NAV["people"]:
        for role, info in person["pages"].items():
            name = names_en.get(person["name"], person["name"]) if LANG == "en" else person["name"]
            result[int(info["slide"])] = {"person": name, "page": role}
    return result


def make_groups(slide_number, role, items):
    if role in ("home", "intro"):
        return [{"id": "FULL", "step": 0, "indices": list(range(len(items)))}]
    header = [i for i, item in enumerate(items) if item["y"] < 0.22]
    body = [i for i in range(len(items)) if i not in header]
    groups = [{"id": "H", "step": 0, "indices": header}]
    if role == "contribution":
        cells = {(0, 0): [], (0, 1): [], (1, 0): [], (1, 1): []}
        for i in body:
            item = items[i]
            row = 0 if item["y"] < 0.55 else 1
            col = 0 if item["x"] < 0.5 else 1
            cells[(row, col)].append(i)
        for n, key in enumerate(((0, 0), (0, 1), (1, 0), (1, 1)), 1):
            if cells[key]:
                groups.append({"id": "C{:02d}".format(n), "step": n,
                               "indices": cells[key]})
    elif role in ("life", "deeds"):
        # The cleaned deck uses distinct vertical timeline rows. Merge each row
        # into one reveal so dates, titles, and descriptions appear together.
        anchors = []
        for i in body:
            y = items[i]["y"]
            match = next((a for a in anchors if abs(a - y) <= 0.085), None)
            if match is None:
                anchors.append(y)
        anchors.sort()
        for n, anchor in enumerate(anchors, 1):
            row = [i for i in body if abs(items[i]["y"] - anchor) <= 0.085]
            groups.append({"id": "R{:02d}".format(n), "step": n, "indices": row})
    elif body:
        groups.append({"id": "BODY", "step": 1, "indices": body})
    return groups


def draw_text_layer(items, indices):
    canvas = Image.new("RGBA", (W, H), (KEY[0], KEY[1], KEY[2], 0))
    draw = ImageDraw.Draw(canvas)
    for i in indices:
        item = items[i]
        normalized = " ".join(item["text"].split())
        value = TRANSLATIONS.get(normalized, item["text"])
        if LANG == "en" and item["x"] > 0.88 and item["y"] < 0.20:
            value = {
                "Biography": "Life",
                "Major Contributions": "Impact",
                "Notable Stories": "Stories",
                "Interactive Quiz": "Quiz",
            }.get(value, value)
        x, y = int(item["x"] * W), int(item["y"] * H)
        bw, bh = max(1, int(item["w"] * W)), max(1, int(item["h"] * H))
        if len(value) <= 4 and item["h"] < 0.09:
            preferred, color = 24, GOLD
        elif item["h"] > 0.12:
            preferred, color = 21, IVORY
        elif item["h"] > 0.07:
            preferred, color = 30, IVORY
        elif item["h"] < 0.05:
            preferred, color = 16, GOLD
        else:
            preferred, color = 22, GOLD
        face, lines, line_height = fitted(draw, value, (x, y, bw, bh), preferred)
        for line_no, line in enumerate(lines):
            draw.text((x, y + line_no * line_height), line, font=face, fill=color)
    return canvas


def bmp_keyed(rgba, path):
    rgb = Image.new("RGB", rgba.size, KEY)
    mask = rgba.getchannel("A").point(lambda a: 255 if a >= 128 else 0)
    rgb.paste(rgba.convert("RGB"), (0, 0), mask)
    rgb.save(str(path), format="BMP")
    rgb.close()


def save_layer(items, group, slide, role, person):
    rgba = draw_text_layer(items, group["indices"])
    nonempty = [items[i] for i in group["indices"]]
    x0 = min(int(item["x"] * W) for item in nonempty)
    y0 = min(int(item["y"] * H) for item in nonempty)
    x1 = max(int((item["x"] + item["w"]) * W) for item in nonempty)
    y1 = max(int((item["y"] + item["h"]) * H) for item in nonempty)
    pad = 6
    box = (max(0, x0 - pad), max(0, y0 - pad), min(W, x1 + pad), min(H, y1 + pad))
    crop = rgba.crop(box)
    stem = "S{:03d}_{}".format(slide, group["id"])
    png = OUT / (stem + ".png")
    bmp = OUT / (stem + ".BMP")
    crop.save(str(png), optimize=True)
    bmp_keyed(crop, bmp)
    row = {
        "slide": slide, "person": person, "page": role, "layer": group["id"],
        "file": bmp.name, "preview": png.name, "x": box[0], "y": box[1],
        "width": crop.size[0], "height": crop.size[1],
        "key4_reveal_step": group["step"], "text_indices": group["indices"],
    }
    crop.close()
    rgba.close()
    return row


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    slide_meta = page_metadata()
    records = []
    pages = []
    for slide_no, slide_data in enumerate(INDEX["slides"], 1):
        meta = slide_meta.get(slide_no, {"person": "", "page": "unknown"})
        items = slide_data.get("texts", [])
        groups = make_groups(slide_no, meta["page"], items)
        page_layers = []
        for group in groups:
            if not group["indices"]:
                continue
            record = save_layer(items, group, slide_no, meta["page"], meta["person"])
            records.append(record)
            page_layers.append(record)
        pages.append({"slide": slide_no, "person": meta["person"],
                      "page": meta["page"], "layers": page_layers})

    with (OUT / "manifest.csv").open("w", newline="", encoding="utf-8-sig") as stream:
        fields = ["slide", "person", "page", "layer", "file", "preview", "x", "y",
                  "width", "height", "key4_reveal_step", "text_indices"]
        writer = csv.DictWriter(stream, fieldnames=fields)
        writer.writeheader()
        for record in records:
            row = dict(record)
            row["text_indices"] = ",".join(str(i) for i in row["text_indices"])
            writer.writerow(row)

    (OUT / "layer_index.json").write_text(
        json.dumps({"canvas": "1280x720", "language": LANG, "key_color_rgb": list(KEY),
                    "slide_count": len(pages), "layer_count": len(records),
                    "pages": pages}, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    total = sum((OUT / row["file"]).stat().st_size for row in records)
    (OUT / "README.md").write_text(
        "# {} cropped text layers\n\n".format("Chinese" if LANG == "zh" else "English") +
        "- Pages: {}\n- Cropped keyed BMP layers: {}\n- Binary size: {:,} bytes ({:.1f} MiB)\n"
        "- Layer locations and KEY4 reveal steps: `layer_index.json` / `manifest.csv`.\n"
        "- Current output is an asset prototype. It is not yet supported by the board RTL.\n"
        .format(len(pages), len(records), total, total / 1048576.0), encoding="utf-8"
    )
    print("Rendered {} {} text layers across {} PPT slides ({:,} bytes).".format(
        len(records), "Chinese" if LANG == "zh" else "English",
        len(pages), total))


if __name__ == "__main__":
    main()
