#!/usr/bin/env bash
# test_test_budget.sh - scripts/test-budget.sh: under, at and over the
# ceiling + allowance threshold, a dated raise line is accepted, malformed
# BUDGET files fail with the field named, an absent BUDGET skips, untracked
# test files and blank lines are counted correctly, report sorts descending.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" || { echo "$0: cannot load lib.sh; stopped before writing anything" >&2; exit 2; }

# lines FILE N: write N non-blank lines.
lines() { local i; : > "$1"; for (( i = 1; i <= $2; i++ )); do echo "echo $i" >> "$1"; done; }
# budget CEILING ALLOWANCE [EXTRA...]: write tests/BUDGET.
budget() {
  local c="$1" a="$2"; shift 2
  { echo "# fixture"; echo "paths: tests/*.sh"; echo "ceiling: $c"; echo "allowance: $a"; local x; for x in "$@"; do echo "$x"; done; } > tests/BUDGET
}
setup() {
  make_fixture
  cp_script test-budget.sh
  mkdir -p tests
  lines tests/a.sh 60
  lines tests/b.sh 40
  git add -A >/dev/null 2>&1
}

# Threshold: 100 lines, ceiling 80, allowance 20 -> limit exactly 100.
setup
budget 80 20
run ./scripts/test-budget.sh check
assert_rc "at the threshold passes" 0
assert_contains "prints the count line" "test-budget: 100 lines, ceiling 80, allowance 20"
budget 90 20
run ./scripts/test-budget.sh check
assert_rc "under the threshold passes" 0
budget 80 19
run ./scripts/test-budget.sh check
assert_rc "one line over the threshold fails" 1
assert_contains "names the remedy" "consolidate or delete duplicate tests, or raise the ceiling with a dated reason in tests/BUDGET"
assert_contains "names the overage" "over by 1"

# A raise line with a reason is accepted; the ceiling it records passes.
budget 100 0 "raise: 80->100 2026-11-17 added the budget tests"
run ./scripts/test-budget.sh check
assert_rc "a dated raise line is accepted" 0

# Malformed BUDGET files.
budget 80 20 "raise: 80->100 2026-11-17"
run ./scripts/test-budget.sh check
assert_rc "a raise line without a reason fails" 1
assert_contains "names the raise format" "non-empty reason"
budget 80 20 "raise: 80->100 yesterday because"
run ./scripts/test-budget.sh check
assert_rc "a raise line with a bad date fails" 1
budget 80 20 "raise: 100->80 2026-11-17 shrink"
run ./scripts/test-budget.sh check
assert_rc "a raise that lowers the ceiling fails" 1
printf 'paths: tests/*.sh\nallowance: 20\n' > tests/BUDGET
run ./scripts/test-budget.sh check
assert_rc "a missing ceiling fails" 1
assert_contains "names the missing field" "'ceiling:'"
printf 'paths: tests/*.sh\nceiling: many\nallowance: 20\n' > tests/BUDGET
run ./scripts/test-budget.sh check
assert_rc "a non-numeric ceiling fails" 1
printf 'paths: tests/*.sh\nceiling: 80\n' > tests/BUDGET
run ./scripts/test-budget.sh check
assert_rc "a missing allowance fails" 1
assert_contains "names the allowance" "'allowance:'"
printf 'ceiling: 80\nallowance: 20\n' > tests/BUDGET
run ./scripts/test-budget.sh check
assert_rc "missing paths fails" 1
printf 'paths: tests/*.sh\nceiling: 80\nallowance: 2x\n' > tests/BUDGET
run ./scripts/test-budget.sh check
assert_rc "a non-numeric allowance fails" 1
printf 'paths: tests/*.sh\nceiling: 80\nallowance: 20\nbogus: 1\n' > tests/BUDGET
run ./scripts/test-budget.sh check
assert_rc "an unknown line fails" 1
run ./scripts/test-budget.sh frobnicate
assert_rc "an unknown mode is a usage error" 2

# Absent BUDGET skips with a line, exit 0.
setup
run ./scripts/test-budget.sh check
assert_rc "absent tests/BUDGET exits 0" 0
assert_contains "absent tests/BUDGET prints a skip line" "test-budget: skipped"

# Untracked files count; blank and whitespace-only lines do not.
setup
budget 100 0
git add -A >/dev/null 2>&1
lines tests/c.sh 5
run ./scripts/test-budget.sh check
assert_rc "an untracked test file is counted" 1
assert_contains "the untracked file lifts the count" "test-budget: 105 lines"
rm -f tests/c.sh
printf '\n   \n\t\n\r\n' >> tests/a.sh
printf 'echo last\n\n\n' > tests/d.sh
git add -A >/dev/null 2>&1
run ./scripts/test-budget.sh check
assert_contains "blank lines are not counted" "test-budget: 101 lines"

# A file outside paths is not counted.
lines tests/notes.txt 500
run ./scripts/test-budget.sh check
assert_contains "files outside paths are ignored" "test-budget: 101 lines"

# report: per-file counts, largest first.
budget 100 0
run ./scripts/test-budget.sh report
assert_rc "report exits 0" 0
first="$(printf '%s\n' "$OUT" | sed -n 1p)"
assert_contains "report lists the largest file first" "60 tests/a.sh"
assert_eq "report's first line is the largest file" "60 tests/a.sh" "$(echo $first)"
assert_contains "report ends with the totals line" "test-budget: 101 lines, ceiling 100, allowance 0"

t_finish
