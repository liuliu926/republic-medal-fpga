# Run manually with Anlogic bw_commands_prompt.exe. Read/compare only.
set root [file normalize [file join [file dirname [info script]] ..]]
set bit [file join $root fpga prebuilt medal_final.bit]
if {![file exists $bit] || [file size $bit] != 715760} {puts stderr {Missing accepted bitstream};exit 1}
if {[catch {
    download -bit $bit -mode verify_spi -flashsize 16 -spd 7 -sec 64 -cable 0
} problem]} {puts stderr $problem;exit 1}
puts {ACCEPTED_FLASH_VERIFY_SUCCESS}
exit 0
