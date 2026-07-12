# run_sim

`./run_sim` (root-level exec wrapper around `tools/run_sim.py`) is the
single entry point for running tests without hand-typing
`-C verif/cocotb_tb/<dir>` and without any generated file landing in the
source tree. It sits *alongside* the flows in
[`build_flow.md`](build_flow.md), [`regression_flow.md`](regression_flow.md)
and `tools/cov_merge.py`/`lint.py`/`waves.py` -- none of that changes or
is required; `run_sim` just orchestrates it.

## 1. Why this exists

`make -C verif/cocotb_tb/<dir> TESTCASE=<test>` writes `sim_build/`,
`results.xml`, `dump.vcd`, `coverage.dat`, `<dir>_scoreboard_work/` and
`__pycache__` straight into that block's source directory. They're
gitignored, but they still clutter `verif/cocotb_tb/<dir>/` while you
work. `run_sim` redirects everything it can (`SIM_BUILD`,
`COCOTB_RESULTS_FILE`, the trace/coverage file paths are all make-variable
overrides the per-block Makefiles already respect) and sweeps up the rest
(scoreboard work dirs, sram's `coverage.xml`, `__pycache__` -- these are
hardcoded relative `Path("...")` names inside each block's
`scoreboard.py`/`coverage.py` and can't be redirected) into one place
under `$WORK_DIR`, so `verif/cocotb_tb/<dir>/` is clean before and after
every run.

## 2. Setup

```
source env.sh      # sets WORK_DIR (see docs/HANDBOOK.md "Environment")
make venv          # first time only
```

`run_sim` itself execs `.venv/bin/python3` directly, so `source
.venv/bin/activate` isn't required -- but `env.sh` is worth sourcing for
`WORK_DIR` (falls back to `sim/logs/adhoc` if unset).

## 3. Directory layout

```
$WORK_DIR/<work-dir-name, default "WORK">/
├── <dir>.<test>[.seed<N>]/            # one --test run
│   ├── sim_build/                     # this run's Verilator build
│   │   ├── coverage.dat               # always produced (every block Makefile hardcodes
│   │   │                              # --coverage-line/-toggle/-user, see section 8) but left
│   │   │                              # buried here unless -coverage was passed
│   │   └── dump.vcd                   # always traced (--trace/--trace-structs, same story) but
│   │                                  # left buried here unless -waves was passed
│   ├── results.xml                    # cocotb JUnit for this test
│   ├── run.log                        # full make stdout/stderr
│   ├── <dir>_scoreboard_work/         # swept out of the source tree
│   ├── dump.vcd                       # only surfaced here if -waves was passed
│   └── coverage/                      # only created if -coverage was passed
│       ├── coverage.dat               # copy of sim_build/coverage.dat, surfaced at top level
│       ├── <tag>.dat
│       ├── merged_coverage.dat
│       └── coverage_summary.txt
└── <suite>/                           # one --suite run
    ├── <dir>.<test>[.seed<N>]/        # same per-test contents as above (-waves isn't
    │                                  # valid with -suite, so dump.vcd always stays buried)
    ├── regression.xml                 # aggregate JUnit
    └── coverage/                      # only created if -coverage was passed, shared
        ├── <tag>.dat                  # across every test in the suite
        ├── merged_coverage.dat
        └── coverage_summary.txt
```

`<tag>` is `"<dir>.<test>"`, plus `.seed<N>` when a seed is set -- same
naming convention `tools/regression.py` uses under `sim/logs/<suite>/`.
Nothing under `verif/cocotb_tb/` is ever written to, and nothing
coverage- or waveform-related shows up above `sim_build/` unless
`-coverage`/`-waves` is passed -- see section 8.

## 4. Options

Every option accepts both a single- and double-dash spelling
(`-test`/`--test`, etc.) -- pick whichever reads better.

| Flag | Meaning |
|---|---|
| `-test NAME` | Run one test. Its block dir is looked up in `verif/testlists/standalone.yaml` (the master catalog) automatically. |
| `-suite {sanity,smoke,daily,random,standalone}` | Run every entry in `verif/testlists/<suite>.yaml`. Mutually exclusive with `-test`. |
| `-seed N` | `TPE_SEED` override, only meaningful with `-test` on a `kind: random` entry. Suite entries carry their own per-test seed from the testlist YAML -- `-seed` doesn't apply there. |
| `-jobs N` | Max concurrent block directories for `-suite` (default: `nproc`). Tests within the same block directory always run sequentially -- see [`regression_flow.md`](regression_flow.md) section 2 for why. |
| `-timeout N` | Per-test timeout in seconds (default 120). |
| `-farm` | Runs the same local parallel execution as a plain `-suite` run; today this is a naming placeholder only (no remote scheduler wired up), see section 7. |
| `-coverage` | After the run, merge/report coverage via `tools/cov_merge.py` (imported directly, not subprocessed) -- works with `-test` or `-suite`. |
| `-annotate` | With `-coverage`, also write a per-source annotated report (`verilator_coverage --annotate`). |
| `-lint` | Runs `tools/lint.py` (`verilator --lint-only` across `rtl/`). Independent of `-test`/`-suite`. |
| `-block NAME` | With `-lint`, lint only that block. |
| `-waves` | Opens GTKWave on the run's `dump.vcd` afterward. Requires `-test` (ambiguous which test's waves to open for a `-suite`). |
| `-clean` | Removes work dirs under `$WORK_DIR/<work-dir-name>`. Scope with `-test NAME` (that test's dir only) or `-suite NAME` (that suite's whole subtree); with neither, wipes everything under the work-dir-name root. |
| `-list` | Prints every test in `verif/testlists/standalone.yaml` (name, block dir, kind, `expect_fail`) and exits. |
| `-work-dir-name NAME` | Overrides the top-level dir name under `$WORK_DIR` (default `WORK`). |

## 5. Examples

```
./run_sim -test dma_sanity_test
./run_sim -test dma_random_test -seed 12345 -coverage
./run_sim -test matmul_overflow_test -waves            # opens GTKWave once done
./run_sim -suite smoke -jobs 8 -coverage -annotate
./run_sim -suite daily -farm
./run_sim -lint -block tpe_dma
./run_sim -clean -suite smoke
./run_sim -clean                                        # wipe every work dir
./run_sim -list
```

## 6. Exit codes

- `-test`: `0` if the test's status is `PASS`, `1` otherwise (`FAIL`,
  `ERROR`, or `TIMEOUT`). If the test has an `expect_fail` note in
  `standalone.yaml`, a `FAIL` still exits `1` but prints which catalogued
  bug ([`bug_list.md`](../verification/bug_list.md)) it corresponds to --
  useful for ad hoc debugging, where you want a straight pass/fail signal
  for the one test you're looking at.
- `-suite`: matches `tools/regression.py`'s philosophy -- `0` unless a
  test `ERROR`ed or `TIMEOUT`'d (an infrastructure failure). A `FAIL`
  against a catalogued bug is expected across a whole tier and does not
  fail the run; cross-check the printed summary against `bug_list.md`
  before treating a `FAIL` as a regression.

## 7. What `-farm` actually does today

There's no compute farm (LSF/Slurm/Jenkins agents) wired up in this
project -- `-farm` runs identically to a plain `-suite` run (the same
`ThreadPoolExecutor`-based local parallelism `tools/regression.py` uses,
see [`regression_flow.md`](regression_flow.md)'s "Why this instead of a
real job scheduler" section). It exists as a CLI placeholder so the
interface doesn't need to change if a real scheduler gets wired in later
-- swap the `subprocess.run(["make", ...])` call in `run_one()`
(`tools/run_sim.py`) for a submission call and everything upstream
(test resolution, work-dir layout, coverage merge) stays the same.

## 8. Why `-coverage`/`-waves` don't fully suppress coverage.dat/dump.vcd

Every block Makefile hardcodes `--trace --trace-structs` in addition to
`--coverage-line --coverage-toggle --coverage-user`
([`build_flow.md`](build_flow.md) section 4) at compile time, so Verilator
always traces (produces a `dump.vcd`) the same way it always instruments
coverage -- `run_sim` doesn't control either, only where the file lands.
Without `-waves`, `dump.vcd` is redirected into `sim_build/dump.vcd` and
left there; with `-waves`, it's redirected to the top level of the result
dir and opened in GTKWave once the run finishes.

Every block Makefile hardcodes `--coverage-line --coverage-toggle
--coverage-user` ([`build_flow.md`](build_flow.md) section 4) at compile
time, so Verilator always instruments and writes a `coverage.dat`
regardless of whether you asked for it -- `run_sim` doesn't control that,
only where the file lands. Without `-coverage`, it's redirected into
`sim_build/coverage.dat` (an already-expected build-scratch location) and
otherwise ignored: no top-level `coverage.dat`, no `coverage/` dir, no
merge/report. With `-coverage`, it's redirected to the top level of the
result dir instead, and copied into `coverage/<tag>.dat` for
`tools/cov_merge.py` to merge/summarize. Same story for sram's TB-side
`sram_coverage.xml` (produced unconditionally by
`verif/cocotb_tb/sram/coverage.py`, swept out of the source tree either
way -- kept under `coverage/` only when `-coverage` is passed, discarded
otherwise).

## 9. A gotcha worth knowing if you extend this

`SIM_BUILD`, unlike `COCOTB_RESULTS_FILE`/`SIM_ARGS`/`PLUSARGS`, can't be
redirected via an environment variable -- every block's Makefile has
`SIM_BUILD := sim_build` (a hard assignment, see
`verif/cocotb_tb/*/Makefile`), which silently overrides anything supplied
through the environment (`:=` doesn't defer to it the way cocotb's own
`SIM_BUILD ?= sim_build` default does). `tools/run_sim.py` passes all of
`TESTCASE`/`SIM_BUILD`/`COCOTB_RESULTS_FILE`/`SIM_ARGS`/`PLUSARGS`/
`TPE_SEED` as `make VAR=value` command-line overrides instead, uniformly
-- those beat any in-Makefile assignment regardless of `:=`/`=`/`?=`. If
you add a new redirected variable here, use the same command-line-override
approach rather than env vars.
