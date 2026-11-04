from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[1]
src = root / 'fpga/user_source_720p/hdl_source/SD'
run = root / 'fpga/sim/runs/file_reader_bram'
run.mkdir(parents=True, exist_ok=True)
bin_dir = root / 'tools/local_hdl/iverilog/app/bin'
out = run / 'test.vvp'
commands = [[str(bin_dir / 'iverilog.exe'), '-g2012', '-s', 'tb_file_reader_bram',
             '-o', str(out), str(root / 'fpga/sim/tb_file_reader_bram.sv'),
             str(src / 'fat32_file_stream_reader_bgm_bram.v')]]
for length in [1, 2, 511, 512, 513, 1024, 1025, 2048, 2051, 3072]:
    for stall in [0, 1]:
        commands.append([str(bin_dir / 'vvp.exe'), str(out),
                         '+LENGTH=' + str(length), '+STALL=' + str(stall)])
for args in [['+LENGTH=0'], ['+SHORT=1'], ['+HANG=1'], ['+BAD_CHAIN=1']]:
    commands.append([str(bin_dir / 'vvp.exe'), str(out)] + args)
logs = []
for command in commands:
    result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            universal_newlines=True, timeout=90)
    logs.append(result.stdout)
    print(result.stdout, end='')
    (run / 'result.log').write_text('\n'.join(logs), encoding='utf-8')
    if result.returncode:
        raise SystemExit(result.returncode)
