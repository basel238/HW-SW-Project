# Assignment mapping: first three steps only

Checked against the supplied `Project(2).pdf`. The formal project steps are on page 3; they differ from the preliminary guide's step numbering.

| Requirement | Evidence this workflow prepares | What you still do |
|---|---|---|
| **1. Benchmark analysis:** understand purpose, libraries, data structures, algorithms, and relevant dependencies (p. 3) | Unchanged benchmark sources and source/settings snapshots | Study the code and complete `reports/report_nbody.txt` and `reports/report_raytrace.txt` |
| **2. Understand pyperformance:** run tests, capture results, interpret performance data (p. 3) | Genuine, unprofiled pyperformance runs and JSON; recorded settings and commands | Interpret units, variation, warnings, and experimental limits |
| **3. Generate a flamegraph for each selected benchmark through pyperformance (p. 3)** | Default perf recording of the original benchmark's pyperf worker; optional recording around the actual pyperformance command | State the chosen scope, inspect both graphs, and explain their meaning; use the framework option for the closest match to the guide's command |

Nbody and raytrace are on the approved list (p. 7). No optimization, speedup claim, hardware design, or completed bottleneck interpretation is supplied.

## Relationship to the guide

Page 1 explicitly calls for the debug Python build, `python3-dbg`, for profiling. Its example is:

```bash
perf record -F 999 -g -- python3-dbg -m pyperformance run --bench json_dumps
perf report --stdio > perf_report.txt
```

Both collection modes use debug Python, perf, and the unchanged pyperformance benchmark source. They differ in what perf surrounds:

| Mode | Invocation inside perf | Scope |
|---|---|---|
| Default `worker` | Prepared debug worker executes the original `run_benchmark.py --worker ...` | Startup, imports, warmup, computation, worker-side pyperf harness/metadata, shutdown |
| Optional `framework` | `python3-dbg -m pyperformance run ...` | The above plus the outer manager and dependency checks |

The direct-worker mode is a deliberate departure from the guide's literal framework invocation, introduced to remove pip and outer-manager activity from the primary graph. It does not claim instructor approval for this interpretation of step 3. If the requirement is interpreted as perf wrapping the actual pyperformance command, also collect:

```bash
bash collect.sh --framework-profile all guide-reference
bash postprocess.sh results/guide-reference
```

Neither mode records only the benchmark hot loop. Exact internal boundaries would require cooperation inside the target or another synchronization mechanism, which this simplified workflow does not add. Direct-worker recording disables event inheritance to omit metadata-helper subprocesses. This is appropriate for the original single-threaded workloads; whole-framework recording retains inheritance to capture benchmark workers.

The scripts specify DWARF unwinding, user-space CPU-clock sampling, and a default 199 Hz. The PDF does not separately mandate those settings. Use `SAMPLE_HZ=999` to select the example frequency. Postprocessing uses `--no-inline --max-stack 512`; this changes decoding, not already collected samples.

All timing also uses debug Python under the user's chosen policy. The guide's explicit debug instruction concerns profiling; it does not independently require a debug build for every timing run.

## Submission boundary

Pages 7–8 require written `report_<benchmark>.txt`, `script_<benchmark>.sh`, and an AI prompt record. This package provides convenience scripts, unanswered report templates, and an incomplete prompt extract. Setup is a separate explicit step so installation happens before measurement. Add other AI prompts used for the project.

The complete assignment also asks for optimization, comparison, and later-stage work. Those are outside this package. JSONs, SVGs, tool-success markers, and documentation do not certify completion of the written first three steps or the full submission.

## Evidence interpretation

- Use unprofiled JSON for performance timing; perf executions are instrumented.
- Read `raw/collection-mode.txt` and exact commands before comparing graph percentages. Earlier runs without the mode file recorded the whole framework.
- Perf graphs describe sampled activity, not FPU saturation, IPC, bandwidth, or a hardware bottleneck.
- Inclusive frame width contains descendants. A full-width caller can have little self time.
- Python 3.10 native interpreter frames are expected; native debug symbols are not automatic Python source-level symbols.
- Keep raw recordings and source/configuration snapshots. Rerendering old data is not a new measurement and cannot remove activity that was recorded.

Primary references: [pyperformance](https://pyperformance.readthedocs.io/), [pyperf analysis](https://pyperf.readthedocs.io/en/latest/analyze.html), [perf record](https://man7.org/linux/man-pages/man1/perf-record.1.html), [perf script](https://man7.org/linux/man-pages/man1/perf-script.1.html), [FlameGraph](https://www.brendangregg.com/flamegraphs.html), [Python perf integration](https://docs.python.org/3/howto/perf_profiling.html).
