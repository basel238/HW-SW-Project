# First three coursework steps: nbody and raytrace

A small shell workflow for benchmark study, unprofiled pyperformance timing, and perf flamegraphs. Benchmark sources stay unchanged. Both timing and profiling use the verified **CPython debug build**. There is no custom Python workload wrapper, FIFO/ACK protocol, cProfile, py-spy, optimization, or automated bottleneck analysis.

Timing runs through genuine pyperformance. **The default profile directly launches the original benchmark script in its existing pyperf worker mode**, using the same prepared worker environment. This avoids recording the outer pyperformance manager and its pip checks. Interpreter startup, imports, warmup, pyperf bookkeeping/metadata inside the worker, and shutdown remain in the recording; this is not a hot-loop-only or zero-overhead measurement. Timing and profiling are separate executions.

## Run on the Ubuntu VM

Run setup after installing this update, even if the previous version was already prepared. It creates the checked `python3-dbg` alias in the worker environment.

```bash
cd ~/HW-SW-Project
bash setup.sh
bash run_all.sh baseline
```

On Ubuntu, `bash setup.sh --install-system` also installs missing debug Python and matching perf system packages. Ordinary setup prepares the Python environments without collecting measurements. Keep the VM quiet and do not run another benchmark or analysis concurrently.

`baseline` is an output label. Existing run directories are never overwritten. Omit the label to use a fresh timestamped name.

To separate collection from processing explicitly:

```bash
bash collect.sh all baseline-2
bash postprocess.sh results/baseline-2
```

For only one benchmark, use `bash script_nbody.sh nbody-check` or `bash script_raytrace.sh raytrace-check`. Both collect and then process; setup must already be complete.

To repeat unprofiled raytrace timing without collecting another profile:

```bash
bash collect.sh --timing-only raytrace raytrace-timing-2
bash postprocess.sh results/raytrace-timing-2
```

That run produces timing evidence and a timing report, with no perf recording or flamegraph. Keep the original run, including any slow samples. The mode flags belong to `collect.sh`; the convenience wrappers accept only a run label.

## Optional profile matching the guide's invocation

The assignment's guide places perf around `python3-dbg -m pyperformance run ...`. The default direct-worker profile deliberately narrows that scope. To also collect the guide-style whole-framework profile:

```bash
bash collect.sh --framework-profile all guide-reference
bash postprocess.sh results/guide-reference
```

This records the manager, dependency checks, workers, startup, and warmup as well as benchmark computation. Use its graph with that scope stated. It also collects separate unprofiled timing. `--framework-profile` and `--timing-only` cannot be combined.

For the example's 999 Hz frequency, prefix collection with `SAMPLE_HZ=999`; the default is 199 Hz. A higher frequency adds samples, recording overhead, and data. Neither the default direct-worker experiment nor the optional guide experiment automatically certifies coursework compliance: see [docs/ASSIGNMENT.md](docs/ASSIGNMENT.md).

## Reprocess old recordings without rerunning the benchmarks

This update decodes stacks with `--max-stack 512`, replacing perf script's default 127-frame limit. It retains `--no-inline` for readability and the existing DWARF recording format. A larger decode limit cannot recover stack data that was never captured, and some stacks can still be incomplete.

For example, preserve the earlier baseline and write a new set of derived results:

```bash
bash postprocess.sh --output results/baseline-redecoded results/baseline
```

The destination must not already exist. It contains derived reports/graphs and `origin.txt`, which points back to the original run; timing JSONs and raw perf recordings are not duplicated. The original measurements are preserved and no benchmark is executed. Run decoding on the collection VM while retaining the original binaries and environments for symbol resolution. Inspect the generated report's stack-depth/missing-root warnings before interpreting a changed graph. Older runs without `raw/collection-mode.txt` are treated as whole-framework recordings, which was their original scope.

If processing an incomplete run was interrupted, fix the error and use `bash postprocess.sh --retry results/LABEL`. Retry regenerates incomplete derived outputs and does not replace completed output. Use `--output` to derive a separate view of an already completed run.

## Scripts and folders

| Path | Purpose |
|---|---|
| `setup.sh` | Install/verify dependencies, prepare debug environments, check interpreter identity, and record source/configuration hashes |
| `collect.sh` | Collect unprofiled timing, then a separate profile unless `--timing-only`; log exact commands and retain raw evidence |
| `postprocess.sh` | Read existing evidence; produce timing statistics, compact native self-time tables, and perf flamegraphs |
| `run_all.sh` | Collect both benchmarks and then postprocess |
| `script_nbody.sh`, `script_raytrace.sh` | Collect and postprocess just the named benchmark |
| `scripts/common.sh` | Shared shell validation, paths, locks, and configuration helpers |
| `benchmarks/` | Unchanged original benchmark scripts, active dependency lists, provenance, and license |
| `manifests/timing/` | Timing source paths and workload/worker settings |
| `manifests/profile/` | Profile settings used by both direct-worker and optional framework collection |
| `vendor/FlameGraph/` | Bundled stack-collapse and SVG generation tools, provenance, and license |
| `docs/` | Assignment mapping and validation notes |
| `reports/` | Unanswered templates for your benchmark understanding and interpretation |
| `results/` | Generated runs, excluded from Git |
| `.venv/`, `venv/` | Launcher and pyperformance-managed worker environments, excluded from Git |

Small Python commands validate configuration and read metadata **before recording**. They do not import or wrap the benchmark computation. Profiling invokes the upstream benchmark script directly; that script contains the original pyperf harness.

## Results to open first

| File under `results/LABEL/` | Purpose |
|---|---|
| `run.txt` | Exact commands, collection settings, interpreter and environment record |
| `nbody.json`, `raytrace.json` | Unprofiled pyperformance timing results for the selected benchmarks |
| `nbody.svg`, `raytrace.svg` | Interactive perf flamegraphs, absent for timing-only runs |
| `report_nbody.txt`, `report_raytrace.txt` | Timing summaries, warnings, stack diagnostics, and compact native self-time tables where profiles exist |
| `raw/` | Binary recordings, profile JSON, logs, source/settings snapshots, and compressed folded stacks |
| `raw/collection-mode.txt` | `worker`, `framework`, or `timing-only`; identifies measurement scope |

The profile JSON contains instrumented measurements; it must not replace the unprofiled timing JSON. Shell command durations in `run.txt` are operational information, not benchmark timing. Completion markers report tool completion, not successful academic analysis. Write your own explanation in the separate `reports/report_*.txt` templates.

Heavy processing occurs after collection. Decoding debug stacks can take longer than recording. Keep the raw recordings so later processing changes do not require new measurements.

```bash
.venv/bin/python3-dbg -m pyperf show results/baseline/nbody.json
.venv/bin/python3-dbg -m pyperf stats results/baseline/nbody.json
.venv/bin/python3-dbg -m pyperf show results/baseline/raytrace.json
```

## Measurement choices and limits

- **Interpreter:** setup uses `python3-dbg`; validation requires `Py_DEBUG=1` and the same real executable in both environments. A filename or Python's `-d` flag alone does not prove a debug build.
- **Source:** original nbody and raytrace from pyperformance 1.14.0. Active benchmark dependencies are beside `benchmarks/NAME/run_benchmark.py`.
- **Timing:** 20 sequential worker processes, three measured values each, one warmup, one loop per value. This is a fixed protocol, not a guarantee of statistical stability.
- **Profiling:** one direct worker by default, one warmup, one loop per value; 40 nbody values or ten raytrace values. The profile settings are read from the existing manifests before perf starts.
- **Workload:** 20,000 nbody steps or a 100 × 100 raytrace image per call. Nbody state evolves between calls; a 40-call profile follows a longer trajectory than each three-value timing worker.
- **Sampling:** `cpu-clock:u`, 199 Hz by default, DWARF with a 16 KiB stack dump. This measures sampled user-space CPU activity, not IPC or hardware bottlenecks. Collection still has overhead.
- **Child processes:** direct-worker collection uses `--no-inherit`; these original benchmarks compute in the worker's single main thread, so helper processes such as `lsb_release` are excluded. Framework mode retains inheritance so its actual benchmark workers are recorded. Reconsider this choice before substituting a threaded or multiprocess workload.
- **Scope:** direct-worker graphs include startup, imports, warmup, computation, worker-side harness metadata, and shutdown. Whole-framework graphs additionally include the outer manager and its dependency checks. Percentages from the two scopes have different denominators.

Flamegraph width is inclusive sampled weight, not a chronological interval or exclusive runtime. Shared callers can legitimately span the entire width. Python 3.10 native debug symbols expose CPython functions; they do not automatically supply Python source-function names. Deep or unresolved stacks require investigation, not an automatic conclusion that the benchmark is recursive or broken.

## The distutils deprecation warning

Python 3.10 can emit `DeprecationWarning` when the installed pip imports distutils. This warning does not mean the command failed or that a release interpreter was used. Check exit status and completion, and retain diagnostics.

Our environment summary now lists installed distributions through `importlib.metadata`, so it does not start pip merely to print versions. Genuine pyperformance timing and optional framework profiling still perform their own pip checks; warnings from those commands remain in the raw collection log. We do not silence all warnings, edit benchmark code, or upgrade the measurement interpreter to hide this message.

## Git updates

This project uses `git@github.com:basel238/HW-SW-Project.git`. On your Mac, review and commit changes in:

```bash
cd '/Users/baselsalameh/Desktop/M.Sc. Technion/Semester 6/HW:SW Co-Design/HW-SW-Project'
git status
git branch --show-current
git apply --check "$HOME/Downloads/hw-sw-project-worker-update.patch" && \
  git apply "$HOME/Downloads/hw-sw-project-worker-update.patch"
git diff
git add -- README.md collect.sh postprocess.sh setup.sh scripts/common.sh \
  docs/ASSIGNMENT.md docs/TESTING.md prompt.txt \
  reports/report_nbody.txt reports/report_raytrace.txt \
  manifests/profile/nbody/requirements.txt \
  manifests/profile/raytrace/requirements.txt \
  manifests/timing/raytrace/requirements.txt
git diff --cached --stat
git commit -m "Profile debug benchmark workers directly and improve stack decoding"
git push origin HEAD
```

Apply the patch once, against the original `course-first-three` package. If the
check fails because your local files differ, stop and review the differences;
do not force application or replace your local work. The three deleted manifest
dependency lists were unused duplicates; active requirements remain beside the
benchmark scripts. Review the staged changes before committing, including any
changes that were already staged before this update.

After pushing, update the VM on that same branch between runs. For `main`:

```bash
cd ~/HW-SW-Project
git status
git branch --show-current
git pull --ff-only origin main
bash setup.sh
bash run_all.sh
```

Preserve local work before pulling. Setup is required after this update. Existing result directories remain intact and the new run uses a fresh label. No script changes Git history, pushes commits, or migrates your old files.
