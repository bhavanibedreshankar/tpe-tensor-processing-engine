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
