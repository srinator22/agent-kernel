# 0018 - Gate changes need a human label

Date: 2026-11-17
Status: accepted

## Context

CI judges a pull request with the gate files that pull request carries:
`scripts/check.sh`, the self-test runner and its helpers, the workflows,
and the reviewer brief the agent reads. A change can therefore weaken the
check that judges it in the same diff, for example drop a step from
check.sh or loosen an assertion in test_check_always.sh, and still go
green. Kernel rule 2 forbids that in prose; nothing enforced it.

Two designs were on the table.

- Run the base commit's gate against the change: check out the base
  commit's check.sh, quickgate.sh, kernel-hash.sh, tests/template/ and
  reviewer brief into a separate folder and run them on the pull request's
  tree. It lost because the template's gate and its tests describe
  behaviour: a pull request that changes a script and its test on purpose
  fails the base test, and a pull request that changes check.sh fails the
  base check.sh's own fixture-identity step (5i) or the new tests the
  change adds. Every legitimate gate change would turn red, so the run
  could never be required, and an always-red job teaches people to ignore
  it. The reviewer brief is read by an agent session, not by CI, so CI
  cannot run "the base brief" at all.
- Fail a pull request that changes a gate file until a human marks it as
  reviewed. Small, honest about what it proves, and it puts the human on
  exactly the diffs where rule 2 can be broken.

## Decision

The `paths` job in `.github/workflows/ci.yml` lists the gate files a pull
request changes: scripts/check.sh, scripts/quickgate.sh,
scripts/kernel-hash.sh, scripts/selftest.sh, .kernel.hash,
tests/template/lib.sh, tests/template/fixtures/check.sh, the tests of
those scripts (test_check_always.sh, test_quickgate.sh,
test_kernel_hash.sh, test_selftest.sh), .claude/agents/reviewer.md,
.codex/agents/reviewer.toml, .github/workflows/* and
docs/rules/ci-baseline.md. When any is changed, the `gate-label` job
fails unless the pull request carries the label `gate-change`. The job
reads the labels live through the API with `pull-requests: read` only,
so after a human reviews the gate change and adds the label, re-running
the failed job passes. Other test files stay with the reviewer gate:
adding or extending tests is the normal shape of a change, and a label on
every pull request would be noise.

## Consequences

- A gate change cannot merge green without a human having looked at it,
  as far as the monitor and ci-watch.sh treat a red job as a failure.
- Limits, stated plainly:
  - The label proves a human with write access added it, not that the
    review was good; the change to the gate itself still needs human
    review, and this job only forces the question.
  - `gate-label` is not a required check in branch protection; a person
    merging by hand past a red job is not stopped. Making it required is
    the owner's call.
  - Anyone (or any agent) holding a token with label rights can add the
    label. Agents must not add `gate-change`; the owner does.
  - A gate weakened through a file outside the list (another script that
    check.sh calls, such as lessons.sh) is not caught here; the reviewer
    gate remains the control for those.
  - The workflow file is itself in the list, so a pull request that edits
    ci.yml to drop this job still runs the edited workflow; the label job
    then simply does not exist. GitHub runs a pull request's own workflow
    file, and only a required check or a base-branch ruleset prevents
    that.

## Amendment 2026-11-18

The owner made the label binding ("Do those", answering the 2026-11-18
rating): `gate-label` runs on every pull request with `always()` and fails
itself when the paths job did not succeed, so a skipped job can no longer
count as passing; main's branch protection requires `check`, `gate-label`,
`private-terms` and `adopted-project` with `enforce_admins` on, so the owner's token, which
agents use, cannot merge past them either. The gate-file list now also
holds `tests/template/test_check_always*.sh` (the file split into six) with
their shared `tests/template/check_always_lib.sh`, and
`scripts/private-terms.sh`, which the `private-terms` CI job runs.
tests/template/test_ci_gate_files.sh pins the list and the no-skip shape.
