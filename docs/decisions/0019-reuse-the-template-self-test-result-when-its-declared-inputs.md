# 0019 - Reuse the template self-test result when its declared inputs are unchanged

Date: 2026-11-18
Status: accepted

## Context

Every full `scripts/check.sh` runs the template's own self-tests (step 4g,
`scripts/selftest.sh`, tests of the template's tooling, not of the
project). On the owner's Windows machine one run takes 20 to 60 minutes, and
a project pays it on every full check even when its change touched only its
own code, which the self-tests never read. A CI cost survey of 2026-11-17
(Vincent Koc, "Making OpenClaw CI faster and 95% cheaper") reuses a result
whose inputs are unchanged and treats an unknown dependency as a reason to
run more, never to skip.

Selecting self-tests from the diff (`check.sh --fast`) stays a local lane
that says it is not the full gate: a selector can miss, and nothing proves
it complete. Reuse needs a proof instead.

## Decision

- `tests/template/selftest-inputs.list` declares every repository path the
  self-tests read: whole directories where in doubt, and `exists:` entries
  whose presence matters but whose content does not.
- `scripts/selftest-reuse.sh key` hashes the declared inputs' working
  content plus the bash, git, OS, python and ruff identity. After a green self-test run
  outside CI, `record` stores the key in the git dir (per worktree, never
  tracked or synced). Step 4g skips the self-tests only when `check`
  matches that key.
- Unknown means run: a missing list, a missing record or a changed key runs
  the suite; CI never reuses; `CHECK_SELFTEST=full` forces a run.
- The list is proven complete, not trusted: `selftest-reuse.sh
  verify-inputs` runs the suite in a copy that holds only the declared
  inputs, with `exists:` entries emptied, and the CI `selftest-inputs` job
  runs it on main and on pull requests that change scripts/, tests/template/
  or the workflow.

## Consequences

- A project whose change leaves every declared input alone skips the
  template self-tests in its local full check; CI still runs them in full
  for the exact pushed SHA (kernel rule 5).
- A test that starts reading a new path must add it to the list, or
  verify-inputs fails in CI.
- A tool outside the key can change without a key change; after such an
  upgrade run `CHECK_SELFTEST=full ./scripts/check.sh`.
- check.sh takes the key before the suite runs and records it only when the
  key is unchanged after a pass, so an input edited during the run (the
  detached stop gate lets the agent keep working) is tested again.
- The list declares docs/ by path (the procedures, rules, profiles,
  decisions, lessons, library, roster and preferences folders and a few
  files), so a project's own other docs do not break reuse; verify-inputs
  is the proof any narrowing needs.
