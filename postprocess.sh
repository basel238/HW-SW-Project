#!/usr/bin/env bash
# Decode existing recordings only. This script never executes a benchmark.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=scripts/common.sh
source "$ROOT/scripts/common.sh"

usage() {
    printf 'Usage: bash postprocess.sh [--retry] RUN_DIRECTORY\n'
    printf 'Run on the collection VM, with its original binaries and virtual environments retained.\n'
    printf '%s\n' '--retry replaces derived files from an interrupted attempt; completed output is never overwritten.'
}

retry=0
if [[ ${1:-} == --help || ${1:-} == -h ]]; then usage; exit 0; fi
if [[ ${1:-} == --retry ]]; then retry=1; shift; fi
[[ $# == 1 ]] || { usage >&2; exit 2; }
[[ -d $1 ]] || die "Run directory does not exist: $1"
RUN="$(cd -- "$1" && pwd -P)"
RAW="$RUN/raw"
[[ -f "$RAW/collection.complete" ]] || die "Collection has not completed successfully: $RAW/collection.complete is missing."

require_tools flock perf perl gzip mktemp
lock_workflow
[[ ! -e "$RAW/postprocess.complete" ]] || die "This run has already been processed. Its results have been preserved."
clean_python_env
validate_python
validate_worker
[[ -f "$ROOT/vendor/FlameGraph/stackcollapse-perf.pl" ]] || die "Missing vendored stackcollapse-perf.pl; run setup first."
[[ -f "$ROOT/vendor/FlameGraph/flamegraph.pl" ]] || die "Missing vendored flamegraph.pl; run setup first."

benchmarks=()
while IFS= read -r bench || [[ -n "$bench" ]]; do
    case "$bench" in
        nbody|raytrace) ;;
        *) die "Invalid benchmark entry in collection.complete: $bench" ;;
    esac
    for seen in "${benchmarks[@]}"; do
        [[ $seen != "$bench" ]] || die "Duplicate benchmark in collection.complete: $bench"
    done
    benchmarks+=("$bench")
done < "$RAW/collection.complete"
[[ ${#benchmarks[@]} -gt 0 ]] || die "collection.complete is empty."

for bench in "${benchmarks[@]}"; do
    for input in "$RUN/$bench.json" "$RAW/$bench.profile.json" "$RAW/$bench.perf.data"; do
        [[ -s "$input" ]] || die "Missing or empty collection file: $input"
    done
    if (( ! retry )); then
        for output in "$RUN/report_$bench.txt" "$RUN/$bench.svg" "$RAW/$bench.folded.gz"; do
            [[ ! -e "$output" ]] || die "Partial derived output exists: $output. Review the log, then use --retry to regenerate derived files only."
        done
    fi
done

LOG="$RAW/postprocess.log"
WORK="$(mktemp -d "$RAW/.postprocess.XXXXXX")"
cleanup() {
    local code=$?
    rm -rf -- "$WORK"
    if (( code != 0 )); then
        printf 'Postprocessing failed (exit %s). Raw evidence is retained; inspect %s.\n' "$code" "$LOG" >&2
    fi
    exit "$code"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
printf '\nPostprocessing started: %s\n' "$(date -u +%FT%TZ)" >> "$LOG"
printf 'Run: %s\n' "$RUN" >> "$LOG"

for bench in "${benchmarks[@]}"; do
    printf 'Processing %s: existing perf data and timing JSON only\n' "$bench"
    REPORT="$WORK/report_$bench.txt"
    {
        printf '%s\n' "$bench — timing and native perf evidence"
        printf '\n%s\n' 'TIMING SCOPE'
        printf '%s\n' 'The timing JSON comes from the separate unprofiled pyperformance invocation.'
        printf '%s\n' 'Profile-run timings are excluded from this timing report.'
        printf '\n%s\n' 'PROFILE SCOPE'
        printf '%s\n' 'perf recorded the whole pyperformance command and inherited worker activity.'
        printf '%s\n' 'Imports, calibration, framework activity, and other work during that command can appear.'
        printf '%s\n' 'The event is cpu-clock:u. Width is summed sampling period in ns, not elapsed wall time.'
        printf '%s\n' 'Native stacks use DWARF unwinding. Inline expansion is disabled during decoding.'
        printf '%s\n' 'Self-time rows below are limited to at least 0.5%; the omitted tail still contributes to the total.'
        printf '%s\n' 'Inspect raw/collection.log and raw/postprocess.log for lost samples and unwinding diagnostics.'
        printf '%s\n' 'Successful file generation does not certify stack quality, timing stability, or completion of the assignment.'
        printf '\n%s\n' 'JSON VALIDATION'
    } > "$REPORT"

    "$PY" - "$RUN/$bench.json" "$RAW/$bench.profile.json" "$bench" >> "$REPORT" 2>> "$LOG" <<'PY'
import math
import sys
import pyperf

timing_path, profile_path, expected_name = sys.argv[1:]
for path, label, expected_count in (
    (timing_path, "Unprofiled timing", 60),
    (profile_path, "Profile execution receipt", 40 if expected_name == "nbody" else 10),
):
    suite = pyperf.BenchmarkSuite.load(path)
    if suite.get_benchmark_names() != [expected_name]:
        raise SystemExit(f"{label}: benchmark name does not match {expected_name}")
    benchmark = suite.get_benchmark(expected_name)
    values = benchmark.get_values()
    if not values or any(not math.isfinite(value) or value <= 0 for value in values):
        raise SystemExit(f"{label}: missing, nonfinite, or nonpositive measured values")
    if expected_count is not None and len(values) != expected_count:
        raise SystemExit(f"{label}: expected {expected_count} measured values; got {len(values)}")
    metadata = benchmark.get_metadata()
    config_args = str(metadata.get("python_config_args", ""))
    declared_debug = metadata.get("Py_DEBUG", metadata.get("py_debug", metadata.get("python_debug")))
    if declared_debug is not None and str(declared_debug).lower() not in ("1", "true"):
        raise SystemExit(f"{label}: metadata declares a non-debug interpreter")
    if "--without-pydebug" in config_args:
        raise SystemExit(f"{label}: metadata declares --without-pydebug")
    debug_evidence = "--with-pydebug" in config_args or declared_debug is not None
    print(f"{label}: {expected_name}; {len(values)} finite, positive values.")
    print("  Debug build metadata: " + ("present" if debug_evidence else "not recorded; see run.txt interpreter verification"))
PY

    for action in show check stats; do
        printf '\nPYPERF %s — UNPROFILED TIMING\n' "$action" >> "$REPORT"
        "$PY" -m pyperf "$action" "$RUN/$bench.json" >> "$REPORT" 2>> "$LOG"
    done

    printf '\nPERF SELF TIME — WHOLE PROFILE COMMAND\n' >> "$REPORT"
    perf report --stdio --no-children -g none --percent-limit 0.5 \
        --sort comm,dso,symbol --no-inline -i "$RAW/$bench.perf.data" \
        >> "$REPORT" 2>> "$LOG"

    # Stream stacks directly into the collapser; never save a huge perf-script dump.
    perf script --no-inline -i "$RAW/$bench.perf.data" -F +period 2>> "$LOG" \
        | perl "$ROOT/vendor/FlameGraph/stackcollapse-perf.pl" 2>> "$LOG" \
        > "$WORK/$bench.folded"
    "$PY" - "$WORK/$bench.folded" >> "$REPORT" 2>> "$LOG" <<'PY'
import sys
from pathlib import Path

rows = 0
weight = 0
for line in Path(sys.argv[1]).read_text().splitlines():
    if not line.strip():
        continue
    stack, count = line.rsplit(" ", 1)
    if not stack or not count.isdecimal() or int(count) <= 0:
        raise SystemExit("Folded stack data contains a malformed or nonpositive weight")
    rows += 1
    weight += int(count)
if rows == 0 or weight <= 0:
    raise SystemExit("perf recording decoded to no positive stack data; inspect postprocess.log")
print(f"\nFlamegraph input: {rows} distinct folded stack rows; {weight} ns total sampling period.")
print("This total is a sampling weight, not an exact elapsed-time measurement.")
PY

    perl "$ROOT/vendor/FlameGraph/flamegraph.pl" \
        --countname ns --title "$bench: perf / pyperformance (whole command)" \
        --subtitle 'Native user CPU stacks; no inline expansion; separate unprofiled timing in the report' \
        "$WORK/$bench.folded" > "$WORK/$bench.svg" 2>> "$LOG"
    [[ -s "$WORK/$bench.svg" ]] || die "Empty flamegraph generated for $bench; inspect $LOG."
    gzip -n -c "$WORK/$bench.folded" > "$WORK/$bench.folded.gz"
done

# Publish only after every requested benchmark has decoded and validated.
# If the host stops between moves, --retry can rebuild the derived files.
for bench in "${benchmarks[@]}"; do
    mv -f -- "$WORK/report_$bench.txt" "$RUN/report_$bench.txt"
    mv -f -- "$WORK/$bench.svg" "$RUN/$bench.svg"
    mv -f -- "$WORK/$bench.folded.gz" "$RAW/$bench.folded.gz"
done
printf '%s\n' "${benchmarks[@]}" > "$WORK/postprocess.complete"
mv -- "$WORK/postprocess.complete" "$RAW/postprocess.complete"
printf 'Postprocessing completed: %s\n' "$(date -u +%FT%TZ)" >> "$LOG"
printf '\nPostprocessing completed: %s\nReports and SVGs are generated evidence; interpretation remains manual.\n' "$(date -u +%FT%TZ)" >> "$RUN/run.txt"
printf 'Ready: %s/report_*.txt and %s/*.svg\n' "$RUN" "$RUN"
