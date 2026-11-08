# Task: dream-scorecard
Mode: autopilot
Branch: task/dream-scorecard
Date: 2026-11-08

## Goal
Give the dream a scorecard of its own track record, computed by script with
no model, so later passes can improve the dream from evidence instead of
from the dreamer's own judgment. Every digest gets a "## Scorecard" section,
and `scripts/dream.sh scorecard` prints the same section on demand. It
reads the saved reports in the state folder and states, per dream and per
proposal kind, what the owner applied, declined or has not yet decided. It
also shows what happened to the lessons and BACKLOG rows that applied
proposals added, and how many decided proposals exist against the
thresholds for the later self-review (30) and replay (50) passes.

## Non-goals
- Changing the dreamer agent, its prompt or the report format.
- The self-review (meta) pass and the replay check; this task only provides
  their data and their thresholds.
- A scorecard for the taste pass.
- Stable signal ids across dreams; digest signal ids stay digest-local.
- Fixing the Outcome Files line or the hygiene memory folder; the
  task/dream-outcome-fixes branch owns those.

## Budget
- Wall-clock: 3 h
- Subagents / workflow runs: 3 (plan reviewer, change reviewer, monitor)
- Retries per failing step: 2
- Escalate to human when: criteria unreachable, scope exceeds Non-goals, or the merge with task/dream-outcome-fixes conflicts in behaviour

## Assumptions
- [confirmed] the owner asked to build the scorecard as the first self-improvement step ("Yes, build it", 2026-11-08)
- [verified] a saved report holds "## Proposals" with numbered "N. [kind] title" items and Change lines, and dream.sh done appends "## Outcome <date>" with Applied and Declined lines -> scripts/dream/dream.py parse_report and outcome_text; .claude/agents/dreamer.md report format
- [verified] digest signal ids are numbered per digest, so a past proposal's evidence ids cannot be matched to later signals -> scripts/dream/dream.py cmd_digest ("- s%d")
- [verified] the reports and digest live in the gitignored state folder, so the scorecard is per machine -> scripts/dream/dream.py header (State)
- [confirmed] the owner delegated all decisions overnight ("make all decisions", 2026-11-08); decided under it: the digest carries the scorecard, because its measure is the owner's own recorded decisions, which the dreamer cannot write; the dreamer prompt is unchanged, and the section's opening line says what it is
- [verified] another session's task/dream-outcome-fixes edits dream.py, dream.md and test_dream.sh; this branch merges it before ship if it lands first -> git worktree list (C:/dev/work/New-Project-dreamfix)

## Acceptance criteria
- [ ] A1 the digest has a "## Scorecard" section after the Impact section and before Signals, opening with a line that says it is the owner's recorded decisions counted by script and naming the checkout and branch that "now" values were read from ("detached" on a detached HEAD, "N/A - not a git checkout" outside git) -> tests/template/test_dream.sh
- [ ] A2 saved reports are files named exactly YYYY-MM-DD-report.md in the state folder (others ignored); the last 10 get one row each, oldest first: proposals, approved, declined, or "no Outcome recorded"; older reports fold into one totals row -> tests/template/test_dream.sh
- [ ] A3 one row per proposal kind across all reports with an Outcome: approved, declined and the approval rate approved/(approved+declined); the kind is the bracket tag lowercased with spaces around ":" normalised; a proposal with no tag counts as "untagged" -> tests/template/test_dream.sh
- [ ] A4 each lesson id (bracketed or bare L followed by digits) in an approved Change line of the last 10 reports shows its INDEX.md used and last values now, or "not in INDEX.md"; in a digest it also shows the candidate count from the same word matcher the Impact section uses (one shared function), and "N/A - no digest signals" from the scorecard command -> tests/template/test_dream.sh
- [ ] A5 each quoted string containing " | " in an approved Change line that names BACKLOG.md, in the last 10 reports, is a row: its first cell (split on unescaped " | ", "\|" unescaped, edge pipes stripped) is matched against BACKLOG.md rows read the same way and shows that row's last cell now, or "not found"; cells print cut to 80 characters -> tests/template/test_dream.sh
- [ ] A6 a totals line gives the decided count (approved plus declined, from readable reports with an Outcome only) against the self-review (30) and replay (50) thresholds -> tests/template/test_dream.sh
- [ ] A7 `scripts/dream.sh scorecard` prints the section and exits 0, with no file created or changed in the state folder; with no state folder it prints "no saved reports" and creates nothing -> tests/template/test_dream.sh
- [ ] A8 a report that cannot be read (OSError or invalid UTF-8), numbers a proposal twice, or has an Outcome that is not numeric, lacks Applied or Declined, names a number missing from its Proposals or puts one number in both, is listed as skipped with the reason, and the digest still completes; "Applied: none" and "Declined: none" read as empty; dream.sh done still exits 2 on a repeated number -> tests/template/test_dream.sh
- [ ] A9 with no saved report the section says "no saved reports"; when a report has several Outcome sections the last one counts -> tests/template/test_dream.sh
- [ ] A10 lesson lines (A4) and row lines (A5) each print once per distinct id or first cell, newest report first, at most 20 of each, then "K more not shown"; the section stays under 6000 bytes with 15 reports of 12 approved proposals each, every one naming two lessons and two BACKLOG rows whose cells are over 80 characters -> tests/template/test_dream.sh
- [ ] A11 docs/procedures/dream.md (including that `scorecard` is the way to see it when a digest exits 3, and that "approved" is the owner's approval, not proof the change landed), the dream.py header, the dream.sh usage and docs/BLUEPRINT.md describe the scorecard -> docs/procedures/dream.md
- [ ] A12 the scorecard command run read-only on the real state folder (main checkout .work/dream, the 2026-11-07 and 2026-11-08 reports) gives output recorded in the Progress log -> judgment: real-data check, kernel rules 3 and 14
- [ ] A13 ./scripts/check.sh exits 0 on the committed tree -> scripts/check.sh

## Plan
| node | depends on | owner files | worker tier | status |
|---|---|---|---|---|
| N1 | - | tests/template/test_dream.sh | advisor | done |
| N2 | N1 | scripts/dream/dream.py, scripts/dream.sh | advisor | done |
| N3 | N2 | docs/procedures/dream.md, docs/BLUEPRINT.md | advisor | done |
| N4 | N3 | .work/TASK.md | reviewer | doing |

## Plan verdict
PASS. Reviewer plan review, round 3, 2026-11-08: B1 is closed by A10's dedupe and the 20-line caps, tested with a worst-case fixture. Non-blocking: fit the line formats to 6000 bytes before writing A10's test; describe both orders in dream.md. Earlier rounds. Round 1, FAIL: B1 no size bound; B2 candidate source undefined in the command, and a copied matcher; B3 BACKLOG row matching did not fit real reports; B4 die() in parse_report, invalid UTF-8, malformed Outcomes; N1-N10 non-blocking. Round 2, FAIL: B1 not closed (the 6000-byte ceiling was unreachable without line caps); the rest resolved.

## Progress log
- 2026-11-08 branch task/dream-scorecard from origin/main 5ce4e78 in worktree C:/dev/work/New-Project-scorecard
- 2026-11-08 fail-first: tests/template/test_dream.sh 168 passed, 39 failed (every new scorecard case; the 10 negative cases pass with no section), dream.py: error: invalid choice: 'scorecard'
- 2026-11-08 implemented: test_dream.sh 207 passed, 0 failed; size fixture 3695 bytes (ceiling 6000)
- 2026-11-08 real data (A12), read-only, state folder checksums unchanged: scorecard --state-dir "C:/dev/work/New Project/.work/dream" --root "C:/dev/work/New Project" gives 2026-11-07 proposals 11, no Outcome recorded; 2026-11-08 proposals 12, approved 9, declined 3; mechanize 3/1 (75%), pending approve 2/0, pending merge 2/0, pending reject 1/0, stale 1/0, upstream 0/1, none 0/1; L011-L013 not in INDEX.md and 6 BACKLOG rows not found on main (PR 15 unmerged), decided 12 of 30/50

## Review verdict

## Retro
