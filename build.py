"""Build the submitted FPGA design in an isolated directory; never program hardware."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time
import xml.etree.ElementTree as ET

PACKAGE = Path(__file__).resolve().parent
FPGA = PACKAGE / "fpga"
TD_DEFAULT = Path("C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/bin/td_commands_prompt.exe")
HEX_FILES = ("article_voice_cues.hex", "article_cue_compact_main.hex", "article_cue_compact_tail.hex")


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def td_candidates(value: str):
    p = Path(value).expanduser()
    if p.is_file():
        yield p
    else:
        yield p / "td_commands_prompt.exe"
        yield p / "bin/td_commands_prompt.exe"


def find_td(explicit: str | None) -> Path:
    if explicit:
        for p in td_candidates(explicit):
            if p.is_file():
                return p.resolve()
        raise FileNotFoundError("--td must identify td_commands_prompt.exe or its TD/bin directory")
    candidates = []
    if os.environ.get("TD_HOME"):
        candidates.extend(td_candidates(os.environ["TD_HOME"]))
    candidates.append(TD_DEFAULT)
    for name in ("td_commands_prompt.exe", "td_commands_prompt"):
        found = shutil.which(name)
        if found:
            candidates.append(Path(found))
    for p in candidates:
        if p.is_file():
            return p.resolve()
    raise FileNotFoundError("Tang Dynasty command tool not found. Set TD_HOME or use --td <path>.")


def tcl_string(value: str) -> str:
    # Tcl quoted literal; do not permit command/variable substitution in paths.
    for old, new in (("\\", "\\\\"), ('"', '\\"'), ("$", "\\$"), ("[", "\\["), ("]", "\\]")):
        value = value.replace(old, new)
    return '"' + value + '"'


def input_hashes() -> dict[str, str]:
    files = []
    for folder in ("source", "rtl", "user_source"):
        files.extend(p for p in (FPGA / folder).rglob("*") if p.is_file())
    files.extend((FPGA / "run/medal_kiosk_720p.prj", FPGA / "build.tcl"))
    return {p.relative_to(PACKAGE).as_posix(): sha256(p) for p in sorted(files)}


def prepare(work: Path) -> int:
    original_prj = FPGA / "run/medal_kiosk_720p.prj"
    if not original_prj.is_file() or not (FPGA / "build.tcl").is_file():
        raise FileNotFoundError("Expected package/fpga/run/medal_kiosk_720p.prj and package/fpga/build.tcl")
    root = ET.parse(original_prj).getroot()
    entries = root.findall("./Source_Files/*/File")
    if not entries:
        raise ValueError("Project has no source-file entries")
    for entry in entries:
        raw = entry.get("Path", "")
        target = (original_prj.parent / raw).resolve()
        if Path(raw).is_absolute() or not target.is_relative_to(FPGA.resolve()):
            raise ValueError(f"Project must use package-local relative paths: {raw}")
        if not target.is_file():
            raise FileNotFoundError(f"Missing project input: {raw}")
        # The work directory is a sibling of run, so its relative paths stay valid.
        if (work / raw).resolve() != target:
            raise ValueError(f"Project input does not relocate to isolated run: {raw}")
    extra = [FPGA / "source/constraints_source/pin_bilingual.adc",
             FPGA / "source/constraints_source/timing.sdc",
             FPGA / "source/hdl_source/medal_font.vh",
             FPGA / "source/hdl_source/include/global_def.v"]
    extra.extend(FPGA / "source/hdl_source" / name for name in HEX_FILES)
    for p in extra:
        if not p.is_file():
            raise FileNotFoundError(f"Missing auxiliary input: {p.relative_to(PACKAGE)}")
    work.mkdir(parents=True, exist_ok=True)
    shutil.copy2(original_prj, work / original_prj.name)
    for name in HEX_FILES:
        src = FPGA / "source/hdl_source" / name
        dest = work / name
        shutil.copy2(src, dest)
        if sha256(src) != sha256(dest):
            raise IOError(f"ROM copy mismatch: {name}")
    return len(entries)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--td", help="td_commands_prompt.exe, TD installation directory, or its bin directory")
    parser.add_argument("--check-only", action="store_true", help="Import/open/elaborate only; no synthesis, placement, routing, bitgen, or hardware access")
    parser.add_argument("--timeout", type=int, default=2400, help="Command timeout in seconds (default: 2400)")
    args = parser.parse_args()
    mode = "check" if args.check_only else "build"
    work = FPGA / ("check_run" if args.check_only else "build_run")
    try:
        source_count = prepare(work)
        td = find_td(args.td)
        before = input_hashes()
        driver = work / "invoke_build.tcl"
        driver.write_text(
            "set submission_build_mode " + tcl_string(mode) + "\n"
            + "set submission_fpga_root " + tcl_string(FPGA.as_posix()) + "\n"
            + "set submission_work_dir " + tcl_string(work.as_posix()) + "\n"
            + "source " + tcl_string((FPGA / "build.tcl").as_posix()) + "\n",
            encoding="utf-8")
        command = [str(td), driver.as_posix()]
        log_path = work / "console.log"
        print(f"Mode: {mode}; project entries: {source_count}")
        print(f"Tool: {td}")
        print(f"Output: {work}")
        started = time.monotonic()
        timeout = False
        with log_path.open("w", encoding="utf-8") as log:
            try:
                completed = subprocess.run(command, cwd=work, stdout=log, stderr=subprocess.STDOUT, timeout=args.timeout)
                returncode = completed.returncode
            except subprocess.TimeoutExpired:
                timeout = True
                returncode = None
        content = log_path.read_text(encoding="utf-8", errors="replace")
        marker = "SUBMISSION_ELABORATE_COMPLETE" if args.check_only else "SUBMISSION_BUILD_COMPLETE"
        bit = work / "medal_opening_integrated.bit"
        unchanged = input_hashes() == before
        complete = returncode == 0 and marker in content and unchanged and (args.check_only or bit.is_file())
        result = {
            "mode": mode, "complete": complete, "returncode": returncode, "timed_out": timeout,
            "elapsed_seconds": round(time.monotonic()-started, 2),
            "command": command, "project_entries": source_count,
            "tool": str(td), "output_directory": str(work),
            "sources_unchanged": unchanged, "source_hashes": before,
            "hardware_programmed": False, "TF_modified": False,
            "scope": "Elaboration only" if args.check_only else "Synthesis/place/route/bitgen; timing reports must be reviewed separately",
        }
        if not args.check_only and complete:
            result["bit_sha256"] = sha256(bit)
        (work / "result.json").write_text(json.dumps(result, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
        print(f"{'PASS' if complete else 'FAILED'}: {mode}; log: {log_path}")
        return 0 if complete else 1
    except (OSError, ValueError, ET.ParseError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
