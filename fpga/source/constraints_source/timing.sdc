
# ============================================================
# merged_top_tf_hdmi_audio.sdc
# 用于：TF 图片轮播 + HDMI(视频+音频) 整合工程
#
# 合并原则：
# 1) 为当前孤立 720p 测试顶层定义 50 MHz 板级时钟
# 2) 由 PLL 自动推导 75 MHz 像素时钟和 375 MHz HDMI 串行时钟
# ============================================================

# ------------------------------------------------------------
# 1. 板级输入主时钟
#    你的原 top.sdc 里 clk=50MHz，所以这里仍然用 20ns
# ------------------------------------------------------------
create_clock -name clk -period 20 -waveform {0 10} [get_ports {clk}]

# ------------------------------------------------------------
# 2. 自动推导 PLL 输出时钟
# ------------------------------------------------------------
derive_clocks

# ------------------------------------------------------------
# 3. 给当前测试顶层的 HDMI PLL 输出命名
#    顶层没有系统/SDRAM PLL，因此不要保留旧 medal 项目的 sys_pll 路径。
# ------------------------------------------------------------
rename_clock -name {video_clk}   -source [get_ports {clk}] -master_clock {clk} [get_pins {video_pll_m0/pll_inst.clkc[0]}]
rename_clock -name {hdmi_5x_clk} -source [get_ports {clk}] -master_clock {clk} [get_pins {video_pll_m0/pll_inst.clkc[1]}]

# reset_all only crosses from the 50 MHz control clock as an asynchronous
# assertion; deassertion is synchronized independently in the pixel and serial
# domains. The clock-test top has no synchronous data paths from clk into
# either generated HDMI domain, so exclude only these two reset crossings.
set_false_path -from [get_clocks {clk}] -to [get_clocks {video_clk}]
set_false_path -from [get_clocks {clk}] -to [get_clocks {hdmi_5x_clk}]


# ------------------------------------------------------------
# 4. video_clk and hdmi_5x_clk are related outputs of the same PLL.
#    Keep their generated-clock relationship timed; do not mark them exclusive.
# ------------------------------------------------------------
# The falling-edge toggle sampler leaves the subsequent load pipeline on the
# original rising edges. Parallel TMDS data is therefore loaded on serial
# edge 5 (11.330 ns), with the next pixel update at 13.333 ns. Scope this
# exception through only the parallel data nets so toggle/reset paths remain
# subject to their normal edge-to-edge timing checks.
set_multicycle_path 5 -setup -end -from [get_clocks {video_clk}] -through [get_nets {u_hdmi_phy/*/I_data_in*}] -to [get_clocks {hdmi_5x_clk}]
set_multicycle_path 4 -hold -end -from [get_clocks {video_clk}] -through [get_nets {u_hdmi_phy/*/I_data_in*}] -to [get_clocks {hdmi_5x_clk}]

# ------------------------------------------------------------
# 5. 可选：如果你的 frame_read_write 内部异步 FIFO 已经完全处理好了跨域，
#    且报告里总出现 video_clk / sd_card_clk / ext_mem_clk 之间的大量伪违例，
#    可以打开下面这组异步分组。
#
#    建议先不要开，先看报告；
#    只有确认这些跨域都只经过 FIFO / 同步器时再开。
# ------------------------------------------------------------
# set_clock_groups -asynchronous \
#     -group [get_clocks {sd_card_clk}] \
#     -group [get_clocks {ext_mem_clk}] \
#     -group [get_clocks {video_clk}] \
#     -group [get_clocks {hdmi_5x_clk}]

# ------------------------------------------------------------
# 7. 其余 Input/Output delay 先保持空白
#    你当前两个原始 sdc 也都没有写这部分。
# ------------------------------------------------------------
