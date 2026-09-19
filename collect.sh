#!/usr/bin/env bash
# Only collection. There is no Python driver, runtime hook, FIFO, or analysis here.
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/scripts/common.sh"
usage='Usage: bash collect.sh [--framework-profile | --timing-only] [all|nbody|raytrace] [label]'
MODE=worker
if [[ ${1:-} == --help || ${1:-} == -h ]]; then printf '%s\n' "$usage"; exit 0; fi
case ${1:-} in
    --framework-profile) MODE=framework; shift ;;
    --timing-only) MODE=timing-only; shift ;;
esac
[[ $# -le 2 ]] || die "$usage"
[[ $(uname -s) == Linux ]] || die 'Collection requires the Linux VM.'
selected_benchmarks "${1:-all}"
label=${2:-baseline-$(date -u +%Y%m%d-%H%M%S)}
[[ "$label" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || die 'Use a simple label: letters, numbers, dots, underscores, hyphens.'
SAMPLE_HZ=${SAMPLE_HZ:-199}
[[ "$SAMPLE_HZ" =~ ^[1-9][0-9]*$ && ${#SAMPLE_HZ} -le 4 ]] || die 'SAMPLE_HZ must be an integer from 1 to 9999.'
require_tools flock sha256sum cp
if [[ $MODE != timing-only ]]; then require_tools perf; fi
lock_workflow
clean_python_env
cd "$ROOT"
validate_python
validate_worker
PROFILE_PY="$(dirname -- "$ROOT/$(worker_python)")/python3-dbg"
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
printf '%s\n' "$MODE" > "$RUN/raw/collection-mode.txt"
{
    printf 'First three coursework stages: collected evidence\nUTC start: %s\n' "$(date -u +%FT%TZ)"
    printf 'Benchmarks: %s\n' "${BENCHMARKS[*]}"
    printf 'Timing: original benchmark timers; unprofiled pyperformance run.\n'
    printf 'Collection mode: %s\n' "$MODE"
    case "$MODE" in
        worker)
            printf 'Profile: direct original benchmark in upstream pyperf worker mode.\n'
            printf 'Only the worker task is sampled; child tasks are excluded (--no-inherit).\n'
            printf 'Worker startup, imports, warmup, pyperf bookkeeping, metadata and exit remain in scope.\n'
            printf 'No outer pyperformance manager or pip checks run inside this profile.\n'
            ;;
        framework)
            printf 'Profile: whole pyperformance command, inherited children, user CPU time.\n'
            printf 'Profile includes framework checks, startup, warmups and benchmark activity.\n'
            ;;
        timing-only) printf 'Profile: none; unprofiled timing collection only.\n' ;;
    esac
    printf 'No custom Python execution wrapper. perf sampling still has overhead.\n'
    if [[ $MODE != timing-only ]]; then
        printf 'Event: cpu-clock:u; requested frequency: %s Hz; unwind: dwarf,16384.\n' "$SAMPLE_HZ"
    fi
    printf 'Analysis and interpretation remain your work.\n\nEnvironment\n'
    uname -a
    if [[ $MODE != timing-only ]]; then perf --version; fi
    "$PY" -c 'import sys,sysconfig,os; print("Python:",sys.version); print("Executable:",sys.executable); print("Resolved:",os.path.realpath(sys.executable)); print("Py_DEBUG:",sysconfig.get_config_var("Py_DEBUG"))'
    sha256sum "$(readlink -f "$PY")"
    # No pip import is needed to list installed versions. In particular, this
    # avoids pip's distutils DeprecationWarning in the terminal before the run.
    "$PY" -c 'from importlib.metadata import distributions; print("\n".join(sorted(d.metadata["Name"] + "==" + d.version for d in distributions())))'
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
if [[ $MODE != timing-only ]]; then
    active='perf availability check (not benchmark evidence)'
    run_command perf record -q -e cpu-clock:u -F "$SAMPLE_HZ" --call-graph dwarf,16384 \
        -o "$RUN/raw/preflight.perf.data" -- /bin/true
    rm -- "$RUN/raw/preflight.perf.data"
fi

# ALL unprofiled timing precedes profiling. Both recordings precede postprocessing.
for bench in "${BENCHMARKS[@]}"; do
    active="$bench: unprofiled pyperformance timing"
    run_command "$PY" -m pyperformance run --manifest manifests/timing.manifest \
        --benchmarks "$bench" --python "$PY" --inherit-environ PIP_NO_INDEX,PIP_DISABLE_PIP_VERSION_CHECK \
        --output "$RUN/$bench.json"
    [[ -s "$RUN/$bench.json" ]] || die "No timing JSON for $bench."
done
for bench in "${BENCHMARKS[@]}"; do
    [[ $MODE != timing-only ]] || break
    if [[ $MODE == worker ]]; then
        active="$bench: perf recording of the original benchmark worker"
        options_text=$(profile_arguments "$bench")
        mapfile -t profile_options <<< "$options_text"
        # The target IS the benchmark worker, so --no-inherit cannot drop a
        # downstream benchmark worker. These two original benchmarks have no
        # computational child processes; metadata helper children are excluded.
        run_command perf record -P --no-inherit -e cpu-clock:u -F "$SAMPLE_HZ" --call-graph dwarf,16384 \
            -o "$RUN/raw/$bench.perf.data" -- \
            "$PROFILE_PY" "$ROOT/benchmarks/$bench/run_benchmark.py" \
            --worker --worker-task=0 "${profile_options[@]}" --output "$RUN/raw/$bench.profile.json"
    else
        active="$bench: guide-reference perf recording of pyperformance"
        run_command perf record -P -e cpu-clock:u -F "$SAMPLE_HZ" --call-graph dwarf,16384 \
            -o "$RUN/raw/$bench.perf.data" -- \
            "$PY" -m pyperformance run --manifest manifests/profile.manifest \
            --benchmarks "$bench" --python "$PY" --inherit-environ PIP_NO_INDEX,PIP_DISABLE_PIP_VERSION_CHECK \
            --output "$RUN/raw/$bench.profile.json"
    fi
    [[ -s "$RUN/raw/$bench.perf.data" && -s "$RUN/raw/$bench.profile.json" ]] || die "Incomplete profile for $bench."
done
active='final provenance check'
sha256sum --check --status "$RUN/raw/source.sha256" || die 'Source or settings changed during collection; this run must not be used.'
printf '%s\n' "${BENCHMARKS[@]}" > "$RUN/raw/collection.complete"
printf '\nCollection finished: %s\nNext: bash postprocess.sh %q\n' "$(date -u +%FT%TZ)" "$RUN" | tee -a "$RUN/run.txt"
