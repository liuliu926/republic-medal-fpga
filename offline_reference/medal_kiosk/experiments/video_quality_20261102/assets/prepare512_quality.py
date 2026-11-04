"""PC-only 512x288/10fps 4x8 B4Q-style asset preparation.

Each block: RGB565LE A (16), RGB565LE B (16), 32 little-endian two-bit
selectors (64). The palette matches the already-tested quarter interpolation.
No hardware or removable-media access.
"""
from pathlib import Path
import hashlib
import json
import subprocess

import numpy as np
from PIL import Image, ImageDraw

from analyze_quality import SOURCE, FF, codec, quantize_nearest

ROOT = Path(__file__).resolve().parent
W, H, BH, BW, FPS = 512, 288, 8, 4, 10
DT = np.dtype([('a', '<u2'), ('b', '<u2'), ('m', '<u8')])


def run(args, payload=None):
    return subprocess.run([FF, '-hide_banner', '-loglevel', 'error', *args], input=payload,
                          capture_output=True, check=True).stdout


def encode(frame, iterations=8):
    blocks = frame.reshape(H // BH, BH, W // BW, BW, 3).transpose(0, 2, 1, 3, 4).reshape(-1, BH * BW, 3).astype(np.float32)
    centered = blocks - blocks.mean(axis=1, keepdims=True)
    covariance = np.einsum('nki,nkj->nij', centered, centered)
    _, eigenvectors = np.linalg.eigh(covariance)
    projection = np.einsum('nki,ni->nk', centered, eigenvectors[:, :, -1])
    n = np.arange(len(blocks))
    a = codec.pack565(blocks[n, projection.argmin(axis=1)])
    b = codec.pack565(blocks[n, projection.argmax(axis=1)])

    def evaluate(qa, qb):
        table = codec.colors(qa, qb).astype(np.float32)
        errors = ((blocks[:, :, None, :] - table[:, None, :, :]) ** 2).sum(axis=3)
        index = errors.argmin(axis=2)
        score = errors[n[:, None], np.arange(BH * BW)[None, :], index].sum(axis=1)
        return index, score

    idx, best_score = evaluate(a, b)
    initial = best_score.copy()
    best_a, best_b, best_idx = a.copy(), b.copy(), idx.copy()
    wb_lut = np.array([0., .25, .75, 1.], np.float32)
    for _ in range(iterations):
        wb = wb_lut[idx]
        wa = 1. - wb
        aa, ab, bb = (wa * wa).sum(axis=1), (wa * wb).sum(axis=1), (wb * wb).sum(axis=1)
        xa = (wa[:, :, None] * blocks).sum(axis=1)
        xb = (wb[:, :, None] * blocks).sum(axis=1)
        det = aa * bb - ab * ab
        valid = det > 1e-5
        inverse = np.where(valid, 1. / np.maximum(det, 1e-5), 0.)[:, None]
        ca = (bb[:, None] * xa - ab[:, None] * xb) * inverse
        cb = (aa[:, None] * xb - ab[:, None] * xa) * inverse
        a = np.where(valid, quantize_nearest(ca), a)
        b = np.where(valid, quantize_nearest(cb), b)
        idx, score = evaluate(a, b)
        improved = score < best_score
        best_a[improved], best_b[improved], best_idx[improved] = a[improved], b[improved], idx[improved]
        best_score[improved] = score[improved]
    flat = quantize_nearest(blocks.mean(axis=1))
    flat_idx, flat_score = evaluate(flat, flat)
    improved = flat_score < best_score
    best_a[improved], best_b[improved], best_idx[improved] = flat[improved], flat[improved], flat_idx[improved]
    best_score[improved] = flat_score[improved]
    assert np.all(best_score <= initial + 1e-4)
    out = np.empty(len(blocks), DT)
    out['a'], out['b'] = best_a, best_b
    out['m'] = np.sum(best_idx.astype(np.uint64) << np.arange(0, 64, 2, dtype=np.uint64), axis=1, dtype=np.uint64)
    return out.tobytes(), dict(initial_sse=float(initial.sum()), fitted_sse=float(best_score.sum()),
                              improved_blocks=int((best_score < initial).sum()), total_blocks=len(blocks))


def decode(payload):
    blocks = np.frombuffer(payload, DT)
    assert len(blocks) == (W // BW) * (H // BH)
    table = codec.colors(blocks['a'], blocks['b'])
    selectors = ((blocks['m'][:, None] >> np.arange(0, 64, 2, dtype=np.uint64)) & 3).astype(np.int32)
    rgb = table[np.arange(len(blocks))[:, None], selectors].astype(np.uint8)
    return rgb.reshape(H // BH, W // BW, BH, BW, 3).transpose(0, 2, 1, 3, 4).reshape(H, W, 3)


def main():
    ROOT.mkdir(parents=True, exist_ok=True)
    raw = run(['-i', str(SOURCE), '-an', '-vf', f'fps={FPS},scale={W}:{H}:flags=lanczos',
               '-pix_fmt', 'rgb24', '-f', 'rawvideo', 'pipe:1'])
    frames = np.frombuffer(raw, np.uint8).reshape(-1, H, W, 3)
    payloads, decoded, statistics = [], [], []
    for index, frame in enumerate(frames):
        payload, metrics = encode(frame)
        assert len(payload) == 55296
        reconstructed = decode(payload)
        actual_sse = float(np.sum((reconstructed.astype(np.float64) - frame.astype(np.float64)) ** 2))
        assert abs(actual_sse - metrics['fitted_sse']) < 1
        metrics['frame'] = index
        payloads.append(payload)
        decoded.append(reconstructed)
        statistics.append(metrics)
    data = b''.join(payloads)
    target = ROOT / 'OPEN512.Q3V'
    target.write_bytes(data)
    assert len(data) == 55296 * 50 == 2764800
    saved = target.read_bytes()
    for index, expected in enumerate(decoded):
        assert np.array_equal(decode(saved[index * 55296:(index + 1) * 55296]), expected)
    rgb_data = b''.join(x.tobytes() for x in decoded)
    for filter_name in ['neighbor', 'bilinear']:
        preview = ROOT / f'512x288_fit_{filter_name}_preview.mp4'
        run(['-y', '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-s', f'{W}x{H}', '-r', str(FPS), '-i', 'pipe:0',
             '-an', '-vf', f'scale=1280:720:flags={filter_name}', '-c:v', 'libx264', '-preset', 'fast',
             '-crf', '16', '-pix_fmt', 'yuv420p', '-movflags', '+faststart', str(preview)], rgb_data)
        check = run(['-i', str(preview), '-an', '-pix_fmt', 'rgb24', '-f', 'rawvideo', 'pipe:1'])
        assert len(check) == len(frames) * 1280 * 720 * 3
    sheet = Image.new('RGB', (1280, 1170), (24, 24, 24))
    draw = ImageDraw.Draw(sheet)
    for row, index in enumerate([10, 25, 49]):
        for col, (name, filt) in enumerate([('nearest', Image.Resampling.NEAREST), ('bilinear', Image.Resampling.BILINEAR)]):
            sheet.paste(Image.fromarray(decoded[index]).resize((640, 360), filt), (col * 640, row * 390))
            draw.text((col * 640 + 8, row * 390 + 367), f'512x288 4x8 fit / {name} / frame {index}', fill='white')
    sheet.save(ROOT / '512_full_fit_comparison.jpg', quality=96)
    samples, blocks_per_frame = [], 4608
    for frame_index in [0, 25, 49]:
        for block_index in [0, blocks_per_frame // 2, blocks_per_frame - 1]:
            offset = frame_index * 55296 + block_index * 12
            payload = data[offset:offset + 12]
            fields = np.frombuffer(payload, DT)[0]
            table = codec.colors(np.array([fields['a']]), np.array([fields['b']]))[0]
            indices = ((np.uint64(fields['m']) >> np.arange(0, 64, 2, dtype=np.uint64)) & np.uint64(3)).astype(int)
            samples.append(dict(frame=frame_index, block=block_index, file_byte_offset=offset,
                                payload_hex=payload.hex(), a_rgb565=int(fields['a']), b_rgb565=int(fields['b']),
                                selectors_uint64=str(int(fields['m'])), decoded_rgb24_row_major=table[indices].astype(int).tolist()))
    (ROOT / 'golden_blocks_512.json').write_text(json.dumps(samples, indent=2), encoding='utf-8')
    mse_initial = sum(x['initial_sse'] for x in statistics) / (len(frames) * W * H * 3)
    mse_fitted = sum(x['fitted_sse'] for x in statistics) / (len(frames) * W * H * 3)
    report = dict(file=target.name, target_sfn='OPEN512 Q3V', width=W, height=H, fps=FPS,
                  frame_count=len(frames), duration_seconds=len(frames) / FPS, header_bytes=0,
                  payload_frame_bytes=55296, bytes=len(data), sha256=hashlib.sha256(data).hexdigest(),
                  payload_bytes_per_second=552960, double_framebuffer_bytes=110592,
                  block_width=BW, block_height=BH, block_bytes=12,
                  format='RGB565LE A + RGB565LE B + uint64LE 32 2-bit selectors per 4x8 block',
                  selector_index='2*(local_y*4+local_x)', block_order='row-major',
                  interpolation='bit-replicate endpoints; A,(3*A+B)>>2,(A+3*B)>>2,B',
                  encoder='PCA initial endpoints, eight least-squares refinements, flat-mean fallback, retain best block',
                  initial_native_psnr_db=float(10 * np.log10(255 ** 2 / mse_initial)),
                  optimized_native_psnr_db=float(10 * np.log10(255 ** 2 / mse_fitted)),
                  no_block_mse_increase=True, all_stored_frames_verified=True, previews_decode_frames=50,
                  no_tf_or_hardware_access=True,
                  previews=['512x288_fit_neighbor_preview.mp4', '512x288_fit_bilinear_preview.mp4'],
                  frame_metrics=statistics)
    (ROOT / 'manifest_512.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(json.dumps({k: v for k, v in report.items() if k != 'frame_metrics'}, indent=2), flush=True)


if __name__ == '__main__':
    main()
