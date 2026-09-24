###############################################################################
# Baseline evaluation of the original contest DEF (no optimization).
###############################################################################

source [file join [file dirname [file normalize [info script]]] common.tcl]

set t_start [clock milliseconds]
probc_load_design
probc_snapshot_positions

set pair [probc_open_metrics baseline]
set fd [lindex $pair 0]
set path [lindex $pair 1]

set m [probc_report_ppa baseline $fd]
set runtime_s [expr {([clock milliseconds] - $t_start) / 1000.0}]
puts $fd "runtime_s: $runtime_s"
puts $fd "displacement_um: 0"
close $fd

set summary [file join [probc_outdir] baseline_summary.txt]
probc_write_kv_metrics $summary [dict create \
    strategy baseline \
    runtime_s $runtime_s \
    displacement_um 0 \
    post_tns [dict get $m tns] \
    post_wns [dict get $m wns] \
    post_power [dict get $m power] \
    output_def $::probc::LOADED_DEF \
]

puts "Metrics written to $path"
puts "Summary: $summary"
