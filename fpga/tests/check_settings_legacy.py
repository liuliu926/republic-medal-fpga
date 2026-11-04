"""Run actual control, mixer-gain and popup RTL with independent golden checks.

No TD, TF, Flash, source or build mutation. The generated PNGs are RTL renders.
"""
from pathlib import Path
import hashlib
import json
import re
import subprocess
import os
import shutil
import time
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
TESTS = ROOT / 'tests'
KIOSK = ROOT.parents[1]
SOURCE = ROOT / 'source/hdl_source/settings_percent_osd.v'
TOP = ROOT / 'source/hdl_source/top_title_waveform_candidate.v'
BIN = Path(os.environ['IVERILOG_BIN']) if os.environ.get('IVERILOG_BIN') else Path(shutil.which('iverilog') or 'iverilog').resolve().parent
CREAM = (255, 242, 208)
DIGITS = {
    '0': ['01110','10001','10011','10101','11001','10001','01110'],
    '1': ['00100','01100','00100','00100','00100','00100','01110'],
    '9': ['01110','10001','10001','01111','00001','00001','01110'],
}

def check_glyphs(image, step):
    text = str(step * 10)
    width = len(text) * 12 - 2
    pixels = image.load()
    for center in (1172, 1232):
        origin = center - width // 2
        for yy in range(14):
            for xx in range(width):
                digit, col = divmod(xx, 12)
                expected = col < 10 and DIGITS[text[digit]][yy // 2][col // 2] == '1'
                actual = pixels[origin + xx - 1128, 552 + yy - 240] == CREAM
                assert actual == expected, (text, center, xx, yy, actual, expected)
        # Every numeral pixel must lie within the expected centred box.
        lit = [(x + 1128, y + 240) for y in range(552-240, 566-240)
               for x in range(center-22-1128, center+22-1128)
               if pixels[x, y] == CREAM]
        assert lit and min(x for x,y in lit) >= origin and max(x for x,y in lit) < origin+width

def main():
    started = time.time()
    report = {'status':'running', 'scope':'Actual settings_percent_control/audio_volume_percent/brightness_popup_720p RTL. Control key pulses, boundaries/persistence; 1529 signed audio vectors; 2816 RGB triplets; continuous fill heights; actual centred digit pixels and bilingual labels. No hardware operations.'}
    try:
        compile_cmd = [str(BIN/'iverilog.exe'), '-g2012', '-s', 'tb_settings_percent', '-o', 'settings_percent.vvp', str(SOURCE), str(TESTS/'tb_settings_percent.sv')]
        artifact=TESTS/'settings_percent.vvp'
        if artifact.exists(): artifact.unlink()
        compile_start=time.time()
        compiled = subprocess.run(compile_cmd,cwd=TESTS,capture_output=True,text=True)
        (TESTS/'compile.log').write_text(compiled.stdout+compiled.stderr,encoding='utf-8')
        report['compile_returncode']=compiled.returncode
        fresh=artifact.is_file() and artifact.stat().st_mtime>=compile_start-1
        # This bundled Windows driver has a known shutdown AV after emitting
        # valid VVP. Match the existing project harness: only permit a fresh
        # artifact and empty diagnostics, then require all runtime assertions.
        driver_shutdown_av=compiled.returncode in (3221225477,-1073741819,1) and not (compiled.stdout+compiled.stderr).strip()
        report['fresh_vvp']=fresh
        report['compiler_shutdown_av']=driver_shutdown_av
        assert fresh and (compiled.returncode==0 or driver_shutdown_av), compiled.stdout+compiled.stderr
        run = subprocess.run([str(BIN/'vvp.exe'),'settings_percent.vvp'],cwd=TESTS,capture_output=True,text=True,timeout=120)
        (TESTS/'simulation.log').write_text(run.stdout+run.stderr,encoding='utf-8')
        report['simulation_returncode']=run.returncode
        assert run.returncode == 0 and 'PASS SETTINGS_PERCENT' in run.stdout, run.stdout+run.stderr
        report['assertions']=int(re.search(r'assertions=(\d+)',run.stdout).group(1))
        images=[]
        for language in (0,1):
            for step in (0,1,9,10):
                ppm=TESTS/f'ui_{step}_{language}.ppm'
                im=Image.open(ppm).convert('RGB')
                check_glyphs(im,step)
                # Both labels contain foreground, and switching language changes them.
                for left in (1156,1216):
                    crop=im.crop((left-1128,528-240,left-1128+32,544-240))
                    assert sum(p==CREAM for p in crop.getdata())>30, (language,left,'missing label')
                im.save(ppm.with_suffix('.png'))
                images.append((language,step,im))
        for step in (0,1,9,10):
            zh=Image.open(TESTS/f'ui_{step}_0.ppm')
            en=Image.open(TESTS/f'ui_{step}_1.ppm')
            assert zh.crop((20,288,130,304)).tobytes()!=en.crop((20,288,130,304)).tobytes(), 'labels did not switch'
        sheet=Image.new('RGB',(4*184,2*380),(35,24,25))
        draw=ImageDraw.Draw(sheet)
        for language,step,im in images:
            column=(0,1,9,10).index(step)
            x,y=column*184,language*380
            draw.text((x+8,y+8),f'{"EN" if language else "ZH"} {step*10}',fill=(255,240,208))
            sheet.paste(im,(x+8,y+28))
        sheet.save(TESTS/'settings_percent_rtl_preview.png')
        # Navigation belongs to top-level gating, not the standalone controller.
        top=TOP.read_text(encoding='utf-8')
        for port in ('key_prev_pulse','key_back_pulse','key_enter_pulse'):
            match=re.search(r'\.'+port+r'\(([^\n]+)',top)
            assert match and '!brightness_open' in match.group(1), port
        assert '.key_next_pulse(focus_nav_next && !brightness_open' in top
        report['navigation_check']='Actual top-level static wiring: popup gates all four navigation inputs only while brightness_open; closed-controller pulses do not change retained values. Full system runtime navigation remains a hardware regression item.'
        report['status']='passed'
        report['preview']='settings_percent_rtl_preview.png'
    except Exception as exc:
        report['status']='failed'
        report['error']=str(exc)
        raise
    finally:
        report['source_sha256']=hashlib.sha256(SOURCE.read_bytes()).hexdigest()
        report['elapsed_seconds']=round(time.time()-started,3)
        (TESTS/'legacy_result.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
        print(json.dumps(report,ensure_ascii=False,indent=2))

if __name__=='__main__':
    main()
