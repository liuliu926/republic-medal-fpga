"""Run the accepted frame and PCM integration benches with only the reader replaced.

Runner source is evaluated in memory; accepted RTL/scripts remain unchanged.
Fixtures and outputs use separate BGM names.
"""
from contextlib import redirect_stdout
from io import StringIO
from pathlib import Path

root = Path(__file__).resolve().parents[1]
result_log = root / 'fpga/sim/runs/file_reader_bram/integration.log'
logs = []
for name in ['run_sharedmeta_frame_sim.py', 'run_sharedmeta_loader_sim.py']:
    path = root / 'tools' / name
    source = path.read_text(encoding='utf-8')
    source = source.replace("'fat32_file_stream_reader'", "'fat32_file_stream_reader_bgm_bram'")
    source = source.replace("'frame_sharedmeta'", "'bgm_frame_sharedmeta'")
    source = source.replace("'pcm_sharedmeta'", "'bgm_pcm_sharedmeta'")
    buffer = StringIO()
    with redirect_stdout(buffer):
        exec(compile(source, str(path), 'exec'), {'__file__': str(path), '__name__': '__main__'})
    logs.append(name + '\n' + buffer.getvalue())
    print(logs[-1])
    result_log.write_text('\n'.join(logs), encoding='utf-8')
