# tools/ -- Python infrastructure

| Tool | Purpose | Status |
|---|---|---|
| `regmap_gen.py` | Generates `rtl/include/tpe_regs_pkg.sv`, `model/include/tpe_regs.h`, `docs/register_map/generated/register_map.md` from `docs/register_map/tpe_regs.yaml` | done |
| `common/logger.py` | Shared structured/colorized logging used by every tool below | done |
| `gen_tests.py` | Expands testlist templates + seeds into the 100 daily / 100 random concrete test invocations | M6 |
| `regression.py` | Parallel job-scheduler/regression runner (the local farm/Jenkins-replacement); JUnit XML + summary reports | M6 |
| `cov_merge.py` | Merges per-test Verilator + cocotb-coverage results into one report | M6 |
| `profiler.py` | Per-test wall-clock/cycle-throughput profiling, outlier flagging | M6 |
| `lint.py` | `verilator --lint-only` wrapper across the whole `rtl/` tree + waiver list | M6 |
| `waves.py` | Convenience GTKWave launcher for a given test's dump | M6 |

Run any tool through the project venv (`make venv` first):

```
source .venv/bin/activate
python3 tools/regmap_gen.py
```

or via the top-level `Makefile` wrappers (`make regmap`, etc. -- see
`make help`).
