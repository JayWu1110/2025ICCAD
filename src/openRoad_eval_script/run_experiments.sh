#!/usr/bin/env bash
# Launch clean OpenROAD processes for each strategy; build comparison CSV.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="${SCRIPT_DIR}/results"
mkdir -p "${OUT_DIR}"

if ! command -v openroad >/dev/null 2>&1; then
  echo "ERROR: openroad not found in PATH" >&2
  echo "Tip: run inside OpenROAD container, or:" >&2
  echo "  cd ../openroad_docker && ./run.sh strengthen" >&2
  exit 1
fi

run_one () {
  local name="$1"
  echo "======== Running strategy: ${name} ========"
  export PROBC_FORCE_STRATEGY="${name}"
  openroad -exit "${SCRIPT_DIR}/optimize_adaptive.tcl" \
    2>&1 | tee "${OUT_DIR}/${name}_log.txt"
}

run_hybrid () {
  echo "======== Running strategy: hybrid ========"
  openroad -exit "${SCRIPT_DIR}/optimize_hybrid.tcl" \
    2>&1 | tee "${OUT_DIR}/hybrid_log.txt"
}

run_polish () {
  local def="${1:-aes_cipher_top_full_buffer.def}"
  local tag="${2:-polish}"
  echo "======== Polishing DEF: ${def} -> ${tag} ========"
  export PROBC_DEF="${def}"
  export PROBC_POLISH_TAG="${tag}"
  openroad -exit "${SCRIPT_DIR}/optimize_polish.tcl" \
    2>&1 | tee "${OUT_DIR}/${tag}_log.txt"
}

eval_def () {
  local def="$1"
  local name="$2"
  echo "======== Evaluating DEF: ${def} (${name}) ========"
  export PROBC_DEF="${def}"
  openroad -exit "${SCRIPT_DIR}/eval_result.tcl" \
    2>&1 | tee "${OUT_DIR}/${name}_eval_log.txt"
}

STRATEGIES=(size_only full_buffer timing_first adaptive)
MODE="${1:-help}"

case "$MODE" in
  --all|all)
    for s in "${STRATEGIES[@]}"; do
      run_one "$s"
    done
    run_hybrid
    ;;
  --hybrid|hybrid)
    run_hybrid
    ;;
  --polish|polish)
    # Usage: run_experiments.sh --polish [def] [tag]
    run_polish "${2:-aes_cipher_top_full_buffer.def}" "${3:-polish}"
    ;;
  --polish-best)
    run_polish aes_cipher_top_full_buffer.def full_buffer_polish
    run_polish aes_cipher_top_size_only.def size_only_polish
    ;;
  --strengthen)
    run_hybrid
    run_polish aes_cipher_top_full_buffer.def full_buffer_polish
    run_polish aes_cipher_top_size_only.def size_only_polish
    if [[ -f "${OUT_DIR}/aes_cipher_top_hybrid.def" ]]; then
      run_polish aes_cipher_top_hybrid.def hybrid_polish
    fi
    ;;
  --adaptive|adaptive)
    run_one adaptive
    ;;
  --eval)
    DEF_PATH="${2:-${OUT_DIR}/aes_cipher_top_timing_first.def}"
    eval_def "${DEF_PATH}" "eval_$(basename "${DEF_PATH}" .def)"
    ;;
  help|-h|--help)
    cat <<EOF
Usage: bash run_experiments.sh <mode>

  --all              base strategies + hybrid
  --hybrid           optimize_hybrid.tcl only
  --polish [def] [tag]
  --polish-best      polish full_buffer + size_only
  --strengthen       hybrid + polish winners (recommended)
  --eval <def>       evaluate a DEF
  <strategy>         size_only|full_buffer|timing_first|adaptive
EOF
    exit 0
    ;;
  *)
    run_one "$MODE"
    ;;
esac

echo "======== Building comparison CSV ========"
python3 "${SCRIPT_DIR}/../python/compare_results.py" \
  --results-dir "${OUT_DIR}" \
  --ref-def "${SCRIPT_DIR}/../aes_cipher_top/aes_cipher_top.def"

echo "======== Done. See ${OUT_DIR}/comparison.csv ========"
