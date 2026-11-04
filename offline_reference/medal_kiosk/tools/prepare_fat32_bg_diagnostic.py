"""Create isolated board diagnostic sources from the previously tested top.

The application sources, TF content and stable bitstreams are not modified.
"""
from pathlib import Path

root=Path(__file__).resolve().parents[1]
hdl=root/'fpga/user_source_720p/hdl_source'
sd=hdl/'SD'

def replace_once(text, old, new):
    if text.count(old)!=1: raise RuntimeError(f'Expected exactly one match: {old[:80]}')
    return text.replace(old,new,1)

mem=(sd/'frame_read_write_home_intro.v').read_text(encoding='utf-8')
mem=replace_once(mem,
    'input[WRITE_DATA_BITS - 1:0]     write_data                 // write data',
    'input[WRITE_DATA_BITS - 1:0]     write_data,\n    output wire write_fifo_full')
mem=replace_once(mem,'.full_flag                  (                         ),',
                      '.full_flag                  (write_fifo_full          ),')
(sd/'frame_read_write_fat32_diag.v').write_text(mem,encoding='utf-8')

top=(hdl/'top_home_intro_pilot.v').read_text(encoding='utf-8')
begin=top.index('sd_card_bmp #(')
end=top.index('// Diagnostic digits, left to right:',begin)
top=top[:begin]+'''// One BG001.BMP load; the new FAT32 frontend owns the TF SPI pins.
wire diag_sd_ready, diag_busy, diag_done, diag_error, diag_recovery;
wire [7:0] diag_error_code;
wire [3:0] diag_bpb_error, diag_boot_error;
wire [8:0] diag_bpb_offset;
wire [7:0] diag_fat_count, diag_cluster_size;
wire diag_fifo_full;
wire [20:0] diag_write_len, diag_offset, diag_jump;
wire [15:0] diag_width;
reg [1:0] memory_ready_sync;
reg started, diag_start, committed;
always @(posedge sd_card_clk or posedge rst_all) begin
    if (rst_all) begin
        memory_ready_sync<=0; started<=0; diag_start<=0; committed<=0;
    end else begin
        memory_ready_sync<={memory_ready_sync[0], Sdr_init_done};
        diag_start<=0;
        if (!started && memory_ready_sync[1] && diag_sd_ready) begin
            started<=1; diag_start<=1;
        end
        if (diag_done && !diag_error && !diag_recovery) committed<=1;
    end
end
fat32_bmp_spi_frontend u_fat32_diag (
    .clk(sd_card_clk), .mem_clk(ext_mem_clk), .rst(rst_all),
    .start(diag_start), .target_sfn("BG001   BMP"), .frame_index(2'd0),
    .SD_nCS(sd_ncs), .SD_DCLK(sd_dclk), .SD_MOSI(sd_mosi), .SD_MISO(sd_miso),
    .write_req_ack_mem(sd_card_write_req_ack), .write_finish_mem(frame_write_finish),
    .write_fifo_full(diag_fifo_full), .write_req(sd_card_write_req),
    .write_addr_index(write_buf_idx), .write_len(diag_write_len),
    .write_first_offset(diag_offset), .write_line_width(diag_width),
    .write_line_jump(diag_jump), .write_en(sd_card_write_en), .write_data(sd_card_write_data),
    .sd_init_done(diag_sd_ready), .busy(diag_busy), .done(diag_done),
    .error(diag_error), .error_code(diag_error_code), .recovery_required(diag_recovery),
    .debug_bpb_error(diag_bpb_error), .debug_bpb_offset(diag_bpb_offset), .debug_boot_error(diag_boot_error),
    .debug_fat_count(diag_fat_count), .debug_sectors_per_cluster(diag_cluster_size)
);
assign disp_buf_idx=2'd0;
assign display_valid=committed;
assign selected_image_valid=committed;
assign intro_active=1'b0;
assign fullportrait_mode=1'b0;
assign portrait_load_mode=1'b0;
assign portrait_image_index=4'd0;
assign home_text_start=1'b0;
assign home_text_valid=1'b0;
assign home_text_pixel=24'd0;
assign state_code=diag_error_code[3:0];
assign debug_found_count=diag_error_code[7:4];
assign debug_display_index={3'b000,committed};
assign debug_requested_index={3'b000,diag_recovery};
assign debug_load_busy=diag_busy;
assign debug_load_progress=2'd0;

''' + top[end:]
top=replace_once(top,'.I_rgb         (loading_overlay_rgb)', '.I_rgb         (vout_data)')
top=replace_once(top,'.write_len         (fullportrait_mode ? 21\'d128000 : (portrait_load_mode ? 21\'d8000 : FRAME_PIXELS)),',
                      '.write_len         (diag_write_len),')
top=replace_once(top,'.write_first_offset(fullportrait_mode ? 21\'d332800 : (portrait_load_mode ? portrait_first_offset : 21\'d920320)),',
                      '.write_first_offset(diag_offset),')
top=replace_once(top,'.write_line_width  (fullportrait_mode ? 16\'d320 : (portrait_load_mode ? 16\'d80 : 16\'d1280)),',
                      '.write_line_width  (diag_width),')
top=replace_once(top,'.write_line_jump   (fullportrait_mode ? 21\'d2097151 : (portrait_load_mode ? 21\'d2096975 : 21\'d2559)),',
                      '.write_line_jump   (diag_jump),')
top=replace_once(top,'.write_data        (sd_card_write_data)\n);',
                      '.write_data        (sd_card_write_data),\n    .write_fifo_full   (diag_fifo_full)\n);')
(hdl/'top_fat32_bg_diag.v').write_text(top,encoding='utf-8')
detail=top
detail=replace_once(detail, 'seg_decoder seg_decoder_m5(.bin_data(debug_found_count)',
                    'seg_decoder seg_decoder_m5(.bin_data(diag_bpb_error)')
detail=replace_once(detail, 'seg_decoder seg_decoder_m4(.bin_data(debug_display_index)',
                    "seg_decoder seg_decoder_m4(.bin_data({3'b000,diag_bpb_offset[8]})")
detail=replace_once(detail, 'seg_decoder seg_decoder_m3(.bin_data(debug_requested_index)',
                    'seg_decoder seg_decoder_m3(.bin_data(diag_bpb_offset[7:4])')
detail=replace_once(detail, "seg_decoder seg_decoder_m2(.bin_data({3'b000, debug_load_busy})",
                    'seg_decoder seg_decoder_m2(.bin_data(diag_bpb_offset[3:0])')
detail=replace_once(detail, "seg_decoder seg_decoder_m1(.bin_data({2'b00, diag_fifo_full_seen, diag_fifo_empty_seen})",
                    'seg_decoder seg_decoder_m1(.bin_data(diag_boot_error)')
(hdl/'top_fat32_bpb_detail.v').write_text(detail,encoding='utf-8')
print('Prepared isolated BG001 diagnostic sources')
