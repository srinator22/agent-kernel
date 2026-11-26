# Task: b21 backlog wave - papercuts, fast selection, final verdict wiring
Mode: standard
Branch: claude/gracious-fermat-f7u5de
Date: 2026-11-26

## Goal
Work every open BACKLOG.md row that can be built inside this repository in
this session: papercuts (agent-filed friction reports), the check.sh --fast
selection that runs 12 heavy tests whenever .work/TASK.md changes, and the
mechanical wiring of tasklint.sh final into the ship path. Record why each
other open row is not started.

## Non-goals
<!-- explicitly out of scope; scope creep gets caught here -->
- Fleet projects (rows: sync lagging projects, ci-cost in each project, the
  fleet half of cancel-superseded-runs): this session reaches one repository.
- Kernel wording row: kernel edits need the owner's wording and approval.
- Rows whose trigger has not fired or that are recorded as cannot close
  (flicker calibration, audio, paper simulation, multi-machine rendering,
  owner rewrites, running-task count).
- Test consolidation campaign: it rewrites tests/template while three nodes
  add tests there; it runs as its own task after this wave.
- Papercuts never become rules on their own (kernel rule 9), and no new
  skill is added (kernel rule 10 cap).

## Budget
<!-- declare before work starts; on exhaustion: stop, keep the best verified
     artifact, and report unresolved items with reasons - never hide a partial
     result behind a fluent answer -->
- Wall-clock: 3 hours
- Subagents / workflow runs: 3 workers, 1 reviewer, 1 monitor
- Retries per failing step: 2
- Escalate to human when: budget exhausted | criteria unreachable | scope exceeds Non-goals
- Shared budgets: docs/procedures has 34 words of headroom (10166/10200),
  so each node is net-zero there; tests have 383 lines of headroom
  (13289 against 13272 + 400): N1 60, N2 80, N3 220.
- Reducer: each worker edits its own worktree and commits nothing; the
  advisor applies N1, then N2, then N3 onto the branch, resolves overlap in
  scripts/check.sh and docs/BLUEPRINT.md by hand, and runs the full gate
  after each.

## Assumptions
<!-- one line per assumption the work rests on: [confirmed] the human said so,
     [verified] -> evidence (a command or file), [open] not yet settled.
     scripts/tasklint.sh ship (the full gate) fails while any line is [open],
     except in quick mode -->
- [confirmed] The owner asked on 2026-11-26 to start papercuts and the other backlog rows in parallel with agents.
- [open] Papercut storage: a gitignored local log under .work/, as the feedback log is; the owner has not chosen between local and committed.
- [open] Papercut filing: scripts/papercut.sh plus one session-context line that names it; no skill, no kernel edit.
- [open] Papercut cap: 200 entries, oldest dropped at add time with a stderr line; each text field at most 300 characters.
- [open] Papercut false reports: a required refusal field (correct, wrong, none); the dream digest counts correct refusals apart and never proposes from them.
- [open] The acceptance criteria below are the advisor's draft; the owner has not approved them (kernel rule 4).
- [verified] The template CI already cancels superseded pull-request runs -> .github/workflows/ci.yml concurrency block (cancel-in-progress on pull_request).
- [verified] check.sh fails under a POSIX locale before any real check -> `git grep -P` exits 128 on `\x{2013}`; workers run the gate with LANG=C.UTF-8 LC_ALL=C.UTF-8.
- [open] Three unrelated changes land on one branch and one pull request, because this session may push to one branch only.

## Acceptance criteria
<!-- each maps to an executable test where possible; list test paths. A ticked
     line needs "-> <existing path>" or "-> judgment: <reason>"
     (scripts/tasklint.sh check) -->
- [ ] N1: a change to a path that tests/template/selftest-inputs.list declares `exists:` selects no test by name, with a reason line on stderr; any other path selects as before -> tests/template/test_check_always_fast.sh
- [ ] N2: the ship path fails mechanically when a non-quick task has no PASS verdict for the current tree, at a point after the verdict can exist -> tests/template (file named by the worker)
- [ ] N3: scripts/papercut.sh add refuses a missing or invalid field and an over-long field, writes one entry, and enforces the cap -> tests/template/test_papercut.sh
- [ ] N3: scripts/papercut.sh list groups entries and reports correct refusals apart -> tests/template/test_papercut.sh
- [ ] N3: the dream digest carries the papercut groups as evidence -> tests/template/test_dream.sh
- [ ] N3: the papercut log is gitignored and holds no prompt text or file contents -> tests/template/test_papercut.sh
- [ ] Full gate green on the integrated tree -> judgment: check.sh output with its verified tree line

## Plan
<!-- task graph: one node per row; nodes that can run in the same wave must
     own disjoint files. Tiers: cheap, standard, strong, advisor, reviewer.
     Status: todo, doing, done, blocked. Validate: scripts/taskgraph.sh check -->
| node | depends on | owner files | worker tier | status |
|---|---|---|---|---|
| N1 | - | scripts/check.sh, tests/template/test_check_always_fast.sh | standard | doing |
| N2 | - | scripts/tasklint.sh, scripts/push-scan.sh, docs/procedures/ship.md, tests/template/test_tasklint.sh, tests/template/test_push_scan.sh | strong | doing |
| N3 | - | scripts/papercut.sh, scripts/dream/dream.py, scripts/session-context.sh, .gitignore, tests/template/test_papercut.sh, tests/template/test_dream.sh, tests/template/test_session_context.sh | strong | doing |
| N4 | N1, N2, N3 | BACKLOG.md, docs/BLUEPRINT.md, tests/template/selftest-inputs.list, tests/BUDGET | advisor | todo |

## Plan verdict
<!-- autopilot only: the reviewer's plan review of Goal, Assumptions,
     Acceptance criteria and Plan, written before any node starts;
     scripts/tasklint.sh requires PASS once a node is doing or done -->

## Progress log
<!-- timestamped one-liners; this is what survives compaction -->
- 2026-11-26 15 open rows read: 3 buildable here (rows for --fast selection, tasklint final, papercuts); the template half of cancel-superseded-runs is already in ci.yml; 11 not started, reasons in Non-goals.

## Review verdict
<!-- written ONLY by the independent reviewer -->

## Retro
<!-- filled by docs/procedures/retro.md -->
