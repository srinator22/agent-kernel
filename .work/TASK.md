# Task: python-probe-shared-taste
Mode: autopilot
Branch: task/python-probe-shared-taste
Date: 2026-11-09

## Goal
Two fixes found by a project dream on the owner's second computer.
1. **Python probe.** The scripts pick `python3` before `python` with `command -v` only. On Windows `python3` can be the Microsoft Store stub, which `command -v` finds but which exits non-zero when run, so `scripts/dream.sh` fails, the feedback hook writes nothing, and `preferences.sh` and check.sh step 5f misfire. One shared helper, `scripts/find-python.sh`, chooses the interpreter by running it, and every script and test that picks Python uses it.
2. **Project taste.** The owner works on two computers and wants taste learned into the project, the same on every computer, and carried to another project only when asked. The taste pass becomes per project: its digest reads only this project's transcripts and this project's auto-memory notes; `apply` writes approved lines as rows in the project's preference registers (`docs/preferences/<area>.md`), which git carries between computers; every session start loads the registers' rules into context; `scripts/preferences.sh port --from <project>` copies rows from another project on the owner's explicit request. The user-level profile (`~/.claude/taste/*.md` and its managed blocks) is no longer written; existing files stay as the owner left them. This supersedes ADR 0011, recorded as ADR 0013.
3. **First-run setup check.** A missing or broken tool today degrades silently ("skipped locally"), which is how the second computer ran for days with no feedback log. `scripts/doctor.sh` runs each tool the template uses, reports what is missing or broken, and prints the install command for the detected system; session start prints one line when a required tool is missing; the README and the start procedure send a new owner to it first.

## Non-goals
- Moving or deleting the existing user-level profile or its managed blocks in `~/.claude/CLAUDE.md` and `~/.codex/AGENTS.md`.
- Porting rows between projects without the owner asking.
- Loading registers in Codex sessions (no SessionStart hook there yet; the BACKLOG Codex parity row covers it).
- Merging the two computers' taste state: each computer keeps its own offsets, pool and ledger for its own transcripts, under the project's gitignored `.work/dream/taste/`.
- Changing the evidence rule or the signal extraction.
- Syncing projects to the release (separate step after the release).

## Budget
- Wall-clock: 4 h
- Subagents / workflow runs: 9 (plan reviewer, 3 workers, change reviewer, monitor, spare)
- Retries per failing step: 2
- Escalate to human when: criteria unreachable, scope exceeds Non-goals, or a kernel edit is needed

## Assumptions
- [confirmed] the owner approved the python fix in the template instead of a project lesson (2026-11-09, answering the recommendation to fix it upstream as v0.5.2)
- [confirmed] taste is learned into the project, the same on every computer, and ported between projects only on request (owner, 2026-11-09); a shared private profile repository was rejected by the owner the same day
- [verified] the four scripts take python3 first by `command -v` only -> scripts/dream.sh:20, scripts/feedback-log.sh:11, scripts/preferences.sh:47, scripts/check.sh:313
- [verified] tests that pick Python the same way: fixtures/check.sh, test_dream.sh, test_preferences.sh, test_profile_tools.sh, test_taste.sh; test_session_context.sh:106-117 builds a no-Python PATH and is not a pick -> tests/template
- [verified] the stub exits 49 on the second computer while `python` is Python 3.13 -> judgment: proposal 1 of a project dream plan, 2026-11-09
- [verified] registers exist with a checked format (ID, Rule, Source with date and owner's words, Check, optional Repeats) and template mode refuses any register file -> docs/preferences/README.md, scripts/dream/preferences.py
- [verified] session start prints only a one-line register summary today, not the rules -> scripts/session-context.sh:47-91
- [verified] the project dream scopes transcripts to the repository by cwd against the root, its worktrees and known roots -> scripts/dream/dream.py:324, 1046, 1200
- [verified] taste.py writes user-level files and managed blocks and keeps state in ~/.claude/taste/.dream -> scripts/dream/taste.py:1-45, 528-591
- [verified] ADR 0011 records the user-level profile; replacing it needs a new ADR and a superseded status line -> docs/decisions/0011-personal-taste-profile.md, docs/procedures/adr.md:43-48
- [verified] `.work/dream/` is gitignored in the template -> .gitignore:35
- [verified] scripts/ is in the synced set as a directory, so a new scripts/find-python.sh reaches projects -> scripts/template-sync.sh:43
- [confirmed] (owner chose, 2026-11-09) recorded answer (c): the advisor ports the 11 user-level profile lines into the owner's four projects after they sync to this release, then removes the Claude import block; the Codex block stays until the BACKLOG Codex parity row loads registers in Codex. A template import command for user-level lines is out of scope
- [confirmed] (owner delegated, 2026-11-09) the user-level taste report on one project's second computer is not applied; after that project syncs to this release, a fresh `/dream taste` there reads that project's transcripts into its registers; the old report and pool stay in `~/.claude/taste/.dream/` for reference. The four taste lines the owner picked from it (T1, T2, T3, T5) are added to that project's registers by the advisor as owner-approved rows after the release

## Acceptance criteria
- [ ] A1 `scripts/find-python.sh`, sourced, sets PY to the first of python3, python that runs a Python 3 check with exit 0, else empty, and leaves no other variable set; with a temp bin holding a python3 that exits 49 and a python that execs the real interpreter, PY is python (never skipped) -> tests/template/test_find_python.sh
- [ ] A2 dream.sh, feedback-log.sh, preferences.sh and check.sh step 5f use the helper; with the stub first on PATH, `dream.sh due` finds Python and the feedback hook writes a log line; feedback-log.sh exits 0 even without the helper; check.sh 5f survives a missing or stub helper -> tests/template/test_find_python.sh
- [ ] A3 the four scripts and five picking tests source find-python.sh, and no other `command -v python3` pick remains in scripts/ or tests/template/ (test_find_python.sh and the no-Python PATH builder excepted) -> tests/template/test_find_python.sh
- [ ] A4 the taste digest reads only transcripts whose cwd matches this project (root, worktrees, known roots, as dream.py) and only this project's auto-memory feedback and user notes (from `D.memory_dir(c)`, the folder named after the main checkout); a transcript from another project contributes no signal, and a note in another project's memory folder contributes no signal even when one of its sessions worked here -> tests/template/test_taste_project.sh
- [ ] A5 taste state (state, pool, ledger, digest, reports) lives in `<main checkout>/.work/dream/taste/`, gitignored; nothing is written under `~/.claude/taste`, `~/.claude/CLAUDE.md` or `~/.codex/AGENTS.md` by any taste command (asserted with a temp HOME holding an existing profile and blocks, byte-identical after digest, apply and done) -> tests/template/test_taste_project.sh
- [ ] A6 `taste apply` writes each approved add as a row in `docs/preferences/<area>.md` (the file created with a title and the rules header when missing): ID per the Design's writer, Rule the proposal line, Source the signal's date and the quoted owner words of a cited P or O signal (for an O signal only the owner's part) else "YYYY-MM-DD: inferred from sessions <ids>", Check `Review`; revise and remove name the area and a register ID; the evidence rule and the 160-character line cap still apply; the result passes `scripts/preferences.sh check`; cases: a file holding a baselines table, a rule containing `|`, a hyphenated area -> tests/template/test_taste_project.sh
- [ ] A7 an add whose rule text (case and whitespace folded) already exists in any register records the proposal as applied and its evidence as used and adds no row; two proposals with the same folded text in one apply add one row; applying the same report twice adds nothing -> tests/template/test_taste_project.sh
- [ ] A8 in template mode (no .start-done) apply refuses (exit 1) and writes nothing -> tests/template/test_taste_project.sh
- [ ] A9 session start prints the registers' rules (ID and Rule, grouped by area) under a 4000-byte cap; past the cap it prints one line naming the files with the rest; nothing when there are no registers; the existing summary line stays -> tests/template/test_session_context.sh
- [ ] A10 `scripts/preferences.sh port --from <path>` lists the other project's rules rows (dry run, exit 0, writes nothing); with `--apply` and optional `--area <a>` and `--id <ID>` filters (`--id` requires `--area`) it copies them into this project's registers through the same writer, with Source "YYYY-MM-DD: ported from <folder name> (<original source>)", Check `Review (was <original check> in <folder name>)` and Repeats empty, skips rows whose rule text already exists, never copies baselines, refuses in template mode, when the path has no registers and when `--from` is this project's own root, and the result passes the check, including a ported row whose Check named a test -> tests/template/test_preferences.sh
- [ ] A11 the taste-dreamer agent (Claude and Codex twins) reads the project's registers first and proposes project register lines: `add <area>: <line>`, `revise <area> <ID>: <line>`, `remove <area> <ID>: <reason>`, areas free-named as the registers allow; it does not re-propose an existing row; its size guidance points at the session-start print cap -> judgment: the reviewer reads both files against taste.py's parser
- [ ] A12 ADR 0013 records project taste, the rejected options (user-level profile, a shared private profile repository, a cloud folder) and the frozen user-level profile; 0011's status line reads "superseded by 0013"; `scripts/adr.sh check` passes -> judgment: the reviewer reads it; check.sh runs adr.sh check
- [ ] A13 dream.md and preferences.md describe the project taste pass, where its state lives (per computer, in the main checkout) and that rows it writes are tracked changes on the current checkout that follow the git workflow (the live task branch or `chore/dream-<date>`), what loads at session start, porting only on the owner's request, that the user-level profile is no longer written, that it still loads where its import block remains and how to remove the block by hand, and that a user-level report from an older release is not applied (run a fresh project taste pass); preferences/README.md mentions ported sources; README.md, BLUEPRINT.md, the dream skill twins and dream.sh's usage header describe the project taste pass -> judgment: prose read by the reviewer
- [ ] A15 `scripts/doctor.sh` checks, by running each one: required git, bash 3.2+ and Python 3 (through find-python.sh); recommended gh, gitleaks, git-cliff, and `git grep -P` (git built with PCRE); in template mode (no .start-done) ruff 0.16.10, uvx or pipx is required, since check.sh 5k fails without one, and in a project it is not checked; each missing or broken tool gets one line with the install command for the detected system (Windows winget ids, macOS brew, Linux apt or the official page), each id or name verified with evidence recorded in the Progress log; it never installs anything; exit 0 when every required tool for the current mode works (recommended gaps are warnings), 1 otherwise, 2 on a usage error; `--quiet` prints only problems; `--list` prints the tool names; `--required` checks only git, bash and Python 3, in either mode; for uvx and pipx doctor runs only `--version` (never a download), and reports ruff 0.16.10 present only when it is on PATH at exactly that version; tests use PATH shims only (never real winget, brew or apt) and doctor.sh is bash 3.2 safe -> tests/template/test_doctor.sh
- [ ] A16 doctor names the Windows Store stub when `python3` or `python` resolves under WindowsApps and fails to run, and prints both fixes (turn off the App execution aliases, or install Python and put it first on PATH); the test uses a temp folder named WindowsApps holding a python3 that exits 49, so it runs on Linux CI -> tests/template/test_doctor.sh
- [ ] A17 session start runs doctor's required checks only, as `bash scripts/doctor.sh --required --quiet`: git, bash and the find-python.sh probe, with no network command (asserted with logging shims on PATH: no gh, winget, brew or curl call); prints one line naming the missing tool and `bash scripts/doctor.sh` when a required tool fails; nothing when all work; the no-Python case also asserts that line and keeps every existing assertion; the time on this computer is measured once and recorded in the Progress log, not asserted -> tests/template/test_session_context.sh
- [ ] A18 docs/procedures/start.md runs doctor first: a required failure stops start, shows doctor's install lines and asks the owner to install and rerun; a recommended gap is logged the way start logs a missing gitleaks; README.md opens its setup with a short "Before you start" step running `bash scripts/doctor.sh`, and its tool list names every tool `doctor.sh --list` prints (test_doctor.sh asserts it; it passes once N3 and N5 have both landed, checked at N4) -> tests/template/test_doctor.sh
- [ ] A19 README.md ends with a short Credits section naming only what the repository's own records cite or run: the AGENTS.md format (ADR 0001), Anthropic's agent-memory research for dreaming (ADR 0009), Karpathy's autoresearch and Claude Code workflows for declared budgets (ADR 0002), Claude Code and Codex, and the tools check.sh runs (git-cliff, gitleaks, ruff, uv, GitHub CLI); each link opened and confirmed by the worker, recorded in the Progress log -> judgment: the reviewer checks each credit against its ADR and the link record
- [ ] A14 ./scripts/check.sh green on the pushed head (CI run) -> judgment: CI log of the PR head

## Design
**find-python.sh.** Sourced, never executed. Loop over `python3 python`; take the first where `command -v` succeeds and `"$c" -c 'import sys; sys.exit(sys.version_info < (3,))'` exits 0; unset the loop variable. Bash 3.2 safe. feedback-log.sh sources it with `|| exit 0`. check.sh 5f takes PY from a subshell (`PY="$(bash -c '. scripts/find-python.sh 2>/dev/null; printf %s "${PY:-}"')"`) so a missing or stub helper cannot end check.sh. find-python.sh, test_find_python.sh and test_taste_project.sh join check.sh's required list and the BLUEPRINT tree.

**Project taste (taste.py).**
- Root: the repository taste.py runs in (`--root`, default the repo root above scripts/); state in `D.main_worktree(root)/.work/dream/taste/` with the existing state format (format version bumped; an older state there is not expected).
- Scope: reuse dream.py's roots (root, worktrees, `known_roots` from `.work/dream/state.json` plus taste's own) and `cwd_match`, and pass `--match` through as dream.py does; auto-memory notes only from `D.memory_dir(c)` (the folder named after the main checkout).
- Apply: parse the same report format with the ops `add <area>: <line>`, `revise <area> <ID>: <line>`, `remove <area> <ID>: <reason>`; write rows through the one writer in preferences.py (taste.py imports it).
- Removed: the user-level profile, import block, Codex block, `sync`, the git-work-tree guard and the 6000-byte profile cap. The digest's "profile:" line reports the registers' session-start print size against the 4000-byte cap. `check` validates the taste state and runs the register check.
**Registers (preferences.py).** One writer, `write_rows(root, area, adds, revises, removes, floor)`, used by taste apply and port:
- inserts after the last data row of the file's first rules table, or adds a rules table before any baselines table (a new file gets a title and the rules header);
- escapes `|` as `\|` and refuses a newline;
- takes the ID prefix used by most rows in the file, else the area upper-cased with non-alphanumerics removed;
- numbers above the highest number for that prefix in the file and a caller-given `floor` (taste passes its ledger's high-water mark for the file; port passes 0), never reusing a removed number;
- folds rule text (case and whitespace) for duplicate checks;
- keeps the file's line endings.
Revise replaces Rule, appends `; YYYY-MM-DD: "<words>"` to Source and keeps Check. Remove deletes the row. A revise or remove of a row whose Check names a test prints a warning naming that test. Port sets Check to `Review (was <check> in <folder>)` and leaves Repeats empty.
**Session start.** session-context.sh prints the rules after the summary line, from a POSIX awk reader (mawk and BSD awk safe) that strips CR, keeps `\|` inside a Rule, skips fenced blocks and counts bytes under `LC_ALL=C`.
**Two computers.** Rows added on two unsynced branches can collide in git or produce a duplicate ID; preferences.sh check (run by check.sh) reports a duplicate ID, so it is caught before merge.

## Plan
| node | depends on | owner files | worker tier | status |
|---|---|---|---|---|
| N1 | - | scripts/find-python.sh, scripts/dream.sh, scripts/feedback-log.sh, scripts/preferences.sh, scripts/check.sh, docs/BLUEPRINT.md, tests/template/test_find_python.sh, tests/template/fixtures/check.sh, tests/template/test_dream.sh, tests/template/test_preferences.sh, tests/template/test_profile_tools.sh, tests/template/test_feedback.sh, tests/template/test_check_always.sh | standard | done |
| N2 | N1 | scripts/dream/preferences.py, scripts/preferences.sh, scripts/session-context.sh, tests/template/test_preferences.sh, tests/template/test_session_context.sh, docs/procedures/preferences.md, docs/preferences/README.md | strong | done |
| N3 | N2 | scripts/dream/taste.py, tests/template/test_taste.sh, tests/template/test_taste_project.sh, .claude/agents/taste-dreamer.md, .codex/agents/taste-dreamer.toml, docs/procedures/dream.md, docs/decisions/0013-project-taste.md, docs/decisions/0011-personal-taste-profile.md, README.md, docs/BLUEPRINT.md, scripts/dream.sh, .claude/skills/dream/SKILL.md, .agents/skills/dream/SKILL.md | strong | doing |
| N5 | N2 | scripts/doctor.sh, tests/template/test_doctor.sh, docs/procedures/start.md, scripts/check.sh, tests/template/fixtures/check.sh, scripts/session-context.sh, tests/template/test_session_context.sh | standard | doing |
| N4 | N3, N5 | .work/TASK.md | reviewer | todo |

N3 test retirement: test_taste.sh keeps the signal extraction, owner filter, stable ids, pool, stop-early, evidence rule, 160-character cap, outcome and impact assertions, with fixture cwds set to the fixture root; it retires the assertions for profile files, managed blocks, sync, the 6000-byte cap, the git guard and cross-project merging, because Goal 2 removes them (ADR 0013); `--projects-dir` is kept only if it filters by cwd, else retired with the same reason. test_taste.sh stays in the required list. N3 edits scripts/dream.sh's usage header only. N3 also writes README's "Before you start" step and the BLUEPRINT tree lines for scripts/doctor.sh and tests/template/test_doctor.sh (A18); N5 adds both to check.sh's required list. N2 and N5 both touch session-context.sh and test_session_context.sh, so N5 runs after N2. N5 copies scripts/check.sh to tests/template/fixtures/check.sh after its edit. N3 and N5 share a wave, so check.sh's BLUEPRINT parity step fails until both land: each node is verified by its own tests, and the full check.sh runs at N4.

## Plan verdict
PASS (round 7, reviewer, 2026-11-09). Goal 3 addition: round 6 blockers B1-B3 fixed, no new blocker; notes N1 (--required scope) and N2 (no download) folded into A15. Earlier PASS (round 5) stands for Goals 1 and 2.
Round 6 (reviewer, 2026-11-09): FAIL. B1 fixture owner; B2 wall-clock assertion; B3 tool list.
PASS (round 5, reviewer, 2026-11-09). Round 4 blockers B2-B6 fixed; no new blocker. B1 stays [open] and tasklint fails ship until it is settled. Non-blocking N1 (writer floor), N2 (write_rows), N3 (warn on a tested row), N4 (this line) folded in. N1 node covered by the round 3 PASS.
Round 4 (reviewer, 2026-11-09): FAIL. B1 owner decision on the user-level block; B2 in-flight report; B3 writer; B4 retired tests; B5 doc owners; B6 note scope.
Round 3 (reviewer, 2026-11-09): PASS for the shared-profile design, since replaced; its Goal 1 and N1 verdict stands.
Round 1 (reviewer, 2026-11-09): FAIL. B1 no ADR for reversing 0011; B2 guard exempted any .git; B3 non-area remote files became instructions or blocked pulls; B4 stale pushes stuck or duplicated ids; B5 ids reused across computers; B6 concurrent runs; B7 credential prompts; B8 fixture owners and N1/N2 race.
Round 2 (reviewer, 2026-11-09): FAIL. Apply path sound. B1 sync pushed duplicates or over-cap after rebase; B2 non-rejection push failure unspecified; B3 non-area remote files checked only by apply; B4 refresh and digest outside the lock; B5 sync could abort the owner's manual rebase.

## Progress log
- 2026-11-09 task opened in its own worktree
- 2026-11-09 plan rounds 1 and 2 FAIL, round 3 PASS for the shared-profile design; N1 started
- 2026-11-09 the owner rejected a shared profile repository and asked for project taste; Goal 2, A4-A13, Design and nodes N2-N4 rewritten; N1 unchanged except the second test file is test_taste_project.sh (worker told)
- 2026-11-09 plan round 4 FAIL (B1 owner decision on the user-level block, B2 in-flight report, B3 writer, B4 retired tests, B5 doc owners, B6 note scope); B2-B6 and notes N1-N7, N9 applied; B1 recorded as an [open] assumption and asked of the owner
- 2026-11-09 plan round 5 PASS; notes N1-N4 folded into Design and the verdict
- 2026-11-09 the owner asked that the repo name the tools a first run needs; Goal 3, A15-A18 and node N5 added; round 6 review FAIL (B1 fixture owner, B2 wall-clock, B3 tool list); fixed with notes N1, N2, N4, N5, N6
- 2026-11-09 round 7 PASS; notes folded into A15
- 2026-11-09 N1 done. Fail-first on this computer (real Store stub as python3): test_find_python 7 passed, 17 failed before the change. After: test_find_python 22 passed, 2 failed (both the test_taste.sh case, closed by N3), test_dream 310/0, test_preferences 53/0, test_profile_tools 6/0, test_feedback 93/0; test_check_always not finished (needs test_taste_project.sh from N3). N2 started
- 2026-11-09 N2 done. Fail-first: test_preferences 77 passed, 68 failed; test_session_context 73 passed, 8 failed. After: test_preferences 145/0, test_session_context 81/0, test_find_python 22/2 (the known test_taste.sh pair). write_rows(root, area, adds, revises, removes, floor, warn=None) returns added, skipped, revised, removed, warnings. N3 and N5 started

## Review verdict
<!-- written ONLY by the independent reviewer -->

## Retro
<!-- filled by docs/procedures/retro.md -->
