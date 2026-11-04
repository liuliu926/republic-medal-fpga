"""Derive an isolated raw PCM file loader from the existing FAT32 client."""
from pathlib import Path

root = Path(__file__).resolve().parents[1]
folder = root / 'fpga/user_source_720p/hdl_source/SD'
source = (folder/'fat32_bmp_asset_loader.v').read_text(encoding='utf-8')
source = source.replace('module fat32_bmp_asset_loader #(', 'module fat32_pcm_asset_loader #(', 1)
source = source.replace('    input  wire        pixel_enable,',
                        '    output wire        pcm_valid,\n    input wire pcm_ready,\n    output wire [7:0] pcm_data,\n    input  wire        pixel_enable,', 1)
source = source.replace('    assign header_done      = decoder_header_done;',
                        '    assign pcm_valid = reader_valid;\n    assign pcm_data = reader_data;\n    assign reader_ready = pcm_ready;\n    assign header_done      = decoder_header_done;', 1)
start = source.index('    bmp_stream_decoder u_bmp_stream_decoder (')
end = source.index('\n    always @(posedge clk) begin', start)
source = source[:start] + '''    // Raw little-endian PCM is forwarded byte for byte with backpressure.
    assign decoder_header_done = 1'b0;
    assign decoder_header_valid = 1'b0;
    assign decoder_width = 0;
    assign decoder_height = 0;
    assign decoder_pixel_valid = 1'b0;
    assign decoder_pixel_data = 0;
    assign decoder_done = reader_done;
    assign decoder_error = 1'b0;
''' + source[end:]
(folder/'fat32_pcm_asset_loader.v').write_text(source, encoding='utf-8')
print('Prepared isolated FAT32 raw PCM loader')
