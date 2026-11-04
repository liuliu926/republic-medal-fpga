"""Pack the PPT slide 6 Chinese captions into the existing intro text mask."""

import json
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
LAYERS = ROOT / "assets_ppt_720p" / "text_zh"
INDEX = json.loads((LAYERS / "layer_index.json").read_text(encoding="utf-8"))
LAYER = next(page["layers"][0] for page in INDEX["pages"] if page["slide"] == 6)

source = Image.open(LAYERS / LAYER["preview"]).convert("RGBA")
screen = Image.new("RGBA", (1280, 720), (0, 0, 0, 0))
screen.paste(source, (LAYER["x"], LAYER["y"]))

atlas = Image.new("RGB", (768, 320), (0, 0, 0))
strips = (160, 260, 316, 367, 478, 561)
for index, y in enumerate(strips):
    strip = screen.crop((457, y, 1225, y + 48))
    atlas.paste(strip.convert("RGB"), (0, index * 48), strip.getchannel("A"))
atlas = atlas.convert("L").point(lambda value: 255 if value >= 110 else 0).convert("RGB")

target = ROOT / "assets_720p" / "SJTEXT.BMP"
atlas.save(target, "BMP")

preview = Image.open(ROOT / "assets_ppt_720p" / "BG006.BMP").convert("RGB")
portrait = Image.open(ROOT / "assets_ppt_720p" / "POR02.BMP").convert("RGB")
preview.paste(portrait, (100, 160))
for index, y in enumerate(strips):
    strip = atlas.crop((0, index * 48, 768, index * 48 + 48))
    preview.paste((255, 241, 205), (457, y, 1225, y + 48), strip.convert("L"))
preview.save(ROOT / "materials_review" / "preview_shen_text_atlas.png")
print(target)
