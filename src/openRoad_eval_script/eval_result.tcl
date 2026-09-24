###############################################################################
# Evaluate an existing DEF (optimized result or arbitrary path).
#
# Usage:
#   openroad -exit eval_result.tcl
#   PROBC_DEF=aes_cipher_top_timing_first.def openroad -exit eval_result.tcl
#   PROBC_DEF=/workspace/openRoad_eval_script/results/aes_cipher_top_adaptive.def \
#       openroad -exit eval_result.tcl
#
# Compares displacement against the original aes_cipher_top.def by loading
# the reference positions from the original DEF's companion snapshot when
# PROBC_REF_DEF is set (default: original contest DEF).
###############################################################################

source [file join [file dirname [file normalize [info script]]] common.tcl]

set def_arg ""
if {[info exists ::env(PROBC_DEF)]} {
    set def_arg $::env(PROBC_DEF)
}

# Optional: first load reference to snapshot, then load candidate.
# OpenROAD cannot easily swap DEFs in one session → snapshot from REF then
# re-read is not portable. Instead: if evaluating a result DEF, compute D by
# Python compare_results.py (Bookshelf/DEF parse). Here we still report PPA.

set t_start [clock milliseconds]

set tag "eval"
if {$def_arg ne ""} {
    set tag [file rootname [file tail $def_arg]]
    regsub -all {[^A-Za-z0-9_]+} $tag {_} tag
}

probc_load_design $def_arg

set pair [probc_open_metrics ${tag}]
set fd [lindex $pair 0]
set path [lindex $pair 1]

puts $fd "evaluated_def: $::probc::LOADED_DEF"
set m [probc_report_ppa eval $fd]
set runtime_s [expr {([clock milliseconds] - $t_start) / 1000.0}]
puts $fd "runtime_s: $runtime_s"
close $fd

set summary [file join [probc_outdir] ${tag}_summary.txt]
probc_write_kv_metrics $summary [dict create \
    strategy $tag \
    runtime_s $runtime_s \
    post_tns [dict get $m tns] \
    post_wns [dict get $m wns] \
    post_power [dict get $m power] \
    output_def $::probc::LOADED_DEF \
]

puts "============================================================"
puts "Evaluated: $::probc::LOADED_DEF"
puts "TNS=[dict get $m tns]  WNS=[dict get $m wns]"
puts "Metrics: $path"
puts "Summary: $summary"
puts "For displacement D vs original, run:"
puts "  python3 ../python/compare_results.py --results-dir [probc_outdir] --ref-def ../aes_cipher_top/aes_cipher_top.def"
puts "============================================================"
