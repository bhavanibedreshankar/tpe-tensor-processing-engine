# Regression Flow

How the M6 tooling turns per-block testbenches into the five test tiers
from [`docs/verification/test_plan.md`](../verification/test_plan.md)
section 2, and how to reproduce, merge coverage for, and profile any run.

## 1. The testlists

`verif/testlists/*.yaml` are the tier definitions, each a flat list of
`{dir, test, seed?}` entries (`dir` = a `verif/cocotb_tb/<dir>/` block,
`test` = the `@cocotb.test()` function name, `seed` = optional, sets
`TPE_SEED` for a `kind: random` test -- see `tools/common/seed.py`).

- `standalone.yaml` -- hand-maintained master catalog of every test in the
  repo, tagged by `kind` (sanity/directed/random/error/integration) and,
  where relevant, an `expect_fail` note pointing at
  [`bug_list.md`](../verification/bug_list.md). Every other tier is a
  subset or expansion of this file.
- `sanity.yaml`, `smoke.yaml` -- hand-curated subsets (fast golden path;
  golden path + directed error/boundary paths).
- `daily.yaml`, `random.yaml` -- **generated**, not hand-edited (same
  "YAML source of truth + generator" convention as
  `docs/register_map/tpe_regs.yaml` + `tools/regmap_gen.py`):
  ```
  make gen-tests   # or: python3 tools/gen_tests.py
  ```
  `daily.yaml` = every `smoke.yaml` entry once, padded out with seeded
  sweeps of each `kind: random` test to ~100 total. `random.yaml` = a pure
  100-seed sweep of those same random-capable tests, no directed entries.
  Seeds walk upward from `--seed-base` (default 10000) across both files,
  so every entry in either tier is distinct and independently reproducible
  (see section 3).

## 2. Running a tier

```
make sanity      # ~6 tests, seconds
make smoke       # ~18 tests, ~1-3 min
make daily       # 100 tests, ~2 min
make random      # 100 tests, ~2 min
```

Each depends on `build-all` (builds every block's Verilator sim binary
once) and, for daily/random, `gen-tests`. Under the hood these all call:

```
python3 tools/regression.py <suite> --jobs N
```

**Parallelism model**: jobs run across different block directories (each
already has one compiled Verilator sim binary, reused per test via
cocotb's `TESTCASE=` selection); tests within the *same* directory run
sequentially, since two concurrent `make` invocations there would race on
that directory's shared `sim_build/`/`results.xml`. `--jobs` (a
`ThreadPoolExecutor` of subprocess calls, not a multiprocessing pool --
the work is I/O-bound `make`/Verilator subprocesses, not CPU-bound Python)
bounds how many directories run concurrently; it does not further
parallelize within one.

**Exit code reflects infrastructure health, not a blanket pass/fail
count**: 0 unless a test `ERROR`ed (no results.xml / harness crash) or
`TIMEOUT`'d. A `FAIL` against a catalogued bug
([`bug_list.md`](../verification/bug_list.md)) is expected and does not
fail the run -- see [`test_plan.md`](../verification/test_plan.md) section
5's bug-injection policy. `regression.py`'s summary prints a reminder to
cross-check any `FAIL` against that file before treating it as a
regression.

## 3. Reproducing a specific failure

Every test's per-run log lands at
`sim/logs/<suite>/<dir>.<test>[.seed<N>].log`. To re-run any single entry
standalone with the exact same seed:

```
TESTCASE=<test> TPE_SEED=<seed> make -C verif/cocotb_tb/<dir>
```

(omit `TPE_SEED` for a non-random entry). This is exactly what
`tools/regression.py` itself runs per entry, so a standalone re-run always
reproduces a regression failure bit-for-bit.

## 4. Coverage merge

Each test overwrites its directory's `coverage.dat` (one shared sim binary
per directory); `tools/regression.py` copies each one out under its own
name to `sim/logs/<suite>/coverage/<tag>.dat` immediately after that test
runs, specifically so it isn't lost before the next test in that
directory starts. Merge and summarize:

```
make cov-merge SUITE=smoke     # or: python3 tools/cov_merge.py smoke
```

writes `sim/logs/smoke/merged_coverage.dat` and prints/writes
`coverage_summary.txt`. Pass `--annotate` (via the Python script directly)
for a per-source annotated report. See
[`coverage_plan.md`](../verification/coverage_plan.md) for what's inside
(line/toggle/branch + RTL-side functional/FSM covergroups, all in the same
Verilator-written `coverage.dat` -- no separate cocotb-coverage merge step
exists because no testbench in this repo uses `cocotb-coverage`'s
CoverPoint/CoverCross; all functional coverage here is the RTL-side SV
covergroup model the architecture settled on from M2 onward).

## 5. Profiling

```
make profile SUITE=daily       # or: python3 tools/profiler.py daily
```

Reads `sim/logs/<suite>/results.json` (written by `regression.py`
alongside its JUnit XML), lists the slowest tests, and flags outliers --
any test whose wall time exceeds 3x its own directory's median (comparing
across directories isn't meaningful; `matrix_engine`/`dma` naturally run
slower per-test than `pmu`/`debug` regardless of anything being wrong).

## 6. Waveforms

```
python3 tools/waves.py <block>   # e.g. dma, top, pmu
```

Opens GTKWave on that block's last simulation's `dump.vcd`, whichever test
last ran there (equivalent to that block's own `make waves`, callable from
anywhere without `cd`-ing in).

## 7. What a "clean" regression looks like

Not all-green. Per the bug-injection policy, a fixed set of `FAIL`s is
expected on every `smoke`/`daily`/`random` run, tracking exactly which
catalogued bugs each tier's tests can reach:

- `matmul_random_test` -- bugs #1/#2 (fires on most seeds: any rolled
  `dim_k < ROWS` or nonzero accumulator seed)
- `matmul_overflow_test` -- bug #3 (always, it's a directed test)
- `dma_multiburst_write_test` -- bug #4 (always, directed);
  `dma_random_test` also hits it on any seed landing on the trigger
  residue (`n_rows % 16 == 1` on a SRAM->DDR transfer) -- see `bug_list.md`
  bug #4 for how M6's 100-seed sweep surfaced this
- `matmul_full_width_test` -- bug #5 (always, directed)
- `irq_independent_clear_test` -- bug #6 (always, directed)
- `latency_test` -- bug #7 (always, directed)
- `sram_cmodel_integration_test` -- bug #8 (always; a golden-model config-
  drift bug, not RTL -- see `bug_list.md`)
- `dma_cmodel_integration_test` -- bug #9 (always, same category as #8)
- `matmul_cmodel_integration_test` -- bug #10 (always, same category as #8)

A run with *fewer* `FAIL`s than this on a tier that includes these tests is
the actual red flag (it means a bug was accidentally fixed, or a test
stopped exercising it) -- see `test_plan.md` section 5.

`run_sim`'s `FAILURE SIGNATURE` column (`docs/flows/run_sim_flow.md`
section 10) shows *which category* caught each: `MismatchError` for #1-#4,
`UVMError`/`UVMFatalError` for #5-#7, `CModelError` for #8-#10 -- see
`bug_list.md`'s header for why these are distinct exception types, not
just distinct message text.

## Why this instead of a real job scheduler

No access to paid CI/farm infrastructure, so `tools/regression.py` is a
from-scratch, dependency-free replacement built on the Python standard
library (`concurrent.futures`, `subprocess`, `xml.etree`) -- no LSF/Slurm/
Jenkins agents needed. It runs identically on a laptop or in GitHub
Actions (see [`ci_flow.md`](ci_flow.md)).
