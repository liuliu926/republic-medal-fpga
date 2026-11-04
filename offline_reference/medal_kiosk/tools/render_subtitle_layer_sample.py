"""Create a bilingual, key-revealed subtitle-layer sample for PPT slide 4."""

from __future__ import print_function

import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
REVIEW = ROOT / "materials_review"
BACKGROUND_DIR = REVIEW / "clean_template_png"
OUT = REVIEW / "subtitle_layer_sample"
INDEX = json.loads((REVIEW / "ppt_text_and_asset_index.json").read_text(encoding="utf-8-sig"))
FONT_FILE = r"C:\Windows\Fonts\msyh.ttc"
W, H = 1280, 720
KEY_COLOR = (255, 0, 255)
IVORY = (255, 247, 225)
GOLD = (255, 211, 104)

# Text supplied from the PPT is the source of truth. English is deliberately
# kept as a keyed translation map so SW2 can select a matching text layer.
EN = {
    "共和国勋章 · 人物志": "Republic Medal · Profiles",
    "于敏　|　主要贡献": "Yu Min  |  Major Contributions",
    "生平": "Bio",
    "主要贡献": "Contrib.",
    "代表事迹": "Deeds",
    "互动问答": "Quiz",
    "01": "01",
    "突破氢弹原理": "Breakthrough in H-Bomb Theory",
    "提出从原理到构形的完整设想，解决氢弹自持热核燃烧的关键问题。":
        "Proposed a complete concept from principle to configuration, resolving a key challenge in sustaining thermonuclear burn.",
    "02": "02",
    "填补理论空白": "Filled a Theoretical Gap",
    "建立我国核武器物理研究体系，完成大量基础性计算与论证。":
        "Established China's nuclear-weapons physics research system and completed extensive foundational calculations and analyses.",
    "03": "03",
    "引领技术路线": "Guided the Technical Roadmap",
    "长期主持核武器理论研究，为多次试验成功提供核心支撑。":
        "Led nuclear-weapons theory research for many years, providing key support for multiple successful tests.",
    "04": "04",
    "培育科研队伍": "Mentored Research Teams",
    "带出一批核物理研究骨干，形成我国自主的核理论研究力量。":
        "Trained nuclear-physics researchers and helped build China's independent nuclear-theory research capacity.",
}

ALWAYS = list(range(0, 6))
CARD_GROUPS = [[6, 7, 8], [9, 10, 11], [12, 13, 14], [15, 16, 17]]


def font(size):
    return ImageFont.truetype(FONT_FILE, size)


def wrap(draw, value, face, max_width):
    lines, line = [], ""
    if " " in value:
        units = value.split(" ")
        for unit in units:
            candidate = unit if not line else line + " " + unit
            if line and draw.textsize(candidate, font=face)[0] > max_width:
                lines.append(line)
                line = unit
            else:
                line = candidate
            if draw.textsize(line, font=face)[0] > max_width:
                # Break only an unusually long English token, never at a normal
                # word boundary that would make a line hard to read.
                prefix = ""
                for char in line:
                    if prefix and draw.textsize(prefix + char, font=face)[0] > max_width:
                        lines.append(prefix)
                        prefix = char
                    else:
                        prefix += char
                line = prefix
    else:
        for char in value:
            candidate = line + char
            if line and draw.textsize(candidate, font=face)[0] > max_width:
                lines.append(line)
                line = char
            else:
                line = candidate
    if line:
        lines.append(line)
    return lines


def fit_size(draw, value, box, start):
    x, y, w, h = box
    for size in range(start, 11, -1):
        face = font(size)
        lines = wrap(draw, value, face, w)
        line_h = size + max(2, size // 5)
        if len(lines) * line_h <= h:
            return face, lines, line_h
    face = font(11)
    lines = wrap(draw, value, face, w)
    return face, lines, 13


def render_layer(language, visible_indices=None):
    page = INDEX["slides"][3]
    rgba = Image.new("RGBA", (W, H), (KEY_COLOR[0], KEY_COLOR[1], KEY_COLOR[2], 0))
    draw = ImageDraw.Draw(rgba)
    for i, item in enumerate(page["texts"]):
        if visible_indices is not None and i not in visible_indices:
            continue
        value = item["text"] if language == "zh" else EN[item["text"]]
        x, y = int(item["x"] * W), int(item["y"] * H)
        box = (x, y, max(1, int(item["w"] * W)), max(1, int(item["h"] * H)))
        if i < 2:
            start_size, color = (23 if i == 0 else 38), IVORY
        elif i < 6:
            start_size, color = 15, GOLD
        elif i in (6, 9, 12, 15):
            start_size, color = 26, GOLD
        elif i in (7, 10, 13, 16):
            start_size, color = 25, GOLD
        else:
            start_size, color = 22, IVORY
        face, lines, line_h = fit_size(draw, value, box, start_size)
        for line_no, line in enumerate(lines):
            draw.text((x, y + line_no * line_h), line, font=face, fill=color + (255,))
    return rgba


def to_keyed_bmp(rgba, path):
    rgb = Image.new("RGB", rgba.size, KEY_COLOR)
    hard_mask = rgba.getchannel("A").point(lambda alpha: 255 if alpha >= 128 else 0)
    rgb.paste(rgba.convert("RGB"), (0, 0), hard_mask)
    rgb.save(str(path), format="BMP")
    rgb.close()


def crop_for_indices(rgba, indices):
    items = INDEX["slides"][3]["texts"]
    x0 = min(int(items[i]["x"] * W) for i in indices)
    y0 = min(int(items[i]["y"] * H) for i in indices)
    x1 = max(int((items[i]["x"] + items[i]["w"]) * W) for i in indices)
    y1 = max(int((items[i]["y"] + items[i]["h"]) * H) for i in indices)
    pad = 6
    box = (max(0, x0 - pad), max(0, y0 - pad), min(W, x1 + pad), min(H, y1 + pad))
    return rgba.crop(box), box


def render_reveal_preview(language, step, path):
    bg = Image.open(str(BACKGROUND_DIR / "slide_004.png")).convert("RGBA")
    allowed = set(ALWAYS)
    for group_no in range(step):
        allowed.update(CARD_GROUPS[group_no])
    visible = render_layer(language, allowed)
    bg.alpha_composite(visible)
    bg.convert("RGB").save(str(path), optimize=True)
    bg.close()


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    records = []
    for language in ("zh", "en"):
        layer = render_layer(language)
        layer.save(str(OUT / "TXT004_{}_full.png".format(language.upper())), optimize=True)
        layer_specs = [("H", ALWAYS, 0)] + [
            ("C{:02d}".format(i + 1), group, i + 1)
            for i, group in enumerate(CARD_GROUPS)
        ]
        layer_records = []
        for layer_id, indexes, reveal_step in layer_specs:
            crop, box = crop_for_indices(layer, indexes)
            stem = "S004_{}_{}".format(layer_id, language.upper())
            png_path = OUT / (stem + ".png")
            bmp_path = OUT / (stem + ".BMP")
            crop.save(str(png_path), optimize=True)
            to_keyed_bmp(crop, bmp_path)
            layer_records.append({
                "id": layer_id, "file": bmp_path.name, "preview": png_path.name,
                "x": box[0], "y": box[1], "width": crop.size[0],
                "height": crop.size[1], "key4_reveal_step": reveal_step,
                "text_indices": indexes,
            })
            crop.close()
        for step in range(5):
            preview = OUT / "preview_slide004_{}_step{}.png".format(language, step)
            render_reveal_preview(language, step, preview)
        records.append({
            "slide": 4, "language": language, "canvas": "1280x720",
            "key_color_rgb": list(KEY_COLOR), "layers": layer_records,
            "always_visible_text_indices": ALWAYS,
            "key4_reveal_groups": CARD_GROUPS,
            "key4_max_step": len(CARD_GROUPS),
        })
        layer.close()
    (OUT / "reveal_map.json").write_text(
        json.dumps(records, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    print("Created Chinese/English keyed text layers and 10 reveal previews.")


if __name__ == "__main__":
    main()
