# TPE Intentional Bug Catalog

This repo's RTL contains deliberately injected bugs, added block-by-block as
each milestone lands, to prove the verification environment (assertions,
scoreboard, coverage) actually catches real defects. Each entry below is
filled in when its bug is injected -- **not before** -- so this file always
reflects the true current state of the RTL, not a forward-looking plan.

Columns: which test(s) are expected to fail, what the observable symptom is
(assertion fire / scoreboard mismatch / coverage gap), and root cause.

## Status

No bugs injected yet -- M0 (foundation) contains no functional blocks.
Entries are added starting with M2 (Matrix Compute Engine), the first block
with enough behavior to meaningfully misbehave.

| # | Block | File:Line | Symptom | Root cause | Caught by |
|---|---|---|---|---|---|
| _(none yet)_ | | | | | |
