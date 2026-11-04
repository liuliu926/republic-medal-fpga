/************************************************************\
 ** Copyright (c) 2012-2025 Anlogic Inc.
 ** 720p experimental PLL adapted from the vendor EG4S20 HDMI example.
 ** Input: 50 MHz; outputs: 75 MHz pixel and 375 MHz 5x serial (90 deg).
 ************************************************************/
`timescale 1 ns / 100 fs

module video_pll (
  refclk,
  reset,
  extlock,
  clk0_out,
  clk1_out
);

  input refclk;
  input reset;
  output extlock;
  output clk0_out;
  output clk1_out;

  wire clk0_buf;

  EG_LOGIC_BUFG bufg_feedback (
    .i(clk0_buf),
    .o(clk0_out)
  );

  EG_PHY_PLL #(
    .DPHASE_SOURCE("DISABLE"),
    .DYNCFG("DISABLE"),
    .FIN("50.000000"),
    .FEEDBK_MODE("NORMAL"),
    .FEEDBK_PATH("CLKC0_EXT"),
    .STDBY_ENABLE("DISABLE"),
    .PLLRST_ENA("ENABLE"),
    .SYNC_ENABLE("DISABLE"),
    .GMC_GAIN(2),
    .ICP_CURRENT(9),
    .KVCO(2),
    .LPF_CAPACITOR(1),
    .LPF_RESISTOR(8),
    .REFCLK_DIV(2),
    .FBCLK_DIV(3),
    .CLKC0_ENABLE("ENABLE"),
    .CLKC0_DIV(10),
    .CLKC0_CPHASE(9),
    .CLKC0_FPHASE(0),
    .CLKC1_ENABLE("ENABLE"),
    .CLKC1_DIV(2),
    .CLKC1_CPHASE(1),
    .CLKC1_FPHASE(4)
  ) pll_inst (
    .refclk(refclk),
    .reset(reset),
    .stdby(1'b0),
    .extlock(extlock),
    .load_reg(1'b0),
    .psclk(1'b0),
    .psdown(1'b0),
    .psstep(1'b0),
    .psclksel(3'b000),
    .psdone(video_pll_open0),
    .dclk(1'b0),
    .dcs(1'b0),
    .dwe(1'b0),
    .di(8'b00000000),
    .daddr(6'b000000),
    .do({video_pll_open8, video_pll_open7, video_pll_open6, video_pll_open5,
         video_pll_open4, video_pll_open3, video_pll_open2, video_pll_open1}),
    .fbclk(clk0_out),
    .clkc({video_pll_open10, video_pll_open9, video_pll_open11,
           clk1_out, clk0_buf})
  );

endmodule

