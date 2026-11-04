"""Build TF-card BMP assets from the cleaned PPT slide backgrounds.

The legacy ``assets_720p`` pack remains untouched.  This script emits a new
pack containing 53 1280x720 page backgrounds and 13 independently addressable
portrait layers, plus CSV/JSON indexes for the later FPGA sector mapper.
"""

from __future__ import print_function

import csv
import hashlib
import json
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
MATERIALS = Path(r"C:\Users\20251\Desktop\材料")
REVIEW = ROOT / "materials_review"
TEMPLATES = REVIEW / "clean_template_png"
NAVIGATION = REVIEW / "medal_navigation_map.json"
OUT = ROOT / "assets_ppt_720p"
CANVAS = (1280, 720)
PORTRAIT = (320, 400)
PORTRAIT_MATTE = (47, 16, 22, 255)


def resampling_lanczos():
    return getattr(getattr(Image, "Resampling", Image), "LANCZOS")


def rgb_flattened(path, size, matte=None):
    image = Image.open(str(path))
    if image.mode in ("RGBA", "LA") or "transparency" in image.info:
        rgba = image.convert("RGBA")
        base = Image.new("RGBA", rgba.size, matte or (0, 0, 0, 255))
        base.alpha_composite(rgba)
        image = base.convert("RGB")
    else:
        image = image.convert("RGB")
    if image.size != size:
        image = image.resize(size, resampling_lanczos())
    return image


def save_bmp(image, destination):
    image.save(str(destination), format="BMP")
    raw = destination.read_bytes()
    if raw[:2] != b"BM":
        raise ValueError("BMP signature missing: {}".format(destination.name))
    declared = int.from_bytes(raw[2:6], "little")
    offset = int.from_bytes(raw[10:14], "little")
    width = int.from_bytes(raw[18:22], "little", signed=True)
    height = int.from_bytes(raw[22:26], "little", signed=True)
    depth = int.from_bytes(raw[28:30], "little")
    compression = int.from_bytes(raw[30:34], "little")
    if declared != len(raw) or offset < 54 or depth != 24 or compression != 0:
        raise ValueError("Unexpected BMP header: {}".format(destination.name))
    if width <= 0 or height <= 0:
        raise ValueError("Unsupported BMP orientation: {}".format(destination.name))
    return len(raw), hashlib.sha256(raw).hexdigest().upper()


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    nav = json.loads(NAVIGATION.read_text(encoding="utf-8"))
    rows = []
    slide_meta = {1: {"person": "", "page": "home"}}
    for person in nav["people"]:
        for page, info in person["pages"].items():
            slide_meta[int(info["slide"])] = {"person": person["name"], "page": page}

    # Slides are exported from the cleaned PowerPoint backgrounds and resized
    # with high-quality filtering to match the intended HDMI canvas exactly.
    for slide in range(1, 54):
        source = TEMPLATES / "slide_{:03d}.png".format(slide)
        if not source.exists():
            raise FileNotFoundError("Missing cleaned slide background: {}".format(source))
        target = OUT / "BG{:03d}.BMP".format(slide)
        image = rgb_flattened(source, CANVAS)
        length, digest = save_bmp(image, target)
        image.close()
        rows.append({
            "id": "BG{:03d}".format(slide), "type": "page_background",
            "person": slide_meta.get(slide, {}).get("person", ""),
            "page": slide_meta.get(slide, {}).get("page", "unknown"),
            "source": "slide_{:03d}.png".format(slide),
            "file": target.name, "slide": slide, "width": CANVAS[0],
            "height": CANVAS[1], "bytes": length, "sha256": digest,
        })

    for person in nav["people"]:
        index = int(person["index"]) + 1
        portrait_path = MATERIALS / person["portrait"]
        if not portrait_path.exists():
            raise FileNotFoundError("Missing portrait: {}".format(portrait_path))
        target = OUT / "POR{:02d}.BMP".format(index)
        image = rgb_flattened(portrait_path, PORTRAIT, PORTRAIT_MATTE)
        length, digest = save_bmp(image, target)
        image.close()
        rows.append({
            "id": "POR{:02d}".format(index), "type": "portrait_layer",
            "person": person["name"], "source": person["portrait"],
            "file": target.name, "width": PORTRAIT[0], "height": PORTRAIT[1],
            "bytes": length, "sha256": digest,
        })

    fields = ["id", "type", "person", "page", "source", "file", "slide",
              "width", "height", "bytes", "sha256"]
    with (OUT / "manifest.csv").open("w", newline="", encoding="utf-8-sig") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)

    index = {
        "resolution": "1280x720",
        "background_count": 53,
        "portrait_count": len(nav["people"]),
        "source": "materials_review/clean_template_png",
        "assets": rows,
    }
    (OUT / "asset_index.json").write_text(
        json.dumps(index, ensure_ascii=False, indent=2), encoding="utf-8"
    )

    total = sum(row["bytes"] for row in rows)
    (OUT / "README_TF_ASSETS.md").write_text(
        "# PPT kiosk TF asset pack\n\n"
        "- 53 cleaned PPT page backgrounds: 1280x720, 24-bit uncompressed BMP.\n"
        "- 13 independent portrait layers: 320x400, 24-bit uncompressed BMP.\n"
        "- Total binary assets: {} files, {:,} bytes ({:.1f} MiB).\n"
        "- `manifest.csv` and `asset_index.json` map assets to slide/person identity and SHA-256.\n\n"
        "This is a prepared local asset pack, not yet a board-ready TF layout. The current HDL does not yet provide FAT32 directory/file lookup for all assets or a sector map for this manifest. Wait until the FPGA reader and image-layer compositor are integrated before copying this pack to the TF card.\n"
        .format(len(rows), total, total / (1024.0 * 1024.0)),
        encoding="utf-8",
    )
    print("Prepared {} BMP assets ({:,} bytes) at {}".format(len(rows), total, OUT))


if __name__ == "__main__":
    main()
