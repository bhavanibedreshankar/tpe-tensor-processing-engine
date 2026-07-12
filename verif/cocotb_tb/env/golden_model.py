"""Helper for invoking the C++ golden-model CLI (model/build/tpe_model)
from a pyuvm scoreboard's report_phase. See model/README.md for why this is
a subprocess call to a built binary rather than a Python binding."""
import os
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]
TPE_MODEL_BIN = REPO_ROOT / "model" / "build" / "tpe_model"


def run_tpe_model(*args: str) -> None:
    if not TPE_MODEL_BIN.exists():
        raise FileNotFoundError(f"{TPE_MODEL_BIN} not found -- run `make -C model` first")
    result = subprocess.run([str(TPE_MODEL_BIN), *args], capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(f"tpe_model {' '.join(args)} failed (rc={result.returncode}): {result.stderr}")
    # Only tpe_model's own TPE_LOG(...) output (model/include/Verbosity.hpp)
    # lands on stderr when TPE_VERBOSITY is set (see run_sim -verbosity) --
    # print it through so it interleaves with the RTL's own `TPE_LOG_*
    # (rtl/include/tpe_verbosity.svh) in this test's console/run.log instead
    # of being silently discarded by capture_output=True above.
    if os.environ.get("TPE_VERBOSITY") and result.stderr:
        print(result.stderr, end="" if result.stderr.endswith("\n") else "\n", file=sys.stderr)
