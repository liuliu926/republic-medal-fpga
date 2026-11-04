"""Fixed-rate 4x4 block codec: two RGB565 endpoints + sixteen 2-bit selectors.
PC feasibility only. FPGA implementation, throughput and memory allocation unverified.
"""
from pathlib import Path
import json, struct, subprocess, hashlib
import numpy as np
from PIL import Image,ImageDraw
from trial import ROOT,SOURCE,FF,run

def pack565(rgb):
    q=rgb.astype(np.uint16)
    return ((q[...,0]>>3)<<11)|((q[...,1]>>2)<<5)|(q[...,2]>>3)

def unpack565(q):
    q=q.astype(np.uint32)
    # Bit replication, matches inexpensive hardware expansion.
    r=q>>11; g=(q>>5)&63; b=q&31
    return np.stack([(r<<3)|(r>>2),(g<<2)|(g>>4),(b<<3)|(b>>2)],axis=-1).astype(np.uint16)

def colors(a,b):
    a=unpack565(a); b=unpack565(b)
    # Quarters instead of thirds remove division from decoder.
    return np.stack([a,(3*a+b)>>2,(a+3*b)>>2,b],axis=1)

def encode(frame):
    h,w=frame.shape[:2]
    blocks=frame.reshape(h//4,4,w//4,4,3).transpose(0,2,1,3,4).reshape(-1,16,3).astype(np.float32)
    centered=blocks-blocks.mean(axis=1,keepdims=True)
    cov=np.einsum('nki,nkj->nij',centered,centered)
    _,vectors=np.linalg.eigh(cov)
    axis=vectors[:,:,-1]
    proj=np.einsum('nki,ni->nk',centered,axis)
    n=np.arange(len(blocks))
    a=pack565(blocks[n,proj.argmin(axis=1)]); b=pack565(blocks[n,proj.argmax(axis=1)])
    table=colors(a,b)
    dist=((blocks[:,:,None,:]-table[:,None,:,:])**2).sum(axis=3)
    idx=dist.argmin(axis=2).astype(np.uint32)
    masks=np.sum(idx<<np.arange(0,32,2,dtype=np.uint32),axis=1,dtype=np.uint32)
    out=np.empty(len(blocks),dtype=[('a','<u2'),('b','<u2'),('m','<u4')]);out['a']=a;out['b']=b;out['m']=masks
    return out.tobytes()

def decode(payload,w,h):
    data=np.frombuffer(payload,dtype=[('a','<u2'),('b','<u2'),('m','<u4')])
    table=colors(data['a'],data['b'])
    idx=(data['m'][:,None]>>np.arange(0,32,2,dtype=np.uint32))&3
    blocks=table[np.arange(len(data))[:,None],idx].astype(np.uint8)
    return blocks.reshape(h//4,w//4,4,4,3).transpose(0,2,1,3,4).reshape(h,w,3)

def trial(w,h,fps):
    folder=ROOT/('block_{}x{}_{}fps'.format(w,h,fps));folder.mkdir(exist_ok=True)
    raw=run(['-i',str(SOURCE),'-vf','fps={},scale={}:{}:flags=lanczos'.format(fps,w,h),'-pix_fmt','rgb24','-f','rawvideo','pipe:1'])
    frames=np.frombuffer(raw,np.uint8).reshape(-1,h,w,3)
    stream=bytearray(struct.pack('<4sHHHHI',b'B4Q1',w,h,fps,0,len(frames)))
    decoded=[];mse=0
    for f in frames:
        payload=encode(f);stream+=payload
        rgb=decode(payload,w,h);decoded.append(rgb)
        mse+=np.mean((rgb.astype(np.float32)-f.astype(np.float32))**2)
    target=folder/'opening.b4q';target.write_bytes(stream)
    # Read file back, parse independently, validate all stored frames.
    saved=target.read_bytes();magic,fw,fh,ffps,reserved,count=struct.unpack_from('<4sHHHHI',saved)
    framebytes=w*h//2
    assert magic==b'B4Q1' and (fw,fh,ffps,count)==(w,h,fps,len(frames))
    assert len(saved)==16+count*framebytes
    for i,expected in enumerate(decoded):
        assert np.array_equal(decode(saved[16+i*framebytes:16+(i+1)*framebytes],w,h),expected)
    preview=folder/'decoded_preview.mp4'
    cmd=[FF,'-y','-hide_banner','-loglevel','error','-f','rawvideo','-pix_fmt','rgb24','-s','{}x{}'.format(w,h),'-r',str(fps),'-i','pipe:0','-i',str(ROOT/'audio.wav'),'-map','0:v:0','-map','1:a:0','-vf','scale=1280:720:flags=neighbor','-c:v','libx264','-crf','16','-preset','fast','-pix_fmt','yuv420p','-c:a','aac','-b:a','96k','-shortest','-movflags','+faststart',str(preview)]
    p=subprocess.Popen(cmd,stdin=subprocess.PIPE,stderr=subprocess.PIPE);_,err=p.communicate(b''.join(x.tobytes() for x in decoded));assert p.returncode==0,err
    run(['-i',str(preview),'-f','null','-'])
    durations=np.arange(count)/float(fps);cum=16+np.arange(1,count+1)*framebytes
    result=dict(width=w,height=h,fps=fps,frames=count,video_bytes=len(stream),video_Bps=framebytes*fps,audio_Bps=32000,audio_bytes=len((ROOT/'audio.pcm').read_bytes()),rgb565_framebuffer_pair_bytes=w*h*4,quantization_PSNR_dB=float(10*np.log10(255**2/(mse/count))),required_start_buffer_by_total_read_Bps={str(rate):int(max(0,np.max(cum-(rate-32000)*durations))) for rate in [800000,1000000,1200000]},stored_stream_roundtrip_verified=True,preview_decode_verified=True,sha256=hashlib.sha256(stream).hexdigest())
    (folder/'metrics.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
    sheet=Image.new('RGB',(1280,1170),(25,25,25));d=ImageDraw.Draw(sheet)
    for row,t in enumerate([.5,2.5,4.5]):
        i=min(int(t*fps),count-1)
        original=run(['-ss',str(t),'-i',str(SOURCE),'-frames:v','1','-vf','scale=640:360','-pix_fmt','rgb24','-f','rawvideo','pipe:1'])
        sheet.paste(Image.frombytes('RGB',(640,360),original),(0,row*390))
        sheet.paste(Image.fromarray(decoded[i]).resize((640,360),Image.NEAREST),(640,row*390))
        d.text((10,row*390+365),'Original {}s'.format(t),fill='white');d.text((650,row*390+365),'Decoded block {}x{} {}fps'.format(w,h,fps),fill='white')
    sheet.save(folder/'comparison.jpg',quality=95)
    print(json.dumps(result),flush=True)
    return result

if __name__=='__main__':
    results=[trial(*spec) for spec in [(448,252,24),(512,288,24)]]
    (ROOT/'block_results.json').write_text(json.dumps(results,indent=2),encoding='utf-8')
