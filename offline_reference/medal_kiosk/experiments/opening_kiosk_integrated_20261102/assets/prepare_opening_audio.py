"""Extract a five-second opening soundtrack for the existing PCM bridge.

PC-only. Writes solely to this assets directory; no GUI, TF, or board access.
"""
from pathlib import Path
import hashlib
import json
import subprocess
import wave

import numpy as np

ROOT = Path(__file__).resolve().parent
WORKSPACE = ROOT.parents[3]
SOURCE = WORKSPACE / 'output/video/republic_medal_repaired/v2_style_match/republic_medal_matched_v2.mp4'
FFMPEG = Path('C:/Users/20251/AppData/Local/kzip_sogou/ffmpeg.exe')
RATE, SAMPLES, CHANNELS, SAMPLE_BYTES = 16000, 80000, 1, 2


def digest(data):
    return hashlib.sha256(data).hexdigest()


def main():
    ROOT.mkdir(parents=True, exist_ok=True)
    target = ROOT / 'OPENING.PCM'
    command = [str(FFMPEG), '-hide_banner', '-loglevel', 'error', '-y', '-i', str(SOURCE),
               '-map', '0:a:0', '-vn', '-af', f'aresample={RATE},apad=whole_len={SAMPLES},atrim=end_sample={SAMPLES}',
               '-ac', str(CHANNELS), '-ar', str(RATE), '-acodec', 'pcm_s16le', '-f', 's16le', str(target)]
    subprocess.run(command, check=True, capture_output=True)
    data = target.read_bytes()
    assert len(data) == SAMPLES * CHANNELS * SAMPLE_BYTES == 160000
    samples = np.frombuffer(data, dtype='<i2')
    assert len(samples) == SAMPLES
    maximum = int(samples.max())
    minimum = int(samples.min())
    absolute_peak = int(np.abs(samples.astype(np.int32)).max())
    rms = float(np.sqrt(np.mean(samples.astype(np.float64) ** 2)))
    clipped = int(np.count_nonzero((samples == 32767) | (samples == -32768)))
    preview = ROOT / 'opening_16k_mono_preview.wav'
    with wave.open(str(preview), 'wb') as writer:
        writer.setnchannels(CHANNELS)
        writer.setsampwidth(SAMPLE_BYTES)
        writer.setframerate(RATE)
        writer.writeframes(data)
    with wave.open(str(preview), 'rb') as reader:
        assert (reader.getnchannels(), reader.getsampwidth(), reader.getframerate(), reader.getnframes()) == (1, 2, RATE, SAMPLES)
        assert reader.readframes(SAMPLES) == data
    # FFmpeg input metadata is retained for source provenance, not used as a
    # substitute for the exact sample-count verification above.
    probe = subprocess.run([str(FFMPEG), '-hide_banner', '-i', str(SOURCE)], capture_output=True)
    probe_text = probe.stderr.decode('utf-8', errors='replace')
    metadata_lines = [line.strip() for line in probe_text.splitlines() if 'Duration:' in line or 'Audio:' in line or 'Video:' in line]
    (ROOT / 'source_media_metadata.txt').write_text('\n'.join(metadata_lines) + '\n', encoding='utf-8')
    bridge = WORKSPACE / 'medal_kiosk/releases/audio_spectrum_fine_accepted_20261102/source/hdl_source/pcm_audio_bridge.v'
    player = bridge.with_name('pcm_voice_player.v')
    player_text = player.read_text()
    assert 'Every input sample is sent three times' in player_text
    assert 'sample_data,8\'b0' in player_text
    report = dict(file=target.name, target_sfn='OPENING PCM', format='signed 16-bit little-endian mono PCM, no header',
                  sample_rate_hz=RATE, channels=CHANNELS, bits_per_sample=16,
                  samples=SAMPLES, duration_seconds=SAMPLES / RATE, bytes=len(data), sha256=digest(data),
                  bytes_per_second=RATE * CHANNELS * SAMPLE_BYTES,
                  normalization='none', volume_filter='none; original downmix level retained',
                  conversion='decode source AAC, resample to16k, mono downmix, pad/trim to exactly80000samples',
                  sample_min=minimum, sample_max=maximum, absolute_peak=absolute_peak,
                  peak_dbfs=float(20 * np.log10(max(absolute_peak, 1) / 32768.)),
                  rms_dbfs=float(20 * np.log10(max(rms, 1e-12) / 32768.)),
                  clipped_samples=clipped, nonzero_samples=int(np.count_nonzero(samples)),
                  boundary_statistics=dict(first_sample=int(samples[0]), last_sample=int(samples[-1]),
                                           first_10ms_peak=int(np.abs(samples[:160].astype(np.int32)).max()),
                                           last_10ms_peak=int(np.abs(samples[-160:].astype(np.int32)).max()),
                                           mean_sample=float(samples.mean())),
                  source=SOURCE.as_posix(), source_sha256=digest(SOURCE.read_bytes()), source_metadata=metadata_lines,
                  preview=preview.name, preview_samples_verified=True, preview_payload_sha256=digest(data),
                  bridge_format_verified=True, bridge_source=bridge.as_posix(), bridge_source_sha256=digest(bridge.read_bytes()),
                  player_source=player.as_posix(), player_source_sha256=digest(player.read_bytes()),
                  playback='existing player repeats each16k input sample three times to48k HDMI audio',
                  video_alignment='75frames at15fps =5seconds =80000audio samples',
                  tf_gui_hardware_untouched=True)
    (ROOT / 'opening_audio_manifest.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(json.dumps(report, indent=2), flush=True)


if __name__ == '__main__':
    main()
