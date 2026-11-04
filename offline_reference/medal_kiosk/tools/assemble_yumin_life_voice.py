"""Assemble one TF PCM clip and exact sample starts for a Yu Min life row."""
import json
import sys
import wave
from pathlib import Path

year = sys.argv[1]
assert year in ('1961', '1967')
clip_number = {'1961': '03', '1967': '04'}[year]
base = Path(__file__).resolve().parents[1] / 'assets_720p/audio_pilot'
segments = json.loads((base / f'yumin_{year}_segments.json').read_text(encoding='utf-8'))
parts = []
position = 0
rate = 16000
for i, segment in enumerate(segments):
    with wave.open(str(base / f'segment{year}_{i}.wav'), 'rb') as wav:
        assert (wav.getnchannels(), wav.getsampwidth(), wav.getframerate()) == (1, 2, rate)
        segment['start_sample'] = position
        pcm = wav.readframes(wav.getnframes())
        parts.append(pcm)
        position += len(pcm) // 2
    if i != len(segments) - 1:
        pause = bytes(2 * int(rate * 0.12))
        parts.append(pause)
        position += len(pause) // 2
(base / f'YUMIN{clip_number}.PCM').write_bytes(b''.join(parts))
(base / f'yumin_{year}_timing.json').write_text(json.dumps({
    'sample_rate': rate, 'total_samples': position, 'segments': segments,
}, ensure_ascii=False, indent=2), encoding='utf-8')
print(f'YUMIN{clip_number}.PCM: {position/rate:.2f} s, {position} samples')
