# Validation of this package

Validated on 2026-09-19:

- Bash syntax for all seven shell scripts.
- Both manifests load through the real pyperformance 1.14.0 CLI and select exactly nbody and raytrace. Their source paths, options, and dependency-file paths were checked against that installed version.
- Included benchmark Python files are byte-for-byte identical to the 1.14.0 wheel and the baseline sources in your supplied September 18 results.
- Both original benchmark entry points execute successfully with real pyperf 2.10.0 using tiny development-only inputs. These checks used release CPython 3.12 in the development environment, not the required measurement interpreter; their output is not included as benchmark evidence.
- The production interpreter guard rejects that actual release interpreter.
- Isolated tests with simulated perf/framework commands verify collection order, direct perf child invocation, error propagation, output preservation, invalid-input rejection, source-change detection, and locking.
- Postprocessing tests cover both benchmarks, partial/failed decoding, empty stacks, malformed benchmark lists, incomplete timing data, recovery, and refusal to overwrite completed output. These use the real bundled FlameGraph Perl scripts with simulated recording and timing inputs.

The development environment does not provide the target debug interpreter or Linux perf. Full dependency installation, real debug timing, real perf recording/unwinding, symbol resolution, sample loss, and statistical stability must be checked on the Ubuntu VM. The scripts preserve diagnostics for those checks; successful mock tests are not a claim of successful hardware profiling.

No supplied benchmark results were replaced and no repository migration or optimization was performed.
