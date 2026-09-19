#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
[[ $# -le 1 ]] || { printf 'Usage: bash script_raytrace.sh [label]\n' >&2; exit 2; }
label=${1:-raytrace-$(date -u +%Y%m%d-%H%M%S)}
bash "$ROOT/collect.sh" raytrace "$label"
bash "$ROOT/postprocess.sh" "$ROOT/results/$label"
