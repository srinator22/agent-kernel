# Task: fleet-sync-fixes
Mode: autopilot
Branch: task/fleet-sync-fixes
Date: 2026-11-08

## Goal
Fix the six template defects that the first real syncs of twelve local
projects to template-v0.3.0 (2026-11-08) exposed, so a started project passes
the template self-tests with no quarantine, no edit of its own to
scripts/selftest.sh or scripts/new-task.sh, and no ruff exclusion of template
folders. Each fix gets a regression test shown failing first and a check that
stops the defect class from coming back. The six: (1) test_blueprint_parity.sh
and test_check_always.sh assume the template's own tree and fail (or run 25+
minutes) in a started project; (2) scripts/selftest.sh ignores
tests/quarantine.list; (3) check.sh step 4a exits 141 on a long match list (a
pipe into head under pipefail); (4) new-task.sh reads "direct-to-main is not a
standing choice" as direct-to-main; (5) template-release.sh tags while
.work/TASK.md holds a live task; (6) the template's own Python fails ruff, so
projects exclude docs/profiles. Defect 6 also covers scripts/dream.py from the
stacked PR #12, which would otherwise reach every project in the same release
and fail the same two gates. This branch is stacked on task/dreaming (PR #12)
because both touch the check.sh required list, BLUEPRINT, BACKLOG and the
lessons counters; both ship in the next release. A seventh defect, added by
the owner: tests/template/lib.sh leaves temp folders behind (make_fixture
drops the previous fixture without removing it, and a test that exits early
keeps its own), so every selftest run grows the system temp dir.

## Non-goals
- Updating the twelve project branches: they take the fixes at their next
  template sync (docs/procedures/upstream.md says what to drop).
- Retagging template-v0.3.0: tags are public and immutable.
- Running ruff format over the template's Python, or linting it with more
  than ruff's default rules (see A8 for why).
- Linting early-exit "grep -q" pipes under pipefail: same mechanism as defect
  3, small inputs today, recorded as a BACKLOG row.
- Speeding up the template's own selftest beyond removing the copied
  started-project run from project mode (the P2 BACKLOG row stays).
- The taste profile and the dream impact report (their own session, branch
  task/taste-profile).

## Budget
- Wall-clock: 6 h
- Subagents / workflow runs: 1 worker, reviewer up to 5 runs (3 plan reviews plus 2 rounds; the third plan review was asked of the owner when round 2 failed on one blocker), 1 monitor
- Retries per failing step: 2
- Escalate to human when: budget exhausted, a fix needs a kernel change, or CI cannot resolve a pinned ruff

## Assumptions
- [confirmed] The owner asked for these six fixes: "Yes, fix them" (2026-11-08), answering the list of six.
- [verified] check.sh runs its template self-test only when "$ROOT/.start-done" is absent -> scripts/check.sh
- [verified] A folder ruff.toml replaces a stricter root config for the files under it, and its [format] exclude keeps ruff format off them -> scratch run with ruff 0.16.10, 2026-11-08: root select ALL and line-length 60; the nested file reported only F401; format --diff listed only src/a.py (A10 now re-proves this on every template run)
- [verified] GitHub ubuntu-latest (24.04) ships pipx 1.16.7 and neither uv nor ruff -> actions/runner-images images/ubuntu/Ubuntu2404-Readme.md, read 2026-11-08
- [verified] Of the eight projects that record direct-to-main, six write the token followed by a comma; one project ("direct-to-main on master") and another project ("direct-to-main as an explicit ...") do not, and will read as gated (the safe side) until reworded at their next sync -> survey of eleven project AGENTS.md "- Git workflow:" lines, 2026-11-08
- [verified] .work/ is outside the synced set, so the live TASK.md inside template-v0.3.0 reached no project -> scripts/template-sync.sh CORE_DIRS and CORE_FILES
- [verified] Under ruff's default rules (E4, E7, E9, F, target py311) the template has 49 findings (codes across all 49: E702, E731, E741, F841): 45 in docs/library, 1 in docs/profiles (E731), 3 in scripts/dream.py (all E741), none needing a behavior change -> ruff 0.16.10 runs, 2026-11-08
- [verified] scripts/dream.py is the only tracked Python outside docs/library and docs/profiles, and no released tag carries it yet, so moving it hurts no project -> git ls-files '*.py'; git tag --contains for its first commit is empty
- [confirmed] Coordination with the taste-profile session (worktree C:/dev/work/New-Project-taste, branch task/taste-profile, from task/dreaming), which already has uncommitted edits to scripts/dream.py: this branch's dream.py diff is limited to the move to scripts/dream/dream.py, the three E741 renames (lines 127, 262, 269) and the default-root line (line 94), so git carries that session's edits across the rename when it merges this branch; its taste.py goes under scripts/dream/, where scripts/dream/ruff.toml and the A10 coverage check apply -> messages exchanged with that session 2026-11-08
- [confirmed] The owner asked for the seventh fix and for the leftover temp folders to be removed: "Yes, fix and clean" (2026-11-08).
- [verified] A pipe into head under pipefail exits 141 once the writer still has output when head exits: 4000 lines (123 KB) gave 141 and 2000 lines (61 KB) gave 0 in Git Bash here -> repro in the Progress log

## Acceptance criteria
- [x] A1 scripts/selftest.sh skips each tests/template path listed in tests/quarantine.list (comment and blank lines ignored with the lessons.sh rule, CR tolerated, the "# owner: ... date: ..." part stripped, duplicates counted once), prints "QUARANTINED  <path>" for each on every run, and ends with "selftest: P passed, F failed, Q quarantined (T test files)" (the existing summary assertions in test_check_always.sh become the stricter "... passed, 0 failed, 0 quarantined (" form); an absent list runs everything; a listed tests/template path that does not exist fails the run and is named; an unlisted failing test still fails -> tests/template/test_selftest.sh
- [x] A2 test_blueprint_parity.sh runs its real-tree case only when "$T_ROOT/.start-done" is absent; otherwise it prints one line "  n/a  <case>: <reason>; covered by <gate>" and still runs its fixture cases -> tests/template/test_check_always.sh
- [x] A3 test_check_always.sh runs its started-project scenario only when "$T_ROOT/.start-done" is absent and prints the same kind of n/a line otherwise (T_NESTED retired). The template-mode copy drops docs/library, docs/roster and tests/docs/questions.md as real started projects do and still passes check.sh --quick with a clean nested selftest whose output shows both n/a lines; in template mode it also runs test_blueprint_parity.sh on the template tree and finds the real-case ok line and no n/a line -> tests/template/test_check_always.sh
- [x] A4 scripts/selftest.sh prints every "  n/a  " line of a passing test file in its normal output, so a log shows each case that did not apply -> tests/template/test_selftest.sh
- [x] A5 check.sh step 4a with at least 1 MiB of dash matches, and again of character matches, exits 1 with its named failure (not 141) and prints at most 20 match lines -> tests/template/test_check_always.sh
- [x] A6 No scripts/*.sh pipes into head (session-context.sh, template-sync.sh, template-release.sh, adr.sh and lessons.sh rewritten with sed); the check.sh template self-test fails and names a script that does -> tests/template/test_check_always.sh
- [x] A7 new-task.sh stays on the current branch only when the "- Git workflow:" value starts with direct-to-main (optional backtick, star or underscore markup around it) followed by end of value, or by optional spaces and then ; . : , or (, or by " - ". Anything else, including "direct-to-main is not allowed; use branches", creates task/<slug>; a value that starts with the token but fails the rule also prints a warning naming the accepted form; both paths print which workflow was read. start.md item 4 and docs/BLUEPRINT.md state the form -> tests/template/test_new_task.sh (plain, backticked, bold, "direct-to-main (solo)", placeholder, "Branch ...", "branch ...", the negated value starting with the token, and "Branch plus pull request ...; direct-to-main is not a standing choice")
- [x] A8 docs/library/ruff.toml, docs/profiles/ruff.toml and scripts/dream/ruff.toml select ruff's default rules (E4, E7, E9, F) at target py311 and exclude their folder's Python from ruff format. A header comment says why: adopted-profile files reach projects only as DIFF reports while these configs are applied, so stricter rules or a format contract would fail every project's copy at the next sync -> scripts/check.sh (A10 enforces the contract)
- [x] A9 The 49 findings are fixed by hand with no behavior change; scripts/dream.py moves to scripts/dream/dream.py with its default root climbing two levels instead of one, so behavior is unchanged (dream.sh, test_dream.sh, required list and BLUEPRINT follow); the library, profile and dream tests still pass -> tests/template/test_profile_tools.sh and tests/template/test_dream.sh
- [x] A10 The check.sh template self-test (template mode only): every tracked .py lies under a folder below the repository root with its own tracked ruff.toml (a root ruff.toml does not count: root files are not synced), or the file is named as a failure. Pinned ruff 0.16.10 runs check and format --check (the latter guards the format exclusion) with --no-cache on those folders, and again from a scratch root whose pyproject.toml selects every rule over copies of them, so the folder config must win. The runner is ruff on PATH at exactly 0.16.10, else uvx, else pipx; TEMPLATE_RUFF overrides it for tests. One line per run names the runner and the version it reported. A failing runner or ruff exit fails the step; no runner fails with an install message -> tests/template/test_check_always.sh (fake TEMPLATE_RUFF that exits 1 for findings and 2 for a config error; the no-runner branch is checked by judgment: a PATH without uvx and pipx can be built, but only by listing every tool scripts/check.sh calls, which costs more than the one-line branch it would test)
- [x] A15 No self-test reaches a real ruff runner or the network: every tests/template fixture that runs check.sh in template mode sets TEMPLATE_RUFF to a fake, and the clean template-mode fixture asserts that its ruff line names the fake -> tests/template/test_check_always.sh
- [x] A11 template-release.sh --tag refuses (exit 2) when HEAD's .work/TASK.md is a live task (present without the title placeholder) and points to the retro; a pristine or absent TASK.md tags as before; the dry run prints a warning for a live task -> tests/template/test_template_release.sh
- [x] A12 The required list and the BLUEPRINT tree carry tests/template/test_selftest.sh, the three ruff.toml files and scripts/dream/dream.py; scripts/check.sh and its fixture stay byte-identical -> scripts/check.sh
- [x] A13 Docs, each checked against the scripts: tests.md step 5 names scripts/selftest.sh as the runner for tests/template entries and the n/a line; upstream.md step 9 tells a syncing project to take the template's selftest.sh and new-task.sh over local fixes (Inventor Macros wrote both), remove the template-fix quarantine entries, reword a direct-to-main line that new-task.sh now reads as gated, and merge the hardware-pcb test DIFF before dropping a docs/profiles ruff exclusion; README.md Prerequisites names ruff 0.16.10 through uvx or pipx, with network, for template-mode check.sh -> judgment: doc text read against scripts/selftest.sh, scripts/new-task.sh and check.sh step 5k
- [x] A16 A test that builds several lib.sh fixtures, or exits early, leaves no template-selftest.* folder in TMPDIR (make_fixture removes the previous fixture; an EXIT trap removes the last one) and keeps its exit status; a full selftest run under a fresh TMPDIR leaves none -> tests/template/test_selftest.sh, plus the full run recorded in the Progress log
- [ ] A14 ./scripts/check.sh exits 0 on the final staged tree and prints the template ruff line; CI on the pushed head reaches success and its log shows the ruff line naming pipx -> judgment: verify log and CI log, recorded in the Progress log

## Plan
| node | depends on | owner files | worker tier | status |
|---|---|---|---|---|
| N1 | - | tests/template/lib.sh, tests/template/test_selftest.sh, tests/template/test_check_always.sh, tests/template/test_blueprint_parity.sh, tests/template/test_new_task.sh, tests/template/test_template_release.sh | advisor | done |
| N2 | - | docs/library/ruff.toml, docs/profiles/ruff.toml, scripts/dream/ruff.toml | advisor | done |
| N3 | N2 | docs/library/tools/render_common.py, docs/library/tools/tests/test_blender_compat.py, docs/library/tools/tests/test_frame_audit.py, docs/library/tools/tests/test_motion_check.py, docs/library/tools/tests/test_render_bundle.py, docs/library/tools/tests/test_render_overlay.py, docs/profiles/hardware-pcb/tools/tests/test_check_bom.py | standard | done |
| N4 | N1, N2 | scripts/dream/dream.py, scripts/dream.py, scripts/dream.sh, tests/template/test_dream.sh | advisor | done |
| N5 | N1 | scripts/selftest.sh, scripts/check.sh, tests/template/fixtures/check.sh, scripts/new-task.sh, scripts/template-release.sh, scripts/session-context.sh, scripts/template-sync.sh, scripts/adr.sh, scripts/lessons.sh | advisor | done |
| N6 | N4, N5 | docs/procedures/tests.md, docs/procedures/upstream.md, docs/procedures/start.md, docs/BLUEPRINT.md, BACKLOG.md, docs/lessons/INDEX.md, README.md | advisor | done |
| N8 | N1 | tests/template/lib.sh, tests/template/test_selftest.sh | advisor | done |
| N7 | N3, N6, N8 | .work/TASK.md | reviewer | done |

N1 writes the regression tests and records each failing for its stated cause
before the patch: for 1a and 1b, the started copy that drops docs/library
fails the nested parity test before the mode condition goes in. Bugs 1a and 1b
are fixed inside the tests (the mode condition), so N1 owns those fixes. The N3
worker brief lists each finding by file, line and rule, with these pitfalls:
- F841: drop the binding and keep the call.
- E731: a def with the same name.
- E741: rename every use.
- No ruff format.
- Run test_profile_tools.sh.
N1 extends cp_script in lib.sh to create subfolders, so N4's test_dream.sh copies dream/dream.py through it, and lib.sh exports a default fake TEMPLATE_RUFF so no self-test can reach a real ruff runner even if a fixture forgets to set one. N4 pitfall: no edit to dream.py beyond the move, the three renames and the root line, not even its docstring header.
Ship (commit, push, PR, monitor) runs after N7 per docs/procedures/ship.md.
The commit that adds the ruff step states why ruff is added and why it is
pinned by exact version (kernel rule 13; no lockfile in the template).

Existing damage:
- Defect 5: template-v0.3.0 carries the template-updates task record in
  .work/TASK.md. It reached no project (.work/ is not synced). The tag stays,
  and A11 makes the next release start from a pristine TASK.md.
- Defect 4: no damage. In Inventor Macros, the one gated project with the
  misread line, every Branch line in .work/done names a task or feature
  branch, and it wrote its own new-task.sh fix.
- Defect 3: none; exit 141 fails closed.
- Defects 1, 2 and 6: the projects' quarantine entries, local selftest
  readers and ruff exclusions go at their next sync (A13).

## Plan verdict
<!-- autopilot only: the reviewer's plan review of Goal, Assumptions,
     Acceptance criteria and Plan, written before any node starts;
     scripts/tasklint.sh requires PASS once a node is doing or done -->
PASS - round 3 (reviewer, 2026-11-08): the round-2 blocker (self-tests reaching a real ruff runner) is fixed by A15, and notes 2 to 9 are taken in; no new blocker. Non-blocking: (1) the taste-profile ordering assumption overstated the agreement, since that session already edits dream.py; reworded to the agreed diff limit, with an N4 pitfall; (2) optional: lib.sh exports a default fake TEMPLATE_RUFF, taken. Rounds 1 and 2 were FAIL (see Progress log).

## Progress log
- 2026-11-08 Branch task/fleet-sync-fixes from task/dreaming 274ffed; causes located for all six (see Goal). Survey of the project branches: 11 of 12 quarantined the two tests, 9 wrote their own selftest reader, and a third project and one project exclude docs/profiles from ruff.
- 2026-11-08 Repro of defect 3 in Git Bash: `set -o pipefail; printf '%s\n' "$big" | head -20` gives rc 0 at 2000 lines (60892 bytes) and rc 141 at 4000 lines (122892 bytes).
- 2026-11-08 Plan review round 1: FAIL, 4 blocking findings. Revised:
  - dream.py goes under a folder ruff.toml, and a coverage check is added;
  - n/a lines are visible, with both branches asserted;
  - the direct-to-main separator rule;
  - the runner/version line.
  Non-blocking findings were taken in: a 1 MiB margin, A1 edge cases, the README line, the DIFF note, fake exit codes, the scratch-root override check, and a BACKLOG row for grep -q.
- 2026-11-08 Plan review round 2: FAIL, round-1 blockers resolved, 1 new blocker (self-tests would reach a real ruff runner): A15 added. Notes 2 to 9 taken in: the dream.py root, cp_script, the root ruff.toml exclusion, the stricter summary assertion, "direct-to-main (solo)" and BLUEPRINT wording, the finding codes, the no-runner reason, and the ordering assumption.
- 2026-11-08 Plan review round 3 (approved by the owner): PASS; record correction and the lib.sh default fake taken in. N1 and N2 start.
- 2026-11-08 Fail-first, each new test run against the scripts before the fix:
  - test_selftest.sh: 8 failed; after the fix 16 of 16;
  - test_new_task.sh: 10 failed; after 64 of 64;
  - test_template_release.sh: 6 failed; after 63 of 63;
  - test_blueprint_parity.sh in a started copy: 10 passed, 1 failed (the real-tree case);
  - test_check_always.sh on a frozen copy of the pre-fix scripts: 72 passed, 26 failed, among them "exit 141, expected 1" on the long dash and character lists, the missing ruff step and head lint, and the started copy failing its nested parity test.
- 2026-11-08 Verify on staged tree a37bd40: ./scripts/check.sh exit 0, "template ruff: uvx, ruff 0.16.10", selftest 21 passed, 0 failed, 0 quarantined.
- 2026-11-08 Defect 7 (owner): 319 template-selftest.* folders in the system temp dir; test_template_release.sh alone left 4 per run (fresh_repo calls make_fixture five times). Fail-first: the two new test_selftest.sh cases left 2 and 3 folders; after the fix 20 of 20. The 319 folders (all older than an hour) and five old sync clones in the session scratchpad were removed by exact path.
- 2026-11-08 Full selftest under a fresh TMPDIR in the session scratchpad: 0 template-selftest.* folders left (A16). One empty tmp.* folder left, source not traced (BACKLOG). test_dream.sh failed 42 cases there, and test_check_always.sh failed through its nested selftest, from the Windows 260-character path limit: the same test passes 121 of 121 under /tmp and under a short custom TMPDIR (BACKLOG).
- 2026-11-08 Verify on staged tree 93976bc: ./scripts/check.sh exit 0, selftest 21 passed, 0 failed, 0 quarantined, "template ruff: uvx, ruff 0.16.10"; 0 template-selftest.* folders left in /tmp afterward.
- 2026-11-08 Review round 1: PASS. Notes 1 and 3 taken (BLUEPRINT step 5 list, upstream.md step 9 wording). Note 2 not taken: scripts/lessons.sh stamps last: with the UTC date (today() is date -u), and the counters were bumped before UTC midnight, so 2026-11-07 is the script's own value. Note 4 goes into the commit body and the A14 check. Note 5 fails closed and is left. Note 6 agrees with the BACKLOG rows.

## Review verdict
<!-- written ONLY by the independent reviewer -->
PASS - review round 1 (reviewer, 2026-11-08), staged tree 93976bc72eb62a50a33f8e9d0435fbe8418872f9. A1 to A13, A15 and A16 are met. A14 waits on CI for the pushed head. Nothing blocks.
Blocking: none.
Non-blocking:
1. docs/BLUEPRINT.md:322: the check.sh spec's template self-test list ends at "BLUEPRINT tree parity" and omits the template Python ruff contract (5k, pinned ruff 0.16.10, network on first use) and the head lint (5l), which the scripts/check.sh success line names.
2. docs/lessons/INDEX.md L001, L003, L009: "used" went up by one but "last" still says 2026-11-07, while the branch dates its work 2026-11-08.
3. docs/procedures/upstream.md step 9: "now reads as gated" and "now carry" describe a change; current-state wording is "reads as gated" and "carry the template's lint contract".
4. Rule 13: the commit that adds step 5k must say why ruff is added and why it is pinned by exact version, with no lockfile. The pipx branch (scripts/check.sh:357) has not run anywhere yet, so the A14 CI log line naming pipx is its first real proof.
5. scripts/check.sh:373-375 (fails closed): a tracked .py or ruff.toml missing from the worktree makes `mkdir -p ... && cp ...` exit check.sh with no message under set -e and leaves the scratch folder behind.
6. The two BACKLOG rows (test_dream.sh MAX_PATH under a long TMPDIR; one empty tmp.* folder per run) belong outside this change.
Evidence checked: verify2.txt complete (tree 93976bc7 before and after, every gate OK, selftest 21 passed, 0 failed, 0 quarantined, "template ruff: uvx, ruff 0.16.10", check.sh exit 0); failfirst-frozen-2.txt (exit 141 on the long lists, old summary form, missing ruff step); the full staged diff, all 37 files, with the fixture check.sh hunks identical to scripts/check.sh; lib.sh, test_selftest.sh, test_check_always.sh, test_new_task.sh, test_template_release.sh, selftest.sh against lessons.sh, template-sync.sh, ci-watch.sh, BLUEPRINT.md; greps for pipes into head, stale dream.py paths, mktemp callers, traps in tests and rm on $FIX.

PASS - review round 2 (reviewer, 2026-11-08), staged tree 5ba2a8198c2a734189c8f3d4be0552324fb85bc7, delta from 93976bc only. The delta takes in round-1 notes 1 and 3: docs/BLUEPRINT.md step 5 names the template Python ruff contract (pinned 0.16.10 from PATH, uvx or pipx, network on first use) and the head lint, matching scripts/check.sh 5k and 5l; docs/procedures/upstream.md step 9 drops both "now" phrasings with its instructions unchanged; .work/TASK.md adds the round-1 verdict as written and two Progress log lines. Note 2 is withdrawn: scripts/lessons.sh:55 stamps today() with date -u, so 2026-11-07 is the script's own value. Nothing blocking. The drafted commit message meets rule 13 (why ruff is added and why it is pinned by exact version with no lockfile) and rule 20 (no em or en dashes, curly quotes or attribution trailers); for rule 6, items 3 and 6 need a Files line before committing. Evidence checked: round2-delta.diff (3 files, read in full); verify3.txt complete (tree 5ba2a81 before and after, every gate OK, selftest 21 passed, 0 failed, 0 quarantined, "template ruff: uvx, ruff 0.16.10", template self-test OK, check.sh exit 0); scripts/lessons.sh:55; commit-msg.txt read in full and searched for typographic characters and trailers (none found).

## Retro
<!-- filled by docs/procedures/retro.md -->
