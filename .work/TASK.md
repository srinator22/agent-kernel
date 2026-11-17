# Task: Faster gates, enforced gates, automatic fleet sync, shorter procedures
Mode: autopilot
Branch: b19/ten
Date: 2026-11-18

## Goal
The owner rated the template 7/10 and said "Do those - aim for a rating of 10" (2026-11-18) for four gaps: (1) the full check and the template self-tests take hours on Windows; (2) gate-label is advisory and the private-terms scan runs only in a local hook, so a leak reached a public branch; (3) a template kernel change strands every project at the last release before it; (4) the procedures are too long to adopt in one sitting. Each gap gets a mechanical fix with a test, measured before and after.

## Non-goals
- Editing the AGENTS.md kernel block (owner approval per instance).
- Rewriting pushed history (85c67ca stays; owner decision).
- Releasing a new template tag (owner action).
- Pushing fleet projects in this task; fleet-sync only prepares local branches.

## Budget
- Wall-clock: one working day
- Subagents / workflow runs: at most 4 workers at once, plus reviewer and monitor (ci-cost.md cap of 8 heavy tasks)
- Retries per failing step: 2
- Escalate to human when: a change needs the kernel block, or a criterion is unreachable

## Assumptions
- [verified] lessons.sh check is the dominant check.sh cost on Windows -> traced run 2026-11-18: 83 s of 109 s for `check.sh --fast`, from per-file grep/awk/sed spawns in shipped_set_errors, twin_errors and handoff_errors
- [verified] test_check_always.sh is the longest self-test file -> tests/template/selftest-weights.txt: 908 s of 3048 s
- [verified] main has no branch protection -> `gh api repos/srinator22/agent-kernel/branches/main/protection` returned 404
- [confirmed] the owner authorized making gate-label required and putting the private-terms list in a CI secret -> "Do those" answering the 7/10 rating's list
- [verified] template-sync stops at any kernel difference -> scripts/template-sync.sh "KERNEL CHANGE: needs owner approval"
- [verified] kernel approval is per project: the kernel header requires human approval for edits and rule 15 allows a standing override only when the human records it in that project's Project decisions -> AGENTS.md kernel header and rule 15; so --accept-kernel is passed by the human, or by fleet-sync only for a project whose Standing overrides line records "template kernel accepted verbatim"
- [verified] the procedures total 1389 lines; the kernel cites procedure paths (AGENTS.md rules 17 and the rules index), so no procedure is renamed or moved -> wc -l docs/procedures/*.md; AGENTS.md

## Acceptance criteria
- [ ] lessons.sh check output is byte-identical before and after the speed-up on the template and on fixtures with each class of problem -> tests/template/test_lessons.sh
- [ ] check.sh --fast on the template on this Windows machine drops from 109 s to under 40 s -> judgment: before/after timing lines recorded in the progress log
- [ ] test_check_always.sh is split so no self-test file exceeds 300 s on Windows CI, and the Windows shard wall time drops -> judgment: CI job durations before and after
- [ ] every split test_check_always*.sh file is a gate file in ci.yml and ADR 0018 -> tests/template/test_ci_gate_files.sh
- [ ] CI fails a pull request whose diff or commit metadata holds a term from the PRIVATE_TERMS secret, without printing the term, and fails when the secret is empty or missing in this repository -> tests/template/test_private_terms.sh
- [ ] gate-label runs on every pull request with if: always() and fails inside the job when paths did not succeed, so it has no skip path; scripts/private-terms.sh is a gate file -> tests/template/test_ci_gate_files.sh
- [ ] main branch protection requires check and gate-label with enforce_admins on -> judgment: gh api read-back of required_status_checks.contexts and enforce_admins.enabled
- [ ] template-sync --accept-kernel applies the template kernel verbatim and runs kernel-hash --update only when the project's kernel equals the kernel of the OLD ref recorded in docs/lessons/MAINTENANCE.log; it stops with KERNEL CHANGE when there is no recorded sync line, when the recorded ref is missing from the template, or when the project kernel differs (CRLF-only differences count as equal) -> tests/template/test_template_sync.sh
- [ ] without --accept-kernel, a kernel difference still stops, and every non-kernel file is still applied so the project is not stranded at the old release -> tests/template/test_template_sync.sh
- [ ] scripts/fleet-sync.sh prepares a sync branch per fleet project without pushing; it passes --accept-kernel only for a project whose AGENTS.md Standing overrides line contains "template kernel accepted verbatim", and otherwise reports KERNEL CHANGE -> tests/template/test_fleet_sync.sh
- [ ] docs/procedures total at most 1100 lines and no procedure over 160 lines (from 1389 and 252), enforced by scripts/doc-budget.sh in check.sh; every anchor in tests/template/fixtures/procedure-anchors.txt (built by N0 from the uncut procedures and committed before N4 starts; the test also checks each anchor is present in docs/procedures at that commit) is still found under docs/, and every path AGENTS.md cites exists -> tests/template/test_doc_budget.sh

## Plan
| node | depends on | owner files | worker tier | status |
|---|---|---|---|---|
| N0 | - | tests/template/fixtures/procedure-anchors.txt | standard | doing |
| N1 | - | scripts/lessons.sh, tests/template/test_lessons.sh | advisor | doing |
| N2 | - | scripts/private-terms.sh, tests/template/test_private_terms.sh, .github/workflows/ci.yml, docs/rules/security.md | standard | doing |
| N3 | - | scripts/template-sync.sh, tests/template/test_template_sync.sh, scripts/fleet-sync.sh, tests/template/test_fleet_sync.sh, docs/procedures/upstream.md, docs/decisions/0020-*.md | standard | doing |
| N4 | N0 | docs/procedures/adr.md, docs/procedures/audit.md, docs/procedures/bugfix.md, docs/procedures/bughunt.md, docs/procedures/ci-cost.md, docs/procedures/discover.md, docs/procedures/doc-eval.md, docs/procedures/dream.md, docs/procedures/longjob.md, docs/procedures/maintain.md, docs/procedures/preferences.md, docs/procedures/retro.md, docs/procedures/ship.md, docs/procedures/start.md, docs/procedures/tests.md | standard | doing |
| N5 | N1 | tests/template/test_check_always.sh, tests/template/test_check_always_project.sh, tests/template/test_check_always_fast.sh, tests/template/test_check_always_selftest.sh, tests/template/test_check_always_reuse.sh, tests/template/test_check_always_template.sh, tests/template/test_check_always_started.sh, tests/template/lib.sh | advisor | doing |
| N6 | N2, N3, N4, N5 | .github/workflows/ci.yml, tests/template/test_ci_gate_files.sh, scripts/check.sh, tests/template/fixtures/check.sh, scripts/doc-budget.sh, tests/template/test_doc_budget.sh, docs/BUDGET, tests/BUDGET, tests/template/selftest-weights.txt, tests/template/selftest-inputs.list, docs/decisions/0018-*.md, BACKLOG.md, README.md, docs/BLUEPRINT.md | advisor | todo |
| N7 | N6 | branch protection on main (GitHub setting) | advisor | todo |

## Plan verdict
PASS - reviewer, round 3 (rounds 1 and 2 FAIL: gate-file pattern for the split files, empty-secret pass, per-project kernel approval, skipped required check, untestable procedure criterion, anchors owned by the cutter; all folded in above)

## Progress log
- 2026-11-18 baseline: check.sh --fast 109 s (lessons.sh check 83 s, adr.sh check 7 s, test-budget 2.6 s); test-budget 12969 lines of 13099.

## Review verdict

## Retro
