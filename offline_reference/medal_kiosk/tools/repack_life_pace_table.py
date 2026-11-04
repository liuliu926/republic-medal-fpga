"""Pack per-person life-audio pacing into 16-bit constants for TD synthesis."""

import json
from pathlib import Path

root = Path(__file__).resolve().parent.parent
source = root / "fpga/user_source_720p/hdl_source/top_fat32_voice_all_life_reveal.v"
manifest = json.loads((root / "assets_720p/audio_life_batch/manifest.json").read_text(encoding="utf-8"))
pace = {}
for clip in manifest:
    person = clip["person_index"]
    if person < 2:
        continue
    value = round((clip["samples"] - 4000) / 26 / 300)
    pace[(person, clip["row"])] = max(0, min(8, value - 8))

lines = []
for person in range(2, 13):
    packed = sum(pace[(person, row)] << (4 * (row - 1)) for row in range(1, 5))
    lines.append(f"        5'd{person}: life_pace_packed = 16'h{packed:04X};")

text = source.read_text(encoding="utf-8")
start = text.index("reg [3:0] life_pace_class;")
end = text.index("reg [12:0] life_voice_step;", start)
replacement = """reg [15:0] life_pace_packed;
always @* begin
    case (nav_person_sync2)
""" + "\n".join(lines) + """
        default: life_pace_packed = 16'h5555;
    endcase
end
reg [3:0] life_pace_class;
always @* begin
    case (nav_page_sync2[2:0])
        3'd1: life_pace_class = life_pace_packed[3:0];
        3'd2: life_pace_class = life_pace_packed[7:4];
        3'd3: life_pace_class = life_pace_packed[11:8];
        3'd4: life_pace_class = life_pace_packed[15:12];
        default: life_pace_class = 4'd5;
    endcase
end
"""
source.write_text(text[:start] + replacement + text[end:], encoding="utf-8")
print(f"Packed {len(pace)} pacing entries into 11 person constants")
