基于安路 FPGA 的交互式功勋人物数字展屏
全部代码与配套素材 / 最终固化版

一、打开哪个工程
  FPGA 器件：HX4S20C V1.0，EG4S20BG256。
  开发工具：Anlogic Tang Dynasty 6.2.168116（TD 6.2.1 工程版）。
  TD 工程：fpga/run/medal_kiosk_720p.prj；顶层模块名：top。
  顶层文件：fpga/source/hdl_source/top_title_waveform_candidate.v。
  文件名中的 candidate / test 等沿用开发时命名；哪些文件实际参与最终构建，
  以该 .prj 的 89 项输入和 fpga/build.tcl 为准，不要按文件名另选旧顶层。

二、文件结构
  fpga/source/             最终 RTL、ADC/SDC 约束、生成 IP、字库和语音 HEX。
  fpga/rtl/                开场视频解码、预加载、缓存与会话控制。
  fpga/user_source/        最终快照保留的补充输入。
  fpga/run/                可移植 TD 工程及 3 个 ROM 初始化 HEX。
  fpga/prebuilt/           已在实物 Flash 固化、验收的 medal_final.bit。
  fpga/reference_reports/  同一冻结工程的资源与时序报告。
  fpga/tests/              真实控件/像素/音频流水 testbench、脚本和原始结果。
  tf_card/                 371 个最终配套文件，直接用于 TF 卡根目录。
  tf_manifest.json         371 个文件的名称、长度、SHA-256。
  offline_reference/       素材与语音转换、字幕生成、视频编码的开发源代码及数据。
  deploy/                  SRAM 下载、U39 配置 Flash 写入与校验 Tcl。
  build.py                 本包的可移植构建入口，不执行下载或 Flash 写入。
  verify_package.py        本包 SHA-256 与工程依赖检查，不访问板卡。
  release.json             最终版本、位流哈希、固化状态和路径整理记录。
  MANIFEST.sha256          全包文件校验清单。

三、完整功能
  1. 上电自动播放 640×360、15 帧/秒、5 秒开场，放大输出 1280×720；
     含原声、16 根实时频谱细柱、末帧停留及淡出淡入首页。
  2. 首页 13 人独立 TF 头像、姓名、高亮导航；人物页四栏目。
  3. 生平、主要贡献、代表事迹；中文标题先显、正文随中文讲解推进；
     中文主要贡献采用自右向左竖排。英文按完整条目增加/退回。
  4. 三选项互动问答；自动轮播跳过问答；背景音乐循环与讲解压低混音。
  5. 人物页长按 KEY1 平移放大/缩回，背景保留颜色并变暗。
  6. SW4 音量和亮度均为 0～100、步长 10，细圆角连续柱与数值叠加。
  7. SW2 中英文显示切换；讲解保留中文。

四、按键与开关
  常规：KEY1 下一项/下一条，KEY2 上一项/上一条，KEY3 返回，KEY4 确认。
  首页：KEY3 重播开场。
  人物主页：长按 KEY1 放大/缩回头像；短按保持常规导航。
  SW2：切换中文/英文文字。
  SW3：自动轮播；轮播中按任一 KEY 提示关闭 SW3，关闭后返回首页。
  SW4：打开音量/亮度弹窗；KEY3/KEY4 循环选项，KEY1/KEY2 增减 10。
  关闭 SW4 后恢复导航并保留本次会话数值；重新上电恢复默认值 100。
  最终工程未使用 SW1 作为额外功能入口。

五、复现步骤
  1. 将整个包解压到本地短路径，例如 D:/FPGA_Medal_Final_Source_20261104。
     保持 fpga/source、rtl 与 run 等目录相对关系。
  2. 安装对应 TD 工程版及官方 USB-JTAG 驱动。
  3. 可先用 Python 3.10 或以上运行：python verify_package.py
  4. 检查工程展开：python build.py --check-only --td "C:/Anlogic/.../bin/td_commands_prompt.exe"
  5. 完整编译：python build.py --td "C:/Anlogic/.../bin/td_commands_prompt.exe"
     也可先设置 TD_HOME 为 TD 安装目录。默认会探测原开发工具安装位置。
     展开输出 fpga/check_run；完整编译输出 fpga/build_run；不会覆盖已验收位流。
     构建参数沿用最终工程：顶层 top、high pack、place seed 9。
     使用约束 pin_bilingual.adc 和 timing.sdc；不要误用较早的 pin.adc。
     不同 TD/操作系统/布局结果可能产生不同哈希，应复核新输出报告和实机效果。
  6. 已提供验收位流，直接复现时不需要重新编译；其 SHA-256 为：
     e97e2a9e39c9b46f131ff39e659e2ffbd45151c6606b8c1ebaab938e1bb2e945

六、TF 卡与固化
  使用 FAT32 TF 卡；将 tf_card/ 内的 371 个文件放在卡的根目录。
  拷贝前保留原卡备份；拷贝后按 tf_manifest.json 核对，再安全弹出。
  本包不含任何自动格式化、磁盘修复或无提示写盘程序。
  未格式化的 RAW 卡、错误目录层级或旧版字幕素材不能用于最终展示。
  视频为 OP64015.Q3V，开场原声为 OPENING.PCM，背景音乐为 BGM.PCM。
  Q3V 为电脑离线转换后的块编码数据，FPGA 实现对应解码；不宣称直接播放 H.264 MP4。
  PCM 为无文件头的有符号 16-bit little-endian、单声道、16000 Hz。
  实际素材以本包成品与哈希为准，历史转换脚本重新 TTS 可能改变音长和同步时序。

  连接 USB-JTAG、HDMI B、显示器/耳机，先关闭 SW3 和 SW4。
  临时 SRAM 下载可在 TD BitWriter 中选 PROGRAM_SRAM 加载 medal_final.bit。
  永久固化使用 U39 W25Q16（16Mbit）配置 Flash，program_spi 后 verify_spi。
  deploy/ 三个脚本均需手动选择执行；不会在编译或校验包时自动运行。
  固化成功后，TF 卡插好再完全断电重启，无需电脑、无需按键自动播放开场。
  用户数据 Flash U33 与配置 Flash U39 不同，勿混用。

七、仿真及依赖
  额外安装 Icarus Verilog、Python Pillow（预览）、NumPy（离线转换）即可审阅测试。
  如 Icarus 不在 PATH，设置 IVERILOG_BIN 为其 bin 目录，再执行：
    python fpga/tests/check_settings_percent.py
  该测试包含独立参考检查、连续/稀疏音频样本与实际两拍像素流水比较。
  原有结果包含 3,807,973 项流水断言、950,432 像素和 6,239 有效音频采样比较；
  这些是针对性模块仿真，不是全系统或所有工作条件的覆盖证明。
  加密厂商 IP 需要 TD 对应设备库；不可用纯 Icarus 代替完整厂商实现。
  offline_reference 下为开发期间的转换实现，部分保留了当时的绝对路径和旧素材断言，
  用于审阅算法及修改来源；最终重建硬件只运行包根 build.py。

八、版本与已知工程边界
  对应已验收固化版 final_flash_settings_percent_20261103（2026-11-03）。
  已通过上电自启动、开场重播/原声/转场/频谱、导航、语音字幕、双语、
  自动轮播、问答、头像缩放及百分比控件的实机验收。
  资源报告：LUT 17877/19600，寄存器 9406，BRAM9K 46/64，BRAM32K 14/16，
  DSP 9，PLL 2；以随包 report 为依据。
  当前静态时序仍有负裕量：全局 setup −6.692ns、hold −1.540ns，
  视频时钟域 setup −5.385ns。实机功能验收不等同于全工程时序收敛。
  本次整理仅修改提交副本的工程/include/工具路径，没有改变功能 RTL。
  原始固化工程、TF 卡及开发板均未在打包期间改写。

九、第三方与提交
  参见 docs/THIRD_PARTY.txt：保留厂商 IP 标识、加密与生成文件；自行设计模块
  与开发板参考接口/厂商模块需按实际来源说明，不将第三方 IP 声称为原创。
  上传“全部代码”时选择本次生成的 .rar 文件，无需把 TD 安装目录放入代码包。
  此文件包仅为本地交付，未自动上传比赛网站。
