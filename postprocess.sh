#!/usr/bin/env bash
# Decode saved evidence only. This script never executes a benchmark.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=scripts/common.sh
source "$ROOT/scripts/common.sh"

usage() {
    printf 'Usage: bash postprocess.sh [--retry] [--output NEW_DIRECTORY] RUN_DIRECTORY\n'
    printf 'Run on the collection VM, retaining its original binaries and environments.\n'
    printf '%s\n' '--retry rebuilds interrupted in-place output; completed output is never overwritten.'
    printf '%s\n' '--output writes a separate derived-only directory, preserving every input-run file.'
    printf '%s\n' 'MAX_STACK=512 controls the native decode-depth limit (integer 1..4096).'
}
retry=0
output_arg=
run_arg=
while (( $# )); do
    case "$1" in
        --help|-h) usage; exit 0 ;;
        --retry) retry=1; shift ;;
        --output)
            [[ $# -ge 2 && -n $2 && $2 != --* ]] || die '--output needs a new directory.'
            [[ -z $output_arg ]] || die '--output was supplied more than once.'
            output_arg=$2; shift 2 ;;
        --*) die "Unknown option: $1" ;;
        *) [[ -z $run_arg ]] || die 'Only one input run is accepted.'; run_arg=$1; shift ;;
    esac
done
[[ -n $run_arg ]] || { usage >&2; exit 2; }
[[ -d $run_arg ]] || die "Run directory does not exist: $run_arg"
RUN="$(cd -- "$run_arg" && pwd -P)"
INPUT_RAW="$RUN/raw"
[[ -f "$INPUT_RAW/collection.complete" ]] || die "Collection has not completed successfully: $INPUT_RAW/collection.complete is missing."
[[ -z $output_arg || $retry == 0 ]] || die '--retry applies only to in-place processing; choose a fresh --output directory instead.'
MAX_STACK=${MAX_STACK:-512}
[[ $MAX_STACK =~ ^[1-9][0-9]{0,3}$ ]] && (( MAX_STACK <= 4096 )) || die 'MAX_STACK must be an integer between 1 and 4096.'

MODE=framework
if [[ -f "$INPUT_RAW/collection-mode.txt" ]]; then
    MODE=$(cat "$INPUT_RAW/collection-mode.txt")
fi
case "$MODE" in worker|framework|timing-only) ;; *) die "Invalid collection mode: $MODE" ;; esac
require_tools flock mktemp
if [[ $MODE != timing-only ]]; then require_tools perf perl gzip; fi
lock_workflow
clean_python_env
validate_python
# No framework worker lookup: decoding does not run a benchmark or query pip.
if [[ $MODE != timing-only ]]; then
    [[ -f "$ROOT/vendor/FlameGraph/stackcollapse-perf.pl" ]] || die 'Missing vendored stackcollapse-perf.pl.'
    [[ -f "$ROOT/vendor/FlameGraph/flamegraph.pl" ]] || die 'Missing vendored flamegraph.pl.'
fi

benchmarks=()
while IFS= read -r bench || [[ -n "$bench" ]]; do
    case "$bench" in nbody|raytrace) ;; *) die "Invalid benchmark entry in collection.complete: $bench" ;; esac
    for seen in "${benchmarks[@]}"; do
        [[ $seen != "$bench" ]] || die "Duplicate benchmark in collection.complete: $bench"
    done
    benchmarks+=("$bench")
done < "$INPUT_RAW/collection.complete"
[[ ${#benchmarks[@]} -gt 0 ]] || die 'collection.complete is empty.'
for bench in "${benchmarks[@]}"; do
    inputs=("$RUN/$bench.json")
    if [[ $MODE != timing-only ]]; then inputs+=("$INPUT_RAW/$bench.profile.json" "$INPUT_RAW/$bench.perf.data"); fi
    for input in "${inputs[@]}"; do [[ -s $input ]] || die "Missing or empty collection file: $input"; done
done

DEST=$RUN
if [[ -n $output_arg ]]; then
    # Resolve symlinks and '..' before creating anything. A sibling output is safe;
    # writing into/above the source run would defeat its preservation guarantee.
    DEST=$("$PY" - "$output_arg" "$RUN" <<'PY'
from pathlib import Path
import sys
out, source = (Path(arg).resolve() for arg in sys.argv[1:])
if out == source or source in out.parents or out in source.parents:
    raise SystemExit('--output must be separate from the input run, not inside or above it.')
if out.exists() or Path(sys.argv[1]).is_symlink():
    raise SystemExit('--output must not already exist; choose a new directory.')
print(out)
PY
    )
else
    [[ ! -e "$INPUT_RAW/postprocess.complete" ]] || die 'This run has already been processed. Use --output with a new directory to decode it again.'
fi
RAW="$DEST/raw"
if [[ -z $output_arg ]] && (( ! retry )); then
    for bench in "${benchmarks[@]}"; do
        outputs=("$DEST/report_$bench.txt")
        if [[ $MODE != timing-only ]]; then outputs+=("$DEST/$bench.svg" "$RAW/$bench.folded.gz"); fi
        for output in "${outputs[@]}"; do
            [[ ! -e $output ]] || die "Partial derived output exists: $output. Review the log, then use --retry."
        done
    done
fi
if [[ -n $output_arg ]]; then
    mkdir -p -- "$(dirname -- "$DEST")"
    mkdir -- "$DEST"
    mkdir -- "$RAW"
    {
        printf 'Derived evidence only; benchmarks were not rerun.\nInput run: %s\n' "$RUN"
        printf 'Collection scope: %s\nDecode max stack: %s\nCreated: %s\n' "$MODE" "$MAX_STACK" "$(date -u +%FT%TZ)"
        printf 'Timing JSONs, native recordings, binaries and collection logs remain in the input run.\n'
    } > "$DEST/origin.txt"
fi
LOG="$RAW/postprocess.log"
WORK="$(mktemp -d "$RAW/.postprocess.XXXXXX")"
cleanup() {
    local code=$?
    rm -rf -- "$WORK"
    if (( code != 0 )); then
        printf 'Postprocessing failed (exit %s). Original evidence is retained; inspect %s.\n' "$code" "$LOG" >&2
    fi
    exit "$code"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
printf '\nPostprocessing started: %s\nInput: %s\nOutput: %s\nScope: %s\nMAX_STACK: %s\n' \
    "$(date -u +%FT%TZ)" "$RUN" "$DEST" "$MODE" "$MAX_STACK" >> "$LOG"
printf 'Postprocessing log: %s\n' "$LOG"

for bench in "${benchmarks[@]}"; do
    printf 'Processing %s: saved timing%s\n' "$bench" "$([[ $MODE == timing-only ]] || printf ' and perf data')"
    REPORT="$WORK/report_$bench.txt"
    {
        printf '%s\n' "$bench — saved measurement evidence"
        printf 'Input run: %s\n' "$RUN"
        printf '\n%s\n' 'TIMING SCOPE'
        printf '%s\n' 'Timing comes from the separate unprofiled pyperformance invocation.'
        printf '%s\n' 'Profile-run timings are excluded from the timing statistics below.'
        printf '\n%s\n' 'PROFILE SCOPE'
        case "$MODE" in
            worker)
                printf '%s\n' 'perf recorded the original benchmark script directly in its pyperf worker mode.'
                printf '%s\n' 'Interpreter startup, imports, warmup, calculation, worker metadata/bookkeeping and exit are included.'
                printf '%s\n' 'The outer pyperformance framework and its pip checks are outside this recording.'
                printf '%s\n' 'Worker-mode collection uses perf --no-inherit; child metadata utilities are excluded.' ;;
            framework)
                printf '%s\n' 'perf recorded the whole pyperformance command and inherited worker activity.'
                printf '%s\n' 'Imports, pip checks, framework management, startup and warmup can appear.'
                [[ -f "$INPUT_RAW/collection-mode.txt" ]] || printf '%s\n' 'Legacy run: no scope marker; retained the original whole-framework interpretation.' ;;
            timing-only) printf '%s\n' 'No native profile was collected for this run. No flamegraph is expected.' ;;
        esac
        if [[ $MODE != timing-only ]]; then
            printf '%s\n' 'Event: cpu-clock:u. Width is summed sampling period in ns, not elapsed wall time.'
            printf 'Native DWARF decoding: inline expansion disabled; maximum native stack depth %s.\n' "$MAX_STACK"
            printf '%s\n' 'Self-time rows show at least 0.5%; the omitted tail still contributes to the total.'
            printf 'Inspect %s/collection.log and %s for lost samples and unwind diagnostics.\n' "$INPUT_RAW" "$LOG"
        fi
        printf '%s\n' 'Successful processing does not certify stack quality, timing stability or coursework completion.'
        printf '\n%s\n' 'JSON VALIDATION'
    } > "$REPORT"

    "$PY" - "$RUN/$bench.json" "$INPUT_RAW/$bench.profile.json" "$bench" "$MODE" >> "$REPORT" 2>> "$LOG" <<'PY'
import math
import sys
import pyperf

timing_path, profile_path, expected_name, mode = sys.argv[1:]
checks = [(timing_path, 'Unprofiled timing', 60, 20, 3)]
if mode != 'timing-only':
    profile_count = 40 if expected_name == 'nbody' else 10
    checks.append((profile_path, 'Profile execution receipt', profile_count, 1, profile_count))
for path, label, expected_count, expected_runs, per_run in checks:
    suite = pyperf.BenchmarkSuite.load(path)
    if suite.get_benchmark_names() != [expected_name]:
        raise SystemExit(f'{label}: benchmark name does not match {expected_name}')
    benchmark = suite.get_benchmark(expected_name)
    values = benchmark.get_values()
    if not values or any(not math.isfinite(value) or value <= 0 for value in values):
        raise SystemExit(f'{label}: missing, nonfinite, or nonpositive measured values')
    if len(values) != expected_count:
        raise SystemExit(f'{label}: expected {expected_count} measured values; got {len(values)}')
    measured_runs = [run for run in benchmark.get_runs() if run.values]
    if len(measured_runs) != expected_runs or any(len(run.values) != per_run for run in measured_runs):
        raise SystemExit(f'{label}: expected {expected_runs} measured workers with {per_run} values each')
    metadata = benchmark.get_metadata()
    config_args = str(metadata.get('python_config_args', ''))
    declared_debug = metadata.get('Py_DEBUG', metadata.get('py_debug', metadata.get('python_debug')))
    if declared_debug is not None and str(declared_debug).lower() not in ('1', 'true'):
        raise SystemExit(f'{label}: metadata declares a non-debug interpreter')
    if '--without-pydebug' in config_args:
        raise SystemExit(f'{label}: metadata declares --without-pydebug')
    debug_evidence = '--with-pydebug' in config_args or declared_debug is not None
    print(f'{label}: {expected_name}; {len(values)} finite, positive values from {len(measured_runs)} measured workers.')
    print('  Debug build metadata: ' + ('present' if debug_evidence else 'not recorded; see input run.txt verification'))
PY

    for action in show check stats; do
        printf '\nPYPERF %s — UNPROFILED TIMING\n' "$action" >> "$REPORT"
        "$PY" -m pyperf "$action" "$RUN/$bench.json" >> "$REPORT" 2>> "$LOG"
    done
    [[ $MODE != timing-only ]] || continue

    printf '\nPERF SELF TIME — %s PROFILE COMMAND\n' "$MODE" >> "$REPORT"
    perf report --stdio --no-children -g none --percent-limit 0.5 \
        --sort comm,dso,symbol --no-inline --max-stack "$MAX_STACK" -i "$INPUT_RAW/$bench.perf.data" \
        >> "$REPORT" 2>> "$LOG"

    # Stream stacks: no enormous decoded text dump is written to disk.
    perf script --no-inline --max-stack "$MAX_STACK" -i "$INPUT_RAW/$bench.perf.data" -F +period 2>> "$LOG" \
        | perl "$ROOT/vendor/FlameGraph/stackcollapse-perf.pl" 2>> "$LOG" \
        > "$WORK/$bench.folded"
    "$PY" - "$WORK/$bench.folded" "$MAX_STACK" >> "$REPORT" 2>> "$LOG" <<'PY'
from collections import Counter
from pathlib import Path
import sys

limit = int(sys.argv[2])
rows = total = at_limit = missing_start = unknown = at_limit_missing_start = 0
depths = Counter()
for line in Path(sys.argv[1]).read_text().splitlines():
    if not line.strip():
        continue
    stack, count = line.rsplit(' ', 1)
    if not stack or not count.isdecimal() or int(count) <= 0:
        raise SystemExit('Folded stack data contains a malformed or nonpositive weight')
    weight = int(count)
    frames = stack.split(';')[1:]  # The first field is the process name, not a native frame.
    if not frames:
        raise SystemExit('Folded stack data has no native frame')
    depth = len(frames)
    capped = depth >= limit
    missing = '_start' not in frames
    unresolved = any('[unknown]' in frame or frame == 'unknown' for frame in frames)
    rows += 1
    total += weight
    depths[depth] += weight
    at_limit += weight if capped else 0
    missing_start += weight if missing else 0
    unknown += weight if unresolved else 0
    at_limit_missing_start += weight if capped and missing else 0
if rows == 0 or total <= 0:
    raise SystemExit('No positive decoded stack data; inspect postprocess.log')

def pct(weight):
    return 100 * weight / total

print(f'\nSTACK CHECKS — {rows} distinct folded rows; {total} ns total sampling period')
print('Percentages below use sampling-period weight, not a count of distinct rows or elapsed time.')
print(f'Maximum folded native depth: {max(depths)} (process-name frame excluded).')
print(f'At/above decoder limit {limit}: {pct(at_limit):.3f}% of weight.')
print(f'Without an exact _start frame: {pct(missing_start):.3f}% of weight.')
print(f'Both at the limit and without _start: {pct(at_limit_missing_start):.3f}% of weight.')
print(f'Containing literal [unknown]/unknown frames: {pct(unknown):.3f}% of weight.')
print('These categories overlap. Missing _start alone does not prove truncation.')
print('Unknown symbols can also be replaced by DSO labels during folding; this is not an exhaustive unresolved-symbol check.')
print('Native depth distribution (sampling-period weight):')
for low, high in ((1, 31), (32, 63), (64, 126), (127, 255), (256, 511), (512, 1023), (1024, 4096)):
    weight = sum(value for depth, value in depths.items() if low <= depth <= high)
    if weight:
        print(f'  {low:4d}..{high:<4d}: {pct(weight):7.3f}%')
if at_limit:
    print('WARNING: Some stacks reach the decode limit. First redecode the same perf.data with a higher MAX_STACK.')
    print('WARNING: Native stacks reach MAX_STACK; inspect the report before interpreting caller percentages.', file=sys.stderr)
print('A larger decode limit cannot restore bytes absent from the original capture.')
print('Only if ancestry remains demonstrably truncated after deeper decoding, consider a new capture using perf --call-graph dwarf,32768; this increases recording overhead and file size.')
print('These checks flag review needs; they do not certify stack correctness.')
PY

    if [[ $MODE == worker ]]; then scope_title='original benchmark / pyperf worker'; else scope_title='pyperformance / whole command'; fi
    perl "$ROOT/vendor/FlameGraph/flamegraph.pl" \
        --countname ns --title "$bench: perf / $scope_title" \
        --subtitle "Native user CPU stacks; no inline expansion; decode limit $MAX_STACK; timing is separate" \
        "$WORK/$bench.folded" > "$WORK/$bench.svg" 2>> "$LOG"
    [[ -s "$WORK/$bench.svg" ]] || die "Empty flamegraph generated for $bench; inspect $LOG."
    gzip -n -c "$WORK/$bench.folded" > "$WORK/$bench.folded.gz"
done

# Publish only after every requested benchmark validates and decodes.
for bench in "${benchmarks[@]}"; do
    mv -f -- "$WORK/report_$bench.txt" "$DEST/report_$bench.txt"
    if [[ $MODE != timing-only ]]; then
        mv -f -- "$WORK/$bench.svg" "$DEST/$bench.svg"
        mv -f -- "$WORK/$bench.folded.gz" "$RAW/$bench.folded.gz"
    fi
done
printf '%s\n' "${benchmarks[@]}" > "$WORK/postprocess.complete"
mv -- "$WORK/postprocess.complete" "$RAW/postprocess.complete"
printf 'Postprocessing completed: %s\n' "$(date -u +%FT%TZ)" >> "$LOG"
if [[ -z $output_arg ]]; then
    printf '\nPostprocessing completed: %s\nReports are generated evidence; interpretation remains manual.\n' "$(date -u +%FT%TZ)" >> "$RUN/run.txt"
fi
printf 'Ready: %s/report_*.txt\n' "$DEST"
if [[ $MODE != timing-only ]]; then printf 'Flamegraphs: %s/*.svg\n' "$DEST"; fi
