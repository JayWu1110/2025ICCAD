###############################################################################
# Hybrid strategy: size_only strengths + limited buffering + polish.
# Goal: TNS near size_only, HPWL/D/runtime nearer full_buffer.
#
# Usage:
#   openroad -exit optimize_hybrid.tcl
#   PROBC_BUFFER_PERCENT=10 PROBC_RECOVER_POWER=12 openroad -exit optimize_hybrid.tcl
###############################################################################

source [file join [file dirname [file normalize [info script]]] common.tcl]

set buffer_pct 10
if {[info exists ::env(PROBC_BUFFER_PERCENT)] && $::env(PROBC_BUFFER_PERCENT) ne ""} {
    set buffer_pct $::env(PROBC_BUFFER_PERCENT)
}
set recover_pct 12
if {[info exists ::env(PROBC_RECOVER_POWER)] && $::env(PROBC_RECOVER_POWER) ne ""} {
    set recover_pct $::env(PROBC_RECOVER_POWER)
}
# Only buffer if |TNS| still above this after resize pass.
set tns_buffer_thresh 14000
if {[info exists ::env(PROBC_TNS_BUFFER_THRESH)] && $::env(PROBC_TNS_BUFFER_THRESH) ne ""} {
    set tns_buffer_thresh $::env(PROBC_TNS_BUFFER_THRESH)
}

set tag hybrid
set t_start [clock milliseconds]

probc_load_design
probc_snapshot_positions

set pair [probc_open_metrics $tag]
set fd [lindex $pair 0]
set mpath [lindex $pair 1]

puts "==== BASELINE ===="
set base_m [probc_report_ppa baseline $fd]
puts $fd "selected_strategy: hybrid"
puts $fd "buffer_percent: $buffer_pct"
puts $fd "recover_power: $recover_pct"
puts $fd "tns_buffer_thresh: $tns_buffer_thresh"

puts "############################################################"
puts "# HYBRID Pass 1: resize-only (skip buffering)"
puts "############################################################"
estimate_parasitics -placement
probc_repair_setup -skip_buffering
probc_legalize
estimate_parasitics -placement

set tns_mid [probc_get_tns]
puts "After resize-only TNS: $tns_mid"

set do_buffer 0
if {$tns_mid ne "" && [string is double -strict $tns_mid]} {
    if {[expr {abs($tns_mid)}] > $tns_buffer_thresh} {
        set do_buffer 1
    }
} else {
    set do_buffer 1
}

if {$do_buffer} {
    puts "############################################################"
    puts "# HYBRID Pass 2: limited buffering (max_buffer_percent $buffer_pct)"
    puts "############################################################"
    if {[catch {probc_repair_setup -max_buffer_percent $buffer_pct}]} {
        puts "WARN -max_buffer_percent unsupported; falling back to full repair_setup"
        probc_repair_setup
    }
    probc_legalize
} else {
    puts "==== |TNS| <= $tns_buffer_thresh; skip buffering to protect HPWL/D ===="
}

puts "############################################################"
puts "# HYBRID Pass 3: improve_placement + power recovery"
puts "############################################################"
probc_improve_wl
estimate_parasitics -placement
probc_recover_power $recover_pct
probc_legalize
probc_improve_wl

puts "==== POST-OPT ===="
set post_m [probc_report_ppa post_opt $fd]

set runtime_s [expr {([clock milliseconds] - $t_start) / 1000.0}]
set disp_um [probc_avg_displacement_um]
puts $fd "runtime_s: $runtime_s"
puts $fd "displacement_um: $disp_um"
puts "METRICS_RUNTIME_S $runtime_s"
puts "METRICS_DISP_UM $disp_um"

set out_def [probc_write_result $tag]
puts $fd "output_def: $out_def"
close $fd

set summary [file join [probc_outdir] ${tag}_summary.txt]
probc_write_kv_metrics $summary [dict create \
    strategy $tag \
    runtime_s $runtime_s \
    displacement_um $disp_um \
    output_def $out_def \
    baseline_tns [dict get $base_m tns] \
    baseline_wns [dict get $base_m wns] \
    mid_tns $tns_mid \
    buffered $do_buffer \
    buffer_percent $buffer_pct \
    post_tns [dict get $post_m tns] \
    post_wns [dict get $post_m wns] \
    post_power [dict get $post_m power] \
]

puts "============================================================"
puts "Done. Strategy=hybrid buffered=$do_buffer"
puts "Runtime_s=$runtime_s  AvgDisp_um=$disp_um"
puts "Metrics: $mpath"
puts "Summary: $summary"
puts "DEF:     $out_def"
puts "Next:    python3 ../python/compare_results.py --results-dir [probc_outdir]"
puts "============================================================"
