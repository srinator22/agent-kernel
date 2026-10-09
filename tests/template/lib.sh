#!/usr/bin/env bash
# lib.sh - tiny assertion helpers shared by tests/template/test_*.sh. Sourced,
# never run directly (scripts/selftest.sh only runs test_*.sh). Tests are plain
# bash with no network; each builds a throwaway git repo fixture under the
# system temp dir and removes it on exit.

T_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# The pristine template check.sh. After start wires scripts/check.sh to a stack,
# the tests must still see the template version, so it ships as a fixture that
# check.sh keeps byte-identical to itself while in template mode.
T_CHECK="$T_ROOT/tests/template/fixtures/check.sh"
[[ -f "$T_CHECK" ]] || T_CHECK="$T_ROOT/scripts/check.sh"
T_PASS=0
T_FAIL=0
T_NAME="$(basename "$0")"
FIX=""
OUT=""
RC=0

t_ok()  { T_PASS=$((T_PASS + 1)); echo "  ok   $*"; }
t_bad() { T_FAIL=$((T_FAIL + 1)); echo "  FAIL $*"; }

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

# make_fixture: a fresh temp git repo, cwd set to it, $FIX set.
make_fixture() {
  FIX="$(mktemp -d "${TMPDIR:-/tmp}/template-selftest.XXXXXX")"
  cd "$FIX" || exit 1
  git init -q . >/dev/null 2>&1
  git config user.email "selftest@example.invalid"
  git config user.name "selftest"
  git config core.autocrlf false
  mkdir -p scripts
}

# cp_script NAME...: copy template scripts into the fixture's scripts/.
cp_script() {
  local s
  for s in "$@"; do
    if [[ "$s" == check.sh ]]; then cp "$T_CHECK" "$FIX/scripts/$s"; else cp "$T_ROOT/scripts/$s" "$FIX/scripts/$s"; fi
    chmod +x "$FIX/scripts/$s"
  done
}

t_cleanup() {
  cd / || true
  case "$FIX" in
    */template-selftest.*) rm -rf "$FIX" ;;
  esac
}

t_finish() {
  t_cleanup
  echo "$T_NAME: $T_PASS passed, $T_FAIL failed"
  (( T_FAIL == 0 ))
  exit $?
}
