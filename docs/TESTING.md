# Validation of this package

## Original package checks

Validated on 2026-09-19 before the direct-worker update:

- Bash syntax for all seven shell scripts.
- Both manifests load through the real pyperformance 1.14.0 CLI and select exactly nbody and raytrace. Their source paths, options, and dependency-file paths were checked against that installed version.
- Included benchmark Python files are byte-for-byte identical to the 1.14.0 wheel and the baseline sources in your supplied September 18 results.
- Both original benchmark entry points execute successfully with real pyperf 2.10.0 using tiny development-only inputs. These checks used release CPython 3.12 in the development environment, not the required measurement interpreter; their output is not included as benchmark evidence.
- The production interpreter guard rejects that actual release interpreter.
- Isolated tests with simulated perf/framework commands verify collection order, direct perf child invocation, error propagation, output preservation, invalid-input rejection, source-change detection, and locking.
- Postprocessing tests cover both benchmarks, partial/failed decoding, empty stacks, malformed benchmark lists, incomplete timing data, recovery, and refusal to overwrite completed output. These use the real bundled FlameGraph Perl scripts with simulated recording and timing inputs.

The development environment does not provide the target debug interpreter or Linux perf. Full dependency installation, real debug timing, real perf recording/unwinding, symbol resolution, sample loss, and statistical stability must be checked on the Ubuntu VM. The scripts preserve diagnostics for those checks; successful mock tests are not a claim of successful hardware profiling.

No supplied benchmark results were replaced and no repository migration or optimization was performed.

## Direct-worker update

The following checks passed on 2026-09-19:

- Both original benchmark scripts ran with real pyperf 2.10.0 in direct worker
  mode, using reduced development inputs (100 nbody steps; 8 x 8 raytrace).
  Each produced one worker, one warmup, and exactly 40 or 10 finite positive
  measured values. The available interpreter was release CPython 3.12: this
  validates the upstream CLI, not debug performance or native recording.
- Collector fixtures used the real profile-manifest parser and simulated
  measurement commands. They checked timing before profiling, direct debug
  worker invocation with `--no-inherit`, framework mode with inheritance,
  timing-only mode without perf, paths containing spaces, failure propagation,
  conflicting flags, source mutation, locking, and overwrite protection.
- The actual interpreter guard rejected release CPython. Metadata listing
  performed no pip invocation; framework stderr still goes to the raw log.
- Postprocessing fixtures covered worker/framework/legacy/timing-only modes,
  decode-depth options, invalid data, empty stacks, failed decoding, retries,
  locking, and refusal to overwrite completed outputs. Native perf output was
  simulated; the bundled FlameGraph tools were real.
- Actual uploaded baseline JSONs passed validation and real pyperf
  show/check/stats. Separate-output processing preserved every input-file hash;
  synthetic capped stacks triggered the expected diagnostic.

The Ubuntu VM must still establish debug-run completion, usable native
symbols/stacks, sample loss, and statistical stability. No supplied results are
reclassified as benchmark-only merely by regenerating their flamegraphs.
