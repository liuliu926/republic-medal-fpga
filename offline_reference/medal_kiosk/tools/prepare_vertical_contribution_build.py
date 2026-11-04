"""Create an isolated TD build that keeps the accepted release intact."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RUN = ROOT / "fpga/td_project_720p/cli_runs/contribution_vertical_20261101"
BASE = ROOT / "fpga/td_project_720p/cli_runs/portrait_focus_linecache_20261031"
ASSETS = ROOT / "assets_720p/contribution_vertical_candidate"
RUN.mkdir(parents=True, exist_ok=True)
project = (BASE / "medal_kiosk_720p.prj").read_text(encoding="utf-8")
assert project.count("home_text_mask_bgm_compact.v") == 1
project = project.replace("home_text_mask_bgm_compact.v", "home_text_mask_vertical_contrib.v")
(RUN / "medal_kiosk_720p.prj").write_text(project, encoding="utf-8")
(RUN / "article_voice_cues.hex").write_bytes((ASSETS / "article_voice_cues.hex").read_bytes())
print(RUN)
