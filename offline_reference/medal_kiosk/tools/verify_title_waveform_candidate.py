"""Offline checks for the isolated title/waveform build; never access the TF card."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
RELEASE = ROOT / "releases/title_waveform_candidate_20261101"
BASELINE = ROOT / "releases/bilingual_display_fix_20261101"
ORIGINAL = ROOT / "releases/bilingual_layout_v2_20261101/card_asset_manifest.json"
EXPECTED_BASE_BIT = "dfe64a3b9f4793a9ff73bfc91a0a9073182739ba9236e3d030b8a5ca3311e94e"
EXPECTED_NEW_BIT = "1e6df2fcc3af899e4ce9c228df3d4dfb9904c64459228abfa4817db8672830cd"


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    originals = {row["file"]: row for row in json.loads(ORIGINAL.read_text("utf-8"))}
    for name in ("HOMETXT.BMP", "HOMEENG.BMP"):
        old = Path(originals[name]["source"])
        new = RELEASE / name
        assert digest(old) == originals[name]["sha256"].lower(), name
        with Image.open(old) as im_old, Image.open(new) as im_new:
            assert im_old.size == im_new.size == (768, 320), name
            assert im_old.convert("RGB").crop((0, 0, 768, 256)).tobytes() == (
                im_new.convert("RGB").crop((0, 0, 768, 256)).tobytes()
            ), f"name/date region changed: {name}"
            assert im_old.convert("RGB").crop((0, 256, 512, 320)).tobytes() != (
                im_new.convert("RGB").crop((0, 256, 512, 320)).tobytes()
            ), f"title not changed: {name}"
    assert digest(BASELINE / "medal_720p_bilingual_display_fix.bit") == EXPECTED_BASE_BIT
    assert digest(RELEASE / "medal_720p_title_waveform.bit") == EXPECTED_NEW_BIT
    default = (ROOT / "download_720p_current.tcl").read_text("utf-8")
    assert "download_720p_title_waveform_accepted.tcl" in default
    accepted = (ROOT / "download_720p_title_waveform_accepted.tcl").read_text("utf-8")
    assert "title_waveform_candidate_20261101" in accepted
    assert "medal_720p_title_waveform.bit" in accepted
    assert json.loads((RELEASE / "verification.json").read_text("utf-8"))["status"] == "user_display_verified"
    candidate = (ROOT / "tools/download_720p_title_waveform.tcl").read_text("utf-8")
    assert "title_waveform_candidate_20261101" in candidate
    assert "medal_720p_title_waveform.bit" in candidate
    top = (RELEASE / "source_delta/top_title_waveform_candidate.v").read_text("utf-8")
    assert ".audio_valid(hdmi_audio_valid), .audio_sample(hdmi_audio_data)" in top
    assert ".rgb_in(waveform_overlay_rgb), .rgb_out(brightness_overlay_rgb)" in top
    project = (RELEASE / "medal_kiosk_720p.prj").read_text("utf-8")
    for name in (
        "top_title_waveform_candidate.v",
        "home_text_mask_title_candidate.v",
        "audio_waveform_overlay_720p.v",
    ):
        assert name in project, name
    assert "BILINGUAL_BUILD_COMPLETE" in (RELEASE / "build_seed9.log").read_text(
        "utf-8", errors="replace"
    )
    files = sorted(
        p for p in RELEASE.rglob("*")
        if p.is_file() and p.name != "sha256_manifest.json"
    )
    manifest = [
        {"file": p.relative_to(RELEASE).as_posix(), "size": p.stat().st_size,
         "sha256": digest(p).upper()}
        for p in files
    ]
    (RELEASE / "sha256_manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(f"TITLE_WAVEFORM_OFFLINE_PASS ({len(files)} release files)")


if __name__ == "__main__":
    main()
