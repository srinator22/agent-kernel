#!/usr/bin/env bash
# selftest.sh - runs every tests/template/test_*.sh (plain bash, hermetic temp
# git repos, no network) and reports pass/fail counts. These tests exercise the
# template's own tooling; they are not the project's test suite.
# Usage: scripts/selftest.sh [-v]    -v prints every test's output, not only failures.
#
# Quarantine (docs/procedures/tests.md step 5): a tests/template path listed in
# tests/quarantine.list ("<test path> # owner: <task> date: YYYY-MM-DD"; blank
# lines and lines starting with "#" ignored, the rule scripts/lessons.sh uses)
# is skipped and named on every run; lessons.sh enforces the owner, date and
# 30-day limit. A listed tests/template path that does not exist fails the run.
# Entries outside tests/template belong to the project's own test runner.
# Lines starting "  n/a  " in a passing test's output (cases that do not apply
# in this repository) are printed even without -v.
# Exit: 0 when every test file that ran passed, 1 on any failure.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

verbose=0
[[ "${1:-}" == "-v" ]] && verbose=1

passed=0
failed=0
quarantined=0
failed_names=""
shopt -s nullglob
tests=(tests/template/test_*.sh)
if (( ${#tests[@]} == 0 )); then
  echo "selftest: no tests found under tests/template/" >&2
  exit 1
fi

# Quarantined tests/template paths, each once, space-delimited for lookup.
qlist=" "
if [[ -f tests/quarantine.list ]]; then
  while IFS= read -r ql || [[ -n "$ql" ]]; do
    ql="${ql%$'\r'}"
    [[ "$ql" =~ ^[[:space:]]*(#|$) ]] && continue
    qp="${ql%%#*}"
    qp="${qp%"${qp##*[![:space:]]}"}"
    qp="${qp#"${qp%%[![:space:]]*}"}"
    [[ "$qp" == tests/template/* ]] || continue
    [[ "$qlist" == *" $qp "* ]] && continue
    if [[ ! -e "$qp" ]]; then
      failed=$((failed + 1))
      failed_names="$failed_names $qp"
      echo "FAIL  tests/quarantine.list names $qp, which does not exist; remove the entry"
      continue
    fi
    qlist="$qlist$qp "
  done < tests/quarantine.list
fi

for t in "${tests[@]}"; do
  if [[ "$qlist" == *" $t "* ]]; then
    quarantined=$((quarantined + 1))
    echo "QUARANTINED  $t (tests/quarantine.list)"
    continue
  fi
  rc=0
  out="$(bash "$t" 2>&1)" || rc=$?
  if (( rc == 0 )); then
    passed=$((passed + 1))
    echo "PASS  $t"
    if (( verbose )); then
      printf '%s\n' "$out" | sed 's/^/      /'
    else
      while IFS= read -r line; do
        if [[ "$line" == "  n/a  "* ]]; then echo "    $line"; fi
      done <<< "$out"
    fi
  else
    failed=$((failed + 1))
    failed_names="$failed_names $t"
    echo "FAIL  $t (exit $rc)"
    printf '%s\n' "$out" | sed 's/^/      /'
  fi
done

echo "selftest: $passed passed, $failed failed, $quarantined quarantined (${#tests[@]} test files)"
if (( failed > 0 )); then
  echo "selftest: FAILED:$failed_names" >&2
  exit 1
fi
