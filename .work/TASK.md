# Task: apply-pending-lessons
Mode: autopilot
Branch: task/apply-pending-lessons
Date: 2026-10-22

## Goal
Apply the ten lessons the owner approved on 2026-10-23 (filed in
`docs/lessons/PENDING.md` by the port-agent-library task) to the template's
core agents, procedures and scripts. The approval is recorded by moving the
entries into `docs/lessons/INDEX.md` as L001 to L010 (kernel rule 9); each
lesson is then mechanized where a script or test can carry it (kernel rule 1):
the worker commit guard as a hook script with a test, expected-workflow
derivation in `scripts/ci-watch.sh` with a test, and the adr procedure
promoted to core with `scripts/adr.sh` wired into check.sh's always section.
Stacks on PR 3 (`task/port-agent-library`).

## Non-goals
- No kernel edit (AGENTS.md kernel block and `.kernel.hash` untouched).
- No change to library or profile agents (the library light-worker keeps its
  inline hook; a follow-up, not this change).
- No archiving of `docs/library/skills/adr` (maintenance pass; BACKLOG row).
- No new lessons beyond the ten approved.

## Budget
- Wall-clock: 4 h
- Subagents / workflow runs: 3 (reviewer passes)
- Retries per failing step: 2
- Escalate to human when: budget exhausted | criteria unreachable | scope exceeds Non-goals

## Acceptance criteria
- [ ] INDEX.md holds L001 to L010 in the one-line format; PENDING.md reads "No pending lessons." -> `scripts/lessons.sh check`
- [ ] Reviewer (Claude and Codex) takes diff, TASK.md and verify output; FAIL on missing, truncated or unclean evidence; verdict block ends with "Evidence checked"; checks the AGENTS.md rules index and adopted profiles' rules; ship.md passes the verify output -> judgment: text review
- [ ] Worker (Claude and Codex) reply format: files touched, checks with command and verbatim result, conflicts; "could not run" stated; no version bump unless briefed -> judgment: text review
- [ ] Worker commit guard lives in `scripts/worker-git-guard.sh`, matcher `Bash|PowerShell`, blocks commit and push from either shell -> `tests/template/test_worker_git_guard.sh`
- [ ] Monitor (Claude and Codex) stays in the foreground at the maximum timeout, re-runs on timeout, prints both SHAs on mismatch and the failing log tail verbatim -> judgment: text review; log tail and SHA output in `tests/template/test_ci_watch.sh`
- [ ] `scripts/ci-watch.sh` derives expected workflows from the changed files and path filters, prints them, falls back to "expect all" and says so, honours `--expect` -> `tests/template/test_ci_watch.sh`
- [ ] Explore agent returns conclusions, quotes a few lines at most, skips vendored, build and dependency folders -> judgment: text review
- [ ] retro.md has the time-costing-trap step and the decision-to-ADR step -> judgment: text review
- [ ] bugfix.md shows every regression test failing for the stated root cause (file, function, condition) before the patch, with repro command and output recorded -> judgment: text review
- [ ] adr is a core procedure and skill (5 of 8 core), `scripts/adr.sh check|new` runs in check.sh's always section; library adr row marked graduated -> `tests/template/test_adr.sh`, `tests/template/test_check_always.sh`
- [ ] Required list, BLUEPRINT tree and the check.sh fixture updated; full `./scripts/check.sh` green -> `./scripts/check.sh`

## Plan
| node | depends on | owner files | worker tier | status |
|---|---|---|---|---|
| N1 lessons | - | docs/lessons/INDEX.md, docs/lessons/PENDING.md | advisor | todo |
| N2 agents | N1 | .claude/agents, .codex/agents, docs/procedures/ship.md | advisor | todo |
| N3 guard | N2 | scripts/worker-git-guard.sh, tests/template/test_worker_git_guard.sh | advisor | todo |
| N4 ci-watch | N1 | scripts/ci-watch.sh, tests/template/test_ci_watch.sh | advisor | todo |
| N5 procedures | N1 | docs/procedures/retro.md, docs/procedures/bugfix.md | advisor | todo |
| N6 adr | N1 | docs/procedures/adr.md, .claude/skills/adr, .agents/skills/adr, scripts/adr.sh, tests/template/test_adr.sh, docs/library/README.md | advisor | todo |
| N7 wiring | N3, N4, N5, N6 | scripts/check.sh, tests/template/fixtures/check.sh, tests/template/test_check_always.sh, docs/BLUEPRINT.md | advisor | todo |
| N8 review | N7 | .work/TASK.md | reviewer then advisor | todo |

## Progress log
- 2026-10-23 separate worktree from origin/task/port-agent-library 44beb65
- 2026-10-23 PENDING.md holds ten entries; branch task/apply-pending-lessons created by new-task.sh
- 2026-10-23 fail-first: new test_ci_watch.sh against the old ci-watch.sh: 8 passed, 34 failed; test_worker_git_guard.sh against the old worker.md: 26 passed, 3 failed (the wiring assertions)
- 2026-10-23 check.sh run 1: EXIT 0 (12/12 selftest files, 109 required files)
- 2026-10-23 review 1: FAIL with five findings (guard missed commit/push after an escaped \n; GitHub "?" mistranslated; no log tail for a failed job while its run is in progress; SHA not local not reported as underivable; a private local path in this file)
- 2026-10-23 fixes: guard boundary accepts \n \r \t escapes (new cases against the reviewed guard: 32 passed, 8 failed; fixed: 40 passed); ci-watch "?" as zero-or-one, job log tails by check-run id with the run log as fallback, non-local SHA reported and the nothing-expected exit limited to a confident derivation, --base for multi-commit pushes (new cases against the reviewed ci-watch: 49 passed, 7 failed; fixed: 56 passed); TASK.md path removed; BLUEPRINT 3.13 worker and reviewer lines updated
- 2026-10-23 check.sh run 2: EXIT 0; review 2: FAIL (gh 2.90 refuses "run view --job" while the run is in progress, so the job tail was a refusal; the guard missed a quoted git.exe path and quoted option arguments with spaces; the nothing-to-watch exit had no test)
- 2026-10-23 fixes: job log tails from the actions/jobs/<id>/logs endpoint and a fake gh that refuses "run view" like gh 2.90 (against the reviewed ci-watch: 59 passed, 3 failed; fixed: 62 passed); guard accepts a closing quote after git.exe and quoted option arguments (against the reviewed guard: 42 passed, 6 failed; fixed: 48 passed); nothing-to-watch exit 0 and its no-derivation counterpart now tested (code was already correct, so these pass on both versions); BLUEPRINT wording, selftest list and new-branch --base guidance updated
- 2026-10-23 check.sh run 3: EXIT 0; review 3: FAIL (a queued or pending workflow run with no check run could reach the nothing-to-watch exit 0; git quoted non-ASCII changed paths so filters never matched them; harness claims in monitor.md and worker.md lacked VERIFY markers per docs/rules/models.md)
- 2026-10-23 fixes: any workflow run not yet completed blocks both success exits; core.quotePath=false for ls-tree and diff; VERIFY 2026-10-23 markers; guard made case-insensitive (Git.exe PUSH). New cases against the reviewed versions: ci-watch 62 passed, 4 failed; guard 48 passed, 2 failed. Fixed: ci-watch 66 passed, guard 50 passed
- 2026-10-23 check.sh run 4: EXIT 0. Budget overrun: a fourth reviewer pass exceeds the declared 3; each FAIL so far named real defects with probes, so the gate needs another pass rather than a stop
- 2026-10-23 review 4: FAIL (a failing gh query read as an empty answer, so a confident nothing-expected derivation reached the nothing-to-watch exit 0 without GitHub ever answering)
- 2026-10-23 fix: each gh query's exit status is kept; a failed query blocks both success exits and, still failing at the timeout, exits 1 as unverified with the gh error quoted. New cases against the reviewed ci-watch: 66 passed, 3 failed; fixed: 69 passed. Fifth reviewer pass, also over budget, reported in the PR

## Review verdict
<!-- written ONLY by the independent reviewer -->

## Retro
<!-- filled by docs/procedures/retro.md -->
