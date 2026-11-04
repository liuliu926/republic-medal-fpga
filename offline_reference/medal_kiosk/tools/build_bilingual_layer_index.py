#!/usr/bin/env python3
"""Pair Chinese and English text-layer files by page and reveal step."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "assets_ppt_720p"
ZH = json.loads((ASSETS / "text_zh" / "layer_index.json").read_text(encoding="utf-8"))
EN = json.loads((ASSETS / "text_en" / "layer_index.json").read_text(encoding="utf-8"))

if ZH["slide_count"] != EN["slide_count"]:
    raise SystemExit("Chinese/English slide counts differ")

pages = []
for zh_page, en_page in zip(ZH["pages"], EN["pages"]):
    zh_layers = {layer["layer"]: layer for layer in zh_page["layers"]}
    en_layers = {layer["layer"]: layer for layer in en_page["layers"]}
    if zh_layers.keys() != en_layers.keys():
        raise SystemExit(f"Layer mismatch on slide {zh_page['slide']}")
    pairs = []
    for name, zh in zh_layers.items():
        en = en_layers[name]
        for field in ("x", "y", "width", "height", "key4_reveal_step"):
            if zh[field] != en[field]:
                raise SystemExit(f"Layout mismatch on slide {zh_page['slide']} layer {name}: {field}")
        pairs.append({
            "layer": name,
            "zh_file": f"text_zh/{zh['file']}",
            "en_file": f"text_en/{en['file']}",
            "x": zh["x"], "y": zh["y"],
            "width": zh["width"], "height": zh["height"],
            "key4_reveal_step": zh["key4_reveal_step"],
        })
    pages.append({
        "slide": zh_page["slide"],
        "person_zh": zh_page["person"], "person_en": en_page["person"],
        "page": zh_page["page"], "layers": pairs,
    })

out = ASSETS / "bilingual_text_index.json"
out.write_text(json.dumps({
    "canvas": "1280x720", "languages": ["zh", "en"],
    "sw2_selects_language": True,
    "key4_reveal_step_is_shared": True,
    "slide_count": len(pages), "layer_pair_count": sum(len(p["layers"]) for p in pages),
    "pages": pages,
}, ensure_ascii=False, indent=2), encoding="utf-8")
print(f"Paired {sum(len(p['layers']) for p in pages)} bilingual layer pairs across {len(pages)} slides.")
