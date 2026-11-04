#!/usr/bin/env python3
"""Fill the English column from the reviewed translation map."""
import csv
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
review = ROOT / "materials_review"
inventory_path = review / "english_translation_inventory.csv"
translations = json.loads((review / "english_translations.json").read_text(encoding="utf-8"))
with inventory_path.open(encoding="utf-8-sig", newline="") as f:
    rows = list(csv.DictReader(f))
missing = [row["id"] for row in rows if row["id"] not in translations]
if missing:
    raise SystemExit("Missing IDs: " + ", ".join(missing))
for row in rows:
    row["English translation"] = translations[row["id"]]
    row["review_status"] = "draft"
with inventory_path.open("w", encoding="utf-8-sig", newline="") as f:
    writer = csv.DictWriter(f, fieldnames=["id", "Chinese", "English translation", "slide_text_indices", "review_status"])
    writer.writeheader()
    writer.writerows(rows)
print(f"Filled English translations for {len(rows)} strings.")
