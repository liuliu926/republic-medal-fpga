"""Prepare an isolated home-title and mixed-audio waveform candidate.

Only the title strip of each home text atlas changes. The accepted bitstream,
source project, TF card and all 13 name/date tiles remain untouched.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
HDL = ROOT / "fpga/user_source_720p/hdl_source"
BASE = ROOT / "fpga/td_project_720p/cli_runs/bilingual_display_fix_20261101"
RUN = ROOT / "fpga/td_project_720p/cli_runs/title_waveform_20261101"
ASSETS = ROOT / "assets_720p/title_waveform_20261101"
MANIFEST = ROOT / "releases/bilingual_layout_v2_20261101/card_asset_manifest.json"


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def render_title(source: Path, destination: Path, label: str, font: Path,
                 size: int, spacing: int) -> None:
    original = Image.open(source).convert("RGB")
    assert original.size == (768, 320)
    atlas = original.copy()
    canvas = Image.new("L", (512, 64), 0)
    draw = ImageDraw.Draw(canvas)
    fnt = ImageFont.truetype(str(font), size)
    widths = [fnt.getsize(char)[0] for char in label]
    overall = sum(widths) + spacing * (len(label) - 1)
    x = (512 - overall) // 2
    box = fnt.getmask(label).getbbox()
    assert box is not None
    y = (64 - (box[3] - box[1])) // 2 - box[1]
    for char, width in zip(label, widths):
        draw.text((x, y), char, font=fnt, fill=255)
        x += width + spacing
    # The FPGA converts this 24-bit BMP to a one-bit mask. Keep it binary.
    canvas = canvas.point(lambda value: 255 if value >= 110 else 0)
    atlas.paste(canvas.convert("RGB"), (0, 256))
    assert atlas.crop((0, 0, 768, 256)).tobytes() == original.crop(
        (0, 0, 768, 256)).tobytes()
    destination.parent.mkdir(parents=True, exist_ok=True)
    atlas.save(destination, format="BMP")
    print(label, "width", overall, "sha256", sha256(destination))


def main() -> None:
    manifest = {row["file"]: row for row in json.loads(
        MANIFEST.read_text(encoding="utf-8"))}
    chinese = Path(manifest["HOMETXT.BMP"]["source"])
    english = Path(manifest["HOMEENG.BMP"]["source"])
    assert sha256(chinese).lower() == manifest["HOMETXT.BMP"]["sha256"].lower()
    assert sha256(english).lower() == manifest["HOMEENG.BMP"]["sha256"].lower()
    render_title(chinese, ASSETS / "HOMETXT.BMP", "共和国勋章",
                 Path("C:/Windows/Fonts/simsun.ttc"), 60, 17)
    render_title(english, ASSETS / "HOMEENG.BMP", "Medal of the Republic",
                 Path("C:/Windows/Fonts/timesbd.ttf"), 42, 1)

    # Standalone preview uses exactly the same atlas-to-screen coordinates as HDL.
    preview = Image.open(ROOT / "assets_ppt_720p/BG001.BMP").convert("RGB")
    zh = Image.open(ASSETS / "HOMETXT.BMP")
    preview.paste((255, 241, 205), (384, 18, 896, 82),
                  zh.crop((0, 256, 512, 320)).convert("L"))
    preview.save(ASSETS / "homepage_title_preview.png")

    source_top = (HDL / "top_bilingual_candidate.v").read_text(encoding="utf-8")
    assert "wire [23:0] brightness_overlay_rgb;" in source_top
    assert ".rgb_in(prompt_overlay_rgb), .rgb_out(brightness_overlay_rgb)" in source_top
    source_top = source_top.replace(
        "wire [23:0] brightness_overlay_rgb;",
        "wire [23:0] waveform_overlay_rgb;\nwire [23:0] brightness_overlay_rgb;", 1)
    marker = "brightness_popup_720p u_brightness_popup ("
    assert marker in source_top
    source_top = source_top.replace(marker,
        "audio_waveform_overlay_720p u_audio_waveform (\n"
        "    .clk(video_clk), .rst(rst_video), .de(de),\n"
        "    .pixel_x(overlay_x), .pixel_y(overlay_y),\n"
        "    .audio_valid(hdmi_audio_valid), .audio_sample(hdmi_audio_data),\n"
        "    .rgb_in(prompt_overlay_rgb), .rgb_out(waveform_overlay_rgb)\n"
        ");\n" + marker, 1)
    source_top = source_top.replace(
        ".rgb_in(prompt_overlay_rgb), .rgb_out(brightness_overlay_rgb)",
        ".rgb_in(waveform_overlay_rgb), .rgb_out(brightness_overlay_rgb)", 1)
    (HDL / "top_title_waveform_candidate.v").write_text(source_top, encoding="utf-8")

    source_mask = (HDL / "home_text_mask_bilingual.v").read_text(encoding="utf-8")
    old = "next_x >= 11'd320 && next_x < 11'd832"
    assert old in source_mask
    source_mask = source_mask.replace(old, "next_x >= 11'd384 && next_x < 11'd896", 1)
    assert "inside=1; x_bias=10'd704; y_bias=9'd238;" in source_mask
    source_mask = source_mask.replace(
        "inside=1; x_bias=10'd704; y_bias=9'd238;",
        "inside=1; x_bias=10'd640; y_bias=9'd238;", 1)
    (HDL / "home_text_mask_title_candidate.v").write_text(source_mask, encoding="utf-8")

    RUN.mkdir(parents=True, exist_ok=True)
    (RUN / "article_voice_cues.hex").write_bytes((BASE / "article_voice_cues.hex").read_bytes())
    project = (BASE / "medal_kiosk_720p.prj").read_text(encoding="utf-8")
    assert "top_bilingual_candidate.v" in project
    assert "home_text_mask_bilingual.v" in project
    project = project.replace("top_bilingual_candidate.v", "top_title_waveform_candidate.v", 1)
    project = project.replace("home_text_mask_bilingual.v", "home_text_mask_title_candidate.v", 1)
    insertion = '<File Path="../../../user_source_720p/hdl_source/audio_waveform_overlay_720p.v"><FileInfo><Attr Name="UsedInSyn" Val="true" /><Attr Name="UsedInP&amp;R" Val="true" /><Attr Name="BelongTo" Val="design_1" /><Attr Name="CompileOrder" Val="170" /></FileInfo></File>'
    assert "</Verilog>" in project
    project = project.replace("</Verilog>", insertion + "</Verilog>", 1)
    (RUN / "medal_kiosk_720p.prj").write_text(project, encoding="utf-8")

    base_build = (ROOT / "tools/build_720p_bilingual_display_fix.tcl").read_text(encoding="utf-8")
    build = base_build.replace("bilingual_display_fix_20261101", "title_waveform_20261101")
    build = build.replace("medal_720p_bilingual_display_fix.bit", "medal_720p_title_waveform.bit")
    (ROOT / "tools/build_720p_title_waveform.tcl").write_text(build, encoding="utf-8")
    print("Isolated candidate:", RUN)


if __name__ == "__main__":
    main()
