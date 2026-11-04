"""Prepare a deterministic 24-bit BMP pack for the HX4S20C TF-card pipeline."""

from __future__ import annotations

import csv
import hashlib
import json
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
MATERIALS = Path(r"C:\Users\20251\Desktop\材料")
COPY = MATERIALS / "共和国勋章获得者人物志 - 副本"
REVIEW = ROOT / "materials_review"
OUT = ROOT / "assets_720p"
CANVAS = (1280, 720)
PORTRAIT = (320, 400)
PORTRAIT_BG = (47, 16, 22, 255)


def rgb_image(path: Path, size: tuple[int, int], *, is_home: bool = False) -> Image.Image:
    image = Image.open(path)
    if image.mode == "RGBA":
        flattened = Image.new("RGBA", image.size, PORTRAIT_BG)
        flattened.alpha_composite(image)
        image = flattened.convert("RGB")
    else:
        image = image.convert("RGB")
    # The slide PNG backgrounds are already 16:9. The supplied home texture is
    # 2:1, and PowerPoint stretches that texture to the 16:9 slide canvas.
    return image.resize(size, Image.Resampling.LANCZOS)


def save_bmp(image: Image.Image, destination: Path) -> tuple[int, str]:
    image.save(destination, format="BMP")
    data = destination.read_bytes()
    # Check the fields consumed by the current RTL BMP reader before publishing.
    if data[:2] != b"BM":
        raise ValueError(f"BMP signature missing: {destination.name}")
    declared_size = int.from_bytes(data[2:6], "little")
    pixel_offset = int.from_bytes(data[10:14], "little")
    width = int.from_bytes(data[18:22], "little", signed=True)
    height = int.from_bytes(data[22:26], "little", signed=True)
    depth = int.from_bytes(data[28:30], "little")
    compression = int.from_bytes(data[30:34], "little")
    if declared_size != len(data) or pixel_offset < 54 or depth != 24 or compression != 0:
        raise ValueError(f"Unexpected BMP header: {destination.name}")
    if width <= 0 or height <= 0:
        raise ValueError(f"Unsupported BMP orientation: {destination.name}")
    return len(data), hashlib.sha256(data).hexdigest().upper()


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    navigation = json.loads((REVIEW / "medal_navigation_map.json").read_text(encoding="utf-8"))
    records: list[dict[str, str | int]] = []

    home_source = COPY / "幻灯片1背景.jpg"
    home_dest = OUT / "HOME.BMP"
    size, digest = save_bmp(rgb_image(home_source, CANVAS, is_home=True), home_dest)
    records.append({"id": "HOME", "type": "home_background", "person": "", "page": "home",
                    "source": home_source.name, "file": home_dest.name, "width": CANVAS[0],
                    "height": CANVAS[1], "bytes": size, "sha256": digest})

    role_code = {"intro": "I", "life": "B", "contribution": "C", "deeds": "E"}
    for person in navigation["people"]:
        person_id = person["index"] + 1
        for role, info in person["pages"].items():
            source = COPY / info["background"]
            stem = f"P{person_id:02d}{role_code[role]}"
            destination = OUT / f"{stem}.BMP"
            size, digest = save_bmp(rgb_image(source, CANVAS), destination)
            records.append({"id": stem, "type": "page_background", "person": person["name"],
                            "page": role, "source": source.name, "file": destination.name,
                            "slide": info["slide"], "width": CANVAS[0], "height": CANVAS[1],
                            "bytes": size, "sha256": digest})

        portrait_source = MATERIALS / person["portrait"]
        portrait_stem = f"POR{person_id:02d}"
        portrait_dest = OUT / f"{portrait_stem}.BMP"
        size, digest = save_bmp(rgb_image(portrait_source, PORTRAIT), portrait_dest)
        records.append({"id": portrait_stem, "type": "portrait_layer", "person": person["name"],
                        "page": "portrait", "source": portrait_source.name,
                        "file": portrait_dest.name, "width": PORTRAIT[0], "height": PORTRAIT[1],
                        "bytes": size, "sha256": digest})

    fields = ["id", "type", "person", "page", "source", "file", "slide",
              "width", "height", "bytes", "sha256"]
    with (OUT / "manifest.csv").open("w", newline="", encoding="utf-8-sig") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(records)

    total = sum(int(record["bytes"]) for record in records)
    readme = f"""# Republic Medal kiosk TF assets (720p)\n\n- Canvas backgrounds: 1280x720, 24-bit uncompressed BMP.\n- Portrait layers: 320x400, 24-bit uncompressed BMP, flattened over a dark-red matte.\n- Count: {len(records)} assets ({sum(r['type'] == 'page_background' for r in records)} page backgrounds, 13 portrait layers, 1 home background).\n- Total data: {total:,} bytes.\n- `manifest.csv` records exact source slide, person, dimensions, byte count, and SHA-256.\n\nThe card contents are prepared locally only. Do not copy them to the TF card for the current firmware: the running reader scans only the first six BMP headers and assumes each BMP pixel stream occupies contiguous sectors. The new 720p page index and safe image switching still need to be integrated and built before these assets are used on the board. Keep the older tested bitstreams as rollback options.\n"""
    (OUT / "README_TF_ASSETS.md").write_text(readme, encoding="utf-8")
    print(f"Prepared {len(records)} BMP assets, {total:,} bytes total: {OUT}")


if __name__ == "__main__":
    main()
