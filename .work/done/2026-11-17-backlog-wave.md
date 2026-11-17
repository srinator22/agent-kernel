# Task: backlog wave 2026-11-17 (integration of ten groups)
Mode: standard
Branch: b17/backlog
Date: 2026-11-17

## Goal
Add four rows from a 2026-11-16 article on verification to BACKLOG.md, then clear every open row the template can close: ten groups in parallel worktrees (adr, check, fleet, guard, hooks, review, selftest, small, start, sync), merged onto one branch, verified by CI and reviewed once as a whole. Each group's own record is .work/done/2026-11-17-<group>.md.

## Non-goals
- Rows that need a second project, an owner decision or an owner cost approval (product-render graduation, flicker calibration, STEP importer exception, audio check, paper simulation, multi-machine rendering).
- The uncommitted stop-gate and BACKLOG edits in the main checkout (another session's work, preserved untouched).

## Assumptions
- [verified] The groups own disjoint files -> each group's record lists its owner files; the merges into b17/backlog were clean.
- [verified] The full gate is green on Linux CI for the reviewed head -> CI push run 44065208465 at 5e50e54: selftest 36 passed, 0 failed; check.sh: verified tree 94bf86e36d3979e946d10064589ad0643e0062e1.

## Acceptance criteria
- [x] Four article rows queued, finished rows closed with evidence -> BACKLOG.md
- [x] Every group's tests pass in CI -> judgment: CI check job at 5e50e54, 36 of 36 self-test files
- [x] A merge defect found after integration gets a failing test first -> tests/template/test_kernel_hash.sh
- [ ] selftest-windows passes on the merged head (L019) -> judgment: pending at the time of the review

## Plan
Ten group branches, one integration branch, one PR (20), review rounds until PASS.

## Progress log
- 2026-11-17 groups merged; integration fixed kernel-hash --update truncation (test failed first), the double EXIT trap in check.sh, head pipes in adr.sh, a missing-parser pass in lessons.sh, platform-dependent fleet and hooks-dispatch tests.
- 2026-11-17 review round 1 FAIL: stray lessons.sh.orig, template ADR cited by path in synced files, SW-15 gate untested and without an upgrade path. Fixed in e4b7a93, 2d9591a, 5e50e54.
- 2026-11-17 review round 2 PASS.

## Review verdict
PASS - round 2, head 5e50e5493b212d8c44fab055679311bcd7216b49

Reviewed tree: 94bf86e36d3979e946d10064589ad0643e0062e1

Findings: none. Round 1 (FAIL, tree 12da6b2da4b86a7ce87961f922c1ec086865a4e1) found three; each is fixed: scripts/lessons.sh.orig removed and *.orig, *.rej ignored; synced files cite "template ADR 0016" and adr.sh refuses a path citation in the template itself; SW-15 refusal tests and the upstream.md Verify skill upgrade step.

Notes: selftest-windows must pass on this head before merge (L019). The gate-label job stays red until the owner adds the gate-change label (ADR 0018). Unverified: hooks-dispatch exits before reading stdin when no hooks.d folder exists; a very large payload might see EPIPE in the harness.

Evidence checked:
- CI check log for 5e50e54 lines 130-195, every stage clean, verified tree line present.
- round2.diff in full; worktree has no *.orig or *.rej; the only docs/decisions/NNNN path citation is BLUEPRINT.md:586, outside cited_check's scope.
- Lessons L004, L005, L006, L012, L017, L018 satisfied; L019 pending.

## Retro
