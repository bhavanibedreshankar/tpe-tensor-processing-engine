# TPE Handbook

Every command used across this project's flow, in one place. For the
*why* behind any of these, see [`docs/flows/`](flows/) and
[`docs/verification/`](verification/); this doc is just the *what*.

## Setup

```
brew install verilator gtkwave         # macOS toolchain (Icarus Verilog assumed present)
make venv                              # create .venv/, install cocotb/pyuvm/etc from tools/requirements.txt
source .venv/bin/activate              # activate venv manually (needed for any bare `make -C verif/...` call)
```

## Environment

```
source env.sh                          # REPO_ROOT/WORK_DIR + venv activation + tool paths, in one shot
```
Sets `REPO_ROOT`, `WORK_DIR` (scratch dir for ad hoc test-result dumps,
under the already-gitignored `sim/logs/`), activates `.venv` if present,
and resolves `VERILATOR`/`IVERILOG`/`GTKWAVE` to their absolute paths.
Replaces the manual `source .venv/bin/activate` above when you also want
a scratch dir and resolved tool paths for one-off commands/scripts.

## run_sim (unified test orchestration)

```
./run_sim -test <test>                            # resolves the block dir itself, no -C needed
./run_sim -test <test> -seed <seed>                # reproducible seed (random-kind tests only)
./run_sim -test <test> -coverage -waves            # + coverage report + open GTKWave after
./run_sim -suite <sanity|smoke|daily|random>       # run a whole tier
./run_sim -suite <suite> -jobs N -coverage -farm   # parallel + merged coverage ("-farm" today
                                                    # == local parallel, no remote scheduler wired up)
./run_sim -lint [-block <name>]                    # tools/lint.py
./run_sim -clean [-test <test>|-suite <suite>]     # wipe work dirs (everything if neither given)
./run_sim -list                                    # every test in verif/testlists/standalone.yaml
```
Every generated file (`sim_build/`, `results.xml`, `dump.vcd`,
`coverage.dat`, `<block>_scoreboard_work/`) lands under
`$WORK_DIR/WORK/<dir>.<test>[.seed<N>]/` (single `-test`) or
`$WORK_DIR/WORK/<suite>/<dir>.<test>[.seed<N>]/` (`-suite`) --
`verif/cocotb_tb/<dir>/` is never touched. `source env.sh` first (sets
`WORK_DIR`; falls back to `sim/logs/adhoc` otherwise). `-work-dir-name`
overrides the `WORK` top-level dirname. This sits alongside every command
above -- nothing here changes, `run_sim` just orchestrates it without
touching the source tree.

Example:
```
source env.sh
./run_sim -test dma_random_test -seed 12345 -coverage
./run_sim -suite smoke -jobs 8 -coverage -annotate
./run_sim -clean -suite smoke
```

## Register map

```
make regmap                            # regen rtl/include/tpe_regs_pkg.sv, model/include/tpe_regs.h,
                                        # verif/cocotb_tb/env/tpe_regs.py, docs/register_map/generated/*
                                        # source: docs/register_map/tpe_regs.yaml -- edit that, never the outputs
```

## Lint

```
make lint                              # every rtl/ block, tools/lint.py is the source of truth
python3 tools/lint.py                  # same, direct
python3 tools/lint.py --block tpe_dma  # lint one block only
```

## C++ golden model

```
make model                             # builds model/tpe_model CLI + runs its unit tests
```

## Toolchain smoke test

```
make toolchain-smoke                   # proves cocotb+pyuvm+Verilator+coverage+waveform all work
```

## Per-block simulation (one shot)

```
make sim-sram                          # M1 Local SRAM
make sim-matrix-engine                 # M2 Matrix Compute Engine
make sim-dma                           # M3 DMA Engine
make sim-top                           # M4/M5 top-level end-to-end
make sim-pmu                           # M5 PMU
make sim-debug                         # M5 Debug infra
```

## Running a single test

```
TESTCASE=<test> make -C verif/cocotb_tb/<block>                       # run one named test
TESTCASE=<test> TPE_SEED=<seed> make -C verif/cocotb_tb/<block>       # ...with a reproducible seed
make -C verif/cocotb_tb/<block> waves                                 # open that block's last dump.vcd
make -C verif/cocotb_tb/<block> clean-all                             # wipe that block's build/sim artifacts
```
Example:
```
TESTCASE=matmul_sanity_test make -C verif/cocotb_tb/matrix_engine
TESTCASE=dma_random_test TPE_SEED=12345 make -C verif/cocotb_tb/dma
make -C verif/cocotb_tb/dma waves
make -C verif/cocotb_tb/dma clean-all
```
`<block>` = `sram` / `matrix_engine` / `dma` / `top` / `pmu` / `debug` /
`smoke`. Full test catalog: [`verif/testlists/standalone.yaml`](../verif/testlists/standalone.yaml).

## Regression tiers

```
make build-all                         # build every block's sim binary once (prereq, runs automatically)
make gen-tests                         # regen verif/testlists/daily.yaml + random.yaml
make sanity                            # ~6 tests, seconds
make smoke                             # ~18 tests, ~1 min
make daily                             # 100 tests, ~2 min
make random                            # 100 tests, ~2 min
python3 tools/regression.py <suite> --jobs N --timeout N   # direct, any suite name
```
Example: `python3 tools/regression.py smoke --jobs 8 --timeout 120`

Some `FAIL`s on smoke/daily/random are expected (7 catalogued bugs) --
see [`docs/verification/bug_list.md`](verification/bug_list.md). Exit
code only goes nonzero on `ERROR`/`TIMEOUT`.

## Coverage

```
make cov-merge SUITE=smoke                       # merge that suite's coverage.dat + cocotb-coverage XML
python3 tools/cov_merge.py smoke --annotate      # ...plus a per-source annotated report
```

## Profiling

```
make profile SUITE=daily                         # slowest tests + per-directory outliers
python3 tools/profiler.py daily --top 20 --outlier-factor 2.5
```

## Waveforms

```
python3 tools/waves.py dma             # opens that block's last sim dump in GTKWave
```

## Cleanup

```
make clean                             # remove sim/build artifacts (keeps generated docs/register files)
make distclean                         # clean + remove .venv/
```

## Help

```
make help                              # list every Makefile target with its one-line description
```

## Git / GitHub

```
git config --global user.name "<name>"
git config --global user.email "<email>"

git add <files>
git commit -m "message"
git push

gh auth status                                             # check GitHub CLI auth
gh repo create <name> --public --source=. --remote=origin  # create repo + add as origin
git push -u origin main                                    # first push, sets upstream

gh api -X POST repos/<owner>/<repo>/pages \
  -f "source[branch]=main" -f "source[path]=/docs"          # enable GitHub Pages from docs/
```
Example:
```
git config --global user.name "bhavanibedreshankar"
git config --global user.email "bedreshankarbhavani@gmail.com"

git add docs/HANDBOOK.md README.md
git commit -m "Add a command handbook"
git push

gh repo create tpe-tensor-processing-engine --public --source=. --remote=origin
git push -u origin main

gh api -X POST repos/bhavanibedreshankar/tpe-tensor-processing-engine/pages \
  -f "source[branch]=main" -f "source[path]=/docs"
```
