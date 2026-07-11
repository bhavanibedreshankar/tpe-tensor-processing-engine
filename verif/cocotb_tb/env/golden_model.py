"""Helper for invoking the C++ golden-model CLI (model/build/tpe_model)
from a pyuvm scoreboard's report_phase. See model/README.md for why this is
a subprocess call to a built binary rather than a Python binding."""
import subprocess
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]
TPE_MODEL_BIN = REPO_ROOT / "model" / "build" / "tpe_model"


def run_tpe_model(*args: str) -> None:
    if not TPE_MODEL_BIN.exists():
        raise FileNotFoundError(f"{TPE_MODEL_BIN} not found -- run `make -C model` first")
    result = subprocess.run([str(TPE_MODEL_BIN), *args], capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(f"tpe_model {' '.join(args)} failed (rc={result.returncode}): {result.stderr}")
