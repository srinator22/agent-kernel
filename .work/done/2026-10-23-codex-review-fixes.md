# Task: codex-review-fixes
Mode: autopilot
Branch: task/codex-review-fixes
Date: 2026-10-23

## Goal
Fix the seven Codex review findings left on merged PRs 3 and 4, plus the library sync gap found while checking them, each with a regression test shown failing on main first (kernel rule 3). PR 3: check_connectors treats a missing hazard table as benign (P1); calc_trace_width sizes any non-'inner' layer as outer (P1); check_manifest lets a directory row stand in for per-file hashes (P2); kb_index keeps stale rows when an extractor is unavailable (P2); check_release_tags passes a current version reached through a legacy tag unchecked (P2). PR 4: template-sync and the adoption core set skip docs/roster (and docs/library) (P2); lessons.sh accepts a roster missing advertised roles (P2). Owner instruction 2026-10-23.

## Non-goals
<!-- explicitly out of scope; scope creep gets caught here -->
- The two PR 5 findings (ci-watch quoted triggers, adr.sh sections): handled in a separate session.
- check_bom.py's similar directory-row rule (found by the N1 worker): proposed as a follow-up, not changed here.

## Budget
<!-- declare before work starts; on exhaustion: stop, keep the best verified
     artifact, and report unresolved items with reasons - never hide a partial
     result behind a fluent answer -->
- Wall-clock: 2 h
- Subagents / workflow runs: 4
- Retries per failing step: 2
- Escalate to human when: budget exhausted | criteria unreachable | scope exceeds Non-goals

## Acceptance criteria
<!-- each maps to an executable test where possible; list test paths -->
- [x] Each of the eight fixes has a regression test that fails on main and passes after -> tests under docs/profiles/*/tools/tests, docs/library/tools/tests, tests/template/test_template_sync.sh, tests/template/test_lessons.sh (fail-first output in the Progress log)
- [x] ./scripts/check.sh green; reviewer PASS
- [ ] review threads on PRs 3 and 4 answered with the PR link (after the PR opens)

## Plan
<!-- task graph: one node per row; nodes that can run in the same wave must
     own disjoint files. Tiers: cheap, standard, strong, advisor, reviewer.
     Status: todo, doing, done, blocked. Validate: scripts/taskgraph.sh check -->
| node | depends on | owner files | worker tier | status |
|---|---|---|---|---|
| N1 | - | docs/profiles/hardware-pcb/tools/check_connectors.py, docs/profiles/hardware-pcb/tools/calc_trace_width.py, docs/profiles/hardware-pcb/tools/check_manifest.py, docs/profiles/hardware-pcb/tools/tests/test_check_connectors.py, docs/profiles/hardware-pcb/tools/tests/test_calc_trace_width.py, docs/profiles/hardware-pcb/tools/tests/test_check_manifest.py | strong | done |
| N2 | - | docs/library/tools/kb_index.py, docs/library/tools/tests/test_kb_index.py, docs/profiles/embedded-firmware/tools/check_release_tags.py, docs/profiles/embedded-firmware/tools/tests/test_check_release_tags.py | strong | done |
| N3 | - | scripts/template-sync.sh, docs/procedures/upstream.md, tests/template/test_template_sync.sh, scripts/lessons.sh, tests/template/test_lessons.sh | advisor | done |
| N4 | N1, N2, N3 | none | reviewer | done |

## Progress log
<!-- timestamped one-liners; this is what survives compaction -->
- 2026-10-23 fail-first on main: check_connectors 6 of 7 new tests fail; calc_trace_width 3 of 4; check_manifest 3 of 5 (one old test asserted the defect and was rewritten); kb_index 3 of 4; check_release_tags 3 of 3; template-sync 5 assertions; lessons.sh roster inventory 7 assertions.
- 2026-10-23 after fix: hardware-pcb tools 272 OK; library tools 49 OK; embedded-firmware tools 21 OK; test_lessons 112/112.
- 2026-10-23 gauntlet 1 FAIL: the empty-README roster rule failed the template-mode fixture (stub README); rule dropped as low value (a deleted role is still caught), its own test replaced by a deleted-role case.
- 2026-10-23 review 1 FAIL: template-sync header stale; no guard on upstream.md vs CORE_DIRS; misspelt hazard class value still benign; non-current legacy-tag version unchecked; orphan roster .toml and the library had no inventory check. All fixed; fail-first on the STAGED version: connectors 5, release tags 3, lessons inventory 7, core-set parity 1.
- 2026-10-23 review 2 PASS with two non-blocking residuals: the core-set header range never ended (fixed: range ends at 'Never touched at all:', with a guard; probe dropping scripts/ now fails); misspelt pin class hidden by declared_classes (BACKLOG).
- 2026-10-23 after round 2: hardware-pcb tools 277 OK; embedded-firmware 24 OK; test_lessons 119/119; test_template_sync 103/103. check_bom directory-row gap logged in BACKLOG.

## Review verdict
<!-- written ONLY by the independent reviewer -->
PASS (round 2). All five round-1 findings fixed; every new regression test fails on main and passes staged: hardware-pcb tools 17 fail on main / 277 OK; kb_index 3 / 49 OK; release tags 6 / 24 OK; test_template_sync 5 / 103 of 103; test_lessons 13 / 119 of 119. Probes: misspelt '24v' hazard class fails naming closest '24V' (exit 1), a no-mating set without a table still exits 0; an older lightweight legacy-tag release fails (exit 1), a prefixed release passes; an orphan roster .toml and deleted library writer and experiment items are each reported. Dropping the in-change "README advertising no role" rule does not breach rule 2 (added and removed within this unmerged change; the replacement deleted-role test fails on main). Old test changes (check_manifest defect-asserting test, template-sync counts) legitimate. No dashes; BACKLOG row for check_bom present. Non-blocking: header-parity sed range did not end (since fixed); misspelt pin class hidden by declared_classes.

## Retro
<!-- filled by docs/procedures/retro.md -->
- Defects by route: (b) escaped past merge: the seven Codex findings on PRs 3 and 4 and the library sync gap, each now with a regression test shown failing on main first (kernel rule 3); (a) caught pre-merge here: gauntlet 1 (empty-README rule vs the template fixture), review round 1 (five findings) and round 2 (header range); (d) a worker misreported a library agent missing, checked and found present.
- Cause of the escape: the advisor merged PRs 3 to 5 on green CI and mergeability without reading the bot review threads. Recorded as an advisor memory (read review threads before merge); the two P1 findings were safety checks silently passing bad input.
- Process lesson for UPSTREAM.md: none filed; the merge-without-review-threads miss is an advisor habit, not a template rule gap, since ship.md already requires the reviewer verdict.
- BACKLOG: check_bom directory-row gap; check_connectors misspelt pin class with declared_classes.
