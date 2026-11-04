"""Run actual FAT32/BMP/scaler RTL against sparse SD-sector fixtures.

No board, TF card, TD project or installed tool settings are changed.
"""
import argparse
import json
from pathlib import Path
import struct
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
SD = ROOT / 'fpga/user_source_720p/hdl_source/SD'
SIM = ROOT / 'fpga/sim'
OUT = SIM / 'runs/pipeline'
BIN = ROOT / 'tools/local_hdl/iverilog/app/bin'


def bmp(width, height, extended=False, ow=16, oh=12):
    offset = 70 if extended else 54
    stride = (width * 3 + 3) & ~3
    data = bytearray(offset + stride * height)
    struct.pack_into('<2sI4xI', data, 0, b'BM', len(data), offset)
    struct.pack_into('<IiiHHII', data, 14, 40, width, height, 1, 24, 0, stride*height)
    def rgb(x,y):
        return ((x*19+y*3+11)&255, (x*5+y*29+17)&255, (x*7+y*11+23)&255)
    for y in range(height):
        for x in range(width):
            r,g,b = rgb(x,y)
            pos=offset+y*stride+x*3
            data[pos:pos+3]=bytes((b,g,r))
    if width*oh >= height*ow:
        fw,fh=ow,max(1,height*ow//width)
    else:
        fw,fh=max(1,width*oh//height),oh
    px,py=(ow-fw)//2,(oh-fh)//2
    expected=[]
    for y in range(oh):
        for x in range(ow):
            if px<=x<px+fw and py<=y<py+fh:
                r,g,b=rgb((x-px)*width//fw,(y-py)*height//fh)
                expected.append((r<<16)|(g<<8)|b)
            else: expected.append(0)
    return data,expected


def fixture(name,width,height,broken=False,bad_header=False,extended=False,ow=16,oh=12,dir_mode='first',fat_count=2,invalid_range=False,actual_vbr=False,actual_root=False):
    data,expected=bmp(width,height,extended,ow,oh)
    if bad_header: data[0]=0
    disk={}
    mbr=bytearray(512); mbr[450]=0x0c
    vbr=bytearray(512)
    spc=2 if dir_mode=='second_sector' else 1
    struct.pack_into('<HBHB',vbr,11,512,spc,32,fat_count)
    struct.pack_into('<II',vbr,32,70000,36000 if invalid_range else 600)
    struct.pack_into('<I',vbr,44,2); vbr[510:]=b'\x55\xaa'
    base=1
    if actual_vbr:
        vbr=bytearray((OUT/'actual_vbr.bin').read_bytes())
        base=struct.unpack_from('<I',vbr,28)[0]
        spc=vbr[13]; fat_count=vbr[16]
    total=struct.unpack_from('<I',vbr,32)[0]
    struct.pack_into('<II',mbr,454,base,total); mbr[510:]=b'\x55\xaa'; disk[0]=mbr
    disk[base]=vbr
    fat_base=base+struct.unpack_from('<H',vbr,14)[0]
    data_start=fat_base+fat_count*struct.unpack_from('<I',vbr,36)[0]
    fat=bytearray(512)
    struct.pack_into('<III',fat,0,0x0ffffff8,0x0fffffff,0x0fffffff)
    clusters=[(619 if actual_root else 5)+i*2 for i in range((len(data)+512*spc-1)//(512*spc))]
    # Fixtures intentionally use a fragmented cluster chain.
    for i,c in enumerate(clusters):
        fat_sector=c//128
        fat_lba=fat_base+fat_sector
        if fat_lba not in disk: disk[fat_lba]=fat if fat_sector==0 else bytearray(512)
        next_cluster=clusters[i+1] if i+1<len(clusters) and not broken else 0x0fffffff
        struct.pack_into('<I',disk[fat_lba],(c%128)*4,next_cluster)
        for sec in range(spc):
            offset=(i*spc+sec)*512
            if offset<len(data):
                disk[data_start+(c-2)*spc+sec]=data[offset:offset+512].ljust(512,b'\0')
    root=bytearray(512); root[:11]=b'TEST    BMP'; root[11]=0x20
    struct.pack_into('<H',root,26,5); struct.pack_into('<I',root,28,len(data))
    if actual_root:
        root=bytearray((OUT/'actual_root.bin').read_bytes())
        entry=root.find(b'BG001   BMP')
        if entry<0 or entry%32: raise ValueError('BG001 entry not present in first root sector')
        struct.pack_into('<I',root,entry+28,len(data))
    if dir_mode=='first':
        disk[data_start]=root
    else:
        empty=bytearray(512)
        for offset in range(0,512,32): empty[offset]=0xe5
        disk[data_start]=empty
        disk[data_start+1]=root
        if dir_mode=='next_cluster':
            struct.pack_into('<I',disk[fat_base],8,3)
            struct.pack_into('<I',disk[fat_base],12,0x0fffffff)
    dest=OUT/name; dest.mkdir(parents=True,exist_ok=True)
    lbas=sorted(disk)
    (dest/'lbas.hex').write_text(''.join(f'{a:08x}\n' for a in lbas))
    (dest/'sectors.hex').write_text(''.join(f'{b:02x}\n' for a in lbas for b in disk[a]))
    (dest/'expected.hex').write_text(''.join(f'{p:06x}\n' for p in expected))
    return dest,len(lbas)


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--case',default='all')
    parser.add_argument('--720p',dest='full_size',action='store_true')
    args=parser.parse_args()
    OUT.mkdir(parents=True,exist_ok=True)
    sources=['fat32_bmp_frame_pipeline','fat32_bmp_resize_stream','fat32_bmp_asset_loader',
             'fat32_volume_bootstrap','fat32_mbr_partition_scan','fat32_bpb_parser',
             'fat32_root_file_lookup','fat32_dir_sector_scan','fat32_file_stream_reader',
             'bmp_stream_decoder','bmp_resize_stream','bmp_scaled_frame_write_ctrl']
    exe=OUT/('pipeline720.vvp' if args.full_size else 'pipeline.vvp')
    cmd=[str(BIN/'iverilog.exe'),'-g2012','-s','tb_fat32_bmp_pipeline','-o',str(exe),
         str(SIM/'tb_fat32_bmp_pipeline.sv')]+[str(SD/(s+'.v')) for s in sources]
    if args.full_size:
        cmd[1:1]=['-Ptb_fat32_bmp_pipeline.OW=1280','-Ptb_fat32_bmp_pipeline.OH=720']
    compiled=subprocess.run(cmd,text=True,capture_output=True)
    (OUT/'compile.log').write_text(compiled.stdout+compiled.stderr,encoding='utf-8')
    if compiled.returncode:
        print(f'Compilation failed (exit {compiled.returncode})\n'+compiled.stdout+compiled.stderr)
        return compiled.returncode
    cases=[('upscale',7,5,{},0,0,2,0),('downscale',41,31,{},0,0,1,0),
           ('dir_second',7,5,{'dir_mode':'second_sector'},0,0,1,0),
           ('multi_sector_file',41,31,{'dir_mode':'second_sector'},0,0,1,0),
           ('one_fat',7,5,{'fat_count':1},0,0,1,0),
           ('invalid_fat_count',7,5,{'fat_count':0},1,0,1,0),
           ('invalid_volume_range',7,5,{'invalid_range':True},1,0,1,0),
           ('dir_cluster',7,5,{'dir_mode':'next_cluster'},0,0,1,0),
           ('extended',7,5,{'extended':True},0,0,1,0),
           ('busy_start',7,5,{},0,0,1,1),
           ('missing',7,5,{},1,0,1,0),('bad_header',7,5,{'bad_header':True},1,0,1,0),
           ('broken_chain',41,31,{'broken':True},1,0,2,0),
           ('writer_timeout',7,5,{},1,1,1,0),
           ('missing_recover',7,5,{},1,0,2,0),
           ('drain_timeout',7,5,{},1,0,1,0),
           ('sd_timeout',7,5,{},1,0,1,0),
           ('thin',1,810,{},0,0,1,0),('wide',1440,1,{},0,0,1,0)]
    if args.full_size: cases=[('full720p',7,5,{'ow':1280,'oh':720},0,0,1,0)]
    if (OUT/'actual_vbr.bin').exists() and not args.full_size:
        cases.append(('actual_card_vbr',7,5,{'actual_vbr':True},0,0,1,0))
    if (OUT/'actual_root.bin').exists() and not args.full_size:
        cases.append(('actual_card_root',7,5,{'actual_vbr':True,'actual_root':True},0,0,1,0))
    results=[]
    for name,w,h,opts,err,no_ack,repeats,inject in cases:
        if args.case!='all' and args.case!=name: continue
        dest,n=fixture(name,w,h,**opts)
        cmd=[str(BIN/'vvp.exe'),str(exe),f'+FIXTURE={dest.as_posix()}',f'+SECTORS={n}',
             f'+CASE={name}',f'+ERROR={err}',f'+NO_ACK={no_ack}',f'+REPEAT={repeats}',f'+INJECT={inject}']
        cmd += [f'+NO_FINISH={int(name=="drain_timeout")}',
                f'+SD_HANG={int(name=="sd_timeout")}',
                f'+RECOVER_GOOD={int(name=="missing_recover")}']
        run=subprocess.run(cmd,text=True,capture_output=True,timeout=240 if args.full_size else 45)
        output=run.stdout+run.stderr
        (dest/'result.log').write_text(output,encoding='utf-8')
        results.append({'case':name,'passed':run.returncode==0,'output':output.strip()})
        print(output.strip())
    report='results720.json' if args.full_size else 'results.json'
    (OUT/report).write_text(json.dumps(results,indent=2),encoding='utf-8')
    return 0 if results and all(r['passed'] for r in results) else 1


if __name__=='__main__': sys.exit(main())
