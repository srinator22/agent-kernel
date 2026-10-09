#!/usr/bin/env bash
# selftest.sh - runs every tests/template/test_*.sh (plain bash, hermetic temp
# git repos, no network) and reports pass/fail counts. These tests exercise the
# template's own tooling; they are not the project's test suite.
# Usage: scripts/selftest.sh [-v]    -v prints every test's output, not only failures.
# Exit: 0 when every test file passes, 1 on any failure.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

verbose=0
[[ "${1:-}" == "-v" ]] && verbose=1

passed=0
failed=0
failed_names=""
shopt -s nullglob
tests=(tests/template/test_*.sh)
if (( ${#tests[@]} == 0 )); then
  echo "selftest: no tests found under tests/template/" >&2
  exit 1
fi

for t in "${tests[@]}"; do
  rc=0
  out="$(bash "$t" 2>&1)" || rc=$?
  if (( rc == 0 )); then
    passed=$((passed + 1))
    echo "PASS  $t"
    if (( verbose )); then printf '%s\n' "$out" | sed 's/^/      /'; fi
  else
    failed=$((failed + 1))
    failed_names="$failed_names $t"
    echo "FAIL  $t (exit $rc)"
    printf '%s\n' "$out" | sed 's/^/      /'
  fi
done

echo "selftest: $passed passed, $failed failed (${#tests[@]} test files)"
if (( failed > 0 )); then
  echo "selftest: FAILED:$failed_names" >&2
  exit 1
fi
