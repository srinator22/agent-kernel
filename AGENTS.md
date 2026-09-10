<!-- KERNEL:BEGIN -->
## Kernel - how this repo works and learns (edits require human approval + scripts/kernel-hash.sh --update in the same commit)

These rules govern process. Project truth lives in the Project decisions section and may be rewritten there.

1. Mechanize first. A lesson becomes prose only if no lint rule, type, test, or script can express it. Prefer checks over words.
2. Tests are ground truth. Never delete, skip, weaken, or loosen a failing test or gate to get green. A flaky test is a defect: quarantine it in docs/lessons/QUARANTINE.md and fix it as its own task.
3. Root cause, guard, repair. Reproduce first, on real data where it exists. A bug found after merge gets its failing regression test before the fix. Fix the cause at the owning layer, add the check that makes recurrence impossible, and repair existing damage. A workaround is acceptable only when the cause cannot safely be fixed now, and is recorded with its follow-up.
4. Spec before code, tests before implementation. Non-trivial tasks get .work/TASK.md filled in (goal, acceptance criteria, plan, progress). Criteria become executable tests where possible and are approved by the human unless the task is marked autopilot. Patch the smallest safe surface; no unrelated cleanup in the same change.
5. Done is layered. Implementation done: behavior at the correct layer, contracts explicit, tests cover it, nothing unrelated included. Verification done: acceptance tests green, ./scripts/check.sh green, rendered output inspected when presentation matters, reviewer verdict recorded in .work/TASK.md. Delivery done: CI and any deploy for the exact pushed SHA reached terminal success. A push is not done while any required check is queued or running; never report an in-progress state as success.
6. Git discipline. Follow the recorded workflow in Project decisions (default: branch + gated merge). Conventional Commits; a fix commit body states the exact issue, the fix, and the files and functions touched. Inspect git status before editing and before committing; untracked or unrelated changes are preserved, never staged, reverted, or overwritten. No --no-verify, no force-push, no destructive git commands unless explicitly requested with a verified target.
7. Session protocol. At session start and after any compaction: re-read AGENTS.md, .work/TASK.md, and BACKLOG.md before acting. At session end: run the retro procedure and leave the worktree state understandable.
8. Memory tiers. Resident: this file (<= 180 lines). Triggered: scan docs/lessons/INDEX.md and the rules index below before non-trivial work; open only matching entries and increment their usage counter. Queryable: docs/decisions/, CHANGELOG.md, git log - grep on demand. Memory is a snapshot: before acting on something memory says exists, verify it still does.
9. Learning is gated. Proposed lessons go to docs/lessons/PENDING.md as: what happened / what check should have caught it / what was added / retire-when. Confirmed-good calls count as lessons too, not only corrections. Never record what is derivable from the repo itself. Pending entries are not acted on; a human moves approved entries into INDEX.md.
10. Forgetting is mandatory. Hard caps: 20 approved lessons, 180 lines for this file, 8 skills. The maintain procedure archives on evidence (unused > 45 days, or retire-when met), never on vibes.
11. Archive, never delete. Removing a repo artifact means moving it to .archive/ with a one-line reason, only during a maintenance pass, never mid-task. Anything else destructive follows docs/rules/destructive-actions.md: exact absolute target verified read-only first, never a root, home, workspace root, broad glob, or unresolved variable, narrowest recoverable operation, result verified and reported.
12. Security defaults. Proprietary code and data are private by default. Never commit credentials, tokens, production data, or unapproved raw datasets; the secret scan in check.sh is not optional. Widening exposure (public repos, removed auth, wider network access) requires explicit human authorization. See docs/rules/security.md.
13. Dependencies are justified. Check existing capability first; the commit body states why. Lockfile committed; lockfile changes reviewed; unused dependencies removed at maintenance.
14. Evidence before claims. Run it and read the output in this turn before saying it passes. Distinguish built, trained, evaluated, validated, deployed, and production-ready. Never fabricate a value: unverifiable stays empty as "N/A - reason" and is reported. A plausible wrong answer is worse than a visible gap. Full numerical precision internally; round only for display.
15. Scope and autonomy. Read-only inspection authorizes no edits. A build request authorizes normal reversible work inside the requested scope. Irreversible or outward-facing actions (publishing, deleting data, deployments, external messages, cost changes) need human approval; approval is per-instance until the human records a standing override in Project decisions, after which stop re-asking. Do the requested scope completely, then stop; propose extras separately.
16. Delegation. The main session is the advisor: it decomposes, designs schemas, reviews, verifies, and commits. Workers execute bounded mechanical tasks with exact paths and known pitfalls, never commit, and never edit the same file concurrently. A monitor agent tracks every push to terminal state. No agents for conversational turns, judgment calls, or trivial edits. Speed comes from parallel rigor, not less rigor.
17. Long work runs as checkpointed, resumable background processes with a gitignored STATE file, never as a token-burning agent loop. See docs/procedures/longjob.md.
18. Generated artifacts (CHANGELOG.md, lockfiles, build products) are never hand-edited. Change the source or generator and rebuild; CI freshness-checks them.
19. Escape hatch. A task prefixed "quick:" skips spec and plan ceremony. It never skips rules 2, 6, 12, 14, or 15, and anything merged still requires green CI.
20. Style. Plain hyphens only - no em dashes or en dashes anywhere in repo output. No attribution trailers of any kind. Concise, lead with the result, observational reporting: quote the numbers and let evidence carry the conclusion.
<!-- KERNEL:END -->

## Standards

- Non-obvious modules open with a header: purpose, inputs, outputs, dependencies, assumptions, and the validation source when logic is ported from elsewhere.
- Comments explain why, constraints, or provenance - never what, and never the current task or ticket.
- Errors are explicit and actionable; malformed input is never silently converted into plausible output.
- Tests are deterministic: await the actual promises and events, never race real work against a wall-clock timeout. Test contracts and behavior, not incidental internals. Cover empty, malformed, extreme, duplicate, partial, and missing inputs.
- Ported or numerical logic gets golden-master tests pinned to validated real numbers with units, source, and documented tolerance. Never change expected values just to match a new implementation.
- Architectural boundaries are enforced mechanically (lint/import rules wired at start), with dependencies pointing inward and external systems behind adapters.
- No speculative abstraction: three similar lines beat a premature abstraction. Match the surrounding code's idioms. Typed arrays and minimal allocation in numeric hot loops; measure before optimizing and record before/after evidence.
- Local folders mirroring canonical records are named by the canonical ID, no parallel schemes.
- README stays present-tense: what the thing IS, not a history.

## Response shape

- Lead with the result or next action.
- Keep active steps bounded and visible.
- Finish the primary issue before presenting secondary issues separately.
- Distinguish confirmed causes from hypotheses; never present an inference as evidence.
- Preserve relevant information when brevity would make the answer incomplete.

## Rules index (triggered)

- Architecture and boundaries -> docs/rules/architecture.md
- Security, secrets, exposure -> docs/rules/security.md
- Data classes, provenance, hashing, what enters git -> docs/rules/data-provenance.md
- Experiments, models, leakage, validation status -> docs/rules/scientific-integrity.md
- Deleting or overwriting anything material -> docs/rules/destructive-actions.md
- CI permissions, pinning, caching, deploy gating -> docs/rules/ci-baseline.md

## Project decisions

Status: TEMPLATE - not initialized. Run docs/procedures/start.md before any project work.

- Purpose, users, non-goals, boundary: {{FILLED_BY_START}}
- Ownership and visibility: {{private/public, solo/team}}
- Git workflow: {{branch+gated merge (default) OR direct-to-main, recorded as an explicit choice}}
- Release model and versioning source of truth: {{FILLED_BY_START}}
- Deploy target and exposure: {{FILLED_BY_START or none}}
- Canonical verification: ./scripts/check.sh
- Data policy: {{what may enter git; where large/private data lives}}
- Risk profile: {{ordinary / scientific / safety-sensitive / embedded}}
- Standing overrides recorded by the human: {{none yet}}
- Stack and commands: {{FILLED_BY_START - must exactly match scripts/check.sh}}
