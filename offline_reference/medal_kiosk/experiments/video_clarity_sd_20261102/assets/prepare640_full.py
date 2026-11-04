"""Prepare full 640x360 B96 video for an independent SDRAM experiment.

PC-only: no removable-media, board, or accepted-release writes.
"""
from pathlib import Path
import hashlib
import json
import subprocess
import sys
import time

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent
WORKSPACE = ROOT.parents[3]
PREVIOUS = WORKSPACE / 'medal_kiosk/experiments/video_quality_20261102/assets'
sys.path.insert(0, str(PREVIOUS))
import prepare512_quality as q

W, H, FPS, COUNT, FRAME_BYTES = 640, 360, 10, 50, 86400


def run(args, payload=None):
    return subprocess.run([q.FF, '-hide_banner', '-loglevel', 'error', *args], input=payload,
                          capture_output=True, check=True).stdout


def sha(payload):
    return hashlib.sha256(payload).hexdigest()


def main():
    ROOT.mkdir(parents=True, exist_ok=True)
    start = time.time()
    q.W, q.H, q.BH, q.BW = W, H, 8, 4
    raw = run(['-i', str(q.SOURCE), '-an', '-vf', f'fps={FPS},scale={W}:{H}:flags=lanczos',
               '-frames:v', str(COUNT), '-pix_fmt', 'rgb24', '-f', 'rawvideo', 'pipe:1'])
    frames = np.frombuffer(raw, np.uint8).reshape(-1, H, W, 3)
    assert len(frames) == COUNT
    encoded, decoded, records = [], [], []
    for index, frame in enumerate(frames):
        payload, metrics = q.encode(frame)
        assert len(payload) == FRAME_BYTES
        image = q.decode(payload)
        actual_sse = float(np.sum((image.astype(np.float64) - frame.astype(np.float64)) ** 2))
        assert abs(actual_sse - metrics['fitted_sse']) <= 4
        metrics.update(frame=index, fitted_sse_exact=actual_sse,
                       frame_sha256=sha(payload), first_block_hex=payload[:12].hex())
        encoded.append(payload)
        decoded.append(image)
        records.append(metrics)
    payload = b''.join(encoded)
    target = ROOT / 'OPEN640.Q3V'
    target.write_bytes(payload)
    assert len(payload) == FRAME_BYTES * COUNT == 4320000
    saved = target.read_bytes()
    for index, expected in enumerate(decoded):
        frame_payload = saved[index * FRAME_BYTES:(index + 1) * FRAME_BYTES]
        assert sha(frame_payload) == records[index]['frame_sha256']
        assert np.array_equal(q.decode(frame_payload), expected)
    preview = ROOT / '640x360_fit_bilinear_preview.mp4'
    run(['-y', '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-s', f'{W}x{H}', '-r', str(FPS),
         '-i', 'pipe:0', '-an', '-vf', 'scale=1280:720:flags=bilinear', '-c:v', 'libx264',
         '-preset', 'fast', '-crf', '16', '-pix_fmt', 'yuv420p', '-movflags', '+faststart', str(preview)],
        b''.join(x.tobytes() for x in decoded))
    checked = run(['-i', str(preview), '-an', '-pix_fmt', 'rgb24', '-f', 'rawvideo', 'pipe:1'])
    assert len(checked) == COUNT * 1280 * 720 * 3
    sheet = Image.new('RGB', (640, 1170), (24, 24, 24))
    draw = ImageDraw.Draw(sheet)
    for row, index in enumerate([10, 25, 49]):
        sheet.paste(Image.fromarray(decoded[index]).resize((640, 360), Image.Resampling.BILINEAR), (0, row * 390))
        draw.text((8, row * 390 + 367), f'640x360 B96 fit / frame {index} / {index / FPS:.1f}s', fill='white')
    sheet.save(ROOT / '640_full_contact_sheet.jpg', quality=96)
    sample_blocks = []
    for frame_index in [0, 25, 49]:
        for block_index in [0, 3600, 7199]:
            offset = frame_index * FRAME_BYTES + block_index * 12
            block = payload[offset:offset + 12]
            entry = np.frombuffer(block, q.DT)[0]
            palette = q.codec.colors(np.array([entry['a']]), np.array([entry['b']]))[0]
            indexes = ((np.uint64(entry['m']) >> np.arange(0, 64, 2, dtype=np.uint64)) & np.uint64(3)).astype(int)
            sample_blocks.append(dict(frame=frame_index, block=block_index, file_byte_offset=offset,
                                      payload_hex=block.hex(), decoded_rgb24_row_major=palette[indexes].astype(int).tolist()))
    (ROOT / 'golden_blocks_640.json').write_text(json.dumps(sample_blocks, indent=2), encoding='utf-8')
    pixels = COUNT * W * H * 3
    mse_old = sum(x['initial_sse'] for x in records) / pixels
    mse_new = sum(x['fitted_sse_exact'] for x in records) / pixels
    manifest = dict(file=target.name, target_sfn='OPEN640 Q3V', width=W, height=H, fps=FPS,
                    frame_count=COUNT, duration_seconds=COUNT / FPS, header_bytes=0,
                    payload_frame_bytes=FRAME_BYTES, bytes=len(payload), sha256=sha(payload),
                    payload_bytes_per_second=FRAME_BYTES * FPS,
                    source=q.SOURCE.as_posix(), source_sha256=sha(q.SOURCE.read_bytes()),
                    block_width=4, block_height=8, block_bytes=12, blocks_per_frame=7200,
                    format='RGB565LE A + RGB565LE B + uint64LE 32 two-bit selectors per 4x8 block',
                    selector_index='2*(local_y*4+local_x)', block_order='row-major, left-to-right then top-to-bottom',
                    interpolation='bit-replicate endpoints; A, (3*A+B)>>2, (A+3*B)>>2, B',
                    encoder='PCA initial endpoints, eight least-squares refinements, flat-mean fallback, retain best block',
                    initial_native_psnr_db=float(10 * np.log10(255 ** 2 / mse_old)),
                    fitted_native_psnr_db=float(10 * np.log10(255 ** 2 / mse_new)),
                    no_block_mse_increase=True, improved_blocks=sum(x['improved_blocks'] for x in records),
                    total_blocks=sum(x['total_blocks'] for x in records),
                    all_stored_frames_hash_verified=True, all_stored_frames_decode_verified=True,
                    preview=preview.name, preview_decoded_frames=COUNT, preview_has_audio=False,
                    elapsed_seconds=round(time.time() - start, 2), tf_and_hardware_untouched=True,
                    frame_metrics=records)
    (ROOT / 'manifest_640.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')
    print(json.dumps({k: v for k, v in manifest.items() if k != 'frame_metrics'}, indent=2), flush=True)


if __name__ == '__main__':
    main()
