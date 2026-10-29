# Task: kb-adaptations
Mode: standard
Branch: task/kb-adaptations
Date: 2026-10-28

## Goal
Adapt nine process ideas found in the public coleam00/cole-medin-knowledge-base
repository into the template, re-expressed (that repository has no license, so
no text is copied). Six close gaps in the core: a Stop hook that checks the task
state at every turn end and runs the quick gate once every criterion is ticked, a destructive-command guard for every session,
git context at session start, an Assumptions section in TASK.md, evidence for
ticked criteria, and a reviewer plan check in autopilot mode. Three are
lower-priority additions: a quote-integrity checker in the hardware-pcb profile, a
trap-question evaluation of the template's own docs, and a wider character gate
(typographic quotes, ellipsis, non-breaking space, mis-encoded text).

## Non-goals
- No kernel edit (AGENTS.md kernel block and `.kernel.hash` unchanged).
- No vendoring of the knowledge base's pages or scripts.
- No change to the merge of open PRs 6 and 7; this branch starts from main.
- The ideas the earlier comparison rejected (PreCompact hook, Ralph loop,
  markdown link lint, cross-vendor reviewer, commandify retro step).

## Budget
- Wall-clock: 4 hours
- Subagents / workflow runs: 8, raised by the human on 2026-10-29 after it ran out, no new cap set ("Yes, fix and finish")
- Retries per failing step: 2
- Escalate to human when: budget exhausted | criteria unreachable | scope exceeds Non-goals

## Assumptions
<!-- one line per assumption the work rests on: [confirmed] the human said so,
     [verified] evidence names a command or file, [open] not yet settled.
     The full gate fails while any line is [open], except in quick mode. -->
- [confirmed] The human asked for all nine items on 2026-10-29 ("adapt all the ones you stated - the 6 and the 3 lower priority").
- [verified] Claude Code hooks: Stop stdin carries stop_hook_active; exit 2 blocks and feeds stderr back (Stop and PreToolUse); timeout is in seconds, default 600 for command hooks; project settings hooks also run inside subagents; matcher Bash|PowerShell is valid -> code.claude.com/docs/en/hooks.md and sub-agents.md, VERIFY 2026-10-29
- [confirmed] The quote checker ships as a hardware-pcb profile tool for datasheet quotes, not in the library (human, 2026-10-29).
- [confirmed] C1 narrowed for speed: task-state checks at every turn end, the quick gate only once every criterion is ticked, cached by tree state (human approved the amended C1, 2026-10-29).
- [verified] No typographic quotes, ellipsis, non-breaking space, replacement character or mojibake exist in tracked files today -> git grep scan run 2026-10-29, 0 hits.

## Acceptance criteria
- [x] C1 Stop hook: `scripts/stop-gate.sh` blocks (exit 2, reason on stderr) when `.work/TASK.md` holds a live task and its task-state checks fail, or every criterion is ticked and `scripts/quickgate.sh` fails (narrowed 2026-10-29 for speed, approved by the human); allows when the task file is pristine, when `stop_hook_active` is true, when the quick lane is not wired, and when the tree is unchanged since the last green run; `.claude/settings.json` wires it -> tests/template/test_stop_gate.sh
- [x] C2 Destructive guard: `scripts/destructive-guard.sh` blocks force push, remote branch delete, `--no-verify`, `reset --hard`, `clean -f`, `branch -D`, whole-tree checkout and restore, `stash drop` and `clear`, and recursive removal of a root, home, workspace, bare glob or variable path, from Bash and PowerShell payloads; allows the safe forms; wired as a PreToolUse hook with matcher `Bash|PowerShell` -> tests/template/test_destructive_guard.sh
- [x] C3 Session start prints the branch, `git status --short` (capped) and the last 10 commits, and still works outside a git repository -> tests/template/test_session_context.sh
- [x] C4 The TASK.md template carries an Assumptions section (new-task.sh, BLUEPRINT 3.11); `scripts/tasklint.sh ship` fails on an `[open]` line unless the mode is quick, and the full check.sh runs it -> tests/template/test_tasklint.sh, tests/template/test_new_task.sh
- [x] C5 `scripts/tasklint.sh check` fails a ticked criterion whose evidence names no existing path and no `judgment:` reason; runs in the always section -> tests/template/test_tasklint.sh
- [x] C6 Autopilot tasks carry a Plan verdict section; tasklint requires a PASS verdict once a plan node is doing or done, and always in ship mode; the reviewer (Claude and Codex) documents the plan-review input and checks -> tests/template/test_tasklint.sh, .claude/agents/reviewer.md
- [x] C7 `docs/profiles/hardware-pcb/tools/check_quotes.py` verifies every cited quote appears in its local source (Markdown, text; PDF page when pymupdf is installed); exit 0 pass, 1 check failed, 2 could not run; listed in the hardware-pcb PROFILE.md -> docs/profiles/hardware-pcb/tools/tests/test_check_quotes.py
- [x] C8 Doc evaluation: `tests/docs/questions.md` (answerable questions with an answer key, plus trap questions), `scripts/doc-eval.sh check` (format, sources exist, minimum counts) in the always section and `brief` (questions without the key), `docs/procedures/doc-eval.md`, a maintain step, and one recorded run against the template -> tests/template/test_doc_eval.sh
- [x] C9 The character gate fails check.sh, including `--quick`, on typographic quotes, the ellipsis character, non-breaking space, the replacement character and mojibake -> tests/template/test_check_always.sh
- [x] C10 Wiring: required list, BLUEPRINT tree and Amendment 4, README enforcement list, fixture copy identical; `./scripts/check.sh` green -> scripts/check.sh

## Plan
| node | depends on | owner files | worker tier | status |
|---|---|---|---|---|
| N1 guard | - | scripts/destructive-guard.sh, tests/template/test_destructive_guard.sh | standard | done |
| N2 tasklint | - | scripts/tasklint.sh, tests/template/test_tasklint.sh | standard | done |
| N3 quotes | - | docs/profiles/hardware-pcb/tools/check_quotes.py, docs/profiles/hardware-pcb/tools/tests/test_check_quotes.py | standard | done |
| N4 stop+context | - | scripts/stop-gate.sh, scripts/session-context.sh, tests/template/test_stop_gate.sh, tests/template/test_session_context.sh | advisor | done |
| N5 doc-eval | - | scripts/doc-eval.sh, tests/docs/questions.md, docs/procedures/doc-eval.md, docs/procedures/maintain.md, tests/template/test_doc_eval.sh | advisor | done |
| N6 template+reviewer | - | scripts/new-task.sh, tests/template/test_new_task.sh, .claude/agents/reviewer.md, .codex/agents/reviewer.toml | advisor | done |
| N7 wiring | N1, N2, N3, N4, N5, N6 | scripts/check.sh, tests/template/fixtures/check.sh, tests/template/test_check_always.sh, .claude/settings.json, docs/BLUEPRINT.md, docs/profiles/hardware-pcb/PROFILE.md, README.md, BACKLOG.md | advisor | done |
| N8 review | N7 | .work/TASK.md | reviewer | done |

## Progress log
- 2026-10-29 branch task/kb-adaptations from origin/main; spec written.
- 2026-10-29 criteria approved by the human; quote checker moved to the hardware-pcb profile; hook facts verified.
- 2026-10-29 workers delivered N1 guard (523 assertions), N2 tasklint (120), N3 check_quotes (50 tests); advisor spot-checked each by hand. Guard: added re-exec under a Homebrew bash before refusing on bash < 4.4.
- 2026-10-29 measured: quickgate 565 s (3 workers running), test_check_always.sh alone 340 s. C1 narrowed: the Stop gate runs taskgraph and tasklint on every stop and the quick gate only once every criterion is ticked, cached by tree state.
- 2026-10-29 doc-eval run (explore answered, reviewer judged): answerable 11/11 CORRECT, traps 4/4 DECLINED, 0 leaked. PASS. Follow-ups fixed: q12 key accepts check.sh --quick or quickgate.sh (README now says they are the same lane); docs/rules/orchestration.md reviewer line says complete verify output, missing means FAIL.
- 2026-10-29 full gate run 1: red. The character gate caught real non-ASCII bytes in tests/template/test_check_always.sh (escapes expanded while editing); fixed with an ASCII-only loop.
- 2026-10-29 full gate run 2: green (check.sh exit 0, 17/17 self-test files); criteria ticked.
- 2026-10-29 reviewer round 1: FAIL. (1) stop-gate allowed a wired quick lane that exits 2; fixed: "not wired" is decided by quickgate's own test before running, every nonzero exit blocks, test added. (2) `rm "$BUILD_DIR"/*` without -r was allowed; (3) home, workspace and ancestors by literal path, and commands inside bash -c, PowerShell -Command and cmd /c were allowed; both fixed by a worker (915 assertions), advisor spot-checked with this repo's real paths. (4) C1 narrowing lacked approval; the human approved it, Goal aligned. Non-blocking: VERIFY marker added to the hook-timeout claim; upgrade note for running autopilot tasks added to BLUEPRINT Amendment 4.
- 2026-10-29 full gate run 3: green (check.sh exit 0, 17/17). Reviewer round 2: FAIL. Round-1 findings all resolved with tests. New: the guard misses commands behind shell keywords and grouping (then, do, else, braces, parentheses, PowerShell if blocks) and ignores a cd earlier in the same command, so `cd .. && rm -rf "New Project"` would delete the workspace. Advisor reproduced all seven examples (each exits 0). Budget exhausted (9 of 8 subagent runs, wall-clock over 4 hours): stopped and escalated to the human per the Budget section. Nothing committed.
- 2026-10-29 the human raised the budget and chose to fix both guard gaps; worker briefed on shell syntax, cd tracking and .git removal.
- 2026-10-29 guard round 3: split on brackets and backticks, shell keywords skipped, cd/pushd/Set-Location tracked (unresolvable cd refuses relative recursive targets), recursive .git removal refused (worker, 1229 assertions). Advisor closed the subshell-cd gap the worker reported: a relative target is also resolved against the payload cwd (test added, 1235 assertions); 16-case spot check by hand all as expected; 0.09 s per call. C7 evidence run explicitly: 50 tests OK (scratchpad verify-c7.txt).
- 2026-10-29 trap: the live guard refuses any shell command whose text contains a destructive form, including test strings inside heredocs and inline scripts; write such test inputs to a file and run it by path.
- 2026-10-29 full gate run 4: green. Reviewer round 3: FAIL, one finding: an escaped space (bash New\ Project, PowerShell New` Project) split the workspace name, so its removal was allowed. Fixed: a backslash or backtick before a space is read both ways (escaped space, and a Windows path ending in a separator such as C:\ -Recurse); either reading can refuse. Tests added (1243 assertions). Goal wording aligned (quote checker is in the hardware-pcb profile).
- 2026-10-29 full gate run 5: green. Reviewer round 4: FAIL, one finding: a quoted workspace path with a space inside cmd /c or pwsh -Command lost its quotes when the inner command was rebuilt, and bash -c with escaped inner quotes was misread. Fixed: wrapper arguments of a multi-word inner command are re-quoted (a single argument passes through as written), and the second reading treats a backslash-escaped double quote inside double quotes as a literal quote. 7 tests added with this workspace's spaced path (1257 assertions); first attempt re-quoted single arguments too and broke 44 assertions, caught by the existing tests.

## Review verdict
<!-- written ONLY by the independent reviewer -->
Round 5 (rounds 1 to 4 were FAIL; their findings are in the Progress log):

PASS

Earlier findings, each fixed at its cause with a test that asserts the requirement:
- Round 1: `scripts/stop-gate.sh` now decides "not wired" from quickgate's own `--quick` test and blocks on any nonzero exit, pinned by test_stop_gate.sh ("a wired lane that exits 2 is a real failure: block"). `rm "$BUILD_DIR"/*` is refused (`check_removal` glob-under-variable branch, test_destructive_guard.sh "rm \"$BUILD_DIR\"/* (no -r) is blocked"). Home, workspace and ancestors are refused by literal path in every spelling, and `bash -c`, `-Command` and `cmd /c` are unwrapped (the "Home and workspace by literal path" and "Interpreter wrappers" blocks). The C1 narrowing is recorded as human-approved in TASK.md Assumptions line 37 and the Goal.
- Round 2: commands behind keywords and grouping (if/then/else, for/while, braces, subshells, `$(...)`, backticks, PowerShell if/foreach) are covered by the "Shell syntax must not hide the command name" block. cd/pushd/Set-Location tracking is covered by the "A cd earlier in the command" block, including the exact `cd .. && rm -rf "New Project"` case.
- Round 3: escaped spaces (`New\ Project`, PowerShell backtick before a space) are read both ways, with tests at lines 3150-3157 of review5.diff.
- Round 4: wrapper arguments are re-quoted, and a backslash-escaped quote is read as a literal quote in the second reading. Tests use this workspace's real path: `cmd /c`, `cmd //c`, `pwsh -Command` and `bash -c` with escaped quotes are all blocked; narrow spaced paths are allowed (lines 3158-3171).

Criteria C1 to C10 are met by the scripts and tests in the diff. The tests check behaviour (exit codes, messages, quick-gate run counts, an untouched index), not internals.

Required everyday forms, checked against the guard: `git add`, `./scripts/check.sh`, `rm` of a literal file, `cd build && rm -rf out`, if/for loops, Windows paths ending in a backslash, and `powershell -Command "..."` are all allowed by tests. I traced a commit message with escaped inner quotes by hand: allowed in both readings.

No gate was weakened. The kernel is unchanged (kernel-hash OK). No secrets or private data are in the diff. Every new file is ASCII. The check.sh fixture is byte-identical to check.sh (same blob change, 776069c..9b85164).

Non-blocking:
1. The rule doc and guard header say the quote-unaware split only over-blocks. It also under-blocks a quoted protected path that contains `& ; | ( ) { }` or a backtick. Example: a workspace under `C:\x\R&D\proj`, removed by its literal quoted path, is allowed. This does not affect this repo's paths (`C:\dev\work\New Project`, home `C:\Users\<user>`). Suggest adding it to Limits.
2. Rare forms outside the stated contract are allowed: backtick command substitution as a target (`` rm -rf `pwd` ``); a PowerShell expression as a target (`(Get-Location)`); `~+`; partial globs that match the workspace (`cd .. && rm -rf New*`); `-Path:<value>`; shortened git long options (`--no-verif`, `--forc`, `--har`); `git -c core.hooksPath=...`.
3. No test pins the required case `git commit -m "say \"hi\""` (backslash-escaped inner quotes). It is allowed by hand trace; suggest adding an allowed() case.
4. The full check.sh run (verify6.txt) came before the Budget-line edit. verify6-post.txt re-runs tasklint check, tasklint ship and taskgraph. I confirmed .work/TASK.md has 0 non-ASCII bytes, so the character gate result still holds.
5. On bash older than 4.4 with no Homebrew bash, the guard blocks every command. This is documented in manifest.md and BACKLOG.md (P3).
6. Rule 13: pymupdf is an optional, lazily imported package, not a declared dependency. The commit body should still say why it is used.

Evidence checked:
- verify6.txt: kernel-hash OK, line-budget OK 79/180, lessons OK, taskgraph OK (8 nodes), adr OK, tasklint check OK and ship OK (10 ticked, 5 assumptions), doc-eval OK (11 answerable, 4 trap). 17 PASS lines, then "selftest: 17 passed, 0 failed", "template self-test: OK (122 required files ...)", "check.sh exit=0". There is no untracked-files, dash or character warning.
- verify6-post.txt: tasklint check OK, tasklint ship OK, taskgraph OK.
- verify-c7.txt: "Ran 50 tests ... OK" (no skips, so the real-PDF tests ran), "unittest exit=0".
- review5.diff read in full (lines 1-3907): scripts/destructive-guard.sh (all functions traced), stop-gate.sh, tasklint.sh, doc-eval.sh, session-context.sh, new-task.sh, check.sh, check_quotes.py and its tests, all tests/template tests, settings.json, reviewer.md and reviewer.toml, BLUEPRINT, README, rules docs, manifest, BACKLOG.
- review1-findings.txt to review4-findings.txt, each matched to its fix and test as above.
- .work/TASK.md lines 1-84: criteria, Assumptions, Plan, Progress log.
- scripts/quickgate.sh lines 17-21 (its own "not wired" test, which stop-gate mirrors).
- scripts/check.sh lines 84-120 (stages that print nothing when clean).
- docs/BLUEPRINT.md line 419 (3.11 is the TASK.md template).
- docs/profiles/hardware-pcb/PROFILE.md lines 15, 55, 63 (PCB-2, tool exit convention, check_quotes listed).
- tests/template/test_profile_tools.sh lines 7-28 (Python tool tests skip without python, hence the separate C7 run).
- AGENTS.md lines 66 and 76 (template mode, no profiles adopted yet).
- Search for non-ASCII bytes in .work/TASK.md and in all new or changed scripts, tests and docs: 0 hits.
- Search for an escaped-quote commit-message test in test_destructive_guard.sh: none (non-blocking item 3).

## Retro
<!-- filled by docs/procedures/retro.md -->
