# Regression Flow

**Status: not yet implemented -- lands in M6.** This stub documents the
intended flow now so the design is settled before `tools/regression.py` is
written; it will be expanded into the real usage doc once that tool exists.

## Intended flow

1. `tools/gen_tests.py` expands `verif/testlists/daily.yaml` /
   `random.yaml` templates + seeds into 100 concrete test invocations each.
2. `tools/regression.py --suite <sanity|smoke|daily|random>` reads the
   corresponding `verif/testlists/*.yaml`, and runs each test as an
   independent job:
   - a `multiprocessing.Pool` sized to `--jobs N` (default
     `os.cpu_count()`) is the local stand-in for a farm/job scheduler
   - each job gets its own working directory under
     `sim/logs/<suite>/<test>/` so parallel runs never collide on
     `sim_build/`
   - per-test timeout, one automatic retry on infrastructure failures
     (not on genuine test failures -- those are real and stay failed)
3. Results are written as JUnit XML (CI-consumable) plus a plain-text/HTML
   summary table (pass/fail/timeout counts, wall-clock).
4. `tools/cov_merge.py` merges every job's `coverage.dat` +
   cocotb-coverage DB into one report (see
   [`coverage_plan.md`](../verification/coverage_plan.md) section 4).
5. `tools/profiler.py` flags outlier tests (wall-clock or sim-cycle
   throughput far from the suite median) so slow tests get noticed before
   they quietly bloat regression time.

## Why this instead of a real job scheduler

The user has no access to paid CI/farm infrastructure, so
`tools/regression.py` is a from-scratch, dependency-free replacement:
Python's standard library `multiprocessing` gives real parallelism without
needing LSF/Slurm/Jenkins agents. It is intentionally simple enough to run
identically on a laptop or in GitHub Actions (see
[`ci_flow.md`](ci_flow.md)).
