# Task: feedback-loop
Mode: autopilot
Branch: task/feedback-loop
Date: 2026-11-08

## Goal
Make the repository learn what the owner wants, for any kind of task, and
keep it learned. There are five parts:
1. **Capture.** In a Claude Code session with the hook wired, every owner message is logged as it happens, with its situation (task, branch, files being worked on, what the agent just said), and a script guesses its kind (correction, preference, approval, deferral, message).
2. **Preference registers.** Durable preferences live in per-area files, docs/preferences/<area>.md. Each rule there has its source (date and the owner's words) and either a named check that fails when the rule is broken, or "Review".
3. **Repeats.** The dream reads the log, flags feedback that repeats an existing rule (the system knew and failed), and proposes moving that rule to a stronger guard (Review, then a named check).
4. **Baselines.** An approved deliverable is recorded as the baseline for its kind, and a new variant starts from it instead of from zero.
5. **Draft review.** A first draft of an owner-facing deliverable is checked against the relevant registers before the owner sees it.

## Non-goals
- A model in the capture hook: classification is by script, and the hook never blocks or delays a prompt beyond its time budget.
- Committing the raw feedback log. It holds the owner's words and session context, so it stays local and gitignored, like the dream state. Only approved register rows enter git.
- Shipping register rows in the template. The template ships the format, tools and procedures; projects own their rows.
- The self-review (meta) pass and the replay check of the dreamer.
- The cross-project taste profile (~/.claude/taste). It stays as it is; registers are per project.

## Budget
- Wall-clock: 6 h
- Subagents / workflow runs: 8 (plan reviewer, 4 workers, change reviewer, monitor, spare)
- Retries per failing step: 2
- Escalate to human when: criteria unreachable, scope exceeds Non-goals, or a kernel edit is needed

## Assumptions
- [confirmed] the owner asked for this, general across all task types, in the template first and then in three started projects ("Make note taking and my feedback more relevant ... it should log the situation somewhere so dreams have a better chance to change the project repo for the better", "apply it in new project and then in all 3 project repos", "generalize it ... applicable across all types of tasks", 2026-11-08)
- [confirmed] the owner approved the four ideas behind this design (repeat detection, baselines, draft review, registers in every project): "I like those correction- apply it", 2026-11-08
- [confirmed] approval path for register rows (kernel rule 9). Same-turn recording is allowed only for an explicit owner statement: the row quotes the owner's words with the date, and the reply shows the row so the owner can veto it. Everything inferred goes through the dream's numbered approval. The owner asked for automatic recording -> a started project's film taste file and "make note taking and my feedback more relevant", 2026-11-08
- [verified] a UserPromptSubmit hook gets JSON on stdin (prompt, session_id, cwd, transcript_path), and its stdout is added to the model's context; a per-hook "timeout" key bounds it -> the Claude Code hooks reference
- [verified] dream.py has is_human, MACHINE_PREFIXES, is_correction, MSG_LIMIT, main_worktree and offset state committed by done from state.next.json -> scripts/dream/dream.py:55-71, 173-253, 803-879
- [verified] dream.sh runs python -I, so a sibling import needs taste.py's sys.path pattern -> scripts/dream.sh:39, scripts/dream/taste.py:55-56
- [verified] a started project's film taste file is a working register whose real cell formats the check must accept (month-only dates, "Review (note)", bare test file names, commands with arguments, several checks per cell) -> that project's film taste file
- [verified] the digest drops many signals at its 40 KB cap (294, 179 and 701 in the three 2026-11-08 project dreams) -> the three digests
- [verified] started projects customise .claude/settings.json, so a sync reports it as CONFLICT and the hook entry needs a hand merge -> a started project's .claude/settings.json, scripts/template-sync.sh:83

## Design
Capture works only in Claude Code sessions whose settings wire the hook. For Codex, the fallback is the prose step in docs/procedures/preferences.md (A13).

**Feedback log.**
- **Where.** `.work/feedback/log.jsonl` in the main checkout (dream.py main_worktree), shared by worktrees. The folder holds a .gitignore of "*".
- **Rotation.** Only the dream rotates, right after it commits the offset (`dream.sh done`, or a digest that exits 3 and so commits its own offsets): a log over 5 MB is renamed log.1.jsonl (one kept), a new log starts, and the offset resets to 0. The hook never rotates, so no line is lost. A log that is shorter than the saved offset outside that path resets the offset.
- **Each line** is a JSON object with these keys:
  - `v` (1), `ts` (UTC ISO), `session` (first 8 characters)
  - `branch`, `task` (the .work/TASK.md title, or "-" when it is absent or still the template)
  - `kind`: the script's guess, one of deferral, correction, preference, approval or message
  - `text`: the prompt, at most 2000 characters
  - `files`: up to 5 repository-relative paths that Edit, Write, MultiEdit or NotebookEdit tool calls touched in the transcript tail, newest first
  - `said`: the last assistant text in the tail, at most 300 characters

**Hook.**
- **Wiring.** `scripts/feedback-log.sh` (UserPromptSubmit, with `"timeout": 5` in .claude/settings.json) runs `scripts/dream/feedback.py`. feedback.py imports dream for is_human, is_correction and main_worktree, using taste.py's sys.path pattern; dream.py never imports feedback.
- **Bounds.** It reads at most the last 512 KB of the transcript and always exits 0.
- **Skipped.** It does nothing without Python or with FEEDBACK_LOG=0. It skips prompts that are machine-written (MACHINE_PREFIXES) or start with "/" or "<".
- **Prompting.** For a correction, preference or approval it prints one context line: "Owner feedback logged (kind, script guess). If it states a lasting preference, follow docs/procedures/preferences.md." For a deferral it prints: "Owner deferral logged (script guess): record it as a note (BACKLOG.md or the plan) and do not start the work." In template mode (no .start-done) no line asks for a register row.

**Classifier.** `classify(text)` in feedback.py; the first match wins, in this order:
1. **deferral:** later, not now, "just record", "don't|do not (do|build|change|code) ... (yet|now|later)", "no, later";
2. **correction:** is_correction (a start of no, don't, stop, actually, instead...) when not a deferral, or wrong, hate, revert, undo, broke, "why did", "not what i", "back to", "still (not|wrong|broken)", "(happened|doing it|is back) again";
3. **preference:** always, never, "from now on", "i want", "i prefer", "i like", "i don't like", "make sure", "every time";
4. **approval:** perfect, "exactly (right|what)", "love (it|this|that)", "looks (good|great)", "that's (it|great|perfect)", approved;
5. **message:** everything else.

It is a guess by word lists, and is labelled as one.

**Registers.**
- **Location.** docs/preferences/<area>.md, where area is any short name (film, ui, docs, code, communication, process).
- **Template ownership.** docs/preferences/README.md is template-owned (core set; projects do not edit it). It holds the format, how to add rows, the ladder from Review to a check, and baselines. Its example tables sit in code fences, so the check skips them.
- **Tables.** A rules table is any table whose header starts `| ID | Rule | Source | Check |`. A Repeats column is optional. The cells:
  - **ID:** unique within its file.
  - **Rule:** not empty.
  - **Source:** contains a date YYYY-MM or YYYY-MM-DD.
  - **Check:** "Review", optionally followed by a note, or one or more backticked references. A reference's first token is a path, relative to the repository root or a file name found once by git ls-files. "::name" must appear in that file. Words after the path are arguments.
  - **Repeats:** absent, or an integer. It changes only through an approved dream proposal, never by script.
- **Baselines** tables have the header `| Kind | Reference | Owns | Check |`. Reference is an existing path or a commit that git can resolve, plus a date.
- **The check.** `scripts/preferences.sh check` runs scripts/dream/preferences.py.
  - With no register files it prints "preferences: no registers" and exits 0.
  - With registers but no Python it exits 1 and says so.
  - In template mode, any file other than README.md fails, so the owner's words never reach the public template.
  - It warns (but does not fail) when scripts/feedback-log.sh exists and .claude/settings.json does not reference it.
  - check.sh runs it in the always section.

**Dream.** The digest gains two sections after the Scorecard:
- "## Feedback": log lines read since the last dream, of kind deferral, correction, preference or approval (plain messages already appear in Signals). Order is kind priority, then newest first, with ids f1, f2, and so on. Each line is clipped to MSG_LIMIT and shows task, branch and files. The section is capped at 12 KB, with the dropped count shown.
- "## Repeats": correction or preference feedback that shares two or more words with a register rule. Matching uses one word_hits(text, items) function that lesson_hits now calls with its kind filter. Lines read "<rule ID> <- f<N> (words)", at most 40, with the dropped count. These are candidates, not proof.

The log offset is read at digest time into state.next.json, and done commits it, as transcripts do. A partial last line waits for the next run. A malformed line is counted, not fatal.

The dreamer definitions (.claude/agents/dreamer.md and .codex/agents/dreamer.toml) read docs/preferences/*.md and add three kinds:
- [preference]: a new register row;
- [escalate]: a rule with repeats moves from Review to a named check, through a BACKLOG row or a test;
- [baseline]: an approved deliverable becomes a baseline.

**Procedures and wiring.**
- **docs/procedures/preferences.md:** recording in the same turn under the approval path above, the register format, the escalation ladder, baselines (start a variant from its baseline and reuse what it owns), and draft review (before the owner sees a first draft of an owner-facing deliverable, a reviewer checks it against every rule in the relevant registers and reports with evidence).
- **new-task.sh:** prints the register areas and baselines whose area or Kind word appears in the task slug or title.
- **session-context:** prints one line with the areas, the rule count and how many are Review, and the settings warning. It exits 0 on a malformed register.
- **Rules index:** one line points to preferences.md. This is outside the kernel.
- **upstream.md:** step 9 gains a hand merge of the UserPromptSubmit entry when settings.json conflicts.
- **New scripts:** executable in the index, listed in check.sh's required list and in the BLUEPRINT tree.

## Acceptance criteria
- [x] A1 the hook logs an owner prompt with every schema key, the kind set by classify; machine-written prompts and prompts starting with "/" or "<" are not logged -> tests/template/test_feedback.sh
- [x] A2 from a synthetic transcript the hook records up to 5 edited files newest first and the last assistant text; tool calls only in the head of a transcript larger than 512 KB are not reported; task is "-" for an absent or template TASK.md -> tests/template/test_feedback.sh
- [x] A3 the hook prints the feedback line for correction, preference and approval, the deferral line for a deferral, nothing for a message, and no row request in template mode; it exits 0 on a missing or malformed transcript, and writes nothing with FEEDBACK_LOG=0 or without python -> tests/template/test_feedback.sh
- [x] A4 the log is in the main checkout's self-ignoring .work/feedback, also from a linked worktree, and the hook never rotates it, even over 5 MB -> tests/template/test_feedback.sh
- [x] A5 classify, for each kind, matches a positive and rejects a negative, including "don't build it yet" and "no, later" as deferral, "run the tests again" and "what exactly does this do" as message, and "i don't like the font" as preference -> tests/template/test_feedback.sh
- [x] A6 preferences.sh check, as below -> tests/template/test_preferences.sh
  - passes: a valid register using the real cell formats (month date, "Review (note)", bare test file name, command with arguments, several references in one cell); no registers; a fenced README example;
  - fails, naming the file and row: a missing date; an empty rule; an unknown path; a missing ::name; a non-integer Repeats; a duplicate ID; a missing baseline reference; any non-README file in template mode;
  - warns: an unwired hook. -> tests/template/test_preferences.sh
- [x] A7 check.sh runs the register check in the always section, and the required list and blueprint list the new files -> tests/template/test_check_always.sh
- [x] A8 docs/preferences/README.md is in the core set, and template-sync never touches other docs/preferences files -> tests/template/test_template_sync.sh
- [x] A9 Feedback and Repeats sections, as below -> tests/template/test_dream.sh
  - placement and content: they come after the Scorecard, in kind-priority order, with clipped lines and the situation shown; the 12 KB and 40-line caps show their dropped counts; Repeats uses the shared word_hits;
  - offsets: a line appended between digest and done is read by the next digest; a partial line waits; a malformed line is counted; a shrunk log resets; done rotates a log over 5 MB after committing the offset, and the next digest reads the new log from 0. -> tests/template/test_dream.sh
- [x] A10 dreamer.md and dreamer.toml name the preference, escalate and baseline kinds and docs/preferences -> tests/template/test_dream.sh
- [x] A11 new-task.sh prints matching areas and baselines for a slug -> tests/template/test_new_task.sh
- [x] A12 session-context prints the register summary line and the unwired-hook warning, and exits 0 on a malformed register and with registers present but no Python -> tests/template/test_session_context.sh
- [x] A13 .claude/settings.json wires the hook for UserPromptSubmit with timeout 5; docs/rules/models.md (still at most 40 lines) names the Codex capture gap with a VERIFY date after checking current Codex hook support -> tests/template/test_check_always.sh
- [x] A14 docs/procedures/preferences.md, dream.md, upstream.md step 9, BLUEPRINT, README and the rules index describe the loop -> judgment: documentation completeness, read in review
- [x] A15 real data: the hook run on one real prompt and transcript of this session logs the right kind and files; only the kind and file list go in the Progress log -> judgment: real-data check, kernel rules 3 and 14
- [x] A16 ./scripts/check.sh exits 0 on the committed tree -> scripts/check.sh

## Plan
| node | depends on | owner files | worker tier | status |
|---|---|---|---|---|
| N1 | - | scripts/dream/feedback.py, scripts/feedback-log.sh, tests/template/test_feedback.sh, .claude/settings.json, docs/rules/models.md | standard | done |
| N2 | - | scripts/preferences.sh, scripts/dream/preferences.py, docs/preferences/README.md, tests/template/test_preferences.sh, scripts/template-sync.sh, tests/template/test_template_sync.sh | standard | done |
| N3 | N1 | scripts/dream/dream.py, scripts/dream.sh, tests/template/test_dream.sh, .claude/agents/dreamer.md, .codex/agents/dreamer.toml, docs/procedures/dream.md | strong | done |
| N4 | N1, N2, N3 | scripts/check.sh, tests/template/fixtures/check.sh, tests/template/test_check_always.sh, scripts/new-task.sh, tests/template/test_new_task.sh, scripts/session-context.sh, tests/template/test_session_context.sh, docs/procedures/preferences.md, docs/procedures/upstream.md, docs/BLUEPRINT.md, README.md, AGENTS.md | standard | done |
| N5 | N4 | .work/TASK.md | reviewer | done |

## Plan verdict
PASS. Reviewer plan review, round 2, 2026-11-08: all nine round-1 blocking findings are resolved, each with a criterion. Applied after the verdict:
- the non-blocking notes: rotation only at done (A4, A9), the Goal scope wording, the deferral context line (A3), and no Python in A12;
- valid A6 fixtures carry .start-done;
- That project's film taste rows that fall outside the grammar (a "::name" continuation, a Python expression, a flag, "Tested ...") are rewritten in that project's rollout.

Round 1: FAIL with nine blocking findings: B1 latency, B2 classifier order, B3 digest bounds, B4 offsets, B5 approval path, B6 public-template guard, B7 settings conflict, B8 real cell formats, B9 graph.

## Progress log
- 2026-11-08 branch task/feedback-loop from task/dream-scorecard d31a3a6 (the scorecard is not merged yet) in worktree C:/dev/work/New-Project-feedback
- 2026-11-08 N1: test_feedback.sh 92 passed, 0 failed
- 2026-11-08 N2: test_preferences.sh 47 passed, 0 failed (after the shared register reader moved into dream.py; the escaped-pipe case was added with the move and was not run against the old reader)
- 2026-11-08 N3: test_dream.sh 279 passed, 0 failed
- 2026-11-09 N4: test_new_task.sh fail-first 76 passed, 5 failed, then 81 passed, 0 failed; test_session_context.sh 64 passed, 0 failed (no clean fail-first run); test_blueprint_parity.sh 11 passed; test_template_sync.sh 155 passed; test_check_always.sh did not finish on the loaded machine (111 ok, 0 FAIL before the nested case), covered by the full check.sh below
- 2026-11-09 commit 3076532; merged task/dream-scorecard 9724587 (test_dream.sh conflict, both blocks kept) and origin/main af63c7a; test_dream.sh 287 passed, 0 failed on the merge
- 2026-11-09 A15 real data: the hook on this session's transcript (27 MB, last 512 KB read) with a correction and a deferral prompt logged kind correction and deferral; files [] while the tail held only scratchpad edits (outside the repo, correctly dropped), then ['.work/TASK.md'] after a real Edit; each run about 1 s; the two test lines were moved out of the real log so no dream reads them
- 2026-11-09 full ./scripts/check.sh on cd350b1: exit 1. scripts/dream/feedback.py:51 held a literal curly apostrophe (the character scan rejects it), so test_check_always's started-project case failed too. Fixed with the backslash u2019 escape. A new curly-apostrophe classifier case then failed through the hook (92 passed, 1 failed: got message): feedback.py read stdin in text mode, which uses the locale code page on Windows and garbles every non-ASCII prompt. Fixed by decoding stdin bytes as UTF-8; test_feedback.sh 93 passed, 0 failed; ruff check clean. The A15 prompts were ASCII, so A15 could not see this
- 2026-11-09 pushed 71271ac as PR 18; CI check failed on Linux only: test_session_context's no-python case dropped every PATH folder holding a python, and /usr/bin holds bash too. Fixed: such a folder is mirrored without the pythons and bash is called by path; 64 passed on Windows and under WSL Ubuntu 24.04
- 2026-11-09 change review round 1: FAIL. B1 a rotation lost lines logged between the digest and done; B2 template mode checked only top-level *.md, so other files under docs/preferences escaped; B3 a rules header with an extra column hid its table. Non-blocking N1 deferral line imperative on a false positive, N2 internal git timeouts, N3 .work/feedback/ not in the root .gitignore, N4 awk Review count with escaped pipes, N5 classifier order tests
- 2026-11-09 fail-first: test_preferences.sh 47 passed, 6 failed (B2 non-md file and subfolder, B3 extra column); test_dream.sh 309 passed, 1 failed (B1 a line typed during the dream). Fixed: rotation keeps the committed offset as a carry into log.1.jsonl, which the next digest reads first; template mode refuses any file under docs/preferences but the top README.md (preferences.sh counts with a bash recursive glob, so no find is needed); a rules header with other columns is "rules-extra" and every row is reported; N1 the deferral line is conditional; N3 .work/feedback/ added to .gitignore. After: test_preferences.sh 53, test_dream.sh 310, test_feedback.sh 93, all 0 failed; ruff clean. N2, N4, N5 left as BACKLOG rows
- 2026-11-09 change review round 2: PASS on 67ec3b6. GitHub CI ran the full ./scripts/check.sh on 67ec3b6 (push run) and its merge with main: exit 0, selftest 24 passed, 0 failed, template self-test OK; docs/procedures/dream.md now names the rotation carry

## Review verdict
<!-- written ONLY by the independent reviewer -->
Plan review: round 1 FAIL (B1-B9), round 2 PASS (see Plan verdict).

Change review round 1 (reviewer, 2026-11-09, 71271ac): FAIL. F0 no check.sh output for the head; B1 a rotation at done lost lines logged between the digest and done; B2 template mode checked only top-level *.md files under docs/preferences; B3 a rules header with an extra column hid its table. Non-blocking N1 to N5.

Change review round 2 (reviewer, 2026-11-09, 67ec3b6): PASS. F0 closed by the complete CI log of check.sh on an Ubuntu runner (selftest 24 passed, 0 failed; template self-test OK). B1 closed by the carry offset into log.1.jsonl, read first, with a test that fails without it; B2 closed by checking every file at any depth but the top README.md, in both the shell and Python layers, with a non-md file and a subfolder case; B3 closed by the rules-extra kind, reported row by row. N1 and N3 closed; N2, N4, N5 are BACKLOG rows. No assertion removed; the no-python test is stricter. Non-blocking: dream.md and the dream.py header did not mention the carry (dream.md updated).

Evidence checked: fb-full.diff and fb-fix1.diff in full; fb-ci-67ec3b6.txt in full; dream.py read_log_lines, read_feedback, rotate_feedback, register_table_kind, register_rules, cmd_done; preferences.py; preferences.sh; feedback.py; the new test cases; .gitignore.

## Retro
- Defects caught before merge (route a): a literal curly apostrophe in feedback.py and the Windows code-page stdin read (full check.sh, then a new test); a Linux-only test failure (CI); B1 to B3 (review). Each fix has a test that failed first. Nothing escaped.
- Trap (3a, process): the full local check.sh took over an hour on this Windows machine with many gates running, while CI runs the same script in about 2 minutes; the PR head's CI run is now the full-gate evidence. Recorded in docs/lessons/UPSTREAM.md; a BACKLOG row asks for a parallel selftest.
- Trap (3a): a progress note written through a shell heredoc turned an escape into the forbidden character it described; notes about characters go through a script file. Covered by the character scan, which caught it; no entry.
- Not done here: rollout to three started projects (with one project's film taste file moved to docs/preferences/film.md) follows the release.
