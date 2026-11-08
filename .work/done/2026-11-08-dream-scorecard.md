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
- [x] A1 the digest has a "## Scorecard" section after the Impact section and before Signals, opening with a line that says it is the owner's recorded decisions counted by script and naming the checkout and branch that "now" values were read from ("detached" on a detached HEAD, "N/A - not a git checkout" outside git) -> tests/template/test_dream.sh
- [x] A2 saved reports are files named exactly YYYY-MM-DD-report.md in the state folder (others ignored); the last 10 get one row each, oldest first: proposals, approved, declined, or "no Outcome recorded"; older reports fold into one totals row -> tests/template/test_dream.sh
- [x] A3 one row per proposal kind across all reports with an Outcome: approved, declined and the approval rate approved/(approved+declined); the kind is the bracket tag lowercased with spaces around ":" normalised; a proposal with no tag counts as "untagged" -> tests/template/test_dream.sh
- [x] A4 each lesson id (bracketed or bare L followed by digits) in an approved Change line of the last 10 reports shows its INDEX.md used and last values now, or "not in INDEX.md"; in a digest it also shows the candidate count from the same word matcher the Impact section uses (one shared function), and "N/A - no digest signals" from the scorecard command -> tests/template/test_dream.sh
- [x] A5 each quoted string containing " | " in an approved Change line that names BACKLOG.md, in the last 10 reports, is a row: its first cell (split on unescaped " | ", "\|" unescaped, edge pipes stripped) is matched against BACKLOG.md rows read the same way and shows that row's last cell now, or "not found"; cells print cut to 80 characters -> tests/template/test_dream.sh
- [x] A6 a totals line gives the decided count (approved plus declined, from readable reports with an Outcome only) against the self-review (30) and replay (50) thresholds -> tests/template/test_dream.sh
- [x] A7 `scripts/dream.sh scorecard` prints the section and exits 0, with no file created or changed in the state folder; with no state folder it prints "no saved reports" and creates nothing -> tests/template/test_dream.sh
- [x] A8 a report that cannot be read (OSError or invalid UTF-8), numbers a proposal twice, or has an Outcome that is not numeric, lacks Applied or Declined, names a number missing from its Proposals or puts one number in both, is listed as skipped with the reason, and the digest still completes; "Applied: none" and "Declined: none" read as empty; dream.sh done still exits 2 on a repeated number -> tests/template/test_dream.sh
- [x] A9 with no saved report the section says "no saved reports"; when a report has several Outcome sections the last one counts -> tests/template/test_dream.sh
- [x] A10 lesson lines (A4) and row lines (A5) each print once per distinct id or first cell, newest report first, at most 20 of each, then "K more not shown"; the section stays under 6000 bytes with 15 reports of 12 approved proposals each, every one naming two lessons and two BACKLOG rows whose cells are over 80 characters -> tests/template/test_dream.sh
- [x] A11 docs/procedures/dream.md (including that `scorecard` is the way to see it when a digest exits 3, and that "approved" is the owner's approval, not proof the change landed), the dream.py header, the dream.sh usage and docs/BLUEPRINT.md describe the scorecard -> docs/procedures/dream.md
- [x] A12 the scorecard command run read-only on the real state folder (main checkout .work/dream, the 2026-11-07 and 2026-11-08 reports) gives output recorded in the Progress log -> judgment: real-data check, kernel rules 3 and 14
- [x] A13 ./scripts/check.sh exits 0 on the committed tree -> scripts/check.sh

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
- 2026-11-08 change review round 1: FAIL. A lesson id repeated inside one Change line printed twice; kind rows and skipped lines had no cap; an unborn branch printed no name. Fixed in 9724587 with tests ST13, ST13B (the repeat in one line alone, since a later report masked it in ST13), ST14 and the unborn case
- 2026-11-09 after the fix: test_dream.sh 215 passed, 0 failed; ./scripts/check.sh exit 0, selftest 22 passed, 0 failed, 0 quarantined
- 2026-11-09 change review round 2: FAIL. B1: the round-1 fix put the ST13B run before the cross-report row assertion, so it read a one-report run and could not fail. Non-blocking N1 (an unreadable state.json stops the read-only scorecard, left as an explicit error) and N2 (skipped lines and lesson used and last values had no length cut)
- 2026-11-09 B1 and N2 fixed: the row assertion runs on ST13's two reports again; skipped lines are cut to 160 characters, used to 20 and last to 40, with a long-values test. Fail-first with the row dedupe disabled and no cut: 215 passed, 2 failed (the row assertion, the long values); after: 217 passed, 0 failed; ruff check and format clean from scripts/dream
- 2026-11-09 change review round 3: FAIL only for the missing check.sh log on the committed tree; B1 closed, cuts correct; N3 (the 160-character skipped-line cut is untested) non-blocking
- 2026-11-09 merged origin/main 55228eb (PRs 6, 7 and 16): dream.py header and test_dream.sh conflicts kept both sides; the scorecard tests' state folders renamed to scstate11-14 and scprojects11 so they no longer share state11-13 with PR 16's outcome tests; test_dream.sh 231 passed, 0 failed; ruff check clean

## Review verdict
<!-- written ONLY by the independent reviewer -->
Round 1 (reviewer, 2026-11-08, d31a3a6): FAIL. A lesson id repeated inside one Change line printed twice; kind rows and skipped lines had no cap; an unborn branch printed no name.

Round 2 (reviewer, 2026-11-09, 9724587): FAIL. B1: the round-1 fix ran the one-report ST13B case before the cross-report row assertion, so the assertion could not fail. Non-blocking: N1 an unreadable state.json stops the read-only scorecard; N2 skipped lines and lesson used and last values had no length cut.

Round 3 (reviewer, 2026-11-09, 27e5dca): FAIL only for the missing check.sh log on the committed tree. B1 closed (the row assertion reads ST13's two reports and failed with the dedupe disabled, sc-ff3.txt:209); N2 cuts correct (worst lesson line 80 characters); N1 accepted as an explicit error. Non-blocking: N3 the 160-character skipped-line cut has no test.

Round 4 (reviewer, 2026-11-09, merge 16f0cb6 of origin/main 55228eb): PASS. Both conflicts keep both sides: the dream.py header has main's Outcome paragraph then the Scorecard paragraph, main's outcome code is present at consistent offsets, PR 16's test block is unchanged and the scorecard block uses only scstate11-14 and scprojects11, so no state folder is shared. The full check.sh log on 16f0cb6 passes every stage (selftest 22 passed, 0 failed), which gives A13 its evidence. Limit: compared against the PR 16 worktree, not git objects. Non-blocking: N3 stands.

Evidence checked: sc-check3.txt in full; sc-run4.txt (217 passed, 0 failed); sc-ff3.txt (215 passed, 2 failed with the dedupe disabled and no cut); sc-full.diff and sc-fix2.diff; scripts/dream/dream.py 1-49, 440-749; tests/template/test_dream.sh 400-728; docs/procedures/dream.md; docs/BLUEPRINT.md 145, 180.

## Retro
- Defects: the repeated lesson id, the uncapped lists and the unborn branch (review round 1), the test that could not fail and the uncut values (round 2): route (a), caught before merge by the reviewer; nothing recorded. Each fix has a test that failed first (sc-ff2.txt, sc-ff3.txt).
- Trap (3a, process): parallel agents given the same scratchpad log and message file names overwrote each other (one project's check log landed in another's, and one commit took another repo's message). Recorded in docs/lessons/UPSTREAM.md.
- Trap (d, self-noticed): merging main brought PR 16's outcome tests, which reused the state11-13 fixture folders the scorecard tests also used; renamed before running. No entry: the merge review covers it.
- Not done here: N3 (a test for the 160-character skipped-line cut) is a BACKLOG row.
