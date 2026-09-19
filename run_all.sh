#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
[[ $# -le 1 ]] || { printf 'Usage: bash run_all.sh [label]\n' >&2; exit 2; }
label=${1:-baseline-$(date -u +%Y%m%d-%H%M%S)}
bash "$ROOT/collect.sh" all "$label"
bash "$ROOT/postprocess.sh" "$ROOT/results/$label"
