"""Convert a user-provided OGG/WAV to streaming 16-kHz mono PCM and a preview.

No TF card is accessed. FFmpeg performs decoding/resampling on the computer;
the FPGA receives little-endian signed PCM and requires no compressed decoder.
"""
from pathlib import Path
import argparse
import hashlib
import json
import math
import shutil
import subprocess
import wave

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--source', type=Path, required=True)
parser.add_argument('--ffmpeg', type=Path, required=True)
parser.add_argument('--ffprobe', type=Path, required=True)
parser.add_argument('--output', type=Path, default=ROOT / 'assets_720p/bgm_20261031')
args = parser.parse_args()
source = args.source.resolve()
output = args.output.resolve()
assert source.is_file(), source
assert args.ffmpeg.is_file() and args.ffprobe.is_file()
output.mkdir(parents=True, exist_ok=True)
sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest().upper()
source_hash = sha(source)
probe = json.loads(subprocess.check_output([
    str(args.ffprobe), '-v', 'error', '-select_streams', 'a:0',
    '-show_entries', 'format=duration,size:stream=codec_name,sample_rate,channels',
    '-of', 'json', str(source)], encoding='utf-8'))
decoded = subprocess.check_output([
    str(args.ffmpeg), '-v', 'error', '-i', str(source), '-map', '0:a:0',
    '-vn', '-ac', '1', '-ar', '16000', '-c:a', 'pcm_f32le', '-f', 'f32le', 'pipe:1'])
samples = np.frombuffer(decoded, dtype='<f4').astype(np.float64)
assert len(samples) > 16000 and np.all(np.isfinite(samples))
decoded_sample_count = len(samples)
# Vorbis may expose a short trailing decoder block beyond the OGG granule
# duration. Keep the original declared duration, rounded to one PCM sample.
declared_samples = int(round(float(probe['format']['duration']) * 16000))
trailing_decoder_samples_removed = 0
if declared_samples < len(samples) and len(samples) - declared_samples <= 800:
    trailing_decoder_samples_removed = len(samples) - declared_samples
    samples = samples[:declared_samples]
source_peak = float(np.max(np.abs(samples)))
assert source_peak > 0
# Peak headroom protects fixed-point mixing. Restrict boost to +6 dB.
target_peak = 10.0 ** (-3.0 / 20.0)
gain = min(target_peak / source_peak, 10.0 ** (6.0 / 20.0))
samples *= gain
# A 20-ms edge ramp avoids a sample discontinuity at an end-to-start loop.
# It does not turn the musical end into a composed seamless loop; it only
# suppresses clicks, preserving all samples and the original musical duration.
fade_count = min(320, len(samples) // 2)
ramp = np.linspace(0.0, 1.0, fade_count)
samples[:fade_count] *= ramp
samples[-fade_count:] *= ramp[::-1]
quantized = np.rint(samples * 32767.0).clip(-32768, 32767).astype('<i2')
raw = quantized.tobytes()
pcm_path = output / 'BGM.PCM'
pcm_path.write_bytes(raw)
with wave.open(str(output / 'BGM_preview.wav'), 'wb') as wav:
    wav.setnchannels(1)
    wav.setsampwidth(2)
    wav.setframerate(16000)
    wav.writeframes(raw)
original_copy = output / ('source_original' + source.suffix.lower())
shutil.copy2(source, original_copy)
assert sha(source) == source_hash == sha(original_copy)
assert len(raw) == len(quantized) * 2 and quantized[0] == 0 and quantized[-1] == 0
clip_count = int(np.count_nonzero((quantized == -32768) | (quantized == 32767)))
assert clip_count == 0
with wave.open(str(output / 'BGM_preview.wav'), 'rb') as wav:
    assert (wav.getnchannels(), wav.getsampwidth(), wav.getframerate()) == (1, 2, 16000)
    assert wav.readframes(wav.getnframes()) == raw
manifest = {
    'source_path': str(source), 'source_sha256': source_hash,
    'source_probe': probe, 'original_copy': original_copy.name,
    'output_file': pcm_path.name, 'output_sha256': sha(pcm_path),
    'format': 'signed 16-bit little-endian raw PCM, mono, 16000 Hz, no header',
    'sample_rate_hz': 16000, 'channels': 1, 'bits_per_sample': 16,
    'samples': len(quantized), 'seconds': len(quantized) / 16000.0,
    'bytes': len(raw), 'bytes_per_second': 32000,
    'source_decoded_peak': source_peak, 'gain_db': 20.0 * math.log10(gain),
    'output_peak_dbfs': 20.0 * math.log10(float(np.max(np.abs(quantized.astype(np.int32)))) / 32768.0),
    'output_rms_dbfs': 20.0 * math.log10(float(np.sqrt(np.mean((quantized.astype(np.float64) / 32768.0) ** 2)))),
    'clipped_samples': clip_count, 'edge_fade_ms': 20,
    'musical_content_trimmed': False, 'padded': False,
    'decoded_samples_before_duration_alignment': decoded_sample_count,
    'trailing_decoder_samples_removed': trailing_decoder_samples_removed,
    'loop_note': '20 ms edge fades suppress clicks; original musical ending and any source silence are retained.',
    'ffmpeg_path': str(args.ffmpeg),
    'ffmpeg_version': subprocess.check_output([str(args.ffmpeg), '-version'], encoding='utf-8').splitlines()[0],
    'tf_card_written': False,
}
(output / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(json.dumps({k: manifest[k] for k in ['output_file', 'samples', 'seconds', 'bytes', 'output_sha256', 'gain_db', 'output_peak_dbfs', 'clipped_samples']}, indent=2))
