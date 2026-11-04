"""Verify actual two-stage pixel/audio pipelines against the preserved renderer.

The old independent golden tests also exercise the unchanged controller and
combinational math/reference. Pipeline screenshots are rendered by the new DUT.
"""
from pathlib import Path
import hashlib
import importlib.util
import json
import re
import subprocess
import os
import shutil
import sys
import time
from PIL import Image,ImageDraw

ROOT=Path(__file__).resolve().parent.parent
TESTS=ROOT/'tests'
SOURCE=ROOT/'source/hdl_source/settings_percent_osd.v'
BIN=Path(os.environ['IVERILOG_BIN']) if os.environ.get('IVERILOG_BIN') else Path(shutil.which('iverilog') or 'iverilog').resolve().parent

def main():
    started=time.time()
    report={'status':'running','scope':'Actual two-stage popup and audio RTL vs preserved combinational renderer/math; independent golden legacy tests; reset/continuous and sparse audio; full popup coordinate sweep over all 11 steps in both languages; randomized RGB/DE/VS/fade/selection/coefficients.'}
    source_hash=hashlib.sha256(SOURCE.read_bytes()).hexdigest()
    try:
        legacy=subprocess.run([sys.executable,str(TESTS/'check_settings_legacy.py')],cwd=TESTS,capture_output=True,text=True,timeout=180)
        (TESTS/'legacy_driver.log').write_text(legacy.stdout+legacy.stderr,encoding='utf-8')
        assert legacy.returncode==0,legacy.stdout+legacy.stderr
        report['legacy']=json.loads((TESTS/'legacy_result.json').read_text(encoding='utf-8'))
        artifact=TESTS/'settings_pipeline.vvp'
        if artifact.exists():artifact.unlink()
        t=time.time()
        compiled=subprocess.run([str(BIN/'iverilog.exe'),'-g2012','-s','tb_settings_pipeline','-o',str(artifact),str(SOURCE),str(TESTS/'tb_settings_pipeline.sv')],cwd=TESTS,capture_output=True,text=True,timeout=90)
        diagnostics=compiled.stdout+compiled.stderr
        (TESTS/'pipeline_compile.log').write_text(diagnostics,encoding='utf-8')
        fresh=artifact.exists() and artifact.stat().st_mtime>=t-1
        shutdown_av=compiled.returncode in (1,3221225477,-1073741819) and not diagnostics.strip()
        report['compile_returncode']=compiled.returncode
        report['compiler_shutdown_av']=shutdown_av
        report['fresh_vvp']=fresh
        assert fresh and (compiled.returncode==0 or shutdown_av),diagnostics
        simulated=subprocess.run([str(BIN/'vvp.exe'),str(artifact)],cwd=TESTS,capture_output=True,text=True,timeout=300)
        (TESTS/'pipeline_simulation.log').write_text(simulated.stdout+simulated.stderr,encoding='utf-8')
        report['simulation_returncode']=simulated.returncode
        assert simulated.returncode==0 and 'PASS SETTINGS_PIPELINE' in simulated.stdout,simulated.stdout+simulated.stderr
        m=re.search(r'checks=(\d+) pixels=(\d+) audio_samples=(\d+) cycles=(\d+)',simulated.stdout)
        report.update(zip(('pipeline_assertions','pixels_compared','valid_audio_samples_compared','cycles'),map(int,m.groups())))
        spec=importlib.util.spec_from_file_location('legacy_checks',TESTS/'check_settings_legacy.py')
        legacy_module=importlib.util.module_from_spec(spec);spec.loader.exec_module(legacy_module)
        sheet=Image.new('RGB',(736,760),(35,24,25));draw=ImageDraw.Draw(sheet)
        for lg in (0,1):
            for column,step in enumerate((0,1,9,10)):
                path=TESTS/f'pipeline_ui_{step}_{lg}.ppm'
                image=Image.open(path).convert('RGB')
                legacy_module.check_glyphs(image,step)
                reference=Image.open(TESTS/f'ui_{step}_{lg}.ppm').convert('RGB')
                assert image.tobytes()==reference.tobytes(),(step,lg,'new pipeline preview differs from reference')
                image.save(path.with_suffix('.png'))
                x,y=column*184,lg*380
                draw.text((x+8,y+8),f'{"EN" if lg else "ZH"} {step*10}',fill=(255,240,208))
                sheet.paste(image,(x+8,y+28))
        sheet.save(TESTS/'settings_percent_pipeline_preview.png')
        assert hashlib.sha256(SOURCE.read_bytes()).hexdigest()==source_hash,'source changed during verification'
        report['status']='passed'
        report['pixel_latency']='two capture stages: input sampled edge N appears after edge N+1; RGB/OSD/DE/VS/fade align'
        report['audio_latency']='two capture stages: valid/sample captured edge N appear after edge N+1; invalid output data ignored'
        report['preview']='settings_percent_pipeline_preview.png'
    except Exception as exc:
        report['status']='failed';report['error']=str(exc)
        raise
    finally:
        report['source_sha256']=source_hash
        report['elapsed_seconds']=round(time.time()-started,3)
        (TESTS/'settings_percent_result.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
        print(json.dumps(report,ensure_ascii=False,indent=2))

if __name__=='__main__':main()
