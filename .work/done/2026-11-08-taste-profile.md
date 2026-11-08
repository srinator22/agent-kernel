# Task: taste-profile
Mode: standard
Branch: task/taste-profile
Date: 2026-11-08

## Goal
A dream step that learns the owner's tastes across all local projects and
keeps them in a personal profile outside every repository. A script reduces
every project's Claude Code transcripts, and the feedback notes in every
project's auto-memory, to the owner's own preference signals with no model.
One read-only Sonnet agent turns them into numbered profile lines with
evidence. The owner approves by number. A script writes only the approved
lines to `~/.claude/taste/<area>.md`, which `~/.claude/CLAUDE.md` imports so
every Claude session in every project loads it, and mirrors them into
`~/.codex/AGENTS.md` for Codex. The template ships only the mechanism.

## Design
Owner's answers (2026-11-08):
- Location: `~/.claude/taste/`, one file per area, imported by `@` lines in
  `~/.claude/CLAUDE.md`.
- Loading: every area in every session, capped so it stays cheap; a
  generated copy for Codex.
- Areas to start: communication, writing, design, art, code, working.
  Further areas only as approved proposals.
- Evidence: one explicit statement is enough; an inferred preference needs
  signals from two or more sessions.

Builder's calls (the owner checks these when approving):
1. Commands: `scripts/dream.sh taste digest|done|check|apply`, in a new
   `scripts/dream/taste.py` that reuses the helpers in `scripts/dream/dream.py`. All
   user-level paths derive from `TASTE_HOME` (default: the home folder), so
   tests never touch the real one.
2. Only the owner's own words count. A user line is the owner's when its
   `origin.kind` is `human`; in older transcripts without `origin`, when its
   `turnOrigin` is `human`, or, with no `turnOrigin`, when its prompt source
   is not `system` and the text has no known machine-written prefix (another
   session's brief, a skill body, a session continuation). Owner lines
   themselves carry prompt source sdk, so sdk alone never rejects a line. Pasted content, system tags
   and compaction summaries are skipped. The same filter goes into
   `dream.py`, whose project digest counts other sessions' messages as the
   owner's today.
3. Signal kinds, in priority order:
   P explicit preference sentence (strong cue such as "I prefer", "never",
   "too long"), taken sentence by sentence from any owner message;
   O the owner's own words in a question answer (an "Other" answer or a
   note); C correction; D a tool rejection with the owner's typed reason;
   A an option the owner picked (question and label, marked when it was the
   recommended one); R a short reaction (praise or rejection) with `re:`,
   the first 160 characters of the reply it answers; T a weaker taste-topic
   sentence (layout, colour, tone, font); F a `type: feedback` or
   `type: user` auto-memory note from any project, new or changed since it
   was last read (model-written, so supporting evidence only).
4. Sources: every folder under `~/.claude/projects` (top-level transcripts
   only, so every account that ran Claude Code on this computer), plus any
   extra folder given with a repeatable `--projects-dir` (for example a copy
   from another computer). Byte offsets per transcript live in
   `~/.claude/taste/.dream/state.json`, independent of each project's dream.
5. Evidence pool: every signal gets a stable id (`t` plus 6 hex characters
   of a hash of its kind and text) and is kept in the state's pool with its
   sessions, projects, first and last dates, how often it was shown and
   whether an approved line used it. A digest shows never-shown signals
   first (by kind priority, newest first), then unused older ones, under a
   40 KB cap, so nothing the cap cuts is lost and a later pass can pair an
   older signal with new evidence. Shown, unused signals not seen for 180
   days are pruned at `done`.
6. Stop early, no model: the digest exits 3 when fewer than 5 never-shown
   signals exist or the last taste pass was under 7 days ago (`--force`
   skips the day rule). On exit 3 the offsets and the newly found signals
   are saved to the pool, so nothing is read twice or lost. On exit 0 the
   offsets and pool wait in `state.next.json` until `done`.
7. Profile format: `# <Area>`, one purpose line, then `- [Tnnn] <line>`.
   Ids are global and never reused; hand-written `- ` lines are kept and
   counted. Caps, enforced by `check` and `apply`: a line at most 160
   characters; all area files together at most 6000 bytes (about 1.5k
   tokens per session).
8. `apply --report <file> <numbers>` validates each approved proposal
   against the pool: every cited signal exists, and the citation holds a P
   or O signal or signals from two or more sessions. Then it adds, revises
   or removes lines, marks the cited signals used, rewrites the import block
   in `~/.claude/CLAUDE.md` and the profile block in `~/.codex/AGENTS.md`
   between `<!-- taste:begin -->` and `<!-- taste:end -->`, leaving every
   byte outside the markers unchanged, and creates either file when
   missing. It refuses to write when the taste folder sits inside a git
   work tree.
9. Runs from any project: every synced project gets the script and all of
   them share the one user-level state and profile. The state carries a
   format version; a copy that meets a newer version refuses to write and
   says to update the template.
10. Agent: `taste-dreamer` (Sonnet; Read, Grep, Glob) and its Codex twin.
    At most 12 proposals, each `add <area>: <line>`, `revise Tnnn <area>:
    <line>` or `remove Tnnn: <reason>`, with Evidence and Why lines. Lines
    are general: no project names, no quotes.
11. Procedure: a Taste pass section in `docs/procedures/dream.md`, run after
    the project pass or alone with `/dream taste`. Reports stay in
    `~/.claude/taste/.dream/reports/`. ADR 0011 records the decision.
12. Outcome and impact (owner approved 2026-11-08, relayed by the parent
    session and confirmed here). Outcome: `dream.sh done --report <file>
    --applied <numbers>` and `dream.sh taste done --report <file>` (applied
    numbers come from the ledger) append "## Outcome <date>" to the report:
    applied and declined numbers, what each change touched, and memory
    numbers before (a snapshot taken at digest time) and after. Impact: each
    digest gets a script-built "## Impact since the last dream" (or pass):
    a trend of signal counts by kind per earlier dream; for the project,
    approved lessons unused for more than 45 days by git date (retire
    candidates) and lessons whose distinctive words recur in new
    correction, denial, hook, interrupt or failure signals (mechanize
    candidates); for the taste profile, lines added, revised and removed
    since the last pass, lines whose evidence was seen again, and new
    signals sharing words with a line (confirm-or-contradict candidates the
    agent judges). Word overlap only lists candidates; the agents decide.
13. Not read in this version: `edited_text_file` attachments (they show a
    file after any outside change, not the owner's edit), Codex transcripts
    (existing BACKLOG row), interrupts with no text, and claude.ai chats
    outside Claude Code (not stored on this computer).

## Non-goals
<!-- explicitly out of scope; scope creep gets caught here -->
- Any taste content, real quote or private project name in a tracked file.
- Reading Codex session transcripts (BACKLOG row exists).
- Writing any profile line without the owner's approval; a scheduled or
  automatic taste pass.
- A fleet dream that proposes template changes (BACKLOG row exists).
- Changing the Stop hook offer or the project dream's due rule.

## Budget
<!-- declare before work starts; on exhaustion: stop, keep the best verified
     artifact, and report unresolved items with reasons - never hide a partial
     result behind a fluent answer -->
- Wall-clock: one working day
- Subagents / workflow runs: 7 (docs check and builder check, both used; one worker, two reviewer rounds, one real taste-dreamer run, one monitor)
- Retries per failing step: 2
- Escalate to human when: budget exhausted | criteria unreachable | scope exceeds Non-goals

## Assumptions
<!-- one line per assumption the work rests on: [confirmed] the human said so,
     [verified] -> evidence (a command or file), [open] not yet settled.
     scripts/tasklint.sh ship (the full gate) fails while any line is [open],
     except in quick mode -->
- [confirmed] the four design answers above (owner, chat 2026-11-08)
- [confirmed] full permission to read every chat transcript (owner, 2026-11-07)
- [verified] owner lines carry `origin.kind` human, other sessions peer, notifications task-notification; another session's brief has no origin and prompt source sdk -> recon over 45 transcripts and this session's own first line, 2026-11-08
- [verified] question answers sit in `toolUseResult.answers` (a string, or a list for multi-select) -> this session's transcript
- [verified] every account's Claude Code sessions on this computer share `~/.claude/projects` -> transcripts carry three organization ids; no CLAUDE_CONFIG_DIR, no other transcript folder (2026-11-08)
- [verified] a full scan is cheap -> 1.46 GB of top-level transcripts, 3112 owner lines, 1.7 s with a byte prefilter (2026-11-08)
- [verified] `@taste/<area>.md` in `~/.claude/CLAUDE.md` resolves relative to `~/.claude` and user-scope imports load without the approval dialog; block-level HTML comments are stripped -> docs: code.claude.com/docs/en/memory.md, "Import additional files" (checked 2026-11-08)
- [verified] Codex reads `~/.codex/AGENTS.md` as global instructions; it counts toward the 32 KiB project_doc_max_bytes total -> docs: learn.chatgpt.com/docs/agent-configuration/agents-md (checked 2026-11-08)

## Acceptance criteria
<!-- each maps to an executable test where possible; list test paths. A ticked
     line needs "-> <existing path>" or "-> judgment: <reason>"
     (scripts/tasklint.sh check) -->
- [x] Owner filter: human and legacy owner lines kept; peer, task notification, another session's brief, scheduled prompts and skill bodies dropped, in the taste digest and the project digest -> tests/template/test_taste.sh, tests/template/test_dream.sh
- [x] The taste digest reads every project folder and each extra `--projects-dir`, emits kinds P O C D A R T F with stable ids, project, session and `re:` context, merges duplicates across sessions and projects with counts, and keeps the priority order under `--max-bytes` -> tests/template/test_taste.sh
- [x] Pool: a signal the cap cut appears in the next digest; an older unused signal plus a new one from another session meet the two-session rule; shown, unused signals unseen for 180 days are pruned at `done` -> tests/template/test_taste.sh
- [x] Stop early: fewer than `--min-signals` never-shown signals, or under `--min-days` since the last pass, exits 3 with no digest and no model, keeping the new signals in the pool; `--force` skips the day rule -> tests/template/test_taste.sh
- [x] Once only: `done` commits offsets and pool; a second digest with no new lines finds no new signal; a partial last line is read on the next run -> tests/template/test_taste.sh
- [x] `apply` writes only the approved numbers (add, revise, remove), assigns unique global ids, and refuses unknown numbers, malformed proposals, evidence ids missing from the pool, and an inferred proposal whose signals come from one session -> tests/template/test_taste.sh
- [x] `apply` keeps the import block in CLAUDE.md and the profile block in Codex AGENTS.md current, creates them when missing, leaves every byte outside the markers unchanged, and a second identical run changes nothing -> tests/template/test_taste.sh
- [x] Caps: `check` and `apply` fail above 160 characters a line or 6000 bytes in total, naming the file and line -> tests/template/test_taste.sh
- [x] Safety: `apply` refuses a taste folder inside a git work tree; a state with a newer format version is refused with "update the template"; the tests write only under a temporary `TASTE_HOME` -> tests/template/test_taste.sh
- [x] Agent and Codex twin, procedure section, ADR 0011, check.sh required list, BLUEPRINT tree and BACKLOG rows are in place -> scripts/check.sh
- [x] No tracked file holds a profile line, a real quote or a private project name -> judgment: reviewer reads the diff
- [x] `./scripts/check.sh` green and the reviewer's PASS recorded below -> judgment: verify output and Review verdict
- [x] Taste outcome: `taste done --report` appends applied and declined numbers, the changes and files touched, and profile lines and bytes before and after -> tests/template/test_taste.sh
- [x] Taste impact: the next digest lists profile changes since the last pass, lines seen again, word-overlap candidates and a trend of fresh signals by kind per pass -> tests/template/test_taste.sh
- [x] Project outcome: `dream.sh done --report R --applied N...` appends applied and declined numbers, files named in the applied Change lines and hygiene numbers before and after -> tests/template/test_dream.sh
- [x] Project impact: the digest lists a trend of signal counts by kind per dream, approved lessons unused for more than 45 days by git date, and lessons whose words recur in new signals -> tests/template/test_dream.sh
- [x] First real run: a digest over every local project and a taste-dreamer report of numbered proposals, saved under `~/.claude/taste/.dream/reports/` and shown to the owner, with digest time, bytes read and agent tokens in the Progress log -> judgment: the owner reads the report
- [x] First real apply (owner approved this scope 2026-11-08): the owner's approved numbers written by `apply`, `~/.claude/CLAUDE.md` and `~/.codex/AGENTS.md` blocks created, `taste check` OK, `taste done` run, and a fresh session shows the profile loaded -> judgment: command output and the fresh session's answer

## Plan
<!-- task graph: one node per row; nodes that can run in the same wave must
     own disjoint files. Tiers: cheap, standard, strong, advisor, reviewer.
     Status: todo, doing, done, blocked. Validate: scripts/taskgraph.sh check -->
| node | depends on | owner files | worker tier | status |
|---|---|---|---|---|
| N1 | - | tests/template/test_taste.sh, tests/template/test_dream.sh | advisor | done |
| N2 | N1 | scripts/dream/taste.py, scripts/dream/dream.py, scripts/dream.sh | advisor | done |
| N3 | - | .claude/agents/taste-dreamer.md, .codex/agents/taste-dreamer.toml, docs/procedures/dream.md, docs/decisions/0011-personal-taste-profile.md, .claude/skills/dream/SKILL.md, .agents/skills/dream/SKILL.md | advisor | done |
| N4 | N2, N3 | scripts/check.sh, tests/template/fixtures/check.sh, docs/BLUEPRINT.md, BACKLOG.md, README.md | advisor | done |
| N5 | N4 | .work/TASK.md | reviewer | done |
| N6 | N5 | none tracked: ~/.claude/taste/.dream/ only | advisor | done |

## Plan verdict
<!-- autopilot only: the reviewer's plan review of Goal, Assumptions,
     Acceptance criteria and Plan, written before any node starts;
     scripts/tasklint.sh requires PASS once a node is doing or done -->

## Progress log
<!-- timestamped one-liners; this is what survives compaction -->
- 2026-11-08 design questions answered by the owner; worktree C:/dev/work/New-Project-taste on task/taste-profile from task/dreaming 274ffed
- 2026-11-08 builder check: three gaps; evidence pool and format version settled as builder's calls; scope of the first real apply goes to the owner
- 2026-11-08 owner approved the design and the first real apply
- 2026-11-08 N1: test_dream.sh owner filter fails 4 on the old dream.py (122/126), passes 126/126 after the fix; test_taste.sh written first
- 2026-11-08 N2: test_taste.sh 124/124; mutation check: session rule off -> 9 fail, git guard off -> 4, format guard off -> 4, prune ignoring used -> 1, used signals shown again -> 1; prefilter off -> 0 (speed only)
- 2026-11-08 dry run on real transcripts (scratch TASTE_HOME): 256028 lines in 4.1 s, pool 527 signals (P 126, T 120, A 113, O 58, F 55, C 38, R 13, D 4), 228 shown under the 40 KB cap; it showed placeholder answers counted as own words and projects named after subfolders, both fixed test-first
- 2026-11-08 N3, N4 written by the advisor (no worker: the edits were small and judgment-bound)
- 2026-11-08 ./scripts/check.sh exit 0 (selftest 21/21, template self-test OK, 141 required files) on the tree before the check fix below
- 2026-11-08 first real digest: 256225 lines in 4.0 s, 505 signals shown (cap raised to 100 KB for the first pass, 3 dropped), pool 508; taste-dreamer (Sonnet, read-only) 64752 tokens, 12 proposals, all pass the evidence rule and line cap; report at ~/.claude/taste/.dream/reports/2026-11-07-report.md
- 2026-11-08 owner approved 1-11, declined 12 (direct-to-main conflicts with the template default); apply wrote T001-T011 in 5 areas, 1717 of 6000 bytes; ~/.claude/CLAUDE.md created with the import block; ~/.codex/AGENTS.md filled; done and check OK
- 2026-11-08 a subagent saw no T ids: inconclusive, subagents reuse this session's startup instructions; a new session must confirm the profile loads
- 2026-11-08 owner opened a new Claude Code session and confirmed it lists T001-T011 from its instructions; first-real-apply criterion ticked
- 2026-11-08 taste check reported a stale block for a user with no profile and their own CLAUDE.md; failing test first (124/125), fixed (125/125); `l` names renamed ahead of the move under scripts/dream/ruff.toml (E741)
- 2026-11-08 scope addition relayed by the parent session: an end-of-dream outcome and impact report; the owner approved the design here; dream.py edits paused until fleet-sync-fixes moves it to scripts/dream/
- 2026-11-08 taste outcome and impact: 15 new checks failed first (126/141), pass after the change (141/141); agent and procedure point at the Impact section; the project-dream half waits for the dream.py move
- 2026-11-08 merged task/fleet-sync-fixes 9f9bd28 (dream.py now scripts/dream/dream.py); taste.py moved beside it under scripts/dream/ruff.toml; ruff 0.16.10 check clean; test_taste 141/141, test_dream 126/126 after the merge
- 2026-11-08 project outcome and impact: 17 new checks failed first (136/153), pass after the change (153/153); words, STOP and fmt_counts shared from dream.py, taste.py reuses them (141/141); mutation check: plain messages as mechanize evidence -> 1 fail, trend dropped on an exit-3 digest -> 1, used lessons as retire candidates -> 1, declined Change files listed -> 1
- 2026-11-08 real project digest (scratch state): 258573 lines in 3.1 s, 102 signals; impact lists 5 lessons sharing words with new failures, no retire candidate (no approved used: 0 line older than 45 days)
- 2026-11-08 ./scripts/check.sh exit 0: selftest 22/22, template self-test OK (146 required files, ruff 0.16.10 contract, blueprint parity)
- 2026-11-08 review round 1 FAIL: a repeated approved number applied twice, and a report numbering two proposals alike silently kept the later. Failing tests first (taste 129/149, dream 151/158), then fixed: apply and done refuse both (taste 149/149, dream 158/158). Also from the review: a .git entry git cannot read now counts as a repository for the guard (failing test first); design call 2 corrected to the rule is_human applies. Accepted as is: taste parse_report reads only the first line of a proposal, since the agent format forbids wrapping, and apply's line cap still bounds what lands
- 2026-11-08 review round 2 PASS on 7202d81 (verdict below); the cosmetic printf note fixed after it (format strings only; taste 149/149, dream 158/158)

## Review verdict
<!-- written ONLY by the independent reviewer -->
Round 1 (reviewer, 2026-11-08, HEAD f50a390, diff against task/fleet-sync-fixes, 19 files): FAIL. Blocking: a duplicate approved number was applied twice (taste.py cmd_apply checked the ledger only before its update), and a report numbering two proposals alike silently kept the later (taste.py and dream.py parse_report); no test covered either. Non-blocking: design call 2 text did not match is_human; inside_git failed open on a git error such as dubious ownership; parse_report reads only a proposal's first line; the fleet-sync-fixes record belongs to that branch's retro; commit bodies of 7d680f4 and a6cb0ac not readable without git.

Round 2 (reviewer, 2026-11-08, HEAD 7202d81): PASS. The round-1 blocker is fixed with failing-first tests and nothing new blocks. cmd_apply records a repeated approved number as a problem (exit 1, nothing written, all-or-nothing); both parse_report functions exit 2 on a repeated proposal number; dream.py outcome_text refuses a repeated --applied number before any state write. Design call 2 now states the rule is_human applies. inside_git walks up for any .git entry before asking git; the real home has no .git above it. Non-blocking: two printf format strings held a literal line break instead of \n (cosmetic; fixed after the verdict). Both judgment criteria may be ticked: no profile line, real quote or private project name in any added tracked text; private names appear only in removed base TASK.md lines.

Evidence checked: check3.log in full (every stage OK; selftest 22 passed, 0 failed, 0 quarantined; template ruff 0.16.10; template self-test OK, 146 required files; exit 0); review2.diff in full (5 files); review.diff in full (round 1, 19 files); scripts/dream/taste.py 182-211 in the tree; .work/TASK.md criteria; COMMIT_EDITMSG for 7202d81 (no trailers); grep of both diffs for em/en dashes and curly quotes (none); the home folder and drive root hold no .git; the RDUP and RD10 test blocks.

## Retro
<!-- filled by docs/procedures/retro.md -->
- Defects by route: (a) caught pre-merge: review round 1 FAIL (a repeated approved number applied twice; a report repeating a proposal number accepted), fixed test-first (taste 129/149 and dream 151/158 failing before, 149/149 and 158/158 after). No defect escaped past merge (b) or was reported by the human (c). (d) self-noticed: an outcome test compared a /tmp path with the C:/ form Python printed; the assertion now matches only the path-free part.
- Traps: inline heredoc scripts lost escapes in the shell tool again (PENDING "Inline generator scripts lose their escapes through the shell" recurred; patch files written with the Write tool instead). ADR 0010 collided with main's ADR 0010 at the merge (PENDING "ADR numbers collide across parallel branches" recurred); renumbered to 0011 in the merge commit. One new process entry in docs/lessons/UPSTREAM.md: a path printed by Python under Git Bash is in Windows form.
- Confirmed by the owner: 11 of 12 proposed profile lines approved; a fresh session lists T001 to T011, so the profile loads. CI on 87ba9fe: check success, deploy skipped.
- Decision recorded: ADR 0011 personal taste profile (was 0010 on this branch).
- Lessons consulted: L002, L005, L006, L008, L009, L010 (counters bumped after the merge, on top of main's).
