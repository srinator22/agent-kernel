# Task: sync-defects
Mode: standard
Branch: task/sync-defects
Date: 2026-11-08

## Goal
Fix three template defects that the syncs of three projects to
template-v0.4.0 exposed. (1) A tests/template test that cannot load lib.sh
keeps running under set -uo pipefail and writes its fixture files into the
current folder, which is the project. (2) template-v0.4.0 stores
tests/template/test_taste.sh as 100644 while every other test is 100755, and
nothing catches a test committed without the exec bit. (3) The kernel rule 10
skills cap counts template core skills inside the same 8 slots a project fills
with its own skills, so a new core skill (dream) pushed one project from 16
to 17 skills, over its cap. Each fix gets a regression test shown failing
first.

## Non-goals
- Changing the three synced projects: they take the fixes at their next sync.
- Retagging template-v0.4.0 or tagging a new release (the owner tags).
- Guarding helpers other than the lib.sh load (for example make_fixture's own
  mktemp failure path, which already exits).
- The template-mode looseness of the skills cap (existing BACKLOG row).

## Budget
- Wall-clock: 4 h
- Subagents / workflow runs: reviewer up to 3 runs, 1 monitor
- Retries per failing step: 2
- Escalate to human when: budget exhausted, the skills-cap decision is not answered, or a fix needs a kernel change the owner has not approved

## Assumptions
- [verified] Every tests/template/test_*.sh loads lib.sh on one line `source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"` after `set -uo pipefail`, with nothing else before it -> awk over tests/template/test_*.sh, 2026-11-08
- [verified] Only tests/template/test_taste.sh is 100644 among tests/template/*.sh; scripts/dream/taste.py is also 100644 but runs through python, not as a program -> git ls-files -s tests/template scripts/dream
- [confirmed] Rule 10 counts template core skills apart, with 2 project slots, and the kernel edit is approved: the owner chose "Count core apart (Recommended)", presented as "Rule becomes up to 8 template core skills, plus 2 project skills, plus profile skills. A new template skill never pushes a project over. A one-time kernel edit." (relayed by the starting session, 2026-11-08)
- [confirmed] The owner delegated remaining decisions to the starting session and asked for a green, reviewed PR left unmerged: "im going to sleep- make all decisions- oyu have all perms" (relayed 2026-11-08)
- [verified] The template has no version file; template releases are annotated template-vX.Y.Z tags the owner pushes, so ship step 4 bumps nothing here -> docs/procedures/ship.md step 8, scripts/template-release.sh

## Acceptance criteria
- [x] Every tests/template/test_*.sh run without lib.sh next to it exits non-zero, names lib.sh on stderr and writes nothing into its working folder -> tests/template/test_test_files.sh
- [x] Every tests/template/test_*.sh loads lib.sh with the one canonical guarded line -> tests/template/test_test_files.sh
- [x] Every tracked tests/template/*.sh is 100755 in the git index -> tests/template/test_test_files.sh
- [x] Skills cap is the core skills present (CORE_SKILLS, at most 8) + 2 project skills + profile skills; a seventh core skill keeps a full project within the cap; a removed core skill frees no slot -> tests/template/test_lessons.sh
- [x] Template mode: .claude/skills equals CORE_SKILLS -> judgment: check.sh step 5m, shown failing on a probe skill folder (Progress log); template mode has no fixture test
- [x] template-sync reports the skills cap after a sync; a new core skill on a full project is no action item; a breach prints ACTION: skills cap and exits 1 -> tests/template/test_template_sync.sh
- [x] ./scripts/check.sh green -> judgment: verify output attached to the review

## Plan
| node | depends on | owner files | worker tier | status |
|---|---|---|---|---|
| N1 | - | tests/template/test_test_files.sh, tests/template/test_*.sh, tests/template/lib.sh | advisor | done |
| N2 | N1 | tests/template/test_taste.sh | advisor | done |
| N3 | N1 | scripts/lessons.sh, scripts/template-sync.sh, scripts/check.sh, tests/template/test_lessons.sh, tests/template/test_template_sync.sh, AGENTS.md, .kernel.hash, docs/decisions/0012-*.md | advisor | done |
| N4 | N1, N2, N3 | .work/TASK.md, BACKLOG.md | reviewer | done |

## Plan verdict

## Progress log
- 2026-11-08 task opened; skills-cap decision sent to the owner through the starting session.
- 2026-11-08 fix 1 fail-first: `bash tests/template/test_test_files.sh` before the guard: 1 passed, 4 failed. Root cause: tests/template/test_*.sh line `source .../lib.sh` under set -uo pipefail without -e, so a failed source continues. 15 of 22 tests wrote files into their start folder (test_selftest: tests/; test_session_context: .work f1.txt..., and so on), all 22 printed no lib.sh message, test_taste.sh 100644. After: 5 passed, 0 failed (11 s).
- 2026-11-08 fix 3 report fail-first: test_template_sync.sh section p before the template-sync change: 153 passed, 3 failed (no skills line, no ACTION line, exit 0). After: 156 passed.
- 2026-11-08 owner chose A (relayed). Counting fail-first: test_lessons.sh against HEAD's lessons.sh: 107 passed, 16 failed, including "a seventh core skill keeps a full project within the cap (exit 1, expected 0)", the template-v0.4.0 case; root cause scripts/lessons.sh cmd_check cap=BASE_SKILLS+sets with core and project skills in one count. After: 123 passed. test_template_sync.sh with real core names: 156 passed.
- 2026-11-08 step 5m: the snippet run alone passes on the tree and fails with a probe folder .claude/skills/zz-probe ("differ from CORE_SKILLS"); the probe was removed.
- 2026-11-09 merged origin/main twice (af63c7a, 55228eb), both clean. Full check.sh on the first merge failed test_check_always (95 passed, 3 failed): its started-project fixture records every file 100644 where git does not track modes, so the copy's exec-bit check failed; fixed by carrying the template's 100755 index modes into the fixture (98 passed). taskgraph: N3 now depends on N1 (both touch test_lessons.sh and test_template_sync.sh).
- 2026-11-09 review 1: APPROVE WITH NITS. Finding 1 fail-first: test_template_sync.sh section p with a v3 lessons.sh lacking the skills command, before the fix: "FAIL a lessons.sh without the skills command is no cap breach (output has: ACTION: skills cap)", output "ACTION: skills cap: . Merge or archive a project skill ...; the sync is recorded." (run stopped before its total); fixed so only exit 1 is a breach, other exits report "skills cap not checked", and the ACTION line says whether the sync was recorded. Nits 2-4 fixed (printf newlines, non-empty GUARD assertion, stderr-only capture): test_test_files.sh 6 passed.

## Review verdict
<!-- written ONLY by the independent reviewer -->
Round 1 (reviewer, 2026-11-09, 3c2ee12 against main 55228eb): APPROVE WITH NITS. Low: template-sync treated any non-zero exit of lessons.sh skills as a cap breach, so a lessons.sh without the skills command printed "ACTION: skills cap: ." and always said the sync was recorded. Nits: literal line breaks in printf formats; an empty canonical guard line would pass every file; the lib.sh message was checked on merged output, not stderr; TASK.md lacked its Review verdict and Retro sections. Observation: a core skill the template later retires counts as a project skill (ADR 0012 covers only added core skills).

Round 2 (reviewer, 2026-11-09, 141075c against main 55228eb): PASS. Every criterion is backed by the test or judgment it names (test_test_files.sh, test_lessons.sh, test_template_sync.sh section p, check.sh step 5m with probe evidence, the verify output). The rule 10 kernel edit matches the owner's recorded choice and .kernel.hash matches the verified value; no private project names and no em or en dashes in either diff. Round 1 is resolved in 141075c: only exit 1 is a breach (template-sync.sh:623), other exits print "skills cap not checked" and set rc=1 (:626-628) with a fail-first case (test_template_sync.sh:452-464); the ACTION line says whether the sync was recorded; printf uses 
; test_test_files.sh asserts a non-empty guard (:14) and captures stderr only (:36); the sections are restored. No test or gate was removed or loosened. Open, non-blocking: the retired-core-skill observation.

Evidence checked: verify.txt for 141075c in full (39 lines; tree 8a4cbd3 unchanged; kernel-hash, line-budget, lessons, taskgraph, adr, tasklint check and ship, doc-eval OK; selftest 23 passed, 0 failed, 0 quarantined; template self-test OK; exit=0); review.diff (1146 lines, 40 files) and review.log; review2.diff (159 lines); .work/TASK.md; scripts/lessons.sh, scripts/template-sync.sh, scripts/check.sh step labels, tests/template/lib.sh, test_test_files.sh, test_check_always.sh, test_template_sync.sh helpers; ship.md, retro.md, new-task.sh, tasklint.sh, .gitattributes; greps for leftover cap wording, project names, sed -z usage. The advisor confirmed with git that 2c90847 changes AGENTS.md and .kernel.hash together.

## Retro
<!-- filled by docs/procedures/retro.md -->
- Defects by route: (b) escaped past merge: all three shipped in template-v0.4.0 and showed in the project syncs. Each has its failing-first regression test (test_test_files.sh 1 passed, 4 failed; test_template_sync.sh section p 153 passed, 3 failed; test_lessons.sh 107 passed, 16 failed), and each cause is now a check, so no PENDING entry. (a) caught pre-merge: the started-project fixture losing exec bits on Windows (check.sh, test_check_always.sh), the N1/N3 file overlap (taskgraph), and review round 1's cap-exit finding (fail-first case added).
- Trap: the destructive-action hook blocks a shell command whose heredoc text names rm -rf with a variable target, even when the command only writes that text into a file. One process entry in docs/lessons/UPSTREAM.md.
- Deferred: a retired core skill counts as a project skill (BACKLOG row).
- Lessons consulted: L001, L002, L005, L006, L009.
