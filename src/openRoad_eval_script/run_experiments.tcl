###############################################################################
# Deprecated entrypoint — use run_experiments.sh instead.
# OpenROAD DB reset is unreliable across versions; shell launches clean procs.
###############################################################################
puts "Use: bash run_experiments.sh          # adaptive only"
puts " Or: bash run_experiments.sh --all    # size_only/full_buffer/timing_first/adaptive"
