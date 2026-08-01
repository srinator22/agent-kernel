#!/usr/bin/env bash
# ci-watch.sh - a push is not done until every required check for the exact
# pushed SHA reaches terminal success (kernel rule 5). This script mechanizes
# that: it verifies the remote branch points at the SHA, then polls the checks
# for that SHA until each is terminal, printing transitions.
# Usage: scripts/ci-watch.sh [SHA] [--timeout SECONDS]
set -euo pipefail

SHA=""
TIMEOUT=1800
while (( $# )); do
  case "$1" in
    --timeout) TIMEOUT="${2:?--timeout needs a value}"; shift 2 ;;
    *) SHA="$1"; shift ;;
  esac
done
[[ -n "$SHA" ]] || SHA="$(git rev-parse HEAD)"

if ! command -v gh >/dev/null 2>&1; then
  echo "ci-watch: gh CLI not found, so the checks for $SHA could NOT be verified." >&2
  echo "Unverified is not success (kernel rule 14). Install gh, or watch the CI UI and record the result." >&2
  exit 1
fi

branch="$(git rev-parse --abbrev-ref HEAD)"
remote_sha="$(git ls-remote origin "refs/heads/$branch" | awk '{print $1}')"
if [[ "$remote_sha" != "$SHA" ]]; then
  echo "ci-watch: remote '$branch' points at ${remote_sha:-nothing}, not $SHA." >&2
  echo "Push first; watch what is actually on the remote." >&2
  exit 1
fi

echo "ci-watch: watching checks for $SHA (timeout ${TIMEOUT}s)"
start=$SECONDS
prev_total=-1
declare -A last_state

while :; do
  runs="$(gh api "repos/{owner}/{repo}/commits/$SHA/check-runs" --paginate \
    --jq '.check_runs[] | "\(.name)\t\(.status)\t\(.conclusion // "-")\t\(.html_url)"' \
    2>/dev/null || true)"

  total=0; completed=0; failed=0; failures=""
  while IFS=$'\t' read -r name status conclusion url; do
    [[ -n "$name" ]] || continue
    total=$((total + 1))
    state="$status/$conclusion"
    if [[ "${last_state[$name]:-}" != "$state" ]]; then
      echo "  [$(date -u +%H:%M:%S)] $name: $state"
      last_state[$name]="$state"
    fi
    if [[ "$status" == "completed" ]]; then
      completed=$((completed + 1))
      case "$conclusion" in
        success|neutral|skipped) ;;
        *) failed=$((failed + 1)); failures+="  $name -> $conclusion  $url"$'\n' ;;
      esac
    fi
  done <<< "$runs"

  if (( total != prev_total )); then
    if (( total == 0 )); then
      echo "  (no checks reported yet for $SHA)"
    fi
    prev_total=$total
  fi

  if (( failed > 0 )); then
    echo "ci-watch: FAILURE for $SHA" >&2
    printf '%s' "$failures" >&2
    echo "Inspect the log URL above, fix the root cause, verify locally, push the replacement, and watch the replacement SHA." >&2
    exit 1
  fi
  if (( total > 0 && completed == total )); then
    echo "ci-watch: all $total checks reached terminal success for $SHA"
    exit 0
  fi
  if (( SECONDS - start > TIMEOUT )); then
    echo "ci-watch: TIMEOUT after ${TIMEOUT}s with $completed/$total checks completed for $SHA." >&2
    echo "This is not success - investigate before reporting anything as done." >&2
    exit 1
  fi
  sleep 15
done
