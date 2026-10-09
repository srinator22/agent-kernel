#!/usr/bin/env bash
# quickgate.sh - the uniform "fast lane": quick gate while working, full gate
# (scripts/check.sh) before ship. It runs only the steps of check.sh that fit
# the budget by delegating to "check.sh --quick". The always section of check.sh
# (style, memory caps, task graph, selftest) is never skipped by the quick lane.
# A project opts in by teaching its check.sh that flag; until then this exits 2
# so procedures can tell "not wired" from "failed".
# Usage: scripts/quickgate.sh [args passed through to check.sh --quick]
# QUICKGATE_BUDGET (seconds, default 60) is exported for check.sh to honour and
# is checked here after the run as a warning, never a failure.
# Exit: check.sh's own status, or 2 when the project has no quick lane.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK="$ROOT/scripts/check.sh"

if [[ ! -f "$CHECK" ]] || ! grep -q -e '--quick' "$CHECK"; then
  echo "quickgate: this project has not wired a quick lane: scripts/check.sh has no --quick flag." >&2
  echo "quickgate: add one that runs only the fast steps, or run the full gate: ./scripts/check.sh" >&2
  exit 2
fi

export QUICKGATE_BUDGET="${QUICKGATE_BUDGET:-60}"
echo "quickgate: the quick lane never skips the always section of check.sh (style, memory caps, task graph, template self-tests)."
start=$SECONDS
rc=0
"$CHECK" --quick "$@" || rc=$?
elapsed=$((SECONDS - start))
if (( elapsed > QUICKGATE_BUDGET )); then
  echo "quickgate: WARNING: took ${elapsed}s, over the ${QUICKGATE_BUDGET}s budget; trim the quick lane." >&2
fi
exit "$rc"
