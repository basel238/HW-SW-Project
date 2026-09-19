# First three coursework steps: nbody and raytrace

A small, separate workflow for the assignment's benchmark study, pyperformance timing, and perf flamegraphs. It keeps the benchmark sources unchanged and invokes the debug interpreter through the real pyperformance command. There is no custom Python workload driver, FIFO control, cProfile, py-spy, hardware-counter campaign, or optimization.

**There is no honest zero-overhead profiling method.** These scripts add no custom Python calls around the benchmark body. The original benchmark's pyperf harness remains, and perf recording itself costs resources. Timing and profiling use separate executions. The profile covers the whole pyperformance invocation, including its framework, worker startup, warmup, and benchmark activity; it is not an isolated hot-loop measurement.

## Run on the Ubuntu Linux VM

Use a quiet VM and avoid running other measurements or analysis concurrently. Run setup once, before collecting results:

```bash
cd course-first-three
bash setup.sh
bash run_all.sh baseline
```

On an Ubuntu VM missing system dependencies, use `bash setup.sh --install-system` once instead; it installs the debug interpreter and matching perf package through apt before preparing the environments.

`baseline` is an output label, not a benchmark name. Existing result directories are not overwritten. Omit the label to get a new timestamped name.

For explicit separation between collection and processing:

```bash
bash collect.sh all baseline-2
# All timing and recording finish before this next command.
bash postprocess.sh results/baseline-2
```

If processing is interrupted, fix the reported problem and use
`bash postprocess.sh --retry results/baseline-2`. This regenerates incomplete
derived files while preserving the collected data. Completed runs are never
overwritten, even with `--retry`.

Collect only one benchmark:

```bash
bash script_nbody.sh nbody-check
bash script_raytrace.sh raytrace-check
```

These two convenience scripts collect the selected benchmark and then process that result. Setup must already have finished. They do not install packages during measurement.

The default sampling frequency is 199 Hz. To request the guide's example frequency of 999 Hz:

```bash
SAMPLE_HZ=999 bash collect.sh all guide-frequency
bash postprocess.sh results/guide-frequency
```

Higher frequency produces more samples and larger recording overhead and files. Collection time depends on the VM and interpreter; decoding debug stacks can take much longer than recording. Progress messages distinguish recording from processing. Do not treat time spent generating a graph as benchmark execution time.

## What you receive

For a two-benchmark run, open these files first:

| File under `results/LABEL/` | Purpose |
|---|---|
| `run.txt` | Commands, collection settings, and environment record |
| `nbody.json`, `raytrace.json` | Unprofiled pyperformance timing results |
| `nbody.svg`, `raytrace.svg` | Interactive perf flamegraphs; open in a browser |
| `report_nbody.txt`, `report_raytrace.txt` | Readable timing summaries and compact native self-time tables |
| `raw/` | Recordings, profile-run JSON, logs, source/settings snapshots, and processing intermediates |

Keep `raw/` for reproducibility and later decoding. You do not need to read it for every review. A profile-run JSON measures execution under perf and must not replace the unprofiled timing JSON. The generated `report_*.txt` files are profiler tables, not completed coursework reports. Write your interpretation in the separate `reports/report_*.txt` templates.

You can inspect timing JSON with the installed pyperf tool:

```bash
.venv/bin/python3-dbg -m pyperf show results/baseline/nbody.json
.venv/bin/python3-dbg -m pyperf stats results/baseline/nbody.json
.venv/bin/python3-dbg -m pyperf show results/baseline/raytrace.json
```

Warnings about instability are evidence to investigate, not reasons to discard inconvenient samples. Do not compare profiled elapsed time with unprofiled benchmark time as if they were the same metric.

## Measurement choices

- **Interpreter:** debug CPython, verified by its build configuration. A process label such as `python` or `python3-dbg` alone does not prove the build type. Neither Python's `-d` flag nor debug symbols alone converts a release executable into a debug build.
- **Source:** the included, unchanged nbody and raytrace benchmarks from pyperformance 1.14.0. Timing and profiling use the same sources and debug interpreter. Read `benchmarks/NAME/run_benchmark.py` for step 1.
- **Timing:** 20 worker processes, three measured values per worker, one warmup value, one loop per value. This is a fixed protocol, not a promise of statistical stability.
- **Profiling:** one worker, one warmup, one loop per value; 40 measured values for nbody and ten for raytrace. The workload per call remains nbody's 20,000 steps and raytrace's 100 × 100 scene. Nbody state evolves between calls, so this is a longer trajectory in one worker than the timing run; the two runs are not identical state histories.
- **Stacks:** `cpu-clock:u`, explicit DWARF unwinding with a 16 KiB stack dump. This samples user-space CPU activity; it does not measure IPC or hardware bottlenecks. Processing disables inline expansion for readability while preserving the raw recording.
- **Scope:** `perf record` surrounds the genuine `python3-dbg -m pyperformance run ...` command, as in the assignment guide. Prepared worker environments and offline package checks reduce preparation surprises, but the framework still executes inside that recording. Whole-invocation scope cannot be removed from aggregate measurements afterward by assumption.

Flamegraph width is inclusive sampled weight, not a chronological interval or a function's exclusive runtime. Shared callers can span the full width. Python 3.10 debug symbols expose native CPython functions; they do not automatically supply Python source-function names to perf. These are interpretation limits, not proof that a wide interpreter frame is a broken graph.

See [docs/ASSIGNMENT.md](docs/ASSIGNMENT.md) for the exact scope and the work that remains yours. No script marks the assignment complete.

## Add this directory to your existing Git repository

This is an additive installation. Keep the previous scripts and results until you decide to archive them. On your Mac, open a terminal **inside the extracted `course-first-three` directory**, then:

```bash
repo='/Users/baselsalameh/Desktop/M.Sc. Technion/Semester 6/HW:SW Co-Design/HW-SW-Co-Design'
mkdir -p "$repo/course-first-three"
rsync -a --exclude '.venv/' --exclude 'venv/' --exclude '.prepared.sha256' --exclude '.workflow.lock' --exclude 'results/' --exclude '__pycache__/' ./ "$repo/course-first-three/"
cd "$repo"
git status --short
git add course-first-three
git diff --cached --stat
git commit -m "Add direct coursework timing and perf workflow"
git branch --show-current
git push -u origin "$(git branch --show-current)"
```

Review any already-staged changes before committing; the commit includes everything staged. The package ignores environments and generated results. This pushes the current branch, not necessarily `main`, and does not merge it.

On the VM, in the existing repository, check `git status` first and preserve any local work. Fetch, switch to the **same branch printed on your Mac**, and pull that branch:

```bash
git fetch origin
# Replace YOUR_BRANCH with the branch printed on your Mac.
git switch YOUR_BRANCH
git pull --ff-only origin YOUR_BRANCH
cd course-first-three
bash setup.sh
bash run_all.sh baseline
```

If you merge your changes into `main` on GitHub first, use `main` instead. This package does not modify Git history, migrate old files, or merge branches for you.
