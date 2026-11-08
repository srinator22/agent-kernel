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
- [ ] Every tests/template/test_*.sh run without lib.sh next to it exits non-zero, names lib.sh on stderr and writes nothing into its working folder -> tests/template/test_test_files.sh
- [ ] Every tests/template/test_*.sh loads lib.sh with the one canonical guarded line -> tests/template/test_test_files.sh
- [ ] Every tracked tests/template/*.sh is 100755 in the git index -> tests/template/test_test_files.sh
- [ ] Skills cap is the core skills present (CORE_SKILLS, at most 8) + 2 project skills + profile skills; a seventh core skill keeps a full project within the cap; a removed core skill frees no slot -> tests/template/test_lessons.sh
- [ ] Template mode: .claude/skills equals CORE_SKILLS -> judgment: check.sh step 5m, shown failing on a probe skill folder (Progress log); template mode has no fixture test
- [ ] template-sync reports the skills cap after a sync; a new core skill on a full project is no action item; a breach prints ACTION: skills cap and exits 1 -> tests/template/test_template_sync.sh
- [ ] ./scripts/check.sh green -> judgment: verify output attached to the review

## Plan
| node | depends on | owner files | worker tier | status |
|---|---|---|---|---|
| N1 | - | tests/template/test_test_files.sh, tests/template/test_*.sh, tests/template/lib.sh | advisor | done |
| N2 | N1 | tests/template/test_taste.sh | advisor | done |
| N3 | - | scripts/lessons.sh, scripts/template-sync.sh, scripts/check.sh, tests/template/test_lessons.sh, tests/template/test_template_sync.sh, AGENTS.md, .kernel.hash, docs/decisions/0012-*.md | advisor | done |
| N4 | N1, N2, N3 | .work/TASK.md, BACKLOG.md | reviewer | todo |

## Plan verdict

## Progress log
- 2026-11-08 task opened; skills-cap decision sent to the owner through the starting session.
- 2026-11-08 fix 1 fail-first: `bash tests/template/test_test_files.sh` before the guard: 1 passed, 4 failed. Root cause: tests/template/test_*.sh line `source .../lib.sh` under set -uo pipefail without -e, so a failed source continues. 15 of 22 tests wrote files into their start folder (test_selftest: tests/; test_session_context: .work f1.txt..., and so on), all 22 printed no lib.sh message, test_taste.sh 100644. After: 5 passed, 0 failed (11 s).
- 2026-11-08 fix 3 report fail-first: test_template_sync.sh section p before the template-sync change: 153 passed, 3 failed (no skills line, no ACTION line, exit 0). After: 156 passed.
- 2026-11-08 owner chose A (relayed). Counting fail-first: test_lessons.sh against HEAD's lessons.sh: 107 passed, 16 failed, including "a seventh core skill keeps a full project within the cap (exit 1, expected 0)", the template-v0.4.0 case; root cause scripts/lessons.sh cmd_check cap=BASE_SKILLS+sets with core and project skills in one count. After: 123 passed. test_template_sync.sh with real core names: 156 passed.
- 2026-11-08 step 5m: the snippet run alone passes on the tree and fails with a probe folder .claude/skills/zz-probe ("differ from CORE_SKILLS"); the probe was removed.
