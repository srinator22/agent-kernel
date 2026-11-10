# Task: {{title}}
Mode: standard | quick | autopilot
Branch: {{branch}}
Date: {{date}}

## Goal
{{one paragraph}}

## Non-goals
<!-- explicitly out of scope; scope creep gets caught here -->
- {{out of scope}}

## Budget
<!-- declare before work starts; on exhaustion: stop, keep the best verified
     artifact, and report unresolved items with reasons - never hide a partial
     result behind a fluent answer -->
- Wall-clock: {{max}}
- Subagents / workflow runs: {{max}}
- Retries per failing step: {{max, default 2}}
- Escalate to human when: {{budget exhausted | criteria unreachable | scope exceeds Non-goals}}

## Assumptions
<!-- one line per assumption the work rests on: [confirmed] the human said so,
     [verified] -> evidence (a command or file), [open] not yet settled.
     scripts/tasklint.sh ship (the full gate) fails while any line is [open],
     except in quick mode -->
- [open] {{assumption}}

## Acceptance criteria
<!-- each maps to an executable test where possible; list test paths. A ticked
     line needs "-> <existing path>" or "-> judgment: <reason>"
     (scripts/tasklint.sh check) -->
- [ ] {{criterion}} -> {{test path or "judgment: reason"}}

## Plan
<!-- task graph: one node per row; nodes that can run in the same wave must
     own disjoint files. Tiers: cheap, standard, strong, advisor, reviewer.
     Status: todo, doing, done, blocked. Validate: scripts/taskgraph.sh check -->
| node | depends on | owner files | worker tier | status |
|---|---|---|---|---|
| N1 | - | path/one, path/two | standard | todo |

## Plan verdict
<!-- autopilot only: the reviewer's plan review of Goal, Assumptions,
     Acceptance criteria and Plan, written before any node starts;
     scripts/tasklint.sh requires PASS once a node is doing or done -->

## Progress log
<!-- timestamped one-liners; this is what survives compaction -->

## Review verdict
<!-- written ONLY by the independent reviewer -->

## Retro
<!-- filled by docs/procedures/retro.md -->
