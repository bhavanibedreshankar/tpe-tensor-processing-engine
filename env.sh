# Source this to set up a shell for ad hoc work against the TPE repo:
#   source env.sh
#
# Sets REPO_ROOT/WORK_DIR, activates the project venv, and resolves the
# external tool binaries this project depends on (verilator/iverilog/
# gtkwave) so ad hoc commands and test-result dumps have somewhere
# consistent to live without hardcoding paths each time.

# Resolve repo root from this file's location, regardless of cwd.
export REPO_ROOT
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

# Scratch space for ad hoc test-result dumps -- lives under sim/logs, which
# .gitignore already excludes wholesale (see sim/logs/.gitkeep).
export WORK_DIR="${WORK_DIR:-$REPO_ROOT/sim/logs/adhoc}"
mkdir -p "$WORK_DIR"

# Project venv (tools/requirements.txt) -- run `make venv` first if missing.
export VENV="$REPO_ROOT/.venv"
if [ -f "$VENV/bin/activate" ]; then
    # shellcheck disable=SC1091
    source "$VENV/bin/activate"
else
    echo "env.sh: $VENV not found -- run 'make venv' to create it" >&2
fi

# External tool references (resolved once here so scripts/README examples
# can just use these vars instead of relying on PATH lookups each time).
export VERILATOR
export IVERILOG
export GTKWAVE
VERILATOR="$(command -v verilator || true)"
IVERILOG="$(command -v iverilog || true)"
GTKWAVE="$(command -v gtkwave || true)"

echo "env.sh: REPO_ROOT=$REPO_ROOT"
echo "env.sh: WORK_DIR=$WORK_DIR"
echo "env.sh: verilator=${VERILATOR:-not found} iverilog=${IVERILOG:-not found} gtkwave=${GTKWAVE:-not found}"
