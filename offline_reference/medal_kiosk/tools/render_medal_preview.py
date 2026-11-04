"""Render 16:9 UI previews from the supplied PPT backgrounds and portrait assets."""

from __future__ import annotations

import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
MATERIALS = Path(r"C:\Users\20251\Desktop\材料")
COPY = MATERIALS / "共和国勋章获得者人物志 - 副本"
OUT = ROOT / "materials_review"
W, H = 1280, 720
FONT_PATH = r"C:\Windows\Fonts\msyh.ttc"


def font(size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(FONT_PATH, size)


def fit_background(path: Path) -> Image.Image:
    return Image.open(path).convert("RGB").resize((W, H), Image.Resampling.LANCZOS)


def portrait(index: int) -> Image.Image:
    path = next(MATERIALS.glob(f"图片{index + 1}.*"))
    return Image.open(path).convert("RGB")


def put_fitted(draw: ImageDraw.ImageDraw, text: str, xy: tuple[int, int], max_width: int,
               max_lines: int, face: ImageFont.FreeTypeFont, fill: tuple[int, int, int], spacing: int = 5) -> None:
    words: list[str] = []
    line = ""
    for char in text:
        candidate = line + char
        if line and draw.textbbox((0, 0), candidate, font=face)[2] > max_width:
            words.append(line)
            line = char
        else:
            line = candidate
    if line:
        words.append(line)
    for n, line in enumerate(words[:max_lines]):
        draw.text((xy[0], xy[1] + n * (face.size + spacing)), line, font=face, fill=fill)


def render_home(data: dict, index: dict) -> None:
    bg = Image.open(COPY / "幻灯片1背景.jpg").convert("RGB").resize((W, H), Image.Resampling.LANCZOS)
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    draw.rounded_rectangle((28, 20, 1252, 112), radius=18, fill=(45, 8, 18, 190), outline=(236, 190, 76, 225), width=2)
    draw.text((64, 32), "共和国勋章人物志", font=font(42), fill=(255, 244, 211, 255))
    draw.text((68, 82), "13 位获得者 · 按 KEY1 / KEY2 选择，KEY4 进入", font=font(18), fill=(244, 206, 102, 255))
    card_w, card_h, gap_x, gap_y = 230, 174, 14, 12
    left0, top0 = 43, 132
    for person in data["people"]:
        idx = person["index"]
        col, row = idx % 5, idx // 5
        x, y = left0 + col * (card_w + gap_x), top0 + row * (card_h + gap_y)
        selected = idx == 0
        draw.rounded_rectangle((x, y, x + card_w, y + card_h), radius=12,
                               fill=(36, 17, 27, 225 if selected else 200),
                               outline=(255, 213, 92, 255) if selected else (215, 169, 75, 190),
                               width=4 if selected else 2)
        photo = portrait(idx)
        photo = photo.resize((78, 112), Image.Resampling.LANCZOS)
        mask = Image.new("L", photo.size, 0)
        ImageDraw.Draw(mask).rounded_rectangle((0, 0, photo.width - 1, photo.height - 1), radius=10, fill=255)
        layer.paste(photo, (x + 13, y + 18), mask)
        page_texts = index["slides"][person["pages"]["intro"]["slide"] - 1]["texts"]
        year = next((item["text"] for item in page_texts if "—" in item["text"]), "")
        draw.text((x + 102, y + 43), person["name"], font=font(23), fill=(255, 247, 226, 255))
        draw.text((x + 103, y + 83), year, font=font(15), fill=(239, 205, 123, 255))
        if selected:
            draw.rounded_rectangle((x + 100, y + 119, x + 207, y + 153), radius=14,
                                   fill=(187, 43, 40, 245), outline=(255, 227, 150, 255), width=1)
            draw.text((x + 124, y + 124), "当前选择", font=font(16), fill=(255, 249, 225, 255))
    draw.rounded_rectangle((44, 696, 1238, 715), radius=8, fill=(45, 8, 18, 180))
    bg.paste(layer, (0, 0), layer)
    bg.save(OUT / "preview_home_720p.png")


def render_intro() -> None:
    bg = fit_background(COPY / "幻灯片2.png").convert("RGBA")
    photo = portrait(0).resize((316, 396), Image.Resampling.LANCZOS)
    mask = Image.new("L", photo.size, 255)
    bg.alpha_composite(Image.new("RGBA", bg.size, (0, 0, 0, 0)))
    bg.paste(photo, (116, 176), mask)
    draw = ImageDraw.Draw(bg, "RGBA")
    draw.rounded_rectangle((102, 168, 445, 586), radius=16, outline=(247, 198, 66, 255), width=4)
    # The PPT already provides the four focusable options. This prompt makes the
    # KEY4 reveal interaction visible in the preview without changing the template.
    draw.rounded_rectangle((514, 656, 1224, 703), radius=12, fill=(45, 10, 20, 220), outline=(231, 183, 64, 255), width=2)
    draw.text((544, 666), "KEY1 / KEY2 选择栏目     KEY4 逐条显现     KEY3 返回", font=font(20), fill=(255, 244, 218, 255))
    bg.convert("RGB").save(OUT / "preview_intro_720p.png")


def fill_text_shapes(slide_id: int, replacements: dict[str, str], out_name: str,
                     highlight: tuple[int, int, int, int] | None = None) -> None:
    idx = json.loads((OUT / "ppt_text_and_asset_index.json").read_text(encoding="utf-8"))
    page = idx["slides"][slide_id - 1]
    bg = fit_background(COPY / f"幻灯片{slide_id}.png").convert("RGBA")
    draw = ImageDraw.Draw(bg, "RGBA")
    for item in page["texts"]:
        raw = item["text"]
        if raw not in replacements:
            continue
        x, y = int(item["x"] * W), int(item["y"] * H)
        max_width = int(item["w"] * W)
        max_height = int(item["h"] * H)
        # Small label/key text is already baked into the PPT PNG; these replacements
        # target body placeholders and use the template's gold/ivory palette.
        title = len(raw) <= 12 and item["h"] < 0.08
        size = 24 if title else 20
        face = font(size)
        color = (243, 196, 73, 255) if title else (255, 244, 223, 255)
        put_fitted(draw, replacements[raw], (x + 2, y + 2), max_width - 8,
                   max(1, max_height // (size + 5)), face, color, spacing=4)
    if highlight:
        draw.rounded_rectangle(highlight, radius=10, outline=(255, 219, 110, 255), width=4)
    bg.convert("RGB").save(OUT / out_name)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    index = json.loads((OUT / "ppt_text_and_asset_index.json").read_text(encoding="utf-8"))
    render_home(json.loads((OUT / "medal_navigation_map.json").read_text(encoding="utf-8")), index)
    render_intro()

    # The source PPT leaves these boxes empty. Fill them with the exact source captions.
    fill_text_shapes(3, {
        "生于天津宁河，少年时代立志科学报国": "生于天津宁河，少年时代立志科学报国",
        "毕业于北京大学物理系，留校从事原子核理论研究": "毕业于北京大学物理系，留校从事原子核理论研究",
        "奉命转向氢弹理论预研，从此隐姓埋名": "奉命转向氢弹理论预研，从此隐姓埋名",
        "参与我国第一颗氢弹试验，理论方案获得验证": "参与我国第一颗氢弹试验，理论方案获得验证",
    }, "preview_life_720p.png")
    fill_text_shapes(4, {
        "突破氢弹原理": "突破氢弹原理",
        "提出从原理到构形的完整设想，解决氢弹自持热核燃烧的关键问题。": "提出从原理到构形的完整设想，解决氢弹自持热核燃烧的关键问题。",
        "填补理论空白": "填补理论空白",
        "建立我国核武器物理研究体系，完成大量基础性计算与论证。": "建立我国核武器物理研究体系，完成大量基础性计算与论证。",
        "引领技术路线": "引领技术路线",
        "长期主持核武器理论研究，为多次试验成功提供核心支撑。": "长期主持核武器理论研究，为多次试验成功提供核心支撑。",
        "培育科研队伍": "培育科研队伍",
        "带出一批核物理研究骨干，形成我国自主的核理论研究力量。": "带出一批核物理研究骨干，形成我国自主的核理论研究力量。",
    }, "preview_contribution_720p.png", highlight=(66, 184, 628, 321))
    fill_text_shapes(5, {
        "临危受命": "临危受命",
        "在国力薄弱、技术封锁的条件下，毅然接受氢弹理论预研任务。": "在国力薄弱、技术封锁的条件下，毅然接受氢弹理论预研任务。",
        "原理突破": "原理突破",
        "带领团队完成关键计算，攻破氢弹自持热核燃烧的理论难关。": "带领团队完成关键计算，攻破氢弹自持热核燃烧的理论难关。",
        "震惊世界": "震惊世界",
        "我国第一颗氢弹爆炸成功，从原子弹到氢弹仅用两年零八个月。": "我国第一颗氢弹爆炸成功，从原子弹到氢弹仅用两年零八个月。",
    }, "preview_deeds_720p.png")
    print("Rendered 4 template-matched previews at 1280x720.")


if __name__ == "__main__":
    main()
