"""Generate a compact, sample-driven subtitle cue ROM from local TTS metadata.

Speech word starts are measured by the synthesizer. Within each multi-character
word we interpolate, so this is word-aligned karaoke, not phoneme alignment.
The shipped PCM and bitmap atlases are not modified.
"""
import hashlib
import json
import wave
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / 'fpga/user_source_720p/hdl_source'
OUT = ROOT / 'assets_720p/audio_article_cues'

def main():
    manifest = json.loads((ROOT / 'assets_720p/audio_article_batch/manifest.json').read_text(encoding='utf-8-sig'))
    rom = [0x8003ff] * 4096  # Invalid slots finish harmlessly.
    report = []
    draw = ImageDraw.Draw(Image.new('L', (768, 64)))
    for item in manifest:
        pcm = (ROOT / 'assets_720p/audio_article_batch' / item['sfn']).read_bytes()
        assert hashlib.sha256(pcm).hexdigest().upper() == item['sha256']
        with wave.open(str(OUT / item['wav']), 'rb') as wav:
            assert (wav.getnchannels(), wav.getsampwidth(), wav.getframerate()) == (1, 2, 16000)
            assert wav.readframes(wav.getnframes()) == pcm, item['sfn']
        tracks = json.loads((OUT / (item['sfn'] + '.json')).read_text(encoding='utf-8-sig'))
        raw_words = next(t['cues'] for t in tracks if t['id'] == 'SpeechWord')
        words = []
        for cue in raw_words:
            # Windows emits each spoken part of e.g. "2号" with the same
            # full written token. Keep the token's first onset only.
            if words and cue['text'] == words[-1]['text'] and any(c.isdigit() for c in cue['text']):
                continue
            words.append(cue)
        speech, body = item['speech'], item['subtitle']
        body_start = speech.rindex(body)
        timings, cursor = {}, 0
        for n, cue in enumerate(words):
            word = cue['text'].strip()
            start = speech.find(word, cursor)
            assert start >= cursor, (item['sfn'], word, cursor)
            cursor = start + len(word)
            a = cue['time_ticks'] * 16000 // 10000000
            # Last-word duration excludes the small trailing silence.
            b = words[n+1]['time_ticks'] * 16000 // 10000000 if n+1 < len(words) else item['samples'] - 1600
            assert b >= a
            for k in range(len(word)):
                timings[start+k] = a + (b-a)*k//len(word)
        offset = 130 if item['section'] == 'deeds' else 2
        width = 630 if offset == 130 else 495
        for size in range(23, 12, -1):
            font = ImageFont.truetype('C:/Windows/Fonts/msyh.ttc', size)
            if draw.textsize(body, font=font)[0] <= width:
                break
        events = []
        for k, char in enumerate(body):
            if body_start+k not in timings:
                assert not char.isalnum(), (item['sfn'], char)
                continue
            # Include following punctuation with the preceding spoken glyph.
            end = k+1
            while end < len(body) and body_start+end not in timings:
                end += 1
            x = offset + draw.textsize(body[:end], font=font)[0]
            tick = (timings[body_start+k]+63)//64  # 4 ms ticks, never reveal early.
            events.append([tick, x])
        assert 1 <= len(events) <= 31, item['sfn']
        assert all(a[0] <= b[0] and a[1] < b[1] for a,b in zip(events,events[1:]))
        # Last 4 ms interval, reachable at the finite PCM sample count.
        # Spoken glyphs are already complete before trailing silence.
        events.append([item['samples']//64, 768])
        slot = item['person_index']*8 + (4 if offset == 130 else 0) + item['row']-1
        for index, (tick, x) in enumerate(events):
            assert tick < 8192 and x < 1024
            rom[slot*32+index] = ((index == len(events)-1) << 23) | (tick << 10) | x
        report.append(dict(sfn=item['sfn'], slot=slot, size=size, body=body,
                           title=item['title'], samples=item['samples'], events=events,
                           body_start_seconds=events[0][0]/250.0))
    assert len(report) == 91
    (SRC / 'article_voice_cues.hex').write_text(''.join('%06X\n' % word for word in rom), encoding='ascii')
    (OUT / 'cue_index.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    print('Verified 91 original PCM files; generated 4096 x 24-bit cue ROM.')
    print('Yu Min C01 body starts at %.3f seconds.' % report[0]['body_start_seconds'])

if __name__ == '__main__':
    main()
