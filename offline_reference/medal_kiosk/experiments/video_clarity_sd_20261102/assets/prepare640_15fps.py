"""PC-only 640x360/15fps B96 asset, padded to 1024-byte SDRAM chunks.

Keeps the existing 10fps asset and all accepted files untouched.
"""
from pathlib import Path
import json
import time

import numpy as np
from PIL import Image, ImageDraw

from prepare640_full import q, run, sha

ROOT = Path(__file__).resolve().parent
W, H, FPS, COUNT, FRAME_BYTES, ALIGNMENT = 640, 360, 15, 75, 86400, 1024


def main():
    start = time.time()
    q.W, q.H, q.BH, q.BW = W, H, 8, 4
    preserved = {name: sha((ROOT / name).read_bytes()) for name in ['OPEN640.Q3V', 'manifest_640.json']}
    raw = run(['-i', str(q.SOURCE), '-an', '-vf', f'fps={FPS},scale={W}:{H}:flags=lanczos',
               '-frames:v', str(COUNT), '-pix_fmt', 'rgb24', '-f', 'rawvideo', 'pipe:1'])
    frames = np.frombuffer(raw, np.uint8).reshape(-1, H, W, 3)
    assert len(frames) == COUNT
    payloads, decoded, records = [], [], []
    for index, frame in enumerate(frames):
        payload, metrics = q.encode(frame)
        assert len(payload) == FRAME_BYTES
        picture = q.decode(payload)
        exact_sse = float(np.sum((picture.astype(np.float64) - frame.astype(np.float64)) ** 2))
        assert abs(exact_sse - metrics['fitted_sse']) <= 4
        metrics.update(frame=index, fitted_sse_exact=exact_sse, frame_sha256=sha(payload))
        payloads.append(payload)
        decoded.append(picture)
        records.append(metrics)
    logical = b''.join(payloads)
    assert len(logical) == FRAME_BYTES * COUNT == 6480000
    padding_bytes = (-len(logical)) % ALIGNMENT
    assert padding_bytes == 896
    padded = logical + bytes(padding_bytes)
    assert len(padded) == 6480896 and len(padded) % ALIGNMENT == 0
    target = ROOT / 'OP64015.Q3V'
    target.write_bytes(padded)
    saved = target.read_bytes()
    assert saved[len(logical):] == bytes(padding_bytes)
    for index, expected in enumerate(decoded):
        part = saved[index * FRAME_BYTES:(index + 1) * FRAME_BYTES]
        assert sha(part) == records[index]['frame_sha256']
        assert np.array_equal(q.decode(part), expected)
    file_hash = sha(padded)
    print(json.dumps(dict(stage='asset_verified', file=target.name, fps=FPS, frame_count=COUNT,
                          logical_bytes=len(logical), padding_bytes=padding_bytes,
                          expected_bytes=len(padded), sha256=file_hash)), flush=True)
    preview = ROOT / '640x360_15fps_fit_bilinear_preview.mp4'
    run(['-y', '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-s', f'{W}x{H}', '-r', str(FPS),
         '-i', 'pipe:0', '-an', '-vf', 'scale=1280:720:flags=bilinear', '-c:v', 'libx264',
         '-preset', 'fast', '-crf', '16', '-pix_fmt', 'yuv420p', '-movflags', '+faststart', str(preview)],
        b''.join(x.tobytes() for x in decoded))
    checked = run(['-i', str(preview), '-an', '-pix_fmt', 'rgb24', '-f', 'rawvideo', 'pipe:1'])
    assert len(checked) == COUNT * 1280 * 720 * 3
    sheet = Image.new('RGB', (640, 1170), (24, 24, 24))
    draw = ImageDraw.Draw(sheet)
    for row, index in enumerate([15, 37, 74]):
        sheet.paste(Image.fromarray(decoded[index]), (0, row * 390))
        draw.text((8, row * 390 + 367), f'640x360 15fps B96 fit / frame {index} / {index / FPS:.2f}s', fill='white')
    sheet.save(ROOT / '640_15fps_contact_sheet.jpg', quality=96)
    pixels = COUNT * W * H * 3
    mse_old = sum(x['initial_sse'] for x in records) / pixels
    mse_new = sum(x['fitted_sse_exact'] for x in records) / pixels
    manifest = dict(file=target.name, target_sfn='OP64015 Q3V', width=W, height=H, fps=FPS,
                    frame_count=COUNT, duration_seconds=COUNT / FPS, header_bytes=0,
                    payload_frame_bytes=FRAME_BYTES, logical_bytes=len(logical),
                    zero_padding_bytes=padding_bytes, padding_alignment_bytes=ALIGNMENT,
                    bytes=len(padded), expected_bytes=len(padded), sha256=file_hash,
                    logical_payload_sha256=sha(logical), padded_sdram_chunks=len(padded) // ALIGNMENT,
                    payload_bytes_per_second=FRAME_BYTES * FPS,
                    source=q.SOURCE.as_posix(), source_sha256=sha(q.SOURCE.read_bytes()),
                    block_width=4, block_height=8, block_bytes=12, blocks_per_frame=7200,
                    format='RGB565LE A + RGB565LE B + uint64LE 32 two-bit selectors per 4x8 block',
                    selector_index='2*(local_y*4+local_x)', block_order='row-major, left-to-right then top-to-bottom',
                    interpolation='bit-replicate endpoints; A, (3*A+B)>>2, (A+3*B)>>2, B',
                    encoder='PCA initial endpoints, eight least-squares refinements, flat-mean fallback, retain best block',
                    initial_native_psnr_db=float(10 * np.log10(255 ** 2 / mse_old)),
                    fitted_native_psnr_db=float(10 * np.log10(255 ** 2 / mse_new)),
                    no_block_mse_increase=True,
                    all_stored_frames_hash_verified=True, all_stored_frames_decode_verified=True,
                    padding_verified_all_zero=True,
                    preview=preview.name, preview_decoded_frames=COUNT, preview_has_audio=False,
                    retained_10fps_files_verified=all(sha((ROOT / name).read_bytes()) == expected for name, expected in preserved.items()),
                    elapsed_seconds=round(time.time() - start, 2), tf_and_hardware_untouched=True,
                    frame_metrics=records)
    assert manifest['retained_10fps_files_verified']
    (ROOT / 'manifest_640_15fps.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')
    print(json.dumps({k: v for k, v in manifest.items() if k != 'frame_metrics'}, indent=2), flush=True)


if __name__ == '__main__':
    main()
