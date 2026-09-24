###############################################################################
# Shared helpers for ICCAD 2025 Problem C OpenROAD flows.
###############################################################################

if {![info exists ::probc::SCRIPT_DIR]} {
    namespace eval ::probc {}
    set ::probc::SCRIPT_DIR [file dirname [file normalize [info script]]]
}

proc probc_script_dir {} { return $::probc::SCRIPT_DIR }

proc probc_workspace_root {} {
    return [file normalize [file join [probc_script_dir] ..]]
}

proc probc_outdir {} {
    set d [file join [probc_script_dir] results]
    file mkdir $d
    return $d
}

proc probc_design_dir {} {
    return [file join [probc_workspace_root] aes_cipher_top]
}

# Resolve DEF: absolute path, results/ name, or aes_cipher_top/ name.
proc probc_resolve_def {def_arg} {
    if {$def_arg eq ""} {
        return [file join [probc_design_dir] aes_cipher_top.def]
    }
    if {[file exists $def_arg]} {
        return [file normalize $def_arg]
    }
    set cand [file join [probc_outdir] $def_arg]
    if {[file exists $cand]} { return [file normalize $cand] }
    set cand2 [file join [probc_design_dir] $def_arg]
    if {[file exists $cand2]} { return [file normalize $cand2] }
    error "DEF not found: $def_arg"
}

proc probc_load_libs_lef {} {
    set root [probc_workspace_root]
    set lib_dir [file join $root ASAP7 LIB]
    set lef_dir [file join $root ASAP7 LEF]
    set techlef [file join $root ASAP7 techlef asap7_tech_1x_201209.lef]

    puts "==== Loading Liberty ===="
    foreach libFile [lsort [glob -nocomplain [file join $lib_dir *nldm*.lib]]] {
        puts "  lib: $libFile"
        read_liberty $libFile
    }
    puts "==== Loading LEF ===="
    read_lef $techlef
    foreach lef [lsort [glob -nocomplain [file join $lef_dir *.lef]]] {
        puts "  lef: $lef"
        read_lef $lef
    }
}

# Load design. def_arg may be path or filename.
proc probc_load_design {{def_arg ""}} {
    set def_path [probc_resolve_def $def_arg]
    set sdc_path [file join [probc_design_dir] aes_cipher_top.sdc]
    set rc_tcl [file join [probc_workspace_root] ASAP7 setRC.tcl]

    probc_load_libs_lef
    puts "==== Loading DEF: $def_path ===="
    read_def $def_path
    read_sdc $sdc_path
    source $rc_tcl
    set ::probc::LOADED_DEF $def_path
}

# Snapshot movable instance lower-left (DBU) for displacement vs later state.
proc probc_snapshot_positions {} {
    set d [dict create]
    if {[catch {
        set block [[ord::get_db_chip] getBlock]
        foreach inst [$block getInsts] {
            set status [$inst getPlacementStatus]
            # Skip fixed / cover / locked if API available; still record all placed.
            set bbox [$inst getBBox]
            dict set d [$inst getName] [list [$bbox xMin] [$bbox yMin]]
        }
    } err]} {
        puts "WARN snapshot_positions failed: $err"
    }
    set ::probc::XY_REF $d
    puts "==== Snapshotted [dict size $d] instance positions ===="
    return $d
}

# Average Manhattan displacement in microns (ASAP7 DEF UNITS MICRONS 1000).
proc probc_avg_displacement_um {{dbu_per_um 1000.0}} {
    if {![info exists ::probc::XY_REF] || [dict size $::probc::XY_REF] == 0} {
        return ""
    }
    set total 0.0
    set n 0
    if {[catch {
        set block [[ord::get_db_chip] getBlock]
        foreach inst [$block getInsts] {
            set name [$inst getName]
            if {![dict exists $::probc::XY_REF $name]} { continue }
            set ref [dict get $::probc::XY_REF $name]
            set bbox [$inst getBBox]
            set dx [expr {abs([$bbox xMin] - [lindex $ref 0])}]
            set dy [expr {abs([$bbox yMin] - [lindex $ref 1])}]
            set total [expr {$total + $dx + $dy}]
            incr n
        }
    } err]} {
        puts "WARN displacement calc failed: $err"
        return ""
    }
    if {$n == 0} { return 0.0 }
    return [expr {($total / double($n)) / $dbu_per_um}]
}

proc probc_get_tns {} {
    set s ""
    if {![catch {set s [sta::total_negative_slack -max]}]} { return $s }
    return ""
}

proc probc_get_wns {} {
    set s ""
    if {![catch {set s [sta::worst_slack -max]}]} { return $s }
    return ""
}

# Best-effort total power (Watts). Empty if unavailable.
proc probc_get_power {} {
    set p ""
    if {[catch {set p [sta::design_power [sta::corners]]}]} {
        return ""
    }
    # OpenSTA returns a vector; 4th entry (index 3) is design total power.
    if {[llength $p] >= 4} {
        return [lindex $p 3]
    }
    return $p
}

proc probc_report_ppa {tag {metrics_fd ""}} {
    estimate_parasitics -placement

    puts "==== PPA REPORT (${tag}) ===="
    puts "-- TNS --"
    report_tns
    puts "-- WNS --"
    report_wns
    puts "-- Power --"
    report_power
    puts "-- Design area --"
    report_design_area
    puts "-- Placement legality --"
    if {[catch {check_placement -verbose} err]} {
        puts "WARN check_placement: $err"
    }

    if {[catch {report_wire_length -verbose} wl_err]} {
        puts "note: report_wire_length unavailable ($wl_err)"
    }

    set tns_val [probc_get_tns]
    set wns_val [probc_get_wns]
    set power_val [probc_get_power]
    set disp_val ""
    if {[info exists ::probc::XY_REF]} {
        set disp_val [probc_avg_displacement_um]
    }

    puts "METRICS_TAG ${tag}"
    puts "METRICS_TNS ${tns_val}"
    puts "METRICS_WNS ${wns_val}"
    puts "METRICS_POWER ${power_val}"
    puts "METRICS_DISP_UM ${disp_val}"

    if {$metrics_fd ne ""} {
        puts $metrics_fd "===== $tag ====="
        puts $metrics_fd "tns: $tns_val"
        puts $metrics_fd "wns: $wns_val"
        puts $metrics_fd "power: $power_val"
        puts $metrics_fd "displacement_um: $disp_val"
        flush $metrics_fd
    }

    return [dict create tns $tns_val wns $wns_val power $power_val displacement_um $disp_val]
}

proc probc_repair_setup {args} {
    set cmd [list repair_timing -setup \
        -skip_pin_swap \
        -skip_gate_cloning \
        -skip_buffer_removal \
        -verbose]
    foreach a $args { lappend cmd $a }
    puts "==== Running: $cmd ===="
    eval $cmd
}

proc probc_legalize {} {
    puts "==== detailed_placement (legalize) ===="
    detailed_placement
    if {[catch {check_placement -verbose} err]} {
        puts "WARN check_placement: $err"
    }
}

proc probc_improve_wl {} {
    puts "==== improve_placement (WL polish) ===="
    if {[catch {improve_placement} err]} {
        puts "WARN improve_placement unavailable: $err"
    }
}

proc probc_recover_power {{percent 20}} {
    puts "==== repair_timing -recover_power $percent ===="
    if {[catch {
        repair_timing -recover_power $percent \
            -skip_pin_swap -skip_gate_cloning -skip_buffer_removal -verbose
    } err]} {
        puts "WARN power recovery skipped: $err"
    }
}

proc probc_write_result {tag} {
    set outdir [probc_outdir]
    set def_out [file join $outdir aes_cipher_top_${tag}.def]
    set v_out   [file join $outdir aes_cipher_top_${tag}.v]
    puts "==== Writing $def_out ===="
    write_def $def_out
    if {[catch {write_verilog $v_out} err]} {
        puts "WARN write_verilog: $err"
    }
    return $def_out
}

proc probc_open_metrics {name} {
    set path [file join [probc_outdir] ${name}_metrics.txt]
    set fd [open $path w]
    puts $fd "ICCAD 2025 Problem C metrics log: $name"
    puts $fd "timestamp: [clock format [clock seconds]]"
    return [list $fd $path]
}

proc probc_write_kv_metrics {path kvdict} {
    set fd [open $path w]
    dict for {k v} $kvdict {
        puts $fd "$k: $v"
    }
    close $fd
}
