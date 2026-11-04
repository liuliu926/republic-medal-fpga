# Run manually with td_commands_prompt.exe. Temporary SRAM configuration only.
set root [file normalize [file join [file dirname [info script]] ..]]
set bit [file join $root fpga prebuilt medal_final.bit]
if {![file exists $bit] || [file size $bit] != 715760} {puts stderr {Missing accepted bitstream};exit 1}
if {[catch {
    import_device eagle_s20.db -package EG4S20BG256
    download -bit $bit -mode jtag -spd 7 -sec 64 -cable 0
} problem]} {puts stderr $problem;exit 1}
puts {ACCEPTED_SRAM_DOWNLOAD_SUCCESS}
exit 0
