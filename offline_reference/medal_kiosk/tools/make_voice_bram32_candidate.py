"""Prepare an isolated 32K-bank subtitle-memory experiment."""
from pathlib import Path

root = Path(__file__).resolve().parents[1]
hdl = root / "fpga/user_source_720p/hdl_source"
src = (hdl / "home_text_mask_voice_autoplay.v").read_text(encoding="utf-8")
old = """    // 30 explicit 8K banks avoid allocating two unused banks in a 2^18 RAM.
    wire [29:0] bank_q;
    wire [17:0] addr;
    reg [4:0] read_bank;
    genvar b;
    generate for (b=0; b<30; b=b+1) begin: g_mask_bank
        reg bits [0:8191];
        reg q;
        always @(posedge write_clk)
            if (pixel_valid && !ready && write_addr[17:13] == b)
                bits[write_addr[12:0]] <= pixel_data[23];
        always @(posedge video_clk) if (inside_r) q <= bits[addr[12:0]];
        assign bank_q[b] = q;
    end endgenerate"""
new = """    // Experiment: map the same 245760 subtitle bits into eight 32K banks.
    // Keep independent read/write clocks and identical pixel addresses.
    wire [7:0] bank_q;
    wire [17:0] addr;
    reg [2:0] read_bank;
    genvar b;
    generate for (b=0; b<8; b=b+1) begin: g_mask_bank
        reg bits [0:32767];
        reg q;
        always @(posedge write_clk)
            if (pixel_valid && !ready && write_addr[17:15] == b)
                bits[write_addr[14:0]] <= pixel_data[23];
        always @(posedge video_clk) if (inside_r) q <= bits[addr[14:0]];
        assign bank_q[b] = q;
    end endgenerate"""
assert src.count(old) == 1
src = src.replace(old, new)
assert src.count("if (inside_r) read_bank <= addr[17:13];") == 1
src = src.replace("if (inside_r) read_bank <= addr[17:13];", "if (inside_r) read_bank <= addr[17:15];")
assert src.count("read_bank < 30 ? bank_q[read_bank] : 1'b0") == 1
src = src.replace("read_bank < 30 ? bank_q[read_bank] : 1'b0", "bank_q[read_bank]")
(hdl / "home_text_mask_voice_bram32_candidate.v").write_text(src, encoding="utf-8")
print("Prepared isolated 32K-bank subtitle candidate")
