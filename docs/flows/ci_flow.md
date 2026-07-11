# CI/CD Flow

**Status: not yet implemented -- lands in M6.** This stub documents the
intended flow now so the design is settled before the workflow files are
written.

## GitHub Actions (primary, free)

`ci/github/workflows/regression.yml` (added in M6) will:
- on every push/PR: `make lint` + `make smoke`
- on a nightly schedule: `make daily` + `tools/cov_merge.py`, uploading the
  coverage report and regression summary as build artifacts
- on manual `workflow_dispatch`: `make random`

This is the primary, "just works" CI for anyone who pushes this repo to
GitHub -- no self-hosted infrastructure required, free tier is sufficient
for a project this size.

## Jenkins (reference only, optional)

`ci/jenkins/Jenkinsfile` (added in M6) will be a declarative pipeline that
calls the exact same `make` targets as the GitHub Actions workflow. It is
provided for users who already run their own Jenkins controller; it is
**not exercised in this development environment** (no Jenkins instance is
available here), so treat it as a documented reference implementation
rather than something CI-tested by this repo's own regressions.

## Why `make` is the seam

Both CI backends -- and a developer's laptop -- invoke the same `make`
targets (`lint`, `sanity`, `smoke`, `daily`, `random`, `regmap`). The CI
config files are thin wrappers that decide *when* to run things and *where*
to upload artifacts; they contain no logic of their own. This keeps the
"real" regression behavior reproducible outside of any CI product.
