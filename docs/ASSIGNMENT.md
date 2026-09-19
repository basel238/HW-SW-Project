# Assignment mapping: first three steps only

Checked against the supplied `Project(2).pdf`. The formal project steps are on page 3; they are different from the preliminary VM guide's step numbering.

| Requirement | Evidence this workflow prepares | What you still do |
|---|---|---|
| **1. Benchmark analysis:** understand purpose, libraries, data structures, algorithms, and relevant dependencies (p. 3) | Readable, unchanged benchmark sources; source/settings snapshots with each run | Study the code and write your explanation in `reports/report_nbody.txt` and `reports/report_raytrace.txt` |
| **2. Understand pyperformance:** run tests, capture results, interpret performance data (p. 3) | Genuine pyperformance runs and unprofiled JSON; exact commands and configuration | Interpret values, units, variability, warnings, and the limits of the experiment |
| **3. Generate a flamegraph for each selected benchmark through pyperformance (p. 3)** | `perf record` around genuine pyperformance, then separate perf/FlameGraph processing | Inspect each graph and explain what its width, stacks, and sampling scope mean |

Nbody and raytrace are both on the approved benchmark list (p. 7). Nothing in this package implements steps 4 onward: bottleneck conclusions, proposed improvements, optimization, speedup claims, or hardware design.

## Relationship to the guide

Page 1 explicitly says to use the debug Python build, `python3-dbg`, for profiling. Its example is:

```bash
perf record -F 999 -g -- python3-dbg -m pyperformance run --bench json_dumps
perf report --stdio > perf_report.txt
```

This workflow uses the same framework-based approach for the selected benchmarks, with explicit output paths and manifests. It deliberately specifies DWARF stack unwinding, user-space CPU-clock sampling, and a default 199 Hz sample rate. The PDF does not separately mandate a particular event, unwinder, or frequency; 999 Hz remains selectable. These are documented measurement settings, not a claim to reproduce the example command byte for byte.

All timing also uses the debug interpreter, following your requested policy. Page 1's explicit debug instruction concerns profiling; the PDF does not independently state that every timing run must use a debug build.

Perf records while the framework executes. Therefore the graph includes framework/startup/warmup activity as well as benchmark activity. It cannot honestly be labeled “benchmark hot loop only.” Eliminating that scope requires a different experiment, usually with cooperation inside the target process. This package chooses direct guide alignment and removes our previous custom workload wrapper.

## Submission boundary

Pages 7–8 require written `report_<benchmark>.txt`, `script_<benchmark>.sh`, and an AI prompt record. The root convenience scripts and report templates use those names. Setup is factored into `setup.sh` and must run explicitly before collection; that keeps installation outside measurement. `prompt.txt` records the request that produced this package and must be extended with other AI interactions.

The complete assignment additionally asks for optimization, performance comparison, and other later-stage material. Those sections are deliberately left to you. Producing two SVGs and JSON files is evidence for the first stages, not certification that the written understanding or the full submission is complete.

## Reading the evidence accurately

- Use unprofiled JSON for timing. A perf run is a separate, instrumented execution.
- Perf's native tables and graphs describe sampled CPU activity. They do not establish FPU saturation, IPC, memory bandwidth, or a hardware bottleneck.
- A frame's inclusive width contains its descendants. A full-width ancestor need not have substantial self time.
- Native debug symbols and Python source-level function names are different capabilities. Python 3.10's native interpreter frames are expected.
- Keep the settings, raw recording, and source snapshot with each run. A changed interpreter, source, workload, or measurement scope defines a different experiment.

Primary references: [pyperformance documentation](https://pyperformance.readthedocs.io/), [pyperf analysis](https://pyperf.readthedocs.io/en/latest/analyze.html), [perf record](https://man7.org/linux/man-pages/man1/perf-record.1.html), [FlameGraph documentation](https://www.brendangregg.com/flamegraphs.html), [Python perf integration](https://docs.python.org/3/howto/perf_profiling.html).
