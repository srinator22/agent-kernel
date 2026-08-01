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
# choice; while the Project decisions line still holds a placeholder, the
# default branch+gated-merge workflow applies.
BRANCH="task/$SLUG"
if grep -Eq -- '- Git workflow:.*direct-to-main' AGENTS.md && ! grep -Eq -- '- Git workflow:.*\{\{' AGENTS.md; then
  BRANCH="$(git rev-parse --abbrev-ref HEAD)"
  echo "new-task: recorded workflow is direct-to-main; staying on branch $BRANCH"
else
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
TEMPLATE

echo "new-task: created $TASK_FILE on branch $BRANCH (mode: $MODE)"
echo "Next steps:"
echo "  1. Fill Goal, Acceptance criteria, and Plan in $TASK_FILE."
echo "  2. Unless the mode is autopilot, get the criteria approved by the human (kernel rule 4)."
echo "  3. Work the plan; append timestamped one-liners to the Progress log."
