"""Build the second 16 kHz mono TF PCM clip and sample-aligned cue metadata."""
import json
import wave
from pathlib import Path

base = Path(__file__).resolve().parents[1] / 'assets_720p/audio_pilot'
segments = json.loads((base / 'yumin_1949_segments.json').read_text(encoding='utf-8'))
parts = []
position = 0
rate = 16000
for i, segment in enumerate(segments):
    with wave.open(str(base / f'segment1949_{i}.wav'), 'rb') as wav:
        assert (wav.getnchannels(), wav.getsampwidth(), wav.getframerate()) == (1, 2, rate)
        segment['start_sample'] = position
        pcm = wav.readframes(wav.getnframes())
        parts.append(pcm)
        position += len(pcm) // 2
    if i != len(segments) - 1:
        pause = bytes(2 * int(rate * 0.12))
        parts.append(pause)
        position += len(pause) // 2
(base / 'YUMIN02.PCM').write_bytes(b''.join(parts))
(base / 'yumin_1949_timing.json').write_text(json.dumps({
    'sample_rate': rate, 'total_samples': position, 'segments': segments,
}, ensure_ascii=False, indent=2), encoding='utf-8')
print(f'YUMIN02.PCM: {position/rate:.2f} s, {position} samples')
