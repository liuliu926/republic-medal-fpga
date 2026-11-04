from pathlib import Path
p=Path(__file__).resolve().parents[1]/'fpga/user_source_720p/hdl_source'
s=(p/'top_fat32_voice_autoplay.v').read_text(encoding='utf-8')
assert 'fat32_shared_reused_pcm_frontend u_fat32_shared (' in s
s=s.replace('fat32_shared_reused_pcm_frontend u_fat32_shared (','fat32_shared_boot_frontend u_fat32_shared (',1)
(p/'top_fat32_voice_sharedboot.v').write_text(s,encoding='utf-8')
print('Prepared shared FAT bootstrap integration candidate')
