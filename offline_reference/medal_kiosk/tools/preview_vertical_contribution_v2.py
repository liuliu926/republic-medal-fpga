"""Render the TF bitmap plus FPGA column mapping as a desktop preview."""
from pathlib import Path
from PIL import Image

root = Path(__file__).resolve().parents[1]
assets = root / "assets_720p/contribution_vertical_candidate_v2"
background = Image.open(assets / "BG004.BMP").convert("RGB")
atlas = Image.open(assets / "ART04C.BMP").convert("RGB")

# Recreate the text bank mapping used in home_text_mask_vertical_contrib_v2.v.
header = atlas.crop((0, 0, 600, 64))
mask = header.convert("L").point(lambda v: 255 if v >= 128 else 0)
background.paste((255, 241, 205), (80, 46, 680, 110), mask)
for row, base in enumerate((838, 623, 408, 193), start=1):
    bank = atlas.crop((0, row * 64, 720, (row + 1) * 64)).transpose(Image.TRANSPOSE)
    for src, dst, width, color in ((0, 0, 20, (255, 241, 205)),
                                    (20, 40, 20, (255, 241, 205)),
                                    (40, 110, 24, (255, 225, 109))):
        layer = bank.crop((src, 150, src + width, 662)).convert("L")
        mask = layer.point(lambda v: 255 if v >= 128 else 0)
        background.paste(color, (base + dst, 150, base + dst + width, 662), mask)

target = assets / "preview_yumin_all_four.png"
background.save(target)
print(target)
