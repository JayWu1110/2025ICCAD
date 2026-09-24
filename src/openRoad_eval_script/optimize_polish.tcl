###############################################################################
# Polish an existing optimized DEF (no heavy re-repair by default).
# Loads a seed DEF → improve_placement → optional light recover_power → legalize.
#
# Usage:
#   PROBC_DEF=aes_cipher_top_full_buffer.def openroad -exit optimize_polish.tcl
#   PROBC_DEF=aes_cipher_top_size_only.def PROBC_POLISH_TAG=size_only_polish \
#       openroad -exit optimize_polish.tcl
#
# Env:
#   PROBC_DEF              seed DEF (path or results/ filename)  [required]
#   PROBC_POLISH_TAG       output tag (default: polish)
#   PROBC_RECOVER_POWER    percent (default: 10; set 0 to skip)
#   PROBC_POLISH_REPAIR=1  also run a light resize-only repair before polish
###############################################################################

source [file join [file dirname [file normalize [info script]]] common.tcl]

if {![info exists ::env(PROBC_DEF)] || $::env(PROBC_DEF) eq ""} {
    puts "ERROR: set PROBC_DEF to the seed DEF (e.g. aes_cipher_top_full_buffer.def)"
    exit 1
}

set seed $::env(PROBC_DEF)
set tag polish
if {[info exists ::env(PROBC_POLISH_TAG)] && $::env(PROBC_POLISH_TAG) ne ""} {
    set tag $::env(PROBC_POLISH_TAG)
}
set recover_pct 10
if {[info exists ::env(PROBC_RECOVER_POWER)] && $::env(PROBC_RECOVER_POWER) ne ""} {
    set recover_pct $::env(PROBC_RECOVER_POWER)
}
set do_repair 0
if {[info exists ::env(PROBC_POLISH_REPAIR)] && $::env(PROBC_POLISH_REPAIR) eq "1"} {
    set do_repair 1
}

set t_start [clock milliseconds]

probc_load_design $seed
# Snapshot seed positions (polish-local D). CSV still computes contest D vs original DEF.
probc_snapshot_positions

set pair [probc_open_metrics $tag]
set fd [lindex $pair 0]
set mpath [lindex $pair 1]
puts $fd "seed_def: $::probc::LOADED_DEF"
puts $fd "selected_strategy: polish"
puts $fd "recover_power: $recover_pct"
puts $fd "polish_repair: $do_repair"

puts "==== PRE-POLISH (seed) ===="
set base_m [probc_report_ppa pre_polish $fd]

if {$do_repair} {
    puts "==== Light resize-only repair ===="
    estimate_parasitics -placement
    probc_repair_setup -skip_buffering
    probc_legalize
}

puts "==== improve_placement ===="
probc_improve_wl

if {$recover_pct > 0} {
    estimate_parasitics -placement
    probc_recover_power $recover_pct
    probc_legalize
    probc_improve_wl
}

puts "==== POST-POLISH ===="
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
    seed_def $::probc::LOADED_DEF \
    runtime_s $runtime_s \
    displacement_um $disp_um \
    output_def $out_def \
    pre_tns [dict get $base_m tns] \
    pre_wns [dict get $base_m wns] \
    post_tns [dict get $post_m tns] \
    post_wns [dict get $post_m wns] \
    post_power [dict get $post_m power] \
]

puts "============================================================"
puts "Done. Polish tag=$tag"
puts "Seed:    $::probc::LOADED_DEF"
puts "Runtime_s=$runtime_s  AvgDisp_um(vs seed)=$disp_um"
puts "Metrics: $mpath"
puts "Summary: $summary"
puts "DEF:     $out_def"
puts "Next:    python3 ../python/compare_results.py --results-dir [probc_outdir]"
puts "============================================================"
