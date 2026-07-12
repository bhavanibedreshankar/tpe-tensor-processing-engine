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
`__pycache__` straight into that block's source directory, and fully
recompiles the Verilator binary on every single invocation regardless of
whether any RTL changed (see section 4). `run_sim` fixes both: every
generated file lands under `$WORK_DIR` instead of the source tree, and a
block's compiled binary is built once and reused by every test that
targets it.

## 2. Setup

```
source env.sh      # sets WORK_DIR (see docs/HANDBOOK.md "Environment")
make venv          # first time only
```

`run_sim` itself execs `.venv/bin/python3` directly, so `source
.venv/bin/activate` isn't required -- but `env.sh` is worth sourcing for
`WORK_DIR` (falls back to `sim/logs/adhoc` if unset).

## 3. The pipeline: four stages, each with its own directory

Running a test is split into four independently-tracked stages instead of
one monolithic `make` call:

| Stage | What it does | Scope | Directory |
|---|---|---|---|
| `filelist` | Resolves the block's `VERILOG_SOURCES`/`EXTRA_ARGS`/`TOPLEVEL`/`MODULE` (`make -p -n` against its Makefile) and hashes the source content | per block, cached | `_cache/<dir>/filelist/` |
| `model_build` | `make -C model` -- the C++ golden model the scoreboards shell out to at runtime | global, one instance | `_cache/model_build/` |
| `compile` | `verilator -cc --exe` + C++ build → the block's `Vtop` binary | per block, **shared/reused** across every test targeting that block | `_cache/<dir>/compile/` |
| `rtl_sim` | Runs the compiled `Vtop` binary against one `TESTCASE`/seed | per test | `<tag>/rtl_sim/` |

Every stage writes a `status.json` (state/timing/cached-or-not) to its own
directory as it runs -- see `-monitor` (section 6) to read them back.

## 4. Why compile is reusable, and why rtl_sim bypasses make

The obvious way to reuse a compile is to point `SIM_BUILD` at a directory
that persists across test runs and let Verilator's own incremental `-Mdir`
compile skip regenerating anything unchanged. That works correctly on a
normal filesystem -- confirmed empirically it does *not* work reliably
inside this sandbox, because the project directory's mount doesn't
preserve the sub-second mtime precision Verilator's incremental check
depends on (identical repeated compiles against `/tmp` correctly no-op;
the identical repeated compile against a directory under this repo's own
tree never did, redoing the full ~7s build every time).

So `run_sim` doesn't trust that mechanism:

- `filelist` computes a SHA-256 hash of the block's actual source file
  *content* (plus `EXTRA_ARGS`/`TOPLEVEL`/`MODULE`) -- filesystem-mtime
  independent.
- `compile` compares that hash against the one recorded next to the last
  successful build (`_cache/<dir>/compile/built_hash.txt`) and **skips
  invoking `make` entirely** when they match, rather than invoking make
  and hoping it/Verilator no-ops quickly.
- `rtl_sim` then runs the resulting `Vtop` binary **directly** (not via
  `make -C block_dir` again). This matters even when the hash says
  "unchanged": any `make` invocation that re-evaluates `Vtop.mk`'s rule
  re-triggers `verilator -cc`, because that recipe has a phony `model`
  prerequisite (`verif/cocotb_tb/*/Makefile`) and GNU Make always re-runs
  a target's recipe when a phony prerequisite is remade. On a filesystem
  with reliable mtimes that's a harmless ~1-2s no-op re-verify; on this
  one it's a full rebuild -- so `rtl_sim` never gives Make the chance,
  replicating just the env vars/argv the Makefile recipe would otherwise
  set (`MODULE`/`TESTCASE`/`TOPLEVEL`/`TOPLEVEL_LANG`/
  `COCOTB_RESULTS_FILE`/`LIBPYTHON_LOC`/`PYTHONPATH`, `cwd=block_dir`),
  using the `TOPLEVEL`/`MODULE`/`EXTRA_ARGS` the `filelist` stage already
  resolved.

Net effect, measured on this repo: `dma_sanity_test` cold (nothing built
yet) takes ~10s; every subsequent test against `dma` -- the same test
again, or a different one, in the same run or a later `run_sim`
invocation -- takes ~0.2-0.4s, because `compile` reports `cached` and
`rtl_sim` never touches Make. `-clean -block <dir>` (section 6) forces the
next test against that block to rebuild for real.

## 5. Directory layout

```
$WORK_DIR/<work-dir-name, default "WORK">/
├── _cache/                                 # shared, reused across every run
│   ├── model_build/
│   │   ├── status.json
│   │   └── build.log
│   └── <dir>/
│       ├── filelist/
│       │   ├── status.json
│       │   ├── sources.txt
│       │   ├── vars.json           # TOPLEVEL/MODULE/EXTRA_ARGS
│       │   └── hash.txt
│       └── compile/
│           ├── status.json
│           ├── build.log
│           ├── built_hash.txt      # hash this sim_build/ was last built from
│           └── sim_build/          # the compiled Vtop binary -- shared/reused
├── <dir>.<test>[.seed<N>]/                 # one --test run
│   ├── console.log                 # everything printed this run (see section 12)
│   └── rtl_sim/
│       ├── status.json
│       ├── results.xml
│       ├── run.log
│       ├── dump.vcd                # only kept here if -waves was passed, else deleted
│       ├── coverage.dat            # only kept here if -coverage was passed, else deleted
│       ├── <dir>_scoreboard_work/  # swept out of the source tree
│       └── coverage/               # only created if -coverage was passed
│           ├── coverage.dat
│           ├── <tag>.dat
│           ├── merged_coverage.dat
│           └── coverage_summary.txt
└── <suite>/                                # one --suite run
    ├── console.log                         # everything printed this run
    ├── <dir>.<test>[.seed<N>]/rtl_sim/     # same per-test contents as above
    ├── regression.xml                      # aggregate JUnit
    └── coverage/                           # only if -coverage was passed, shared
        ├── <tag>.dat                       # across every test in the suite
        ├── merged_coverage.dat
        └── coverage_summary.txt
```

`<tag>` is `"<dir>.<test>"`, plus `.seed<N>` when a seed is set -- same
naming convention `tools/regression.py` uses under `sim/logs/<suite>/`.
Nothing under `verif/cocotb_tb/` is ever written to. `coverage.dat`/
`dump.vcd` are always produced by the simulator regardless of flags
(every block Makefile hardcodes coverage instrumentation and tracing at
compile time, see [`build_flow.md`](build_flow.md) section 4) -- without
`-coverage`/`-waves` they're deleted right after the run instead of kept.

## 6. Options

Every option accepts both a single- and double-dash spelling
(`-test`/`--test`, etc.) -- pick whichever reads better.

| Flag | Meaning |
|---|---|
| `-test NAME` | Run one test. Its block dir is looked up in `verif/testlists/standalone.yaml` (the master catalog) automatically. |
| `-suite {sanity,smoke,daily,random,standalone}` | Run every entry in `verif/testlists/<suite>.yaml`. Mutually exclusive with `-test`. |
| `-seed N` | `TPE_SEED` override, only meaningful with `-test` on a `kind: random` entry. Suite entries carry their own per-test seed from the testlist YAML -- `-seed` doesn't apply there. |
| `-jobs N` | Max concurrent block directories for `-suite` (default: `nproc`). Tests within the same block directory always run sequentially -- see [`regression_flow.md`](regression_flow.md) section 2 for why. |
| `-timeout N` | Per-test timeout in seconds (default 120). |
| `-farm` | Runs the same local parallel execution as a plain `-suite` run; today this is a naming placeholder only (no remote scheduler wired up), see section 9. |
| `-coverage` | Keep this run's `coverage.dat`, merge/report it via `tools/cov_merge.py` (imported directly, its own verbose per-hierarchy dump swallowed -- see section 10) -- works with `-test` or `-suite`. |
| `-annotate` | With `-coverage`, also write a per-source annotated report (`verilator_coverage --annotate`). |
| `-lint` | Runs `tools/lint.py` (`verilator --lint-only` across `rtl/`). Independent of `-test`/`-suite`. |
| `-block NAME` | With `-lint`, lint only that block. With `-clean`, remove only that block's `_cache/` entry (forces its next compile to rebuild for real). |
| `-waves` | Keep this run's `dump.vcd` and open it in GTKWave afterward. Requires `-test` (ambiguous which test's waves to open for a `-suite`). |
| `-clean` | Removes work dirs under `$WORK_DIR/<work-dir-name>`. Scope with `-test NAME` (that test's dir only), `-suite NAME` (that suite's whole subtree), or `-block NAME` (just that block's compile cache); with none of those, wipes everything under the work-dir-name root, including `_cache/`. |
| `-monitor` | Combined with `-test`/`-suite`: a single page (cleared and redrawn every second, not a scrolling feed) showing every stage's state/duration/cached-or-not, live, until that run finishes -- per-task one-line notices are suppressed for the run's duration since this page already shows the same thing. Standalone (no `-test`/`-suite`): prints the last run's final status and exits. |
| `-watch` | With a *standalone* `-monitor` (no `-test`/`-suite`), keep re-polling every 2s (Ctrl-C to stop) instead of a single snapshot -- e.g. from a second terminal, watching a `-test`/`-suite` run in a first one. |
| `-list` | Prints every test in `verif/testlists/standalone.yaml` (name, block dir, kind, `expect_fail`) and exits. |
| `-work-dir-name NAME` | Overrides the top-level dir name under `$WORK_DIR` (default `WORK`). |

## 7. Examples

```
./run_sim -test dma_sanity_test
./run_sim -test dma_random_test -seed 12345 -coverage
./run_sim -test matmul_overflow_test -waves            # opens GTKWave once done
./run_sim -suite smoke -jobs 8 -coverage -annotate
./run_sim -suite daily -farm
./run_sim -lint -block tpe_dma
./run_sim -suite smoke -monitor -coverage               # live-watch this run's own stages
./run_sim -monitor                                      # standalone: snapshot of the last run
./run_sim -monitor -watch                               # standalone: live, from a second terminal
./run_sim -clean -suite smoke
./run_sim -clean -block dma                             # force dma's next compile to rebuild
./run_sim -clean                                        # wipe every work dir, including _cache/
./run_sim -list
```

## 8. Exit codes

- `-test`: `0` if the test's status is `PASS`, `1` otherwise (`FAIL`,
  `ERROR`, or `TIMEOUT`). If the test has an `expect_fail` note in
  `standalone.yaml`, a `FAIL` still exits `1` but prints which catalogued
  bug ([`bug_list.md`](../verification/bug_list.md)) it corresponds to --
  useful for ad hoc debugging, where you want a straight pass/fail signal
  for the one test you're looking at.
- `-suite`: matches `tools/regression.py`'s philosophy -- `0` unless a
  test `ERROR`ed or `TIMEOUT`'d (an infrastructure failure, which includes
  a `compile` stage failure). A `FAIL` against a catalogued bug is
  expected across a whole tier and does not fail the run; cross-check the
  printed summary against `bug_list.md` before treating a `FAIL` as a
  regression.

## 9. What `-farm` actually does today

There's no compute farm (LSF/Slurm/Jenkins agents) wired up in this
project -- `-farm` runs identically to a plain `-suite` run (the same
`ThreadPoolExecutor`-based local parallelism `tools/regression.py` uses,
see [`regression_flow.md`](regression_flow.md)'s "Why this instead of a
real job scheduler" section). It exists as a CLI placeholder so the
interface doesn't need to change if a real scheduler gets wired in later.

## 10. The end-of-run summary, and why coverage doesn't dump a giant report

Every `-test`/`-suite` run ends with a `SUMMARY` block: a per-stage
breakdown (how many `filelist`/`model_build`/`compile`/`rtl_sim` tasks
ran, how many were cache hits, `rtl_sim`'s pass/fail split) built from
every `record_task()` call this process made, plus a `Coverage:` section
(only shown if `-coverage` was passed) and a `Waves:` line (only if
`-waves` actually opened one) -- i.e. only the sections for whatever you
actually enabled:

```
============================================================
SUMMARY
============================================================
Tasks:
  model_build : 1 run, 1 cached (0.0s)
  filelist    : 7 run (17.4s)
  compile     : 18 run, 12 cached (75.9s)
  rtl_sim     : 18 run -- 13 passed, 5 failed (7.0s)

Coverage:
  line 83.9%, toggle 54.4%, branch 82.5%, covergroup 66.9%
  full report: .../smoke/coverage_summary.txt
============================================================
```

Every `FAIL`/`ERROR` also carries a **failure signature** -- the last
`SomeError: message`-shaped line pulled out of that test's raw
`rtl_sim/run.log` (`_failure_signature()`, `tools/run_sim.py`; cocotb's
own `results.xml` failure message is just a generic
`"Test failed with RANDOM_SEED=..."`, no detail). It shows up everywhere
a `FAIL`/`ERROR` does: the `-suite` results table's `FAILURE SIGNATURE`
column, `-monitor`'s `NOTES / FAILURE SIGNATURE` column, a single
`-test`'s own `failure: ...` line, and the JUnit `message=` attribute.
Truncated to 80 chars for table display; `run.log` always has the
untruncated text.

`-coverage` itself only prints three short notices --
`coverage: started`, `coverage: processing...`, `coverage: done` (or the
actual error, if `tools/cov_merge.py` raises one) -- swallowing
`merge_verilator()`'s own verbose per-hierarchy console dump (still
written in full to `coverage_summary.txt` either way; the summary above
is a condensed `line`/`toggle`/`branch`/`covergroup` reading of that same
file's top few lines, not a separate calculation).

## 12. console.log

Every `-test`/`-suite` run tees everything durable it prints -- its own
`log.info`/`[stage]` lines, `tools/cov_merge.py`'s notices, the final
`SUMMARY` block -- to `<tag>/console.log` (`-test`) or
`<suite>/console.log` (`-suite`), in addition to the terminal, so it's
still there after the terminal scrolls away or the session closes.
`console_log()` (`tools/run_sim.py`) re-points the `run_sim`/`cov_merge`/
`lint` loggers' `StreamHandler`s at the tee explicitly, not just
`sys.stdout = tee` -- those loggers were already constructed (at import
time, bound to the *original* stdout object) before any run starts, so a
bare reassignment wouldn't have reached them.

**Deliberately not teed**: the live `-monitor` page's repeated
clear-and-redraw (section 6) writes directly to the real terminal stream
`main()` captures *before* `console_log()` swaps `sys.stdout` --
`_monitor_background()` never calls `print()`/touches `sys.stdout` at
all, so its redraws never reach the file. A page every second for a
suite's whole duration would otherwise balloon console.log with
thousands of near-duplicate snapshots; the file is meant to hold the
durable record (what ran, cache hits, pass/fail, the final coverage
score), not a replay of the live view.

## 13. A gotcha worth knowing if you extend this

`SIM_BUILD`, unlike `COCOTB_RESULTS_FILE`, can't be redirected via a plain
environment variable when going through `make` -- every block's Makefile
has `SIM_BUILD := sim_build` (a hard assignment, see
`verif/cocotb_tb/*/Makefile`), which silently overrides anything supplied
through the environment (`:=` doesn't defer to it the way cocotb's own
`SIM_BUILD ?= sim_build` default does). `run_compile()`
(`tools/run_sim.py`) passes it as a `make VAR=value` command-line
override instead, which beats any in-Makefile assignment regardless of
`:=`/`=`/`?=`. `run_rtl_sim()` sidesteps the whole question by not calling
`make` at all (section 4) -- if you ever need to add a new block-Makefile
variable to the `compile` stage specifically, use the same command-line
override approach there.

Separately, `tools/cov_merge.py`'s log lines used to assume its output
always lives under `REPO_ROOT` (`path.relative_to(REPO_ROOT)`, for a
tidy relative path in the log) -- that raises `ValueError` once `WORK_DIR`
points outside the repo (an intentional, documented option, see
`docs/HANDBOOK.md`'s "Environment" section), which `run_sim -coverage`
hit immediately. Fixed with a `_display()` helper that falls back to the
absolute path when `relative_to()` fails, used everywhere `cov_merge.py`
had that pattern.
