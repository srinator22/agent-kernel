# Task: ci-watch-quoted-triggers-adr-sections
Mode: quick
Branch: fix/ci-watch-quoted-triggers-adr-sections
Date: 2026-10-23

## Goal
Fix the two findings an automated review raised on the merged PR 5.
P1: `scripts/ci-watch.sh` read an inline event list with a quoted push
(`on: ["push", pull_request]`, `on: 'push'`) as "no push trigger", so the
watcher could skip waiting for that workflow. P2: `scripts/adr.sh check`
never required the `## Context`, `## Decision` and `## Consequences`
sections, so a truncated ADR passed.

## Acceptance criteria
- [x] Quoted inline events are tokenized and unquoted like `flow()` -> `tests/template/test_ci_watch.sh`
- [x] The three ADR sections are required, in order; existing ADRs pass -> `tests/template/test_adr.sh`
- [x] Each new test fails on main first, then passes -> Progress log
- [x] `./scripts/check.sh` green

## Progress log
- 2026-10-23 root causes: `scripts/ci-watch.sh`, `push_filters`, the inline
  `on:` branch stripped brackets but compared the raw text, so a quoted
  "push" never matched; `scripts/adr.sh`, `cmd_check`, no condition on the
  section headings at all
- 2026-10-23 fail-first against main's scripts: `bash tests/template/test_adr.sh`
  36 passed, 4 failed (missing-sections and order cases);
  `bash tests/template/test_ci_watch.sh` 70 passed, 4 failed (quoted-event
  cases). With the fix: 40 passed, 0 failed; 74 passed, 0 failed
- 2026-10-23 `./scripts/check.sh`: EXIT 0 (selftest 12 passed, 0 failed;
  template self-test OK, 111 required files; adr OK, 5 records)

## Review verdict
PASS

Findings: none (no high, medium or low severity findings).

- P1 met. scripts/ci-watch.sh lines 116-119: the inline on: value is split
  on "," and each token goes through the existing unq(), the same
  tokenizing flow() uses; quoted inline lists and quoted scalars give
  TRIGGER push, quoted non-push events give TRIGGER none, "pushx" does not
  match. Tests at tests/template/test_ci_watch.sh 189-200 assert the
  expected list and the absence of "not expected".
- P2 met. scripts/adr.sh lines 75-84: the first "## Context",
  "## Decision" and "## Consequences" are located after stripping CR; a
  missing section or the wrong order fails; other sections may sit between
  or after. All five ADRs pass. Tests at tests/template/test_adr.sh 68-78;
  the shared fixtures in test_adr.sh and test_check_always.sh gained the
  sections with no assertion removed or weakened.
- Fail-first reproduced independently against origin/main scripts:
  test_adr.sh 36/4, test_ci_watch.sh 70/4; with the fix 40/0 and 74/0.
- Six files, all tied to the two findings; no dependency; kernel hash
  unchanged; no dashes, local paths, private names or secrets.

Evidence checked: check-run8.txt complete and clean (kernel-hash OK,
line-budget 79/180, lessons OK, adr OK 5 records, selftest 12 passed
0 failed, template self-test OK, EXIT 0); the full staged diff; probes of
nine on: forms and three ADR shapes in a temp copy; the five ADRs'
headings; test_check_always.sh 37 passed 0 failed in the worktree.

## Retro
Both defects were caught by an automated PR review after merge (route b).
Each now has a regression test shown failing on main first. No lesson
proposed: the checks that would have caught them are the two tests added
here.
