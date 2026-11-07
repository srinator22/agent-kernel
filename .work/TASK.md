# Task: dreaming
Mode: standard
Branch: task/dreaming
Date: 2026-11-07

## Goal
A local dream: an offline pass that consolidates this repository's memory
(lessons, defect memory, backlog, task retros, Claude's auto-memory notes)
against what actually happened in its sessions, and hands the human a short
numbered list of proposals with evidence. Claude offers it when a session's
work is done and a dream is due. It costs few tokens: a script with no model
reduces transcripts to their signal and reads each transcript line once ever,
the model is skipped when there is no new signal, and one standard-tier agent
writes the report. Nothing in memory changes until the human approves items.

## Non-goals
<!-- explicitly out of scope; scope creep gets caught here -->
- The Managed Agents Dreams API (sessions here are local Claude Code
  transcripts; research preview; not zero-data-retention eligible).
- Applying proposals without approval; editing or moving transcripts.
- The fleet dream across projects (next task, once the per-project dream
  works); Codex transcripts (a different format; BACKLOG).
- Subagent transcripts (`<session>/subagents/`): agent-internal, no human
  signal; a full-text index over the docs.

## Budget
<!-- declare before work starts; on exhaustion: stop, keep the best verified
     artifact, and report unresolved items with reasons - never hide a partial
     result behind a fluent answer -->
- Wall-clock: two working sessions.
- Subagents / workflow runs: 1 worker (N1), 1 dreamer run (N5), 1 reviewer (N6), monitors per push.
- Retries per failing step: 2.
- Escalate to human when: a criterion needs a kernel edit, the digest cannot stay under its cap on real transcripts, or the reviewer fails twice.

## Assumptions
<!-- one line per assumption the work rests on: [confirmed] the human said so,
     [verified] -> evidence (a command or file), [open] not yet settled.
     scripts/tasklint.sh ship (the full gate) fails while any line is [open],
     except in quick mode -->
- [confirmed] The human approved the dreaming spec (2026-11-07, "approve both") and asked that Claude offer a dream when a session's work is done, with few tokens spent.
- [confirmed] The human granted full permission to read all chat transcripts (2026-11-07).
- [verified] Claude Code keeps one JSONL file per session in ~/.claude/projects/<slug>/, with subagents in <session>/subagents/; every line carries its working directory (cwd), so lines can be selected per repository -> judgment: listing of ~/.claude/projects and a parse of this session's transcript, 2026-11-07
- [verified] A signal digest keeps 0.02 to 0.08 percent of a transcript (125 MB session to 83 KB) -> judgment: probe over four real transcripts, 2026-11-07
- [verified] Typed messages are user lines with string content; mid-turn messages are queued_command attachments; tool errors (hook blocks, permission denials, failed commands) are tool_result entries with is_error; system lines carry isMeta or start with "<", and compaction summaries are user lines flagged isCompactSummary (91 on this machine, none with isMeta; found by review 1) -> judgment: parse of this session's transcript and a count-only grep of all transcripts, 2026-11-07

## Acceptance criteria
<!-- each maps to an executable test where possible; list test paths. A ticked
     line needs "-> <existing path>" or "-> judgment: <reason>"
     (scripts/tasklint.sh check) -->
- [x] D1 `scripts/dream.sh digest` (stdlib Python behind a bash wrapper) reads main session transcripts (not subagents) and keeps only lines whose cwd is the repository, one of its worktrees, a root it saw before, or a `--match` path, testing the raw line for the path before parsing JSON; it writes `.work/dream/digest.md` with numbered signals (typed and mid-turn user messages, interrupts, permission denials, hook blocks, failed tool calls; compaction summaries skipped), each with session, date and branch, truncated (messages 400 characters, errors 300), deduplicated with a count, capped at 40 KB (corrections, denials, blocks and interrupts first, then errors, then other messages; newest first; dropped count reported); malformed lines are counted and skipped -> tests/template/test_dream.sh
- [x] D2 Each transcript line is read once ever: the digest proposes byte offsets in `.work/dream/state.next.json` and `scripts/dream.sh done` commits them, so a dream that is not finished loses nothing; a partial last line is never consumed -> tests/template/test_dream.sh
- [x] D3 `scripts/dream.sh due` decides from file stats only and in under a second: due when sessions with new activity exist and (a task retro landed in `.work/done/` since the last dream, or 3 days passed); `due --offer` records the offer once per day and state; no Python means not due, silently -> tests/template/test_dream.sh
- [x] D4 Offer: when no task is live, the Stop hook asks once ("Work is done and a dream is due ... Ask the user: start dreaming?"); the retro procedure's last step asks the same -> tests/template/test_stop_gate.sh
- [x] D5 No new signal ends the dream before any model call: digest exits 3 with "nothing to dream" -> tests/template/test_dream.sh
- [x] D6 `scripts/dream.sh hygiene` prints counts and sizes of the memory files, pending lessons with their age, and dangling links (auto-memory [[name]] links and markdown links in the lessons files), and the digest includes them -> tests/template/test_dream.sh
- [x] D7 A read-only `dreamer` agent (standard tier, Codex twin) reads the digest and the memory files and returns a report of numbered proposals, each with evidence (digest signal id or file:line): pending lessons approve, merge or reject; new lessons seen in two or more sessions; stale or contradicted lessons and auto-memory notes; lessons to mechanize (BACKLOG rows); process lessons for UPSTREAM.md; lesson counters from evidence -> judgment: one real dream on this repository (11 proposals, each with evidence; report kept in the gitignored .work/dream/; usage in the Progress log)
- [x] D8 The `dream` skill and `docs/procedures/dream.md`: offer, digest, dream, present the numbered list, apply only approved numbers, `dream.sh done`; a rules index line in AGENTS.md; `.work/dream/` is gitignored -> tests/template/test_lessons.sh (skill mirror and cap), tests/template/test_dream.sh (the state folder never shows in git status)
- [x] D9 Token cost measured: digest bytes per project across the local transcripts and the dreamer's tokens for one real dream, recorded in the Progress log -> judgment: measured run
- [x] D10 `./scripts/check.sh` green; plain hyphens; kernel hash unchanged -> judgment: check.sh output quoted in the Progress log

## Plan
<!-- task graph: one node per row; nodes that can run in the same wave must
     own disjoint files. Tiers: cheap, standard, strong, advisor, reviewer.
     Status: todo, doing, done, blocked. Validate: scripts/taskgraph.sh check -->
| node | depends on | owner files | worker tier | status |
|---|---|---|---|---|
| N1 | - | scripts/dream.py, scripts/dream.sh, tests/template/test_dream.sh | standard | done |
| N2 | - | .claude/agents/dreamer.md, .codex/agents/dreamer.toml, .claude/skills/dream/SKILL.md, .agents/skills/dream/SKILL.md, docs/procedures/dream.md, AGENTS.md, docs/procedures/retro.md | advisor | done |
| N3 | N1 | scripts/stop-gate.sh, tests/template/test_stop_gate.sh | advisor | done |
| N4 | N1, N2, N3 | .gitignore, docs/BLUEPRINT.md, scripts/check.sh, tests/template/fixtures/check.sh, README.md, docs/decisions/0009-local-dreaming.md, BACKLOG.md | advisor | done |
| N5 | N1, N2 | .work/TASK.md | advisor | done |
| N6 | N4, N5 | .work/TASK.md | reviewer | done |

## Plan verdict
<!-- autopilot only: the reviewer's plan review of Goal, Assumptions,
     Acceptance criteria and Plan, written before any node starts;
     scripts/tasklint.sh requires PASS once a node is doing or done -->

## Progress log
<!-- timestamped one-liners; this is what survives compaction -->
- 2026-11-07 task opened on task/dreaming from main 69c7245 (template-v0.3.0 released; PR #10 and #11 merged, CI green).
- 2026-11-07 transcript layout mapped: 18 project folders, 2741 JSONL files including subagents; sessions that worked in this repo's worktrees ran from another project's folder, so selection is by each line's cwd.
- 2026-11-07 N1 worker: scripts/dream.py and dream.sh; test_dream.sh 87 passed, 0 failed. Real digest of this repository: 87 signals from 9 sessions, 19435 bytes, 251215 new lines read in 3.4 s; `due` 0.2 s. Worker choice accepted: `due` counts only transcripts that ever matched this repository, so other projects' activity never triggers a dream here.
- 2026-11-07 N2 to N4: dreamer agent and Codex twin, dream skill (7 of 8 core skills), docs/procedures/dream.md, rules index line, retro step 8; stop-gate offers once when no task is live (test_stop_gate.sh 43 passed; the real `due --offer` line matches the hook's message); .gitignore, BLUEPRINT, required files, README, ADR 0009, BACKLOG rows (fleet dream, Codex transcripts).
- 2026-11-07 D9 first-dream digest per project (all history since August, scratch state, read-only): 13 projects, 4 to 41 KB each (18 to 216 signals); the five busiest reach the 40 KB signal cap (about 10k tokens) and drop the lowest-priority plain messages first; 2.3 to 5.1 s each. Later dreams read only new lines.
- 2026-11-07 N5 real dream on this repository: digest 87 signals, 19435 bytes; dreamer on the standard tier (Sonnet): 105537 tokens, 27 tool calls, 99 s; 11 proposals with evidence, none applied (the owner approves by number); `dream.sh done` not run, so the next dream re-reads these lines.
- 2026-11-07 the dream found a defect in this task: hygiene counted INDEX.md's format placeholder as a lesson (11 for 10). Regression case in test_dream.sh failed first (86 passed, 1 failed), then 87 passed after dream.py counts lessons the way lessons.sh does.
- 2026-11-07 review 1 FAIL: (1) high, privacy: synced projects do not get the .gitignore line, so the digest could sit unignored; (2) compaction summaries were labelled as the human's messages; (3) `due` counted sibling folders (Foo-bar for Foo), a false offer; (4) tests passed on broken code for partial lines, worktrees, --match, subagents and truncated files; (5) offsets not shared across worktrees; (6) --max-bytes and relative --match unvalidated; (7) `done` edited a tracked file. Fixes: the N1 worker on dream.py and its tests (fail-first), the advisor on dream.md, ADR 0009 and this record.
- 2026-11-07 review-1 fixes in dream.py: the state folder writes its own .gitignore; compaction and transcript-only lines skipped; `due` counts only folders named exactly after a root (or the app worktree prefix); --match resolved to an absolute path; state shared through the main checkout; --max-bytes below 2000 refused and exit 3 only with zero signals; `done` edits no tracked file. Fail-first: the 11 new tests failed on the old code (110 passed, 11 failed); after the fix test_dream.sh 121 passed, 0 failed. A real digest leaves `git status -- .work/dream` empty.

- 2026-11-07 ./scripts/check.sh on the staged tree after the fixes: exit 0; tasklint check and ship OK; selftest 20 passed, 0 failed (20 test files); "template self-test: OK (137 required files, ...)".

## Review verdict
<!-- written ONLY by the independent reviewer -->
Review 1 (2026-11-07): FAIL - (1) high: synced projects lack the .gitignore line, so the digest could sit unignored; (2) compaction summaries labelled as the human's words; (3) `due` counted sibling folders, a false Stop-hook offer; (4) tests passed on broken code for partial lines, worktrees, --match, subagents, truncated files; (5) offsets not shared across worktrees; (6) --max-bytes and relative --match unvalidated; (7) `done` edited a tracked file.

Review 2 (2026-11-07): PASS. All seven findings fixed in dream.py, its docs and its tests; the fresh verify output is complete and clean. Each new test fails on the old code: the partial line across done, the truncated-file reset, the linked worktree kept in known_roots, absolute and relative --match, subagent transcripts not read, the sibling folder not due, the state folder ignoring itself, --max-bytes validation, no tracked write from done. Non-blocking: D8's evidence should also name tests/template/test_dream.sh (done).
Evidence checked: check-dream-2.log (all 33 lines: kernel-hash OK, tasklint OK, PASS test_dream.sh and test_stop_gate.sh, selftest 20 passed 0 failed, template self-test OK, exit 0); dreaming-2.diff (TASK.md, ADR 0009, dream.md, dream.py, dream.sh, stop-gate.sh, test_dream.sh); working-tree greps of dream.py; count-only greps of all transcripts (91 isVisibleInTranscriptOnly lines, all also isCompactSummary); Stop hook order, skill mirror blobs, read-only dreamer tools; no secrets, private names, new dependencies or dashes.

## Retro
<!-- filled by docs/procedures/retro.md -->
Defects by discovery route:
- (a) caught before merge by checks: the first real dream found that hygiene counted INDEX.md's format placeholder as a lesson (regression test failed first, then fixed); check.sh step 4a found a literal typographic apostrophe in dream.py (now written as the escape backslash-u2019); review 1 found seven defects, all fixed with fail-first tests.
- (d) self-noticed: the new scripts were staged without the executable bit; set before the gate ran.
Traps that cost time: inline Python and here-documents through the shell failed or silently did nothing three times in this task; the pending entries on inline scripts already cover it, and the first dream proposes merging them into one rule plus a hook (dream report proposals 1 and 2).
Confirmed by evidence: running the feature on real data before merge found a defect the unit tests missed, the same lesson as the pending entry on worked examples (dream proposal 5 suggests approving it).
Lessons consulted: L001, L003, L009 (counters updated).
Durable decisions: ADR 0009. The first dream's eleven proposals wait for the owner in the gitignored .work/dream/2026-11-07-report.md; `dream.sh done` was not run, so nothing is lost.
