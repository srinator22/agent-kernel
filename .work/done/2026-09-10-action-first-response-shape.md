# Task: action-first-response-shape
Mode: standard
Branch: codex/action-first-response-shape
Date: 2026-09-10

## Goal
Add a small, shared response-shape contract that makes Codex and Claude
answers easier to act on without importing the external skill's branding,
medical claims, persistence machinery, or rigid rules.

## Non-goals
- Tool-specific duplicates, hooks, plugins, and runtime persistence.
- Medical or diagnostic claims about ADHD.
- Importing the external skill or all ten of its rules.

## Budget
- Wall-clock: 20 minutes
- Subagents / workflow runs: 1 independent review
- Retries per failing step: 2
- Escalate to human when: criteria are unreachable or scope exceeds Non-goals

## Acceptance criteria
- [x] Responses lead with the result or next action -> judgment: communication behavior
- [x] Active steps remain bounded and visible -> judgment: communication behavior
- [x] Secondary issues remain separate from the primary issue -> judgment: communication behavior
- [x] Confirmed causes are distinguished from hypotheses -> judgment: communication behavior
- [x] Completeness wins when brevity would hide relevant information -> judgment: communication behavior
- [x] One shared source governs both Codex and Claude -> `CLAUDE.md` imports `AGENTS.md`
- [x] The canonical template gauntlet passes -> `scripts/check.sh`

## Plan
1. Add the smallest shared response-shape section to AGENTS.md outside the kernel.
2. Verify Claude still imports AGENTS.md and run the canonical gauntlet.
3. Review the diff for scope and wording.

## Progress log
- 2026-09-10: User-selected five-rule subset adopted as the approved acceptance criteria.
- 2026-09-10: Created branch codex/action-first-response-shape; no matching approved lessons found.
- 2026-09-10: Added the shared AGENTS.md response-shape section; kernel hash, template self-test, Claude import, and diff check pass.
- 2026-09-10: Independent reviewer returned PASS on all seven acceptance criteria.
- 2026-09-10: Feature committed as 83e19e6 after a green local ship gate.

## Review verdict
PASS - all seven acceptance criteria are met.

Verified with evidence:
- `AGENTS.md` lines 42-46 encode the five approved response-shape behaviors directly.
- `CLAUDE.md` line 1 remains exactly `@AGENTS.md`; the template self-test verifies this shared-source contract.
- `scripts/check.ps1` invoked the canonical `scripts/check.sh` successfully: kernel hash OK, line budget 70/180, and template self-test OK for all 66 required files.
- The response-shape section is outside the protected kernel; `.kernel.hash` is unchanged and verification passed.
- Only `AGENTS.md` and `.work/TASK.md` changed. No scripts, tests, gates, dependencies, lockfiles, secrets, private data, or unrelated artifacts changed.
- Input edge-case testing is not applicable to this prose-only behavioral contract; its non-judgment requirements are mechanically covered by the existing Claude import and canonical gauntlet checks.

## Retro
- Defects encountered: none.
- Lessons consulted: none.
- New pending lessons: none; the selected rules are now directly discoverable from `AGENTS.md`.
- Backlog changes: none.
