#!/usr/bin/env bash
# Helpers to build / enter the project-local OpenROAD Docker environment.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

IMAGE="${OPENROAD_IMAGE:-iccad2025-openroad:local}"
DEB_DEFAULT="openroad_2.0-17598-ga008522d8_amd64-ubuntu-22.04.deb"
DEB="${OPENROAD_DEB:-$DEB_DEFAULT}"

need_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    cat >&2 <<'EOF'
ERROR: docker not found in this WSL distro.

Fix (Windows + Docker Desktop):
  1. Install/start Docker Desktop
  2. Settings → Resources → WSL Integration → enable your distro
  3. Re-open this terminal, then: docker version
EOF
    exit 1
  fi
}

cmd="${1:-help}"
shift || true

case "$cmd" in
  build)
    need_docker
    if [[ ! -f "$DEB" ]]; then
      cat >&2 <<EOF
Missing OpenROAD package: $DIR/$DEB

Download from:
  https://github.com/Precision-Innovations/OpenROAD/releases

Then place it here as:
  $DIR/$DEB

Or: OPENROAD_DEB=your.deb $0 build
EOF
      exit 1
    fi
    echo "Building $IMAGE with $DEB ..."
    docker build \
      --build-arg "OPENROAD_DEB=$DEB" \
      -t "$IMAGE" \
      -f Dockerfile .
    echo "Done. Next: $0 shell"
    ;;

  shell|run)
    need_docker
    docker run --rm -it \
      -v "$DIR/..:/workspace" \
      -w /workspace \
      -e DISPLAY="${DISPLAY:-}" \
      -e QT_X11_NO_MITSHM=1 \
      "$IMAGE" \
      bash
    ;;

  optimize)
    need_docker
    docker run --rm \
      -v "$DIR/..:/workspace" \
      -w /workspace/openRoad_eval_script \
      "$IMAGE" \
      openroad -exit optimize_adaptive.tcl
    ;;

  hybrid)
    need_docker
    docker run --rm \
      -v "$DIR/..:/workspace" \
      -w /workspace/openRoad_eval_script \
      "$IMAGE" \
      bash -lc 'openroad -exit optimize_hybrid.tcl 2>&1 | tee results/hybrid_log.txt; python3 ../python/compare_results.py --results-dir results --ref-def ../aes_cipher_top/aes_cipher_top.def'
    ;;

  polish)
    # Usage: ./run.sh polish [def] [tag] [recover_percent]
    # recover_percent default 10; use 0 to skip power recovery
    need_docker
    def="${1:-aes_cipher_top_full_buffer.def}"
    tag="${2:-polish}"
    recover="${3:-10}"
    docker run --rm \
      -v "$DIR/..:/workspace" \
      -w /workspace/openRoad_eval_script \
      -e "PROBC_DEF=${def}" \
      -e "PROBC_POLISH_TAG=${tag}" \
      -e "PROBC_RECOVER_POWER=${recover}" \
      "$IMAGE" \
      bash -lc "openroad -exit optimize_polish.tcl 2>&1 | tee results/${tag}_log.txt; python3 ../python/compare_results.py --results-dir results --ref-def ../aes_cipher_top/aes_cipher_top.def"
    ;;

  strengthen)
    # hybrid + polish full_buffer + polish size_only (+ polish hybrid)
    need_docker
    docker run --rm \
      -v "$DIR/..:/workspace" \
      -w /workspace/openRoad_eval_script \
      "$IMAGE" \
      bash run_experiments.sh --strengthen
    ;;

  eval)
    need_docker
    docker run --rm \
      -v "$DIR/..:/workspace" \
      -w /workspace/openRoad_eval_script \
      "$IMAGE" \
      openroad -exit eval_def.tcl
    ;;

  eval-result)
    need_docker
    def="${1:-aes_cipher_top_adaptive.def}"
    docker run --rm \
      -v "$DIR/..:/workspace" \
      -w /workspace/openRoad_eval_script \
      -e "PROBC_DEF=${def}" \
      "$IMAGE" \
      openroad -exit eval_result.tcl
    docker run --rm \
      -v "$DIR/..:/workspace" \
      -w /workspace/python \
      "$IMAGE" \
      python3 compare_results.py \
        --results-dir /workspace/openRoad_eval_script/results \
        --ref-def /workspace/aes_cipher_top/aes_cipher_top.def
    ;;

  sweep)
    need_docker
    docker run --rm \
      -v "$DIR/..:/workspace" \
      -w /workspace/openRoad_eval_script \
      "$IMAGE" \
      bash run_experiments.sh --all
    ;;

  csv)
    python3 "$DIR/../python/compare_results.py" \
      --results-dir "$DIR/../openRoad_eval_script/results" \
      --ref-def "$DIR/../aes_cipher_top/aes_cipher_top.def"
    ;;

  export-image)
    need_docker
    out="${1:-openroad-image.tar}"
    echo "Saving $IMAGE -> $DIR/$out ..."
    docker save -o "$out" "$IMAGE"
    ls -lh "$out"
    echo "Load later with: docker load -i $out"
    ;;

  import-from-container)
    need_docker
    cname="${1:-openroad-env}"
    if ! docker ps -a --format '{{.Names}}' | grep -qx "$cname"; then
      echo "Container '$cname' not found. See: docker ps -a" >&2
      exit 1
    fi
    echo "Committing $cname -> $IMAGE ..."
    docker commit "$cname" "$IMAGE"
    echo "Done. Project can use: $0 shell"
    ;;

  help|*)
    cat <<EOF
Project-local OpenROAD Docker (lives under src/openroad_docker/)

  $0 build                      Build image from local .deb
  $0 shell                      Interactive bash with src/ mounted at /workspace
  $0 eval                       Baseline eval (original DEF)
  $0 eval-result [def]          Evaluate an optimized DEF + refresh CSV
  $0 optimize                   Run adaptive optimizer once
  $0 hybrid                     Resize → limited buffer → polish (from scratch)
  $0 polish [def] [tag] [recover%]
                                Polish DEF; recover% default 10, use 0 to skip
  $0 strengthen                 hybrid + polish full_buffer & size_only (recommended)
  $0 sweep                      Run all base strategies + hybrid + CSV
  $0 csv                        Rebuild comparison.csv from results/
  $0 import-from-container NAME Reuse your old container as $IMAGE
  $0 export-image [file.tar]    Save image into this folder (optional backup)

Recommended after sweep:
  $0 strengthen

Or stepwise (faster polish only):
  $0 polish aes_cipher_top_full_buffer.def full_buffer_polish
  $0 polish aes_cipher_top_size_only.def size_only_polish
  $0 csv

Outputs: openRoad_eval_script/results/comparison.csv
EOF
    ;;
esac
