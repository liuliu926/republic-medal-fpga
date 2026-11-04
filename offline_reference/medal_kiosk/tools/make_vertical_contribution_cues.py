"""Recode only contribution reveal coordinates as character counts.

Speech timing and PCM bytes remain identical to the accepted version.
"""
import json
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets_720p/contribution_vertical_candidate"
BASE = ROOT / "fpga/user_source_720p/hdl_source/article_voice_cues.hex"
INDEX = ROOT / "assets_720p/audio_article_cues/cue_index.json"


def main():
    words = [int(line, 16) for line in BASE.read_text(encoding="ascii").splitlines()]
    entries = json.loads(INDEX.read_text(encoding="utf-8-sig"))
    assert len(words) == 4096 and len(entries) == 91
    draw = ImageDraw.Draw(Image.new("L", (768, 64)))
    modified = 0
    for entry in entries:
        # In the accepted ROM, each person's first four 32-word slots are C01-C04.
        if entry["sfn"][3] != "C":
            continue
        slot = entry["slot"]
        assert slot % 8 < 4
        body = entry["body"]
        font = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", entry["size"])
        widths = {2 + draw.textsize(body[:count], font=font)[0]: count
                  for count in range(1, len(body) + 1)}
        for index, (tick, old_x) in enumerate(entry["events"]):
            count = len(body) if index == len(entry["events"]) - 1 else widths[old_x]
            old = words[slot * 32 + index]
            assert (old >> 10) & 0x1fff == tick
            assert old & 0x3ff == old_x
            words[slot * 32 + index] = (old & ~0x3ff) | count
            modified += 1
    assert modified > 400, modified
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "article_voice_cues.hex").write_text(
        "".join(f"{word:06X}\n" for word in words), encoding="ascii")
    print(f"Converted {modified} contribution reveal events; timing bits unchanged")


if __name__ == "__main__":
    main()
