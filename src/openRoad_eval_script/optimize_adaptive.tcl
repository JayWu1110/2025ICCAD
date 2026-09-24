###############################################################################
# Adaptive multi-objective incremental optimization for ICCAD 2025 Problem C.
#
# Env:
#   PROBC_FORCE_STRATEGY = adaptive | full_buffer | size_only | timing_first
#   PROBC_SKIP_POWER_RECOVERY = 1
###############################################################################

source [file join [file dirname [file normalize [info script]]] common.tcl]

proc probc_parse_tns {} { return [probc_get_tns] }

proc probc_strategy_from_baseline {tns_val} {
    if {[info exists ::env(PROBC_FORCE_STRATEGY)] && $::env(PROBC_FORCE_STRATEGY) ne ""} {
        return $::env(PROBC_FORCE_STRATEGY)
    }
    if {$tns_val eq "" || ![string is double -strict $tns_val]} {
        return adaptive
    }
    set mag [expr {abs($tns_val)}]
    if {$mag > 50000} {
        return timing_first
    } elseif {$mag > 15000} {
        return adaptive
    } else {
        return size_only
    }
}

proc probc_run_strategy {strategy} {
    puts "############################################################"
    puts "# STRATEGY: $strategy"
    puts "############################################################"

    switch $strategy {
        timing_first {
            probc_legalize
            estimate_parasitics -placement
            probc_repair_setup
            probc_legalize
            probc_improve_wl
        }
        size_only {
            estimate_parasitics -placement
            probc_repair_setup -skip_buffering
            probc_legalize
            probc_improve_wl
        }
        full_buffer {
            estimate_parasitics -placement
            probc_repair_setup
            probc_legalize
            probc_improve_wl
        }
        adaptive -
        default {
            probc_legalize
            estimate_parasitics -placement
            puts "==== Pass 1: resize-focused setup repair ===="
            probc_repair_setup -skip_buffering
            probc_legalize
            estimate_parasitics -placement

            set tns_now [probc_parse_tns]
            set need_buffer 1
            if {$tns_now ne "" && [string is double -strict $tns_now]} {
                if {[expr {abs($tns_now)}] < 8000} {
                    set need_buffer 0
                    puts "==== TNS magnitude < 8000; skip buffering to protect HPWL ===="
                }
            }
            if {$need_buffer} {
                puts "==== Pass 2: limited buffering + resize ===="
                if {[catch {probc_repair_setup -max_buffer_percent 20}]} {
                    probc_repair_setup
                }
                probc_legalize
            }
            probc_improve_wl
        }
    }

    if {![info exists ::env(PROBC_SKIP_POWER_RECOVERY)] || $::env(PROBC_SKIP_POWER_RECOVERY) eq "0"} {
        estimate_parasitics -placement
        probc_recover_power 15
        probc_legalize
    }
}

# ---------------- main ----------------
set t_start [clock milliseconds]

probc_load_design
probc_snapshot_positions

set strategy_guess "adaptive"
if {[info exists ::env(PROBC_FORCE_STRATEGY)] && $::env(PROBC_FORCE_STRATEGY) ne ""} {
    set strategy_guess $::env(PROBC_FORCE_STRATEGY)
}

set pair [probc_open_metrics $strategy_guess]
set fd [lindex $pair 0]
set mpath [lindex $pair 1]

puts "==== BASELINE ===="
set base_m [probc_report_ppa baseline $fd]
set tns0 [probc_parse_tns]
puts "Parsed baseline TNS: $tns0"

set strategy [probc_strategy_from_baseline $tns0]
puts $fd "selected_strategy: $strategy"
puts "Selected strategy: $strategy"

# If forced strategy renamed metrics file prefix already; keep writing same fd.
probc_run_strategy $strategy

puts "==== POST-OPT ===="
set post_m [probc_report_ppa post_opt $fd]

set t_end [clock milliseconds]
set runtime_s [expr {($t_end - $t_start) / 1000.0}]
set disp_um [probc_avg_displacement_um]

puts $fd "runtime_s: $runtime_s"
puts $fd "displacement_um: $disp_um"
puts "METRICS_RUNTIME_S $runtime_s"
puts "METRICS_DISP_UM $disp_um"

set out_def [probc_write_result $strategy]
puts $fd "output_def: $out_def"
close $fd

# Machine-readable summary for CSV builder
set summary [file join [probc_outdir] ${strategy}_summary.txt]
set kv [dict create \
    strategy $strategy \
    runtime_s $runtime_s \
    displacement_um $disp_um \
    output_def $out_def \
    baseline_tns [dict get $base_m tns] \
    baseline_wns [dict get $base_m wns] \
    post_tns [dict get $post_m tns] \
    post_wns [dict get $post_m wns] \
    post_power [dict get $post_m power] \
]
probc_write_kv_metrics $summary $kv

puts "============================================================"
puts "Done. Strategy=$strategy"
puts "Runtime_s=$runtime_s  AvgDisp_um=$disp_um"
puts "Metrics: $mpath"
puts "Summary: $summary"
puts "DEF:     $out_def"
puts "Next:    python3 ../python/compare_results.py --results-dir [probc_outdir]"
puts "============================================================"
