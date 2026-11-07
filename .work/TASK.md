# Task: template-updates
Mode: standard
Branch: task/template-updates
Date: 2026-11-07

## Goal
Projects started from this template receive its improvements through a
reviewable update with little friction. The template cuts versioned releases;
a project learns at session start that a newer release exists; one skill takes
it from there (branch, three-way sync including the library and roster the
project carries, conflicts merged by the advisor, kernel changes stopped for
the owner, checks, PR). A project with no usable sync record gets a suggested
starting version, and a fleet table in the template shows every local
project's version and readiness. The existing three-way rules of
`scripts/template-sync.sh` stay as they are.

## Non-goals
<!-- explicitly out of scope; scope creep gets caught here -->
- Dreaming (memory consolidation): the next task, with its own TASK.md.
- An auto-PR GitHub Action in project repositories (needs CI write
  permissions; pull requests opened with the Actions token do not trigger CI;
  one project has no remote).
- Updating library items a project copied into its own folders; only the
  `docs/library/` and `docs/roster/` catalogs sync.
- Running a sync in any project inside this task; rollout is delivery (A13),
  one branch and PR per project with owner approval.
- Kernel edits; changes to the three-way outcome rules for existing paths.
- A hook dispatcher so projects stop editing `.claude/settings.json`, and
  start resetting the lessons files to their headers: both go to BACKLOG.md
  with the survey as their reason.

## Budget
<!-- declare before work starts; on exhaustion: stop, keep the best verified
     artifact, and report unresolved items with reasons - never hide a partial
     result behind a fluent answer -->
- Wall-clock: two working sessions plus delivery.
- Subagents / workflow runs: 3 workers (N2, N3, N4), 1 reviewer (N7).
- Retries per failing step: 2.
- Escalate to human when: a criterion needs a kernel edit, the reviewer fails twice, or a project sync needs a decision only the owner can make.

## Assumptions
<!-- one line per assumption the work rests on: [confirmed] the human said so,
     [verified] -> evidence (a command or file), [open] not yet settled.
     scripts/tasklint.sh ship (the full gate) fails while any line is [open],
     except in quick mode -->
- [confirmed] The human chose template updates first and wants started projects to get new features (2026-11-07).
- [confirmed] The human allowed reading every project repository under C:\dev for evidence (2026-11-07).
- [verified] Five local projects started from the template; a dry-run sync of scratch copies to template main 526ff01 gives the counts in the Progress log -> scripts/template-sync.sh
- [verified] A wrong recorded base produces false conflicts: project B shows 5 conflicts from its recorded template-v0.2.1 and 0 from its real base bab43ac -> scripts/template-sync.sh
- [verified] The "- Profiles:" parser takes prose words as profile names (two projects' lines), so a deferred profile is treated as adopted -> scripts/template-sync.sh
- [confirmed] (approved 2026-11-07) `docs/library/` and `docs/roster/` sync only in projects that already carry them; other projects get one "not carried" line.
- [confirmed] (approved 2026-11-07) The script never edits AGENTS.md; in project mode `./scripts/check.sh` fails when the "- Template:" ref disagrees with the last recorded sync, and the skill fixes the line in the sync PR.
- [confirmed] (approved 2026-11-07) Project-specific check steps live in `scripts/stack-check.sh` (the layout one project already uses); each project moves its steps there once, in its first sync PR.
- [confirmed] (approved 2026-11-07) Versions are `template-vMAJOR.MINOR.PATCH`: minor by default, major suggested when the kernel block changed; each tag push is an owner approval (no standing override).

## Acceptance criteria
<!-- each maps to an executable test where possible; list test paths. A ticked
     line needs "-> <existing path>" or "-> judgment: <reason>"
     (scripts/tasklint.sh check) -->
- [x] A1 Profiles parser: a "- Profiles:" line with prose after the names yields only names that have a profile folder in the template or the project, stopping at the first non-name token; the regression test fails on the current code first (kernel rule 3) -> tests/template/test_template_sync.sh
- [x] A2 `docs/library/` and `docs/roster/` sync under the same three-way rules when the project carries the folder; a project without it gets no ADD for them and one "not carried" line -> tests/template/test_template_sync.sh
- [x] A3 `--baseline <ref>` is used as the previous version instead of the MAINTENANCE.log line, printed as such, and recorded normally after a clean sync; an unknown ref exits 1 -> tests/template/test_template_sync.sh
- [x] A4 `--suggest-baseline` prints the git merge-base first when the project shares history with the template, then the three template commits whose core-set files match the project's copies most often (ties to the newest), with the match count; read-only, exit 0 -> tests/template/test_template_sync.sh
- [x] A5 `--latest` uses the newest `template-v*` tag by version order (not date) as the ref; `--latest-tag` prints it via ls-remote without cloning; no such tag exits 1 with a message -> tests/template/test_template_sync.sh
- [x] A6 `--status` (offline, no clone) prints the template URL, the Template-line ref and the last recorded sync; exit 1 when the line is missing, malformed (anything but "- Template: <url> <ref>") or disagrees with the last recorded sync; exit 0 in template mode; `./scripts/check.sh` runs it in project mode -> tests/template/test_template_sync.sh, tests/template/test_check_always.sh
- [x] A7 Session start: in project mode, `scripts/session-context.sh` prints one line when the cached newest tag is newer than the last recorded sync ("Template update available: <tag> (synced <ref>). Run /template-update."); the cache refreshes in the background at most once per 24 h, never delays or fails the hook offline, and TEMPLATE_UPDATE_CHECK=0 turns it off. In template mode it prints one line when synced-set commits exist after the newest tag -> tests/template/test_session_context.sh
- [x] A8 `scripts/template-release.sh` runs in template mode only; by default a dry run prints the last tag, the proposed version (minor; `--major`, `--patch`; major suggested when the kernel block changed) and notes grouped as synced set, library and roster, other; `--tag` refuses unless on main, clean and equal to origin/main, then creates an annotated tag carrying the notes and prints the push command without pushing -> tests/template/test_template_release.sh
- [x] A9 `scripts/fleet.sh` reads absolute project paths from `fleet.local.list` (gitignored; missing file exits 2 with usage) and prints one read-only row per project: Template-line ref, last synced ref, synced-set commits behind the newest tag, uncommitted files, branch, UPSTREAM.md entries, status OK, BEHIND, NO-BASE, BAD-LINE or MISSING; it never clones or writes -> tests/template/test_fleet.sh
- [x] A10 A `template-update` skill, identical in `.claude/skills/` and `.agents/skills/`: stops on a dirty tree; branches `chore/template-sync-<tag>`; dry run with `--latest`; applies; merges conflicts by hand keeping project customizations; stops for the owner on KERNEL CHANGE; merges the rules index by hand; sets the Template line; reruns with `--resolved` when needed; runs `./scripts/check.sh`; ships per `docs/procedures/ship.md` -> judgment: the steps are procedure prose, reviewed against the script's guards; tests/template/test_lessons.sh covers the mirror and the skills cap
- [x] A11 `docs/procedures/upstream.md` and README.md describe releases, the session-start notice, the skill, baselines and the fleet table in present tense; a test checks that the core set listed in upstream.md matches the script's arrays -> tests/template/test_template_sync.sh
- [x] A14 `./scripts/check.sh` runs the project-owned `scripts/stack-check.sh` when present (passing `--full-mutation` through) and `docs/procedures/start.md` wires the stack there instead of into check.sh; template-sync never touches `scripts/stack-check.sh`, so check.sh stays template-owned and syncs cleanly after a one-time move -> tests/template/test_check_always.sh, tests/template/test_template_sync.sh
- [x] A12 `./scripts/check.sh` green; plain hyphens only; kernel hash unchanged -> judgment: check.sh output quoted in the Progress log
- [ ] A13 Delivery, each step an owner approval: tag `template-v0.3.0` pushed; the first real sync runs on the project with the cleanest tree (closes the BACKLOG real-run item); every other project listed by `scripts/fleet.sh` with its next step -> judgment: fleet.sh output and the project C PR link in the Progress log

## Plan
<!-- task graph: one node per row; nodes that can run in the same wave must
     own disjoint files. Tiers: cheap, standard, strong, advisor, reviewer.
     Status: todo, doing, done, blocked. Validate: scripts/taskgraph.sh check -->
| node | depends on | owner files | worker tier | status |
|---|---|---|---|---|
| N1 | - | scripts/template-sync.sh, tests/template/test_template_sync.sh | advisor | done |
| N2 | - | scripts/template-release.sh, tests/template/test_template_release.sh | standard | done |
| N3 | - | scripts/fleet.sh, tests/template/test_fleet.sh, .gitignore | standard | done |
| N4 | N1 | scripts/session-context.sh, tests/template/test_session_context.sh | standard | done |
| N5 | N1 | scripts/check.sh, tests/template/fixtures/check.sh, tests/template/test_check_always.sh, docs/procedures/start.md, docs/BLUEPRINT.md | advisor | done |
| N6 | N1, N2, N3, N4 | .claude/skills/template-update/SKILL.md, .agents/skills/template-update/SKILL.md, docs/procedures/upstream.md, README.md, BACKLOG.md, docs/decisions/0008-template-releases-reach-projects-through-tags-a-notice-and-a.md | advisor | done |
| N7 | N5, N6 | .work/TASK.md | reviewer | done |

## Plan verdict
<!-- autopilot only: the reviewer's plan review of Goal, Assumptions,
     Acceptance criteria and Plan, written before any node starts;
     scripts/tasklint.sh requires PASS once a node is doing or done -->

## Progress log
<!-- timestamped one-liners; this is what survives compaction -->
- 2026-11-07 task opened on task/template-updates from main 526ff01.
- 2026-11-07 dry-run sync of scratch copies to template main 526ff01 (current script): project D update=3 conflict=0; project C update=25 add=21 conflict=2 diff=71 plus a rules-index diff; project B conflict=5 (base template-v0.2.1), conflict=0 update=3 with base bab43ac; project A update=10 add=82 conflict=20; project E no base, add=42 conflict=22 plus a kernel diff, best-matching template commit shares 22 of 45 files.
- 2026-11-07 read-only survey of 18 repos under C:\dev: every derived project customized scripts/check.sh (project A 117 diff lines, project C 162, project E 408) and .claude/settings.json; project B delegates its stack to scripts/stack-check.sh (21 lines differ); project E shares git history with the template (a template remote); three Template-line formats in use, project D has none; kernel hash e70718d identical in 5 projects; no project has synced since start.
- 2026-11-07 parser defect seen: project C adopted list printed with the words of a prose note after its profile names (a deferred profile among them), and an adopted name ending in a period dropped.
- 2026-11-07 human approved the criteria and the four open choices (template updates, then dreaming as the next task); wave 1 starts: N1 advisor, N2 and N3 workers.
- 2026-11-07 N2 worker: scripts/template-release.sh, test_template_release.sh 49 passed 0 failed; real dry run: last tag template-v0.2.1, next template-v0.3.0 (minor), KERNEL CHANGED line (rules 10 and 16 amended after v0.2.1).
- 2026-11-07 N3 worker: scripts/fleet.sh, test_fleet.sh 26 passed 0 failed; real fleet.local.list (5 projects): project A OK, project B, project C, project D, project E BAD-LINE; upstream project A 2, project C 6.
- 2026-11-07 N1: Profiles regression test failed first on the old parser (4 FAIL, 99 passed), then 104 passed after the fix; with the new options test_template_sync.sh 141 passed 0 failed.
- 2026-11-07 N4 worker: session-context update notice, test_session_context.sh 36 passed 0 failed; real template-mode line: "Template release pending: 42 synced-set commits since template-v0.2.1".
- 2026-11-07 N5, N6: check.sh hands the stack to scripts/stack-check.sh and runs --status (4h); start.md, BLUEPRINT, upstream.md, README, skill, ADR 0008, BACKLOG rows; test_check_always.sh 69 passed 0 failed; blueprint parity 11 passed.
- 2026-11-07 ./scripts/check.sh exit 0: selftest 19 passed, 0 failed (19 test files); "template self-test: OK (129 required files, ...)"; tasklint ship OK; doc-eval OK.
- 2026-11-07 review 1 FAIL (verify output predated the staged tree; --resolved step needed a commit first; --suggest-baseline ranking untested; stack-check.sh exec-bit trap; docs still wired the stack into check.sh; fleet status could refresh a project index; stale header and usage; header-file and AGENTS.md commits counted as synced; private project names). Fixed: check.sh runs stack-check.sh with bash and needs no exec bit; upstream.md step 6.7 commits before --resolved; ranking ties broken by topological order and asserted (v3, v2, v1); a real --baseline apply is tested; fleet uses --no-optional-locks and core and catalog paths; --list-set has a header group; release notes and the session-start count classify header and AGENTS.md edits precisely; docs repointed to stack-check.sh; names redacted. test_template_sync.sh 149 passed, test_template_release.sh 57, test_session_context.sh 47, test_fleet.sh 26, all 0 failed.
- 2026-11-07 ./scripts/check.sh on the staged tree (nothing untracked): exit 0; tasklint check and ship OK with 13 ticked criteria; selftest 19 passed, 0 failed (19 test files); "template self-test: OK (129 required files, ...)".

## Review verdict
<!-- written ONLY by the independent reviewer -->
Review 1 (2026-11-07): FAIL - verify output predated the staged tree; --resolved step needed a commit first; --suggest-baseline ranking untested; stack-check.sh executable-bit trap; docs still wired the stack into check.sh; fleet status could refresh a project index; stale header and usage; header-file and AGENTS.md commits counted as synced; private project names; coverage gaps in A3, A7, A10.

Review 2 (2026-11-07): PASS. All ten findings from review 1 are fixed; the new verify output was run on this staged tree and every stage is clean. Non-blocking (Low): (a) fleet.sh behind and the template-mode count ignore a release whose only synced change is a lessons header or the AGENTS.md kernel block or rules index; (b) the software profile Gates table now says to wire rows into stack-check.sh, but kernel hash, line budget, no-dash and untracked report already run in check.sh's always section, and "clean clone: run check.sh" would recurse; (c) the progress log should quote the second check.sh run; (d) GNU-only test constructs, consistent with test_stop_gate.sh and the ubuntu-only CI; (e) rollout: project E's .gitignore lacks .work/template-sync/, which its first sync PR should add.
Evidence checked: check-full-2.log (all 32 lines: kernel-hash OK, tasklint 13 ticked, no untracked block, selftest 19 passed 0 failed, template self-test OK, exit 0); template-updates-2.diff (file modes across all 30 files); .work/TASK.md; upstream.md step 6.7, start.md step 3, check.sh stack block and 5d, fleet.sh, session-context.sh, template-release.sh, template-sync.sh header, usage, suggest_baseline and list_set; test_check_always.sh, test_template_sync.sh (i) to (o), test_template_release.sh, test_session_context.sh, test_fleet.sh; repo searches for project names and check.sh wiring text; docs/profiles/software/PROFILE.md lines 40-69.

## Retro
<!-- filled by docs/procedures/retro.md -->
