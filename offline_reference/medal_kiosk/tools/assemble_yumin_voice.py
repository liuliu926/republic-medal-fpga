"""Combine speech clips and retain exact segment start sample positions."""
import json, wave
from pathlib import Path
base=Path(__file__).resolve().parents[1]/'assets_720p/audio_pilot'
segments=json.loads((base/'yumin_1926_segments.json').read_text(encoding='utf-8'))
data=[]; position=0; rate=16000
for i,item in enumerate(segments):
    with wave.open(str(base/('segment%d.wav'%i)),'rb') as w:
        assert (w.getnchannels(),w.getsampwidth(),w.getframerate())==(1,2,rate)
        item['start_sample']=position
        clip=w.readframes(w.getnframes()); position+=len(clip)//2; data.append(clip)
    if i != len(segments)-1:
        silence=bytes(2*int(rate*0.12)); data.append(silence); position+=len(silence)//2
with wave.open(str(base/'yumin_1926_segmented.wav'),'wb') as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(rate); w.writeframes(b''.join(data))
(base/'YUMIN01.PCM').write_bytes(b''.join(data))
(base/'yumin_1926_timing.json').write_text(json.dumps({'sample_rate':rate,'total_samples':position,'segments':segments},ensure_ascii=False,indent=2),encoding='utf-8')
print('Duration %.2f s; sample-aligned timing prepared.'%(position/rate))
