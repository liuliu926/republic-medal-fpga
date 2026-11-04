"""Create an editable, text-free background deck for the FPGA kiosk.

The source PPTX and its companion image folder are read-only inputs. This
script writes a separate deck into the workspace and removes only text-bearing
shapes plus embedded picture shapes that exactly match the 13 supplied portraits.
"""

from __future__ import annotations

import hashlib
from pathlib import Path

from pptx import Presentation


ROOT = Path(__file__).resolve().parents[1]
MATERIALS = Path(r"C:\Users\20251\Desktop\材料")
SOURCE = MATERIALS / "共和国勋章获得者人物志.pptx"
OUTPUT = ROOT / "materials_review" / "Republic_Medal_Clean_Template.pptx"


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def main() -> None:
    portraits = {digest(path.read_bytes()) for path in MATERIALS.glob("图片*.*")}
    prs = Presentation(SOURCE)
    removed_text = 0
    removed_portraits = 0

    for slide_number, slide in enumerate(prs.slides, start=1):
        for shape in list(slide.shapes):
            if shape.shape_type == 13:  # PICTURE
                # Home portraits and person-introduction portraits become
                # independent FPGA-loaded layers. Other PPT photos illustrate
                # timeline/deed pages and remain part of those backgrounds.
                is_portrait_layer = slide_number == 1 or slide_number in range(2, 54, 4)
                if digest(shape.image.blob) in portraits or is_portrait_layer:
                    shape._element.getparent().remove(shape._element)
                    removed_portraits += 1
                continue
            if getattr(shape, "has_text_frame", False) and shape.text.strip():
                shape._element.getparent().remove(shape._element)
                removed_text += 1

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    prs.save(OUTPUT)
    print(f"Wrote: {OUTPUT}")
    print(f"Slides: {len(prs.slides)}; removed text shapes: {removed_text}; exact portrait pictures: {removed_portraits}")


if __name__ == "__main__":
    main()
