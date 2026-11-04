"""Extract 16-kHz mono 16-bit raw PCM, add checksums and speech durations."""
import hashlib
import json
import sys
import wave
from pathlib import Path

root = Path(__file__).resolve().parents[1]
batch = sys.argv[1] if len(sys.argv) > 1 else 'audio_life_batch'
out = root / 'assets_720p' / batch
manifest = json.loads((out / 'manifest.json').read_text(encoding='utf-8'))
for item in manifest:
    with wave.open(str(out / item['wav']), 'rb') as wav:
        fmt = (wav.getnchannels(), wav.getsampwidth(), wav.getframerate())
        if fmt != (1, 2, 16000):
            raise ValueError(f"{item['wav']}: expected mono 16-bit 16 kHz, got {fmt}")
        samples = wav.getnframes()
        data = wav.readframes(samples)
    if samples < 16000 or samples > 320000:
        raise ValueError(f"{item['wav']}: implausible length {samples}")
    (out / item['sfn']).write_bytes(data)
    item['samples'] = samples
    item['seconds'] = round(samples / 16000, 3)
    item['sha256'] = hashlib.sha256(data).hexdigest().upper()
(out / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding='utf-8')
print(f'Validated {len(manifest)} PCM clips; total {sum(x["seconds"] for x in manifest):.1f} s')
