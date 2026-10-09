# Orchestration - roles, task graph, delegation

Detail for kernel rule 16. Speed comes from parallel rigor, not less rigor.

Roles:
- Advisor: the main session. Decomposes, designs schemas, reviews,
  verifies, commits. Never delegates judgment.
- Worker: one bounded task with exact paths, schemas and pitfalls. Never
  commits or pushes.
- Reviewer: fresh context. Receives the diff, `.work/TASK.md` and the
  verify output, never the implementer's reasoning.
- Monitor: watches the exact pushed SHA to a terminal state, in the
  foreground, with the maximum timeout. Queued or running is not success.
- Explorer: read-only search; returns file:line and where it looked.

The plan is a task graph in `.work/TASK.md`: one node per row with
dependencies, owner files, worker tier (docs/rules/models.md) and status.
Nodes in one wave own disjoint files; a node waits for its dependencies.
`scripts/taskgraph.sh` validates the graph.

Rules:
- One writer per file at a time. Concurrent edit-capable workers use
  separate worktrees; within one tree, owner files never overlap.
- A worker brief carries exact paths, schemas, pitfalls, the facts to
  write from, and the report format. Doc writers write only from facts
  supplied; they never invent numbers or behaviour.
- A worker that cannot do the task says so and stops. It never
  approximates, never widens scope, never substitutes a lookalike.
- The advisor inspects one concrete item (one row, one file, one failing
  case) before accepting a worker's summary or a verdict such as "done",
  "flaky" or "placement-limited".
- Every long pass has a hard time cap and a progress file
  (docs/procedures/longjob.md); exhaustion stops and reports the best
  verified artifact with unresolved items (ADR 0002).
- Declare the TASK.md Budget before fan-out and define the reducer
  (how results merge) first.
- Fan out only independent, scoped, checkable units. Coherent-context
  work (architecture, coupled refactors, narrative) stays in one context.
- The advisor integrates: reads each worker's changes, runs the gate,
  then commits task paths with the pathspec form (shared index safety).
