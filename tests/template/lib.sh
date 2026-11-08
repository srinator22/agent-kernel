#!/usr/bin/env bash
# lib.sh - tiny assertion helpers shared by tests/template/test_*.sh. Sourced,
# never run directly (scripts/selftest.sh only runs test_*.sh). Tests are plain
# bash with no network; each builds a throwaway git repo fixture under the
# system temp dir and removes it on exit.
# Each test loads this file with the guarded source line of test_test_files.sh,
# so a test that cannot load it stops before writing anything.

T_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# The pristine template check.sh. After start wires scripts/check.sh to a stack,
# the tests must still see the template version, so it ships as a fixture that
# check.sh keeps byte-identical to itself while in template mode.
T_CHECK="$T_ROOT/tests/template/fixtures/check.sh"
[[ -f "$T_CHECK" ]] || T_CHECK="$T_ROOT/scripts/check.sh"
# No self-test may reach a real ruff runner or the network: a template-mode
# check.sh run in a fixture uses this fake (check.sh step 5k honours it).
export TEMPLATE_RUFF="$T_ROOT/tests/template/fixtures/fake-ruff.sh"
T_PASS=0
T_FAIL=0
T_NAME="$(basename "$0")"
FIX=""
OUT=""
RC=0

t_ok()  { T_PASS=$((T_PASS + 1)); echo "  ok   $*"; }
t_bad() { T_FAIL=$((T_FAIL + 1)); echo "  FAIL $*"; }
# t_na CASE: REASON; covered by GATE - a case that does not apply in this
# repository. scripts/selftest.sh prints these lines in its normal output.
t_na()  { echo "  n/a  $*"; }

# run CMD...: capture merged output in $OUT and the exit status in $RC.
run() { OUT="$("$@" 2>&1)"; RC=$?; }

assert_rc() { # name expected
  if [[ "$RC" == "$2" ]]; then t_ok "$1"; else t_bad "$1 (exit $RC, expected $2)"; printf '%s\n' "$OUT" | sed 's/^/       | /'; fi
}
assert_contains() { # name needle
  if [[ "$OUT" == *"$2"* ]]; then t_ok "$1"; else t_bad "$1 (output lacks: $2)"; printf '%s\n' "$OUT" | sed 's/^/       | /'; fi
}
assert_not_contains() { # name needle
  if [[ "$OUT" != *"$2"* ]]; then t_ok "$1"; else t_bad "$1 (output has: $2)"; printf '%s\n' "$OUT" | sed 's/^/       | /'; fi
}
assert_eq() { # name expected actual
  if [[ "$2" == "$3" ]]; then t_ok "$1"; else t_bad "$1 (expected '$2', got '$3')"; fi
}
assert_file() { # name path
  if [[ -e "$2" ]]; then t_ok "$1"; else t_bad "$1 (missing: $2)"; fi
}
assert_no_file() { # name path
  if [[ ! -e "$2" ]]; then t_ok "$1"; else t_bad "$1 (should not exist: $2)"; fi
}
assert_file_has() { # name path needle
  if grep -qF -- "$3" "$2" 2>/dev/null; then t_ok "$1"; else t_bad "$1 ($2 lacks: $3)"; fi
}
assert_file_lacks() { # name path needle
  if ! grep -qF -- "$3" "$2" 2>/dev/null; then t_ok "$1"; else t_bad "$1 ($2 has: $3)"; fi
}

# make_fixture: a fresh temp git repo, cwd set to it, $FIX set. The previous
# fixture is removed first, so a test that builds several leaves none behind.
make_fixture() {
  t_cleanup
  FIX="$(mktemp -d "${TMPDIR:-/tmp}/template-selftest.XXXXXX")"
  cd "$FIX" || exit 1
  git init -q . >/dev/null 2>&1
  git config user.email "selftest@example.invalid"
  git config user.name "selftest"
  git config core.autocrlf false
  mkdir -p scripts
}

# cp_script NAME...: copy template scripts into the fixture's scripts/ (a NAME
# may hold a subfolder, such as dream/dream.py).
cp_script() {
  local s
  for s in "$@"; do
    mkdir -p "$(dirname "$FIX/scripts/$s")"
    if [[ "$s" == check.sh ]]; then cp "$T_CHECK" "$FIX/scripts/$s"; else cp "$T_ROOT/scripts/$s" "$FIX/scripts/$s"; fi
    chmod +x "$FIX/scripts/$s"
  done
}

t_cleanup() {
  cd / || true
  case "$FIX" in
    */template-selftest.*) rm -rf "$FIX" ;;
  esac
  FIX=""
}
# A test that exits before t_finish still removes its fixture.
trap t_cleanup EXIT

t_finish() {
  t_cleanup
  echo "$T_NAME: $T_PASS passed, $T_FAIL failed"
  (( T_FAIL == 0 ))
  exit $?
}
