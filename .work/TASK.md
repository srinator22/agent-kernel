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

## Acceptance criteria
<!-- each maps to an executable test where possible; list test paths -->
- [ ] {{criterion}} -> {{test path or "judgment: reason"}}

## Plan
1. {{step}}

## Progress log
<!-- timestamped one-liners; this is what survives compaction -->

## Review verdict
<!-- written ONLY by the independent reviewer -->

## Retro
<!-- filled by docs/procedures/retro.md -->
