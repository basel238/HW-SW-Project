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
    local worker profile_worker
    worker="$ROOT/$(worker_python)"
    profile_worker="$(dirname -- "$worker")/python3-dbg"
    [[ -x "$worker" ]] || die 'Prepared framework environment is missing; rerun setup.sh.'
    [[ -x "$profile_worker" ]] || die 'Debug worker alias is missing; rerun setup.sh after applying this update.'
    "$worker" - "$PY" "$profile_worker" <<'PY'
import importlib.metadata as md
import os, sys, sysconfig
if not sysconfig.get_config_var('Py_DEBUG') or not all(os.path.samefile(sys.executable, p) for p in sys.argv[1:]):
    raise SystemExit('Framework worker is not the same debug executable as the launcher.')
for name, version in [('pyperf','2.10.0'), ('psutil','7.0.0')]:
    if md.version(name) != version:
        raise SystemExit(f'Worker {name} must be {version}; rerun setup.sh.')
PY
}
profile_arguments() {
    # Read the existing upstream CLI settings BEFORE perf starts. This does not
    # import a benchmark or add Python calls around its execution.
    local bench=$1
    "$PY" - "$ROOT" "$bench" <<'PY'
from pathlib import Path
import sys
try:
    import tomllib
except ImportError:
    import tomli as tomllib
root, bench = Path(sys.argv[1]), sys.argv[2]
meta = root / 'manifests' / 'profile' / bench / 'pyproject.toml'
with meta.open('rb') as f:
    settings = tomllib.load(f)['tool']['pyperformance']
source = (meta.parent / settings['runscript']).resolve()
if source != (root / 'benchmarks' / bench / 'run_benchmark.py').resolve():
    raise SystemExit('Profile manifest must select the included original benchmark script.')
args = settings['extra_opts']
if not isinstance(args, list) or not args or any(not isinstance(x, str) or not x or '\n' in x or '\r' in x for x in args):
    raise SystemExit('Invalid profile manifest arguments.')
if '--processes=1' not in args or '--loops=1' not in args or '--warmups=1' not in args:
    raise SystemExit('The worker profile protocol requires one process, one loop, and one warmup.')
print('\n'.join(args))
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
