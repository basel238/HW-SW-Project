#!/usr/bin/env bash
# Only collection. There is no Python driver, runtime hook, FIFO, or analysis here.
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/scripts/common.sh"
[[ $# -le 2 ]] || die 'Usage: bash collect.sh [all|nbody|raytrace] [label]'
[[ $(uname -s) == Linux ]] || die 'Collection requires the Linux VM.'
selected_benchmarks "${1:-all}"
label=${2:-baseline-$(date -u +%Y%m%d-%H%M%S)}
[[ "$label" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || die 'Use a simple label: letters, numbers, dots, underscores, hyphens.'
SAMPLE_HZ=${SAMPLE_HZ:-199}
[[ "$SAMPLE_HZ" =~ ^[1-9][0-9]*$ && ${#SAMPLE_HZ} -le 4 ]] || die 'SAMPLE_HZ must be an integer from 1 to 9999.'
require_tools perf perl flock sha256sum cp
lock_workflow
clean_python_env
cd "$ROOT"
validate_python
validate_worker
[[ -f .prepared.sha256 ]] || die 'Setup has not completed. Run bash setup.sh.'
sha256sum --check --status .prepared.sha256 || die 'Source or manifests changed since setup; inspect the edits and rerun setup.'
mkdir -p results
RUN="$ROOT/results/$label"
mkdir "$RUN" || die "Run already exists: $RUN. Choose a new label; old evidence is preserved."
mkdir "$RUN/raw"
active='preflight'
finish() {
    local code=$?
    if (( code != 0 )); then
        printf '\nFAILED during %s (exit %s). Inspect raw/collection.log.\n' "$active" "$code" | tee -a "$RUN/run.txt" >&2
    fi
}
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
cp -R benchmarks manifests "$RUN/raw/"
cp .prepared.sha256 "$RUN/raw/source.sha256"
{
    printf 'First three coursework stages: collected evidence\nUTC start: %s\n' "$(date -u +%FT%TZ)"
    printf 'Benchmarks: %s\n' "${BENCHMARKS[*]}"
    printf 'Timing: original benchmark timers; unprofiled pyperformance run.\n'
    printf 'Profile: whole pyperformance command, inherited children, user CPU time.\n'
    printf 'Profile includes framework checks, startup, warmups and benchmark activity.\n'
    printf 'No custom Python execution wrapper. perf sampling still has overhead.\n'
    printf 'Event: cpu-clock:u; requested frequency: %s Hz; unwind: dwarf,16384.\n' "$SAMPLE_HZ"
    printf 'Analysis and interpretation remain your work.\n\nEnvironment\n'
    uname -a
    perf --version
    "$PY" -c 'import sys,sysconfig,os; print("Python:",sys.version); print("Executable:",sys.executable); print("Resolved:",os.path.realpath(sys.executable)); print("Py_DEBUG:",sysconfig.get_config_var("Py_DEBUG"))'
    sha256sum "$(readlink -f "$PY")"
    "$PY" -m pip freeze
    if command -v lscpu >/dev/null; then lscpu; fi
    printf '\nCommands and command elapsed durations (NOT benchmark timings)\n'
} > "$RUN/run.txt"

# Disable package indexes during collection. This is not a network sandbox;
# the prepared framework still runs dependency checks through pip.
export PIP_NO_INDEX=1 PIP_DISABLE_PIP_VERSION_CHECK=1
# No background CPU monitor, report generator or busy Python supervisor.
run_command() {
    local started=$SECONDS code=0
    printf '\n%s\n' "$active" | tee -a "$RUN/run.txt"
    printf '  %q' "$@" >> "$RUN/run.txt"
    printf '\n' >> "$RUN/run.txt"
    printf '\n=== %s ===\n' "$active" >> "$RUN/raw/collection.log"
    "$@" >> "$RUN/raw/collection.log" 2>&1 || code=$?
    printf 'Exit: %s; command elapsed: %ss\n' "$code" "$((SECONDS-started))" >> "$RUN/run.txt"
    (( code == 0 )) || return "$code"
}

# Check event/command permissions before long runs. A /bin/true recording may
# contain zero samples and does not establish stack-unwinding quality.
active='perf availability check (not benchmark evidence)'
run_command perf record -q -e cpu-clock:u -F "$SAMPLE_HZ" --call-graph dwarf,16384 \
    -o "$RUN/raw/preflight.perf.data" -- /bin/true
rm -- "$RUN/raw/preflight.perf.data"

# ALL unprofiled timing precedes profiling. Both recordings precede postprocessing.
for bench in "${BENCHMARKS[@]}"; do
    active="$bench: unprofiled pyperformance timing"
    run_command "$PY" -m pyperformance run --manifest manifests/timing.manifest \
        --benchmarks "$bench" --python "$PY" --inherit-environ PIP_NO_INDEX,PIP_DISABLE_PIP_VERSION_CHECK \
        --output "$RUN/$bench.json"
    [[ -s "$RUN/$bench.json" ]] || die "No timing JSON for $bench."
done
for bench in "${BENCHMARKS[@]}"; do
    active="$bench: perf recording of pyperformance"
    run_command perf record -P -e cpu-clock:u -F "$SAMPLE_HZ" --call-graph dwarf,16384 \
        -o "$RUN/raw/$bench.perf.data" -- \
        "$PY" -m pyperformance run --manifest manifests/profile.manifest \
        --benchmarks "$bench" --python "$PY" --inherit-environ PIP_NO_INDEX,PIP_DISABLE_PIP_VERSION_CHECK \
        --output "$RUN/raw/$bench.profile.json"
    [[ -s "$RUN/raw/$bench.perf.data" && -s "$RUN/raw/$bench.profile.json" ]] || die "Incomplete profile for $bench."
done
active='final provenance check'
sha256sum --check --status "$RUN/raw/source.sha256" || die 'Source or settings changed during collection; this run must not be used.'
printf '%s\n' "${BENCHMARKS[@]}" > "$RUN/raw/collection.complete"
printf '\nCollection finished: %s\nNext: bash postprocess.sh %q\n' "$(date -u +%FT%TZ)" "$RUN" | tee -a "$RUN/run.txt"
