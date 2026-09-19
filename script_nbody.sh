#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
[[ $# -le 1 ]] || { printf 'Usage: bash script_nbody.sh [label]\n' >&2; exit 2; }
label=${1:-nbody-$(date -u +%Y%m%d-%H%M%S)}
bash "$ROOT/collect.sh" nbody "$label"
bash "$ROOT/postprocess.sh" "$ROOT/results/$label"
