#!/usr/bin/env python3
"""Export unique visible Chinese strings for the later English layer pass."""
from __future__ import annotations

import csv
import json
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "materials_review" / "ppt_text_and_asset_index.json"
OUTPUT = ROOT / "materials_review" / "english_translation_inventory.csv"


def main() -> None:
    data = json.loads(SOURCE.read_text(encoding="utf-8"))
    occurrences: dict[str, list[str]] = defaultdict(list)
    for slide in data["slides"]:
        slide_no = int(slide["slide"])
        for idx, item in enumerate(slide.get("texts", [])):
            text = " ".join(str(item.get("text", "")).split())
            if text:
                occurrences[text].append(f"{slide_no:03d}:{idx:02d}")

    rows = sorted(occurrences.items(), key=lambda pair: (int(pair[1][0][:3]), pair[1][0]))
    with OUTPUT.open("w", newline="", encoding="utf-8-sig") as f:
        writer = csv.writer(f)
        writer.writerow(["id", "Chinese", "English translation", "slide_text_indices", "review_status"])
        for number, (text, refs) in enumerate(rows, 1):
            writer.writerow([f"T{number:03d}", text, "", ";".join(refs), "pending"])
    print(f"Unique source strings: {len(rows)}")
    print(f"Occurrences: {sum(map(len, occurrences.values()))}")
    print(OUTPUT.resolve())


if __name__ == "__main__":
    main()
