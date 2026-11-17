#!/usr/bin/env bash
# test-budget.sh - caps test-code growth. Agents add tests easily and delete
# them rarely, so the suite grows without protecting more; this guard makes the
# growth visible and makes any exception a recorded decision.
# Usage: scripts/test-budget.sh check    (the gate; check.sh step 4 calls it)
#        scripts/test-budget.sh report   (per-file non-blank line counts, largest first)
# Input: tests/BUDGET (format in its header comments): `paths:` globs,
#   `ceiling:`, `allowance:` and dated `raise:` lines. Run from anywhere in the
#   repository; paths are relative to the repository root.
# Output: `test-budget: <current> lines, ceiling <C>, allowance <A>`.
# Exit codes: 0 within budget, or tests/BUDGET absent (skip line, for projects
#   on an older template sync); 1 over budget, malformed BUDGET, or not in a
#   git work tree; 2 usage error.
# Dependencies: bash 3.2+, git, grep, sort.
# Assumptions: a line counts when it holds a non-whitespace character; tracked
#   and untracked-not-ignored files both count, so a new test file is counted
#   before it is added; a glob's `*` crosses `/` (git pathspec rules).
set -euo pipefail

mode="${1:-}"
case "$mode" in check|report) ;; *) echo "usage: scripts/test-budget.sh check|report" >&2; exit 2 ;; esac

top="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "test-budget: not inside a git work tree" >&2; exit 1; }
cd "$top"
budget="tests/BUDGET"
if [[ ! -f "$budget" ]]; then
  echo "test-budget: skipped, tests/BUDGET is absent (template sync older than the test budget)"
  exit 0
fi

fail() { echo "test-budget: $budget: $*" >&2; exit 1; }

paths="" ceiling="" allowance="" have_paths=0 have_ceiling=0 have_allowance=0
n=0
while IFS= read -r line || [[ -n "$line" ]]; do
  n=$((n + 1))
  line="${line%$'\r'}"
  case "$line" in
    ''|'#'*) continue ;;
    paths:*)
      (( have_paths == 0 )) || fail "line $n: duplicate paths:"
      have_paths=1; paths="${line#paths:}" ;;
    ceiling:*)
      (( have_ceiling == 0 )) || fail "line $n: duplicate ceiling:"
      have_ceiling=1; ceiling="${line#ceiling:}"; ceiling="${ceiling//[[:space:]]/}" ;;
    allowance:*)
      (( have_allowance == 0 )) || fail "line $n: duplicate allowance:"
      have_allowance=1; allowance="${line#allowance:}"; allowance="${allowance//[[:space:]]/}" ;;
    raise:*)
      rest="${line#raise:}"
      # <old>-><new> <YYYY-MM-DD> <reason>
      if [[ ! "$rest" =~ ^[[:space:]]*([0-9]+)-\>([0-9]+)[[:space:]]+([0-9]{4}-[0-9]{2}-[0-9]{2})[[:space:]]+([^[:space:]].*)$ ]]; then
        fail "line $n: a raise line reads 'raise: <old>-><new> <YYYY-MM-DD> <reason>' with a non-empty reason"
      fi
      (( 10#${BASH_REMATCH[2]} > 10#${BASH_REMATCH[1]} )) || fail "line $n: a raise must increase the ceiling (<new> above <old>)" ;;
    *) fail "line $n: unknown line '$line' (expected paths:, ceiling:, allowance:, raise: or a # comment)" ;;
  esac
done < "$budget"

(( have_paths )) && [[ -n "${paths//[[:space:]]/}" ]] || fail "missing or empty 'paths:' (space-separated globs)"
(( have_ceiling )) && [[ "$ceiling" =~ ^[0-9]+$ ]] || fail "missing or non-numeric 'ceiling:'"
(( have_allowance )) && [[ "$allowance" =~ ^[0-9]+$ ]] || fail "missing or non-numeric 'allowance:'"

# Word splitting of $paths is the intent: one pathspec per glob. Globbing is off
# so the shell never expands them; git matches them.
set -f
# shellcheck disable=SC2086
files="$(git ls-files -c -o --exclude-standard -- $paths | sort -u)"
set +f

total=0
report=""
while IFS= read -r f; do
  [[ -n "$f" && -f "$f" ]] || continue
  c="$(grep -c '[^[:space:]]' "$f" 2>/dev/null || true)"
  c="${c:-0}"
  total=$((total + c))
  report="$report$(printf '%7d %s' "$c" "$f")"$'\n'
done <<< "$files"

if [[ "$mode" == report ]]; then
  printf '%s' "$report" | sort -rn
  echo "test-budget: $total lines, ceiling $ceiling, allowance $allowance"
  exit 0
fi

echo "test-budget: $total lines, ceiling $ceiling, allowance $allowance"
limit=$((ceiling + allowance))
if (( total > limit )); then
  echo "test-budget: FAIL: $total lines exceeds ceiling $ceiling + allowance $allowance = $limit (over by $((total - limit)))." >&2
  echo "test-budget: consolidate or delete duplicate tests, or raise the ceiling with a dated reason in tests/BUDGET (add 'raise: $ceiling->$total <YYYY-MM-DD> <reason>' and set ceiling: $total). Never delete the only regression guard for a contract." >&2
  exit 1
fi
exit 0
