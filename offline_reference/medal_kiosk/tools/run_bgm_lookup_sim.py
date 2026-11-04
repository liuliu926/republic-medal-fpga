"""Check shared lookup-only discovery, missing-file recovery, then PCM read."""
from pathlib import Path
import subprocess
from run_pipeline_sim import fixture, bmp
root=Path(__file__).resolve().parents[1]
sd=root/'fpga/user_source_720p/hdl_source/SD'
sim=root/'fpga/sim'
binary=root/'tools/local_hdl/iverilog/app/bin'
dest,n=fixture('bgm_lookup',41,31,dir_mode='first')
data,_=bmp(41,31)
(dest/'pcm_expected.hex').write_text(''.join('{:02x}\n'.format(b) for b in data))
tb=(sim/'tb_pcm_fat_loader.sv').read_text()
tb=tb.replace('tb_pcm_fat_loader','tb_bgm_lookup_reuse')
tb=tb.replace('  wire ready=', '''  integer phase=0, restart_cycle=-1;
  reg lookup_only=1;
  reg [87:0] target="MISSING PCM";
  wire [27:0] cluster;
  wire [31:0] found_size;
  wire ready=''',1)
tb=tb.replace('fat32_bmp_pcm_asset_loader','fat32_sharedmeta_asset_loader_bgm',1)
tb=tb.replace('    .pcm_mode(1\'b1),', '''    .pcm_mode(1'b1),.lookup_only(lookup_only),
    .lookup_file_cluster(cluster),.lookup_file_size(found_size),
    .shared_metadata_valid(1'b1),.shared_boot_done(1'b1),.shared_boot_error_code(4'd0),
    .shared_fat_count(8'd2),.shared_volume_start_lba(32'd1),.shared_volume_sector_count(32'd70000),
    .shared_sectors_per_cluster(8'd1),.shared_sectors_per_fat(32'd600),
    .shared_root_cluster(28'd2),.shared_fat_start_lba(32'd33),.shared_data_start_lba(32'd1233),
    .shared_debug_bpb_error(4'd0),.shared_debug_bpb_offset(9'd0),''',1)
tb=tb.replace('.target_sfn("TEST    BMP")','.target_sfn(target)',1)
tb=tb.replace('    if(!rst) begin','''    if(!rst) begin
      if(cycles==restart_cycle) start<=1;
      else if(cycles==restart_cycle+1) start<=0;''',1)
old='''      if(done) begin
        if(error || n!=length) $fatal(1,"failed error=%h bytes=%d expected=%d",error_code,n,length);
        $display("PASS FAT32 raw stream: %0d bytes with backpressure",n); $finish;
      end'''
new='''      if(done) begin
        if(phase==0) begin
          if(!error || n!=0) $fatal(1,"missing BGM must fail without data");
          phase=1; target="TEST    BMP"; restart_cycle=cycles+5;
        end else if(phase==1) begin
          if(error || n!=0 || cluster!=5 || found_size!=length)
             $fatal(1,"lookup-only failed cluster%0d size%0d n%0d",cluster,found_size,n);
          phase=2; lookup_only=0; restart_cycle=cycles+5;
        end else begin
          if(error || n!=length) $fatal(1,"failed PCM after lookup bytes=%d error=%h",n,error_code);
          $display("PASS missing BGM recovery, lookup-only cached metadata, reused parser PCM %0d bytes",n);
          $finish;
        end
      end'''
assert old in tb
tb=tb.replace(old,new)
(sim/'tb_bgm_lookup_reuse.sv').write_text(tb)
exe=dest/'lookup.vvp'
modules=['fat32_sharedmeta_asset_loader_bgm','bmp_stream_decoder','fat32_root_file_lookup',
         'fat32_file_stream_reader_bgm_bram','fat32_dir_sector_scan']
cmd=[str(binary/'iverilog.exe'),'-g2012','-s','tb_bgm_lookup_reuse','-o',str(exe),
     str(sim/'tb_bgm_lookup_reuse.sv')]+[str(sd/(m+'.v')) for m in modules]
r=subprocess.run(cmd,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,universal_newlines=True,timeout=60)
(dest/'compile.log').write_text(r.stdout+'\nexit='+str(r.returncode),encoding='utf-8')
print(r.stdout)
if r.returncode: raise SystemExit(r.returncode)
r=subprocess.run([str(binary/'vvp.exe'),str(exe),'+FIXTURE='+dest.as_posix(),
                  '+SECTORS='+str(n),'+LENGTH='+str(len(data))],
                 stdout=subprocess.PIPE,stderr=subprocess.STDOUT,universal_newlines=True,timeout=60)
(dest/'result.log').write_text(r.stdout,encoding='utf-8')
print(r.stdout)
raise SystemExit(r.returncode)
