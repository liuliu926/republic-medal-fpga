"""Prepare a subtitle-cache candidate using EG4 dedicated 32K BRAMs."""
from pathlib import Path

root = Path(__file__).resolve().parents[1]
hdl = root / "fpga/user_source_720p/hdl_source"
src = (hdl / "home_text_mask_voice_autoplay.v").read_text(encoding="utf-8")
start = src.index("    // 30 explicit 8K banks")
end = src.index("    reg [17:0] write_addr;", start)
block = """    // Candidate: 16 subtitle bits per word in the device's dedicated 32K BRAM.
    // The TF bitmap and on-screen pixel mapping are unchanged.
    wire [17:0] addr;
    reg inside_r;
    reg [2:0] read_bank;
    reg [3:0] read_bit;
    wire [15:0] word_q [0:7];
    reg [14:0] pack_word;
    wire [15:0] write_word = {pixel_data[23], pack_word};
    reg [17:0] write_addr;
    reg ready;
    always @(posedge write_clk) begin
        if (pixel_valid && !ready && write_addr[3:0] != 4'd15)
            pack_word[write_addr[3:0]] <= pixel_data[23];
    end
    genvar b;
    generate for (b=0; b<8; b=b+1) begin: g_mask_bank
        wire we = pixel_valid && !ready && write_addr[3:0] == 4'd15 &&
                  write_addr[17:15] == b;
        EG_PHY_BRAM32K #(
            .MODE("DP16K"), .DATA_WIDTH_A("16"), .DATA_WIDTH_B("16"),
            .REGMODE_A("NOREG"), .REGMODE_B("NOREG")
        ) bits (
            .doa(), .dia(write_word), .addra(write_addr[14:4]),
            .bytea(1'b0), .bytewea(1'b0), .csa(we), .wea(we),
            .clka(write_clk), .rsta(1'b0), .ocea(1'b1),
            .dob(word_q[b]), .dib(16'd0), .addrb(addr[14:4]),
            .byteb(1'b0), .byteweb(1'b0), .csb(inside_r), .web(1'b0),
            .clkb(video_clk), .rstb(1'b0), .oceb(1'b1)
        );
    end endgenerate
"""
src = src[:start] + block + src[end:]
src = src.replace("    reg [17:0] write_addr;\n    reg ready;\n    always @(posedge write_clk or posedge write_rst)",
                  "    always @(posedge write_clk or posedge write_rst)", 1)
assert src.count("if (inside_r) read_bank <= addr[17:13];") == 1
src = src.replace("if (inside_r) read_bank <= addr[17:13];",
                  "if (inside_r) begin read_bank <= addr[17:15]; read_bit <= addr[3:0]; end")
assert src.count("wire mask_q = read_bank < 30 ? bank_q[read_bank] : 1'b0;") == 1
src = src.replace("wire mask_q = read_bank < 30 ? bank_q[read_bank] : 1'b0;",
                  "wire mask_q = word_q[read_bank][read_bit];")
assert src.count("    reg inside_r;\n    wire [8:0] bottom_row") == 1
src = src.replace("    reg inside_r;\n    wire [8:0] bottom_row", "    wire [8:0] bottom_row")
(hdl / "home_text_mask_voice_bram32_ip_candidate.v").write_text(src, encoding="utf-8")
print("Prepared dedicated 32K BRAM candidate")
