###############################################################################
# Size-only legal flow (skip buffering) — lower HPWL / displacement.
###############################################################################
set ::env(PROBC_FORCE_STRATEGY) size_only
source [file join [file dirname [file normalize [info script]]] optimize_adaptive.tcl]
