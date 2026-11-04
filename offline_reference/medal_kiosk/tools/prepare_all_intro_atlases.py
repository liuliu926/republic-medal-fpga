"""Stage the 13 PPT introduction text masks for the 720p FPGA renderer.

These are PC-side assets only. The board still uses its older two-person
reader until the named-file layer loader is integrated and verified.
"""

import json
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
CATALOG = json.loads((ROOT / "prepared_resource_catalog" / "catalog.json").read_text(encoding="utf-8"))
OUT = ROOT / "assets_720p" / "intro_atlas_staging"
OUT.mkdir(parents=True, exist_ok=True)

STRIPS = (160, 260, 316, 367, 478, 561)
ATLAS_WIDTH = 768
ROW_HEIGHT = 48
order = {item["person"]: i + 1 for i, item in enumerate(CATALOG["portrait_order"])}
rows = []

for page in CATALOG["pages"]:
    if page["page"] != "intro":
        continue
    person = page["person"]
    index = order[person]
    for language, suffix in (("zh", "C"), ("en", "E")):
        layer_index = json.loads(
            (ROOT / "assets_ppt_720p" / f"text_{language}" / "layer_index.json").read_text(encoding="utf-8")
        )
        source_page = next(item for item in layer_index["pages"] if item["slide"] == page["slide"])
        layer = source_page["layers"][0]
        source = Image.open(ROOT / "assets_ppt_720p" / f"text_{language}" / layer["preview"]).convert("RGBA")
        screen = Image.new("RGBA", (1280, 720), (0, 0, 0, 0))
        screen.paste(source, (layer["x"], layer["y"]))
        atlas = Image.new("RGB", (ATLAS_WIDTH, 320), (0, 0, 0))
        for row, y in enumerate(STRIPS):
            strip = screen.crop((457, y, 1225, y + ROW_HEIGHT))
            atlas.paste(strip.convert("RGB"), (0, row * ROW_HEIGHT), strip.getchannel("A"))
        atlas = atlas.convert("L").point(lambda value: 255 if value >= 110 else 0).convert("RGB")
        filename = f"ITX{index:02d}{suffix}.BMP"
        atlas.save(OUT / filename, "BMP")
        rows.append({"person": person, "slide": page["slide"], "language": language, "file": filename,
                     "lit_pixels": sum(1 for value in atlas.convert("L").getdata() if value)})

if len(rows) != 26 or any(row["lit_pixels"] == 0 for row in rows):
    raise RuntimeError("Expected nonempty Chinese and English masks for all 13 introduction pages")
(OUT / "manifest.json").write_text(json.dumps(rows, ensure_ascii=False, indent=2), encoding="utf-8")
print(f"Wrote {len(rows)} introduction atlases to {OUT}")
