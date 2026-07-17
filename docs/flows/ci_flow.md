# CI/CD Flow

## GitHub Actions (primary, free)

`.github/workflows/regression.yml` (must live under `.github/workflows/`
for GitHub Actions to discover it -- it previously sat under
`ci/github/workflows/`, which is not a path Actions scans, so it never
actually ran):
- on every push/PR: `./run_sim -lint` + `./run_sim -suite smoke`,
  artifacts uploaded from `$WORK_DIR/WORK/smoke/`
- on a nightly schedule (06:00 UTC): `./run_sim -suite daily -coverage
  -annotate`, artifacts uploaded from `$WORK_DIR/WORK/daily/` (includes
  the merged coverage report -- `-coverage` drives `tools/cov_merge.py`
  the same way `make cov-merge` used to; there's no `run_sim` equivalent
  of the old `make profile`/`tools/profiler.py` step yet, since that tool
  reads `tools/regression.py`'s `results.json` output, which `run_sim`
  doesn't produce, so it was dropped rather than left silently broken)
- on manual `workflow_dispatch`: `./run_sim -suite random`, artifacts
  uploaded from `$WORK_DIR/WORK/random/`

Each job sets `WORK_DIR` to an **absolute** path
(`${{ github.workspace }}/sim/logs/ci`) before calling `run_sim` --
`run_sim`'s `compile` stage invokes `make -C verif/cocotb_tb/<dir>
SIM_BUILD=$WORK_DIR/...`, and since `-C` changes `make`'s own working
directory, a relative `WORK_DIR` resolves against the wrong directory and
every compile silently fails with a "0 modules" Verilator no-op. Confirmed
locally before this was ever pushed to CI.

Builds Verilator 5.050 from source (`actions/cache`-keyed on `runner.os`,
so only the first run per cache generation pays the ~10-minute build --
Ubuntu's `apt-get` package is version 5.020, which predates Verilator's
`covergroup` support entirely and hard-errors on
`verif/coverage/*_cov.sv`; README.md's toolchain table pins 5.050
specifically, which is also what local development uses) plus GTKWave via
`apt-get` (Icarus Verilog is this repo's secondary/cross-check simulator,
not needed for the primary Verilator-based regression tiers CI runs)
before `make venv` (still needed -- `run_sim` execs `.venv/bin/python3`
directly, so the venv has to exist first, but nothing beyond that goes
through `make`). This is the primary,
"just works" CI for anyone who pushes this repo to GitHub -- no
self-hosted infrastructure required, free tier is sufficient for a project
this size (the repo is public, so Actions minutes and artifact storage are
both free/unmetered). `run_sim -suite <tier>`'s exit code reflects
infrastructure health only (nonzero solely on `ERROR`/`TIMEOUT`, i.e. the
harness itself breaking, same philosophy as `tools/regression.py`'s exit
code) -- a `FAIL` against a catalogued bug in
`docs/verification/bug_list.md` is expected and does not fail the
`run_sim -suite smoke` step or the CI job, so the intentionally-injected
RTL bugs show up as FAILs (with their failure signature) in the uploaded
JUnit artifact without turning the push/PR check red.

## Jenkins (reference only, optional -- currently stale relative to GitHub Actions)

`ci/jenkins/Jenkinsfile` still calls the `make lint`/`make smoke`/`make
daily`+coverage+profile/`make random` targets, i.e. the flow GitHub
Actions moved off of when it switched to `run_sim`. It hasn't been
updated to match (no Jenkins instance is available in this development
environment to validate a `run_sim`-based rewrite against), so treat it as
a `make`-based reference implementation, not a mirror of what GitHub
Actions currently runs. It is provided for users who already run their
own Jenkins controller and assumes Verilator/Icarus/GTKWave are already
installed on the agent (unlike the GitHub Actions workflow, it does not
install them itself).

## Why GitHub Actions runs `run_sim` directly, not `make`

Unlike Jenkins (still `make`-only, see above), the GitHub Actions workflow
calls `./run_sim -lint` / `-suite <tier>` directly -- the same commands a
developer runs locally after `source env.sh` (see
`docs/flows/run_sim_flow.md`), rather than going through `make lint`/`make
smoke`/etc. `make venv` is still a prerequisite step (creates the venv
`run_sim`'s wrapper execs into), and `make`-based `tools/regression.py`
still exists and works standalone -- `run_sim` was designed to sit
alongside it, not replace it (see `tools/run_sim.py`'s module docstring)
-- but GitHub Actions' own regression tiers now exercise the `run_sim`
path specifically, since that's the tool this project is actively
developed against.
