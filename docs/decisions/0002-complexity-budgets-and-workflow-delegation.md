# 0002 - Complexity budgets and workflow delegation

Date: 2026-08-01
Status: accepted

## Context

Two ideas adopted from a verified synthesis of Karpathy's autoresearch
and Anthropic's workflow infrastructure (Amendment 1 to
docs/BLUEPRINT.md). First, every autonomous run should declare its
resource budget up front and, on exhaustion, stop and report honestly
rather than hiding partial failure behind a fluent answer - autoresearch
runs its ~700-experiments-in-two-days loop under exactly such declared
budgets. Second, Claude Code's dynamic workflows (GA 2026) are the
preferred mechanism for large parallel scoped work, replacing hand-rolled
worker spawning: the orchestration script holds intermediate state in
script variables instead of the advisor's context. Caps were verified
against the live harness at amendment time: 16 concurrent (as
min(16, cores - 2)) and 1,000 subagents total per run; the manifest keeps
a VERIFY marker because caps are harness-versioned.

This amendment also carried two repairs. The stale ADR number in
docs/procedures/start.md was real: it hardcoded 0002-stack-choice.md, and
this ADR now occupies 0002; start.md now says "the next-numbered ADR".
The "missing release tag" premise was false: verification showed
template-v0.2.0 already exists on the remote, annotated, at the v0.2.0
build commit (6aaaafa), pushed at build time. No repair was performed;
moving a published tag would violate kernel rule 6. A mechanical check
for "releases are tagged" was considered (CI checks out full history, so
shallow clones are not the blocker) and declined: pre-1.0 there is no
mechanical definition of "a release is pending", so this ADR note stands
as the record.

## Decision

- Task state (.work/TASK.md and the template new-task.sh emits) gains a
  Budget block: wall-clock, subagent/workflow-run count, retries per
  failing step, and an explicit escalation condition. Declared before
  work starts; exhaustion means stop, keep the best verified artifact,
  and report unresolved items with reasons.
- manifest.md gains a "Delegation accelerators" section pointing large
  parallel scoped work on Claude Code at dynamic workflows,
  budget-first and reducer-first; coherent-context work is never
  fragmented.
- The kernel is untouched: the budget is task-state and the workflow
  pointer is harness-specific, which the portability principle keeps
  out of the portable core.

## Consequences

- Every task now declares its limits up front; running out produces an
  honest partial report instead of a fluent cover story.
- Large fan-outs on Claude Code route through dynamic workflows, keeping
  the advisor's context window clear of intermediate state.
- Other harnesses keep the same budget-first and reducer-first rules
  with their native mechanisms.
- ADR numbering is allocated in creation order; start.md no longer
  collides with it.
