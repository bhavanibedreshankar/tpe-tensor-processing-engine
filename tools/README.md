# tools/ -- Python infrastructure

| Tool | Purpose | Status |
|---|---|---|
| `regmap_gen.py` | Generates `rtl/include/tpe_regs_pkg.sv`, `model/include/tpe_regs.h`, `verif/cocotb_tb/env/tpe_regs.py`, `docs/register_map/generated/register_map.md` from `docs/register_map/tpe_regs.yaml` | done |
| `common/logger.py` | Shared structured/colorized logging used by every tool below | done |
| `common/seed.py` | `TPE_SEED` env-var override for every block's `*_random_test`, letting `regression.py` sweep seeds | done (M6) |
| `gen_tests.py` | Expands `verif/testlists/standalone.yaml` + `smoke.yaml` into `daily.yaml` (100 tests) / `random.yaml` (100 tests) | done (M6) |
| `regression.py` | Parallel job-scheduler/regression runner (the local farm/Jenkins-replacement); JUnit XML + JSON + summary reports | done (M6) |
| `cov_merge.py` | Merges per-test Verilator coverage.dat files into one report (`verilator_coverage`) | done (M6) |
| `profiler.py` | Per-test wall-clock profiling from a regression's results.json, outlier flagging | done (M6) |
| `lint.py` | `verilator --lint-only` wrapper across every `rtl/` block + per-block waivers (source of truth for `make lint`) | done (M6) |
| `waves.py` | Convenience GTKWave launcher for a given block's last waveform dump | done (M6) |
| `run_sim.py` | Unified test orchestrator (`../run_sim` at repo root) -- resolves a test name to its block dir, splits a run into filelist/model_build/compile/rtl_sim stages (each its own cached directory under `$WORK_DIR`, a block's compile is reused across every test targeting it), plus suites/coverage/lint/waves/clean/`-monitor`; sits alongside everything above, doesn't replace it | done |

See [`docs/flows/regression_flow.md`](../docs/flows/regression_flow.md) for
how these fit together (testlists -> regression -> coverage/profiling).

Run any tool through the project venv (`make venv` first):

```
source .venv/bin/activate
python3 tools/regmap_gen.py
```

or via the top-level `Makefile` wrappers (`make regmap`, etc. -- see
`make help`).
