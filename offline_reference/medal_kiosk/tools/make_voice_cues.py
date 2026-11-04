"""Create approximate per-character cues anchored to synthesized clips.

Characters within a clip are uniformly spaced, not force-aligned phonemes.
All indices refer to 16 kHz PCM samples, including inter-clip silence.
"""
import json
from pathlib import Path

base = Path(__file__).resolve().parents[1] / 'assets_720p/audio_pilot'
timing = json.loads((base / 'yumin_1926_timing.json').read_text(encoding='utf-8'))
segments = timing['segments']
cues = []
for i, segment in enumerate(segments):
    start = segment['start_sample']
    end = segments[i + 1]['start_sample'] if i + 1 < len(segments) else timing['total_samples']
    chars = list(segment['subtitle'])
    for j, char in enumerate(chars):
        cues.append({'character': char, 'start_sample': start + (end-start)*j//len(chars)})
(base / 'yumin_1926_character_cues.json').write_text(
    json.dumps({'sample_rate': timing['sample_rate'], 'approximate': True, 'cues': cues},
               ensure_ascii=False, indent=2), encoding='utf-8')
print('Prepared', len(cues), 'sample-indexed approximate character cues')
