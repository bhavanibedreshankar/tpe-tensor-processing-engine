# CI/CD Flow

## GitHub Actions (primary, free)

`.github/workflows/regression.yml` (must live under `.github/workflows/`
for GitHub Actions to discover it -- it previously sat under
`ci/github/workflows/`, which is not a path Actions scans, so it never
actually ran):
- on every push/PR: `make lint` + `make smoke`, artifacts uploaded from
  `sim/logs/smoke/`
- on a nightly schedule (06:00 UTC): `make daily` + `make cov-merge
  SUITE=daily` + `make profile SUITE=daily`, artifacts uploaded from
  `sim/logs/daily/` (includes the merged coverage report)
- on manual `workflow_dispatch`: `make random`, artifacts uploaded from
  `sim/logs/random/`

Installs Verilator + GTKWave via `apt-get` (Icarus Verilog is this repo's
secondary/cross-check simulator, not needed for the primary Verilator-based
regression tiers CI runs) before `make venv`. This is the primary,
"just works" CI for anyone who pushes this repo to GitHub -- no
self-hosted infrastructure required, free tier is sufficient for a project
this size. `tools/regression.py`'s exit code reflects infrastructure
health only (nonzero solely on `ERROR`/`TIMEOUT`, i.e. the harness itself
breaking) -- a `FAIL` against a catalogued bug in
`docs/verification/bug_list.md` is expected and does not fail the
`make smoke` step or the CI job, so the intentionally-injected RTL bugs
show up as FAILs in the uploaded JUnit artifact without turning the
push/PR check red.

## Jenkins (reference only, optional)

`ci/jenkins/Jenkinsfile` is a declarative pipeline that calls the exact
same `make` targets as the GitHub Actions workflow (lint+smoke on a normal
build, `make daily`+coverage+profile on the nightly cron trigger, `make
random` when the `RUN_RANDOM` parameter is set). It is provided for users
who already run their own Jenkins controller and assumes Verilator/Icarus/
GTKWave are already installed on the agent (unlike the GitHub Actions
workflow, it does not install them itself). **Not exercised in this
development environment** (no Jenkins instance is available here), so
treat it as a documented reference implementation rather than something
CI-tested by this repo's own regressions.

## Why `make` is the seam

Both CI backends -- and a developer's laptop -- invoke the same `make`
targets (`lint`, `sanity`, `smoke`, `daily`, `random`, `regmap`). The CI
config files are thin wrappers that decide *when* to run things and *where*
to upload artifacts; they contain no logic of their own. This keeps the
"real" regression behavior reproducible outside of any CI product.
