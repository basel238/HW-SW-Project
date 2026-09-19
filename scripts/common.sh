#!/usr/bin/env bash
# Shell orchestration only. No benchmark is imported or called by this file.
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
PY="$ROOT/.venv/bin/python3-dbg"
export LC_ALL=C

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
require_tools() {
    local tool
    for tool in "$@"; do command -v "$tool" >/dev/null || die "Missing $tool; see README.md."; done
}
lock_workflow() {
    exec 9>"$ROOT/.workflow.lock"
    flock -n 9 || die 'Another setup, collection, or postprocessing job is active in this directory.'
}
clean_python_env() {
    # Avoid user-supplied Python instrumentation, allocator overrides or pyperf hooks.
    local name
    while IFS= read -r name; do
        case "$name" in PYTHON*|PYPERF*) unset "$name" ;; esac
    done < <(compgen -e)
}
validate_python() {
    [[ -x "$PY" ]] || die 'Run bash setup.sh first.'
    "$PY" - <<'PY'
import importlib.metadata as md
import sys, sysconfig
if sys.implementation.name != 'cpython' or not sysconfig.get_config_var('Py_DEBUG'):
    raise SystemExit('Expected a CPython debug build, created using python3-dbg. No release fallback.')
if sys.version_info < (3, 10) or sys.flags.optimize:
    raise SystemExit('CPython >=3.10 without -O/-OO is required.')
for name, version in [('pyperformance','1.14.0'), ('pyperf','2.10.0'), ('psutil','7.0.0')]:
    if md.version(name) != version:
        raise SystemExit(f'{name} must be {version}; rerun setup.sh.')
PY
}
worker_python() {
    # Pinned pyperformance 1.14.0 uses this key for its common worker environment.
    "$PY" -c 'import sys; from pyperformance.run import get_run_id; print("venv/" + get_run_id(sys.executable).name + "/bin/python")'
}
validate_worker() {
    local worker
    worker="$ROOT/$(worker_python)"
    [[ -x "$worker" ]] || die 'Prepared framework environment is missing; rerun setup.sh.'
    "$worker" - "$PY" <<'PY'
import importlib.metadata as md
import os, sys, sysconfig
if not sysconfig.get_config_var('Py_DEBUG') or not os.path.samefile(sys.executable, sys.argv[1]):
    raise SystemExit('Framework worker is not the same debug executable as the launcher.')
for name, version in [('pyperf','2.10.0'), ('psutil','7.0.0')]:
    if md.version(name) != version:
        raise SystemExit(f'Worker {name} must be {version}; rerun setup.sh.')
PY
}
selected_benchmarks() {
    case "${1:-all}" in
        all) BENCHMARKS=(nbody raytrace) ;;
        nbody|raytrace) BENCHMARKS=("$1") ;;
        *) die 'Benchmark must be all, nbody, or raytrace.' ;;
    esac
}
write_source_hashes() {
    (cd "$ROOT" && sha256sum benchmarks/{nbody,raytrace}/{run_benchmark.py,requirements.txt} \
        manifests/{timing,profile}.manifest manifests/{timing,profile}/{nbody,raytrace}/pyproject.toml)
}
