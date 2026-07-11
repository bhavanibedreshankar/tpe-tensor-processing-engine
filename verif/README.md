# verif/ -- verification environment

| Directory | Contents | Status |
|---|---|---|
| `cocotb_tb/smoke/` | Toolchain smoke test (throwaway DUT) | done, see its own README |
| `cocotb_tb/env/` | Reusable pyuvm base driver/monitor/scoreboard/env classes every block subclasses | added in M1 |
| `cocotb_tb/<block>/` | Per-block pyuvm environment + sequences | added per block's milestone |
| `sva/` | SystemVerilog Assertions, bound into the DUT via `bind` (not embedded in `rtl/`) | added per block's milestone |
| `coverage/` | Functional/cross/FSM covergroups | added per block's milestone |
| `testlists/` | `standalone.yaml`/`sanity.yaml`/`smoke.yaml`/`daily.yaml`/`random.yaml` -- test tier definitions consumed by `tools/regression.py` | added in M6 |

See [`docs/verification/test_plan.md`](../docs/verification/test_plan.md)
for methodology and per-tier sizing, and
[`docs/verification/coverage_plan.md`](../docs/verification/coverage_plan.md)
for how coverage is modeled and merged.
