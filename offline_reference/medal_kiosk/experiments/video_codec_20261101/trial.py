"""PC-only indexed-frame delta trial. Does not access board or removable disks."""
from pathlib import Path
import subprocess, json, struct, hashlib
import numpy as np
from PIL import Image, ImageDraw

ROOT=Path(__file__).resolve().parent
SOURCE=ROOT.parents[2]/'output/video/republic_medal_repaired/v2_style_match/republic_medal_matched_v2.mp4'
FF='C:/Users/20251/AppData/Local/kzip_sogou/ffmpeg.exe'

def run(args):
    return subprocess.run([FF,'-hide_banner','-loglevel','error']+args,stdout=subprocess.PIPE,stderr=subprocess.PIPE,check=True).stdout

def encode_delta(a,b):
    same=a==b
    edges=np.r_[0,np.flatnonzero(same[1:]!=same[:-1])+1,len(a)]
    out=bytearray()
    for lo,hi in zip(edges[:-1],edges[1:]):
        for start in range(int(lo),int(hi),32767):
            end=min(start+32767,int(hi)); skip=bool(same[start])
            out+=struct.pack('<H',(end-start)|(0x8000 if skip else 0))
            if not skip:out+=a[start:end].tobytes()
    return out

def decode_delta(payload,previous):
    out=previous.copy(); pos=0; dst=0
    while pos<len(payload):
        word=struct.unpack_from('<H',payload,pos)[0]; pos+=2
        count=word&32767
        assert count>0 and dst+count<=len(out)
        if not word&32768:
            out[dst:dst+count]=np.frombuffer(payload[pos:pos+count],np.uint8); pos+=count
        dst+=count
    assert dst==len(out) and pos==len(payload)
    return out

def trial(w,h,fps):
    folder=ROOT/('{}x{}_{}fps'.format(w,h,fps)); folder.mkdir(exist_ok=True)
    raw=run(['-i',str(SOURCE),'-vf','fps={},scale={}:{}:flags=lanczos'.format(fps,w,h),'-pix_fmt','rgb24','-f','rawvideo','pipe:1'])
    frames=np.frombuffer(raw,np.uint8).reshape(-1,h,w,3)
    samples=frames[::max(1,len(frames)//24)]
    atlas=Image.fromarray(samples.reshape(-1,w,3))
    palette_image=atlas.quantize(colors=256,method=0)
    pal=np.array(palette_image.getpalette(),np.uint8).reshape(256,3)
    # Quantize the actual FPGA palette to RGB565; preview uses those same colors.
    packed=((pal[:,0].astype(np.uint16)>>3)<<11)|((pal[:,1].astype(np.uint16)>>2)<<5)|(pal[:,2]>>3)
    pal565=np.stack([((packed>>11)*255//31),(((packed>>5)&63)*255//63),((packed&31)*255//31)],axis=1).astype(np.uint8)
    stream=bytearray(struct.pack('<4sHHHHI',b'PVD1',w,h,fps,256,len(frames)))
    stream+=packed.astype('<u2').tobytes()
    previous=np.zeros(w*h,np.uint8); sizes=[]; decoded=[]; mse=0.0
    for i,frame in enumerate(frames):
        indices=np.asarray(Image.fromarray(frame).quantize(palette=palette_image,dither=0)).reshape(-1)
        delta=encode_delta(indices,previous)
        mode=1 if i and len(delta)<len(indices) else 0
        payload=bytes(delta) if mode else indices.tobytes()
        stream+=struct.pack('<BI',mode,len(payload))+payload
        reconstructed=decode_delta(payload,previous) if mode else np.frombuffer(payload,np.uint8).copy()
        assert np.array_equal(indices,reconstructed),i
        previous=reconstructed
        rgb=pal565[reconstructed].reshape(h,w,3); decoded.append(rgb)
        mse+=float(np.mean((rgb.astype(np.float32)-frame.astype(np.float32))**2))
        sizes.append(5+len(payload))
    (folder/'opening.pvd').write_bytes(stream)
    # Preview video is decoded from the trial stream, including palette precision.
    preview=folder/'decoded_preview.mp4'
    cmd=[FF,'-y','-hide_banner','-loglevel','error','-f','rawvideo','-pix_fmt','rgb24','-s','{}x{}'.format(w,h),'-r',str(fps),'-i','pipe:0','-i',str(ROOT/'audio.wav'),'-map','0:v:0','-map','1:a:0','-vf','scale=1280:720:flags=neighbor','-c:v','libx264','-crf','16','-preset','fast','-pix_fmt','yuv420p','-c:a','aac','-b:a','96k','-shortest','-movflags','+faststart',str(preview)]
    p=subprocess.Popen(cmd,stdin=subprocess.PIPE,stderr=subprocess.PIPE)
    p.communicate(b''.join(x.tobytes() for x in decoded)); assert p.returncode==0
    run(['-i',str(preview),'-f','null','-'])
    # Cumulative underflow model: bytes required at display deadlines minus delivery.
    cumulative=np.cumsum(sizes)+528; deadlines=np.arange(len(sizes))/float(fps)
    audio_rate=32000
    preload={str(rate):int(max(0,np.max(cumulative-(rate-audio_rate)*deadlines))) for rate in [800000,1000000,1200000]}
    result=dict(width=w,height=h,fps=fps,frames=len(frames),seconds=len(frames)/float(fps),video_bytes=len(stream),audio_bytes=len((ROOT/'audio.pcm').read_bytes()),average_video_Bps=len(stream)*fps/len(frames),peak_1s_video_Bps=int(max(sum(sizes[i:i+fps]) for i in range(max(1,len(sizes)-fps+1)))),largest_frame_bytes=max(sizes),required_start_buffer_by_total_read_Bps=preload,rgb565_framebuffer_pair_bytes=w*h*4,palette_bytes=512,quantization_PSNR_dB=float(10*np.log10(255**2/(mse/len(frames)))),frame_roundtrip_verified=True,preview_decode_verified=True,sha256=hashlib.sha256(stream).hexdigest())
    (folder/'metrics.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
    sheet=Image.new('RGB',(1280,390*3),(25,25,25)); draw=ImageDraw.Draw(sheet)
    for row,t in enumerate([.5,2.5,4.5]):
        i=min(int(t*fps),len(frames)-1)
        original=run(['-ss',str(t),'-i',str(SOURCE),'-frames:v','1','-vf','scale=640:360','-pix_fmt','rgb24','-f','rawvideo','pipe:1'])
        sheet.paste(Image.frombytes('RGB',(640,360),original),(0,row*390))
        sheet.paste(Image.fromarray(decoded[i]).resize((640,360),Image.NEAREST),(640,row*390))
        draw.text((10,row*390+365),'Original   {}s'.format(t),fill='white')
        draw.text((650,row*390+365),'Decoded {}x{} {}fps RGB565 palette'.format(w,h,fps),fill='white')
    sheet.save(folder/'comparison.jpg',quality=95)
    print(json.dumps(result),flush=True)
    return result

if __name__=='__main__':
    ROOT.mkdir(exist_ok=True,parents=True)
    assert SOURCE.exists(),SOURCE
    run(['-y','-i',str(SOURCE),'-vn','-ac','1','-ar','16000','-c:a','pcm_s16le',str(ROOT/'audio.wav')])
    run(['-y','-i',str(ROOT/'audio.wav'),'-f','s16le',str(ROOT/'audio.pcm')])
    results=[trial(*spec) for spec in [(320,180,24),(480,270,24),(640,360,24)]]
    (ROOT/'results.json').write_text(json.dumps(results,indent=2),encoding='utf-8')
