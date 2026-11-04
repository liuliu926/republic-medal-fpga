"""PC-only encoder improvement and reconstruction-filter comparison.

The accepted B4Q codec, assets, hardware, and removable media remain untouched.
"""
from pathlib import Path
import hashlib
import importlib.util
import json
import subprocess
import sys

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent
WORKSPACE = ROOT.parents[3]
OLD = WORKSPACE / 'medal_kiosk/experiments/video_codec_20261101'
sys.path.insert(0, str(OLD))
spec = importlib.util.spec_from_file_location('existing_b4q', OLD / 'block_trial.py')
codec = importlib.util.module_from_spec(spec)
spec.loader.exec_module(codec)
SOURCE = WORKSPACE / 'output/video/republic_medal_repaired/v2_style_match/republic_medal_matched_v2.mp4'
BASELINE = WORKSPACE / 'medal_kiosk/experiments/video_bram_hq_20261102/assets/OPEN448.Q4V'
FF = 'C:/Users/20251/AppData/Local/kzip_sogou/ffmpeg.exe'
W, H, FPS = 448, 252, 10
DT = np.dtype([('a', '<u2'), ('b', '<u2'), ('m', '<u4')])


def run(args, payload=None):
    return subprocess.run([FF, '-hide_banner', '-loglevel', 'error', *args], input=payload,
                          capture_output=True, check=True).stdout


def digest(payload):
    return hashlib.sha256(payload).hexdigest()


def quantize_nearest(rgb):
    q = np.floor(np.clip(rgb, 0, 255) * np.array([31., 63., 31.]) / 255. + .5).astype(np.uint16)
    return (q[:, 0] << 11) | (q[:, 1] << 5) | q[:, 2]


def fit(frame, original_payload, iterations=8):
    blocks = frame.reshape(H // 4, 4, W // 4, 4, 3).transpose(0, 2, 1, 3, 4).reshape(-1, 16, 3).astype(np.float32)
    packed = np.frombuffer(original_payload, DT)
    a, b = packed['a'].copy(), packed['b'].copy()
    n = np.arange(len(blocks))

    def evaluate(qa, qb):
        table = codec.colors(qa, qb).astype(np.float32)
        errors = ((blocks[:, :, None, :] - table[:, None, :, :]) ** 2).sum(axis=3)
        selected = errors.argmin(axis=2)
        score = errors[n[:, None], np.arange(16)[None, :], selected].sum(axis=1)
        return selected, score

    idx, best_score = evaluate(a, b)
    original_score = best_score.copy()
    best_a, best_b, best_idx = a.copy(), b.copy(), idx.copy()
    weights_b = np.array([0., .25, .75, 1.], np.float32)
    for _ in range(iterations):
        wb = weights_b[idx]
        wa = 1. - wb
        aa, ab, bb = (wa * wa).sum(axis=1), (wa * wb).sum(axis=1), (wb * wb).sum(axis=1)
        xa = (wa[:, :, None] * blocks).sum(axis=1)
        xb = (wb[:, :, None] * blocks).sum(axis=1)
        det = aa * bb - ab * ab
        valid = det > 1e-5
        inv = np.where(valid, 1. / np.maximum(det, 1e-5), 0.)[:, None]
        ca = (bb[:, None] * xa - ab[:, None] * xb) * inv
        cb = (aa[:, None] * xb - ab[:, None] * xa) * inv
        a = np.where(valid, quantize_nearest(ca), a)
        b = np.where(valid, quantize_nearest(cb), b)
        idx, score = evaluate(a, b)
        improved = score < best_score
        best_a[improved], best_b[improved], best_idx[improved] = a[improved], b[improved], idx[improved]
        best_score[improved] = score[improved]
    mean = quantize_nearest(blocks.mean(axis=1))
    flat_idx, flat_score = evaluate(mean, mean)
    improved = flat_score < best_score
    best_a[improved], best_b[improved], best_idx[improved] = mean[improved], mean[improved], flat_idx[improved]
    best_score[improved] = flat_score[improved]
    assert np.all(best_score <= original_score + 1e-4)
    out = np.empty(len(blocks), DT)
    out['a'], out['b'] = best_a, best_b
    out['m'] = np.sum(best_idx.astype(np.uint32) << np.arange(0, 32, 2, dtype=np.uint32), axis=1, dtype=np.uint32)
    return out.tobytes(), dict(improved_blocks=int((best_score < original_score).sum()),
                              total_blocks=len(blocks), original_sse=float(original_score.sum()), improved_sse=float(best_score.sum()))


def psnr(mse):
    return float(10 * np.log10(255 * 255 / max(mse, 1e-12)))


def main():
    ROOT.mkdir(parents=True, exist_ok=True)
    original = BASELINE.read_bytes()
    baseline_sha = digest(original)
    raw = run(['-i', str(SOURCE), '-an', '-vf', f'fps={FPS},scale={W}:{H}:flags=lanczos',
               '-pix_fmt', 'rgb24', '-f', 'rawvideo', 'pipe:1'])
    frames = np.frombuffer(raw, np.uint8).reshape(-1, H, W, 3)
    frame_bytes = W * H // 2
    assert len(original) == len(frames) * frame_bytes
    payloads, old_rgb, new_rgb, records = [], [], [], []
    for i, frame in enumerate(frames):
        before = original[i * frame_bytes:(i + 1) * frame_bytes]
        after, item = fit(frame, before)
        payloads.append(after)
        old = codec.decode(before, W, H)
        new = codec.decode(after, W, H)
        old_rgb.append(old)
        new_rgb.append(new)
        item.update(frame=i, original_psnr_db=psnr(item['original_sse'] / (W * H * 3)),
                    improved_psnr_db=psnr(item['improved_sse'] / (W * H * 3)))
        records.append(item)
    payload = b''.join(payloads)
    target = ROOT / 'OPEN448_FIT.Q4V'
    target.write_bytes(payload)
    assert len(payload) == len(original)
    for i, expected in enumerate(new_rgb):
        assert np.array_equal(codec.decode(payload[i * frame_bytes:(i + 1) * frame_bytes], W, H), expected)
    print(json.dumps(dict(stage='endpoint_fit_complete', frames=len(frames), bytes=len(payload),
                          psnr_old=psnr(sum(x['original_sse'] for x in records) / (len(frames) * W * H * 3)),
                          psnr_new=psnr(sum(x['improved_sse'] for x in records) / (len(frames) * W * H * 3)))), flush=True)
    source_full = run(['-i', str(SOURCE), '-an', '-vf', f'fps={FPS},scale=1280:720:flags=lanczos',
                       '-pix_fmt', 'rgb24', '-f', 'rawvideo', 'pipe:1'])
    full = np.frombuffer(source_full, np.uint8).reshape(-1, 720, 1280, 3)
    compare_indices = [0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 49]
    results = []
    filters = [('nearest', Image.Resampling.NEAREST), ('bilinear', Image.Resampling.BILINEAR)]
    for encoder, images in [('accepted', old_rgb), ('fit', new_rgb)]:
        for label, filt in filters:
            errors, title_errors = [], []
            for i in compare_indices:
                reconstructed = np.asarray(Image.fromarray(images[i]).resize((1280, 720), filt))
                squared = (reconstructed.astype(np.float32) - full[i].astype(np.float32)) ** 2
                errors.append(float(squared.mean()))
                if i >= 35:
                    title_errors.append(float(squared[180:350, 320:980].mean()))
            results.append(dict(encoder=encoder, reconstruction_filter=label, frames=compare_indices,
                                psnr_720p_db=psnr(float(np.mean(errors))),
                                ending_title_region_psnr_db=psnr(float(np.mean(title_errors)))))
    sheet = Image.new('RGB', (1280, 780), (24, 24, 24))
    draw = ImageDraw.Draw(sheet)
    for i, (label, images, filt) in enumerate([('accepted / nearest', old_rgb, Image.Resampling.NEAREST),
                                               ('fitted / nearest', new_rgb, Image.Resampling.NEAREST),
                                               ('accepted / bilinear', old_rgb, Image.Resampling.BILINEAR),
                                               ('fitted / bilinear', new_rgb, Image.Resampling.BILINEAR)]):
        sheet.paste(Image.fromarray(images[49]).resize((640, 360), filt), ((i % 2) * 640, (i // 2) * 390))
        draw.text(((i % 2) * 640 + 8, (i // 2) * 390 + 368), label, fill='white')
    sheet.save(ROOT / 'ending_comparison.jpg', quality=96)
    title_sheet = Image.new('RGB', (1320, 760), (24, 24, 24))
    td = ImageDraw.Draw(title_sheet)
    for i, (label, images, filt) in enumerate([('accepted / nearest', old_rgb, Image.Resampling.NEAREST),
                                               ('fitted / nearest', new_rgb, Image.Resampling.NEAREST),
                                               ('accepted / bilinear', old_rgb, Image.Resampling.BILINEAR),
                                               ('fitted / bilinear', new_rgb, Image.Resampling.BILINEAR)]):
        enlarged = Image.fromarray(images[49]).resize((1280, 720), filt).crop((320, 180, 980, 350)).resize((1320, 340), Image.Resampling.NEAREST)
        title_sheet.paste(enlarged.resize((660, 170)), ((i % 2) * 660, (i // 2) * 380))
        td.text(((i % 2) * 660 + 8, (i // 2) * 380 + 180), label, fill='white')
    title_sheet.save(ROOT / 'title_comparison.jpg', quality=96)
    preview = ROOT / 'endpoint_fit_nearest_preview.mp4'
    run(['-y', '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-s', f'{W}x{H}', '-r', str(FPS), '-i', 'pipe:0',
         '-an', '-vf', 'scale=1280:720:flags=neighbor', '-c:v', 'libx264', '-crf', '16', '-preset', 'fast',
         '-pix_fmt', 'yuv420p', '-movflags', '+faststart', str(preview)], b''.join(x.tobytes() for x in new_rgb))
    report = dict(width=W, height=H, fps=FPS, frame_count=len(frames), bytes=len(payload), payload_frame_bytes=frame_bytes,
                  header_bytes=0, format='unchanged B4Q 4x4 quarter interpolation',
                  baseline=BASELINE.as_posix(), baseline_sha256=baseline_sha, candidate=target.name, candidate_sha256=digest(payload),
                  baseline_native_psnr_db=psnr(sum(x['original_sse'] for x in records) / (len(frames) * W * H * 3)),
                  candidate_native_psnr_db=psnr(sum(x['improved_sse'] for x in records) / (len(frames) * W * H * 3)),
                  no_block_mse_increase=True, changed_blocks=sum(x['improved_blocks'] for x in records),
                  total_blocks=sum(x['total_blocks'] for x in records), comparisons_720p=results, frame_metrics=records,
                  ending_title_roi=[320, 180, 980, 350],
                  no_tf_or_hardware_access=True, baseline_unchanged=(digest(BASELINE.read_bytes()) == baseline_sha))
    (ROOT / 'analysis.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(json.dumps({k: v for k, v in report.items() if k != 'frame_metrics'}, indent=2), flush=True)


if __name__ == '__main__':
    main()
