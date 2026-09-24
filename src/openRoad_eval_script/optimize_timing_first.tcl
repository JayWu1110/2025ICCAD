###############################################################################
# Timing-first legal flow: DP -> buffer+resize -> DP -> improve.
###############################################################################
set ::env(PROBC_FORCE_STRATEGY) timing_first
source [file join [file dirname [file normalize [info script]]] optimize_adaptive.tcl]
