"""Build an isolated BMP/PCM client which shares the FAT sector buffer."""
from pathlib import Path
p=Path(__file__).resolve().parents[1]/'fpga/user_source_720p/hdl_source/SD'
s=(p/'fat32_bmp_asset_loader.v').read_text(encoding='utf-8')
s=s.replace('module fat32_bmp_asset_loader #(', 'module fat32_bmp_pcm_asset_loader #(',1)
s=s.replace('    input  wire        start,', '''    input wire pcm_mode,
    input wire pcm_ready,
    output wire pcm_valid,
    output wire [7:0] pcm_data,
    input  wire        start,''',1)
s=s.replace('    wire decoder_ready;', '    wire decoder_ready;\n    wire bmp_reader_ready;\n    reg pcm_mode_q;',1)
s=s.replace('    assign header_done      = decoder_header_done;', '''    assign pcm_valid = pcm_mode_q && reader_valid;
    assign pcm_data = reader_data;
    assign reader_ready = pcm_mode_q ? pcm_ready : bmp_reader_ready;
    assign header_done      = decoder_header_done;''',1)
s=s.replace('.stream_valid(reader_valid),', '.stream_valid(reader_valid && !pcm_mode_q),',1)
s=s.replace('.stream_ready(reader_ready),', '.stream_ready(bmp_reader_ready),',1)
s=s.replace('            state                    <= ST_IDLE;', '            pcm_mode_q <= 0;\n            state                    <= ST_IDLE;',1)
s=s.replace('                        target_sfn_latched <= target_sfn;', '                        pcm_mode_q <= pcm_mode;\n                        target_sfn_latched <= target_sfn;',1)
s=s.replace("                    decoder_start <= 1'b1;", "                    decoder_start <= !pcm_mode_q;",1)
s=s.replace('                    end else if (decoder_error) begin', '                    end else if (decoder_error && !pcm_mode_q) begin',1)
s=s.replace('(decoder_done_seen || decoder_done)) begin', '(pcm_mode_q || decoder_done_seen || decoder_done)) begin',1)
(p/'fat32_bmp_pcm_asset_loader.v').write_text(s,encoding='utf-8')
print('Prepared shared BMP/PCM FAT client')
