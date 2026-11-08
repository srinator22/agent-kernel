#!/usr/bin/env bash
# new-task.sh - scaffold a task: a branch per the recorded git workflow plus
# .work/TASK.md instantiated from the template.
# Usage: scripts/new-task.sh <slug> [standard|quick|autopilot]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SLUG="${1:-}"
MODE="${2:-standard}"

if [[ -z "$SLUG" ]]; then
  echo "usage: scripts/new-task.sh <slug> [standard|quick|autopilot]" >&2
  exit 2
fi
if [[ ! "$SLUG" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
  echo "ERROR: slug must be lowercase letters, digits, and hyphens" >&2
  exit 2
fi
case "$MODE" in
  standard|quick|autopilot) ;;
  *) echo "ERROR: mode must be standard, quick, or autopilot" >&2; exit 2 ;;
esac

TASK_FILE=".work/TASK.md"
if [[ -f "$TASK_FILE" ]] && ! grep -q '{{title}}' "$TASK_FILE"; then
  echo "ERROR: $TASK_FILE is already in progress (no {{title}} placeholder)." >&2
  echo "Finish it via docs/procedures/retro.md, which archives it to .work/done/, before starting a new task." >&2
  exit 1
fi

# Direct-to-main applies only once start has recorded it as an explicit
# choice (start.md item 4): the "- Git workflow:" value starts with
# direct-to-main (backtick, star or underscore markup allowed) followed by end
# of value, by optional spaces then ; . : , or (, or by " - ". Anything else,
# a placeholder or a negation such as "direct-to-main is not allowed" included,
# reads as the default branch + gated merge, so a misread can only create a
# branch, never commit to main by mistake.
BRANCH="task/$SLUG"
wf="$(grep -m1 -E -- '^- Git workflow:' AGENTS.md 2>/dev/null || true)"
wf="${wf%$'\r'}"
wf="${wf#- Git workflow:}"
direct_re='^[[:space:]]*[`*_]*direct-to-main[`*_]*([[:space:]]*$|[[:space:]]*[;.:,(]|[[:space:]]+-[[:space:]])'
if [[ "$wf" =~ $direct_re ]]; then
  BRANCH="$(git rev-parse --abbrev-ref HEAD)"
  echo "new-task: recorded workflow is direct-to-main; staying on branch $BRANCH"
else
  if [[ "$wf" =~ ^[[:space:]]*[\`*_]*direct-to-main ]]; then
    echo "new-task: WARNING: the - Git workflow: value starts with direct-to-main but reads as branch + gated merge; if direct-to-main is the standing choice, write it as \"direct-to-main, <details>\" (start.md item 4)" >&2
  fi
  echo "new-task: recorded workflow is branch + gated merge; creating branch $BRANCH"
  git checkout -b "$BRANCH"
fi

mkdir -p .work
DATE_UTC="$(date -u +%F)"
cat > "$TASK_FILE" <<TEMPLATE
# Task: $SLUG
Mode: $MODE
Branch: $BRANCH
Date: $DATE_UTC

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
TEMPLATE

echo "new-task: created $TASK_FILE on branch $BRANCH (mode: $MODE)"
echo "Next steps:"
echo "  1. Fill Goal, Assumptions, Acceptance criteria, and Plan in $TASK_FILE."
echo "  2. Unless the mode is autopilot, get the criteria and assumptions approved by the human (kernel rule 4)."
echo "     In autopilot, get the reviewer's plan review into the Plan verdict section before any node starts."
echo "  3. Work the plan; append timestamped one-liners to the Progress log."
