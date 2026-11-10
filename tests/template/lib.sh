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
# No self-test may read the owner's real Codex sessions: dream and taste read
# $DREAM_CODEX_HOME before CODEX_HOME and ~/.codex. A path that does not exist is
# an empty home; make_fixture swaps in a created empty folder beside each
# fixture, which t_cleanup removes with it.
T_NO_CODEX="${TMPDIR:-/tmp}/template-selftest.no-codex-home"
export DREAM_CODEX_HOME="$T_NO_CODEX"
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
  mkdir -p "$FIX-codex" && export DREAM_CODEX_HOME="$FIX-codex"
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

# t_check_exec NAME [EXEMPT...]: every *.sh the fixture holds under scripts/ and
# tests/template/ is executable on disk (a path relative to the fixture may be
# exempted when a case needs it without). Linux refuses to run a script that
# lacks the bit; Git Bash on Windows runs it anyway because it honours the
# shebang, so this assertion bites on Linux and macOS and a Windows-only gate
# cannot see the miss.
# t_exec_bits_work: true where chmod really sets the bit. On Windows (NTFS)
# chmod is a no-op and Git Bash calls a file executable exactly when it starts
# with #!, so a fixture script without one would be reported falsely. Probed
# once per shell.
T_EXEC_BITS=""
t_exec_bits_work() {
  local d
  if [[ -z "$T_EXEC_BITS" ]]; then
    T_EXEC_BITS=0
    if d="$(mktemp -d "${TMPDIR:-/tmp}/template-selftest.xb.XXXXXX")"; then
      printf 'echo x\n' > "$d/p.sh"; chmod +x "$d/p.sh"
      printf '#!/bin/sh\n' > "$d/s.sh"; chmod -x "$d/s.sh"
      if [[ -x "$d/p.sh" && ! -x "$d/s.sh" ]]; then T_EXEC_BITS=1; fi
      case "$d" in */template-selftest.xb.*) rm -rf "$d" ;; esac
    fi
  fi
  [[ "$T_EXEC_BITS" == 1 ]]
}

t_check_exec() {
  local name="$1" f rel x bad="" exempt=0
  shift
  [[ -n "$FIX" && -d "$FIX" ]] || return 0
  if ! t_exec_bits_work; then
    if [[ -z "${T_EXEC_NA:-}" ]]; then
      t_na "$name: executable bits: chmod cannot set them on this platform; covered by Linux CI"
      T_EXEC_NA=1
    fi
    return 0
  fi
  while IFS= read -r f; do
    rel="${f#"$FIX"/}"
    exempt=0
    for x in "$@"; do [[ "$x" == "$rel" ]] && exempt=1; done
    (( exempt )) || [[ -x "$f" ]] || bad="$bad $rel"
  # tests/template/fixtures/ holds data copies (fixtures/check.sh is 100644 in
  # git on purpose), not scripts a test runs.
  done < <(find "$FIX/scripts" "$FIX/tests/template" -path "$FIX/tests/template/fixtures" -prune -o -name '*.sh' -type f -print 2>/dev/null | sort)
  assert_eq "$name: every script the fixture writes is executable on disk" "" "${bad# }"
}

t_cleanup() {
  # T_EXEC_CHECK=1 runs t_check_exec on every fixture just before it goes.
  if [[ "${T_EXEC_CHECK:-}" == 1 && -n "$FIX" ]]; then t_check_exec "$T_NAME fixture"; fi
  cd / || true
  case "$FIX" in
    */template-selftest.*) rm -rf "$FIX" "$FIX-codex" ;;
  esac
  [[ -z "$FIX" ]] || export DREAM_CODEX_HOME="$T_NO_CODEX"
  FIX=""
}

# t_parallel NAME FUNC: run FUNC (a section of the test that builds its own
# fixtures) in a background subshell, so independent sections of a slow test
# overlap. t_parallel_wait then prints each section's lines in call order and
# adds its pass and fail counts. A section must not rely on state from
# another; its assertions count exactly as if it had run inline.
T_PAR_DIR=""
T_PAR_COUNT=0
T_PAR_PIDS=()
T_PAR_NAMES=()
t_parallel() {
  local n dir
  if [[ -z "$T_PAR_DIR" ]]; then
    T_PAR_DIR="$(mktemp -d "${TMPDIR:-/tmp}/template-selftest-par.XXXXXX")" || exit 1
  fi
  T_PAR_COUNT=$((T_PAR_COUNT + 1))
  n=$T_PAR_COUNT; dir="$T_PAR_DIR"
  (
    # The section owns its own fixtures; the shared folder is the parent's.
    T_PAR_DIR=""; T_PASS=0; T_FAIL=0; FIX=""
    "$2"
    t_cleanup
    echo "$T_PASS $T_FAIL" > "$dir/$n.counts"
  ) > "$dir/$n.out" 2>&1 &
  T_PAR_PIDS[$n]=$!
  T_PAR_NAMES[$n]="$1"
}
t_parallel_wait() {
  local n p f
  for (( n = 1; n <= T_PAR_COUNT; n++ )); do
    wait "${T_PAR_PIDS[$n]}" || true
    cat "$T_PAR_DIR/$n.out"
    if [[ -f "$T_PAR_DIR/$n.counts" ]]; then
      read -r p f < "$T_PAR_DIR/$n.counts"
      T_PASS=$((T_PASS + p))
      T_FAIL=$((T_FAIL + f))
    else
      t_bad "section ${T_PAR_NAMES[$n]} ended before it finished"
    fi
  done
  t_par_cleanup
}
t_par_cleanup() {
  case "$T_PAR_DIR" in
    */template-selftest-par.*) rm -rf "$T_PAR_DIR" ;;
  esac
  T_PAR_DIR=""
  T_PAR_COUNT=0
}

# A test that exits before t_finish still removes its fixture and sections.
t_exit() { t_cleanup; t_par_cleanup; }
trap t_exit EXIT

t_finish() {
  t_cleanup
  echo "$T_NAME: $T_PASS passed, $T_FAIL failed"
  (( T_FAIL == 0 ))
  exit $?
}
