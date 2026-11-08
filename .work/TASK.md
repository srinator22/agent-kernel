# Task: dream-outcome-fixes
Mode: standard
Branch: task/dream-outcome-fixes
Date: 2026-11-08

## Goal
Fix two defects the first real `dream.sh done --report` exposed after PR 14
merged. (1) The outcome's Files line lists every file name inside an applied
Change line, including names quoted inside row or entry text and files the
owner only has to decide about, so it claims files changed that did not. (2)
Hygiene looks for auto-memory in the folder named after the checkout it runs
in, so from a linked worktree it reports "none found" although Claude Code
keeps one memory folder per repository under the main checkout's name.

## Non-goals
- Changing the report format or the dreamer agent.
- Reading Change lines with a parser that understands their prose.
- The taste pass (it reads every project's memory folder already).

## Budget
- Wall-clock: 2 h
- Subagents / workflow runs: 3 (reviewer, monitor)
- Retries per failing step: 2
- Escalate to human when: criteria unreachable or scope exceeds Non-goals

## Assumptions
- [confirmed] the owner asked to fix both defects here ("Fix both here", 2026-11-08)
- [verified] this session's auto-memory lives in the folder named after the main checkout although its working directory is a linked worktree -> ~/.claude/projects/C--dev-work-New-Project/memory holds the notes; no memory folder exists for the worktree names
- [verified] the 2026-11-08 outcome listed .claude/settings.json, destructive-guard.sh, adr.sh, refuse_shell_stdin.py and AGENTS.md as Files although none changed -> the main checkout's .work/dream/2026-11-08-report.md, git show --stat a310385

## Acceptance criteria
- [x] Files lists a named file only when it changed since the digest: in git against the commit the digest saw (committed, staged, unstaged or untracked), or in the auto-memory folder by size or modification time -> tests/template/test_dream.sh
- [x] A file named only inside quoted text or as a decision for the owner, and unchanged, is not listed; a bare name matches a changed path by its last components -> tests/template/test_dream.sh
- [x] Without a recorded digest commit (state from an older digest) the line says the files were not checked rather than claiming them -> tests/template/test_dream.sh
- [x] Hygiene from a linked worktree reads the main checkout's auto-memory folder -> tests/template/test_dream.sh
- [x] The existing outcome and hygiene tests still pass unchanged -> tests/template/test_dream.sh
- [x] `./scripts/check.sh` green and the reviewer's PASS recorded -> judgment: gate and review

## Plan
| node | depends on | owner files | worker tier | status |
|---|---|---|---|---|
| N1 | - | tests/template/test_dream.sh | advisor | done |
| N2 | N1 | scripts/dream/dream.py, docs/procedures/dream.md | advisor | done |
| N3 | N2 | .work/TASK.md | reviewer | done |

## Plan verdict

## Progress log
- 2026-11-08 criteria from the two defects the owner asked to fix; the design (digest records HEAD, the stat of files dirty then, and the memory folder's stat; done compares) is the advisor's call
- 2026-11-08 failing tests first on the old dream.py: test_dream.sh 163 passed, 6 failed (Files line names quoted, owner-decision and untouched memory files; no not-checked fallback; worktree hygiene "none found in ...-wt3\memory")
- 2026-11-08 fixed in scripts/dream/dream.py (memory_dir, tree_state, memory_state, changed_since, names_path; outcome_text takes the digest state; hygiene_text uses memory_dir) and docs/procedures/dream.md steps 3 and 6: test_dream.sh 169 passed, 0 failed
- 2026-11-08 mutation: dropping the dirty-at-digest stat rule fails 2 checks (an untracked, untouched note-b.md claimed); restored
- 2026-11-08 real data: scripts/dream.sh hygiene from this linked worktree reads 5 memory files; the old code reports none found in the worktree-named folder
- 2026-11-08 review round 1 FAIL: the memory test passed through git (the fake projects folder sat inside the fixture repo, so notes were untracked files) and the BACKLOG change was never committed before done. Test moved the projects folder outside the fixture and commits the row; also from the review: done refuses to claim files when its history lacks the digest's commit (new test), worktree-side renames skip their origin field, names_path states its last-components limit, dream.md step 6 states the history precondition. test_dream.sh 172 passed, 0 failed
- 2026-11-08 mutations after round 1, each restored: memory stat comparison removed, diff without the digest commit, history check removed: each fails 1 check (171 passed, 1 failed)

## Review verdict
<!-- written ONLY by the independent reviewer -->
Round 1 (reviewer, 2026-11-08, uncommitted diff against main 5ce4e78): FAIL. Blocking: criterion 1 ticked but the test reached the memory notes through git (the fake projects folder sat inside the fixture repo with no .gitignore, so notes were untracked files), and the BACKLOG change was left unstaged, so neither the memory-stat path nor the committed path was exercised; removing the memory comparison left all checks green. Non-blocking: done in a checkout whose HEAD differs from the digest's can claim the difference of two branches; a worktree-side rename's origin field is read as an entry; names_path suffix matching is a limit to state; status -uall cost is bounded; the "git cannot compare" branch is untested; style and privacy clean.

Round 2 (reviewer, 2026-11-08, same base): PASS. The blocker is fixed: the projects folder sits outside the fixture, the BACKLOG row is committed between digest and done, and each of three mutations (memory comparison removed, diff without the digest commit, history check removed) fails exactly the right check. Non-blocking: a descendant checkout that merged unrelated work still shows it in the diff and the digest's dirty stats apply to whichever checkout runs done, both within "changed since the digest" and the stated precondition; the "git cannot compare" branch stays untested (git failure only); an early test exit leaves the -p11 and worktree folders in TMPDIR.

Evidence checked: check7.log in full (every stage OK; selftest 22 passed, 0 failed, 0 quarantined; template self-test OK); after2.log (172 passed, 0 failed); mut-memory.log, mut-nohead.log, mut-noanc.log (each 171 passed, 1 failed, on the right check); review4.diff in full; dream.py and test_dream.sh lines read on disk; the porcelain parse; existing outcome assertions unchanged and passing; no em or en dashes, no attribution, no secrets, no new dependencies.

## Retro
<!-- filled by docs/procedures/retro.md -->
