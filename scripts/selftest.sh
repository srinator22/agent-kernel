#!/usr/bin/env bash
# selftest.sh - runs tests/template/test_*.sh (plain bash, hermetic temp git
# repos, no network) and reports pass/fail counts. These tests exercise the
# template's own tooling; they are not the project's test suite.
# Usage: scripts/selftest.sh [-v] [--serial] [TEST_FILE...]
#   -v         print every test's output, not only failures.
#   --serial   run the test files one at a time (the same as SELFTEST_JOBS=1).
#   TEST_FILE  run only these tests/template/test_*.sh files (relative to the
#              caller's folder or absolute; a file named twice runs once). A
#              path that does not exist or is not such a file exits 2. Without
#              any, every test file runs.
# Test files run in parallel, SELFTEST_JOBS at a time (default: the core count
# or 4, whichever is smaller). A file starts many short processes, so on Git
# Bash 24 files at once starve each other and finish no sooner than a few at a
# time; CI runners have 4 cores. A slot is refilled as soon as any file in it
# finishes, not when the oldest running file does (wait -n where bash has it,
# bash 4.3+; otherwise a poll for the finished file's .rc every 0.1 s, bash 3.2
# on macOS; SELFTEST_POLL=1 forces the poll so tests reach it). Each file's
# output is kept together and printed in file order, so the report reads like
# a serial run. The files share no temp paths: every fixture is its own mktemp
# -d folder (lib.sh).
# INT or TERM (Ctrl-C) stops every running file: each gets TERM, lib.sh's EXIT
# trap removes its fixtures, and the run exits 130 (INT) or 143 (TERM) with
# nothing left in TMPDIR. A run started in the background with INT ignored (a
# shell without job control) cannot trap INT; TERM still works.
# Executable bits are probed once per run through lib.sh (t_exec_bits_work) and
# exported as T_EXEC_BITS, with T_EXEC_CHECK=1 so lib.sh t_cleanup checks every
# fixture. Where chmod cannot set the bits (Windows), the run prints one n/a line
# instead of one per test file.
#
# Quarantine (docs/procedures/tests.md step 5): a tests/template path listed in
# tests/quarantine.list ("<test path> # owner: <task> date: YYYY-MM-DD"; blank
# lines and lines starting with "#" ignored, the rule scripts/lessons.sh uses)
# is skipped and named on every run; lessons.sh enforces the owner, date and
# 30-day limit. A listed tests/template path that does not exist fails the run.
# Entries outside tests/template belong to the project's own test runner.
# Lines starting "  n/a  " in a passing test's output (cases that do not apply
# in this repository) are printed even without -v.
# Exit: 0 when every test file that ran passed, 1 on any failure, 2 on a usage
# error, 130 or 143 when stopped by INT or TERM.
set -euo pipefail

CALLER="$PWD"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

verbose=0
jobs="${SELFTEST_JOBS:-}"
picked=" "
for arg in "$@"; do
  case "$arg" in
    -v) verbose=1 ;;
    --serial) jobs=1 ;;
    -*) echo "selftest: unknown argument $arg (usage: selftest.sh [-v] [--serial] [TEST_FILE...])" >&2; exit 2 ;;
    *)
      p="$arg"
      [[ "$p" == /* || "$p" =~ ^[A-Za-z]:[\\/] ]] || p="$CALLER/$p"
      if [[ ! -f "$p" ]]; then
        echo "selftest: no such test file: $arg" >&2
        exit 2
      fi
      d="$(cd "$(dirname "$p")" && pwd)"
      b="$(basename "$p")"
      if [[ "$d" != "$ROOT/tests/template" || "$b" != test_*.sh ]]; then
        echo "selftest: $arg is not a tests/template/test_*.sh file" >&2
        exit 2
      fi
      picked="${picked}tests/template/$b "
      ;;
  esac
done
# The core count, falling back through the tools each platform has.
cores() {
  local n
  n="$(nproc 2>/dev/null)" || n=""
  [[ "$n" =~ ^[0-9]+$ ]] || n="$(getconf _NPROCESSORS_ONLN 2>/dev/null)" || n=""
  [[ "$n" =~ ^[0-9]+$ ]] || n="$(sysctl -n hw.ncpu 2>/dev/null)" || n=""
  [[ "$n" =~ ^[0-9]+$ ]] || n="${NUMBER_OF_PROCESSORS:-}"
  [[ "$n" =~ ^[1-9][0-9]*$ ]] || n=2
  echo "$n"
}
if [[ -z "$jobs" ]]; then
  jobs="$(cores)"
  (( jobs <= 4 )) || jobs=4
elif ! [[ "$jobs" =~ ^[1-9][0-9]*$ ]]; then
  echo "selftest: SELFTEST_JOBS must be a positive integer, got '$jobs'" >&2
  exit 2
fi

# Every fixture a test builds is checked by lib.sh t_cleanup for scripts that
# lack the executable bit (Linux refuses them; Git Bash does not notice).
export T_EXEC_CHECK=1
# One probe for the run instead of one per test file; lib.sh keeps an exported
# result. A tree without lib.sh (a test fixture) leaves the probe to the tests.
unset T_EXEC_BITS T_EXEC_NA
if [[ -f tests/template/lib.sh ]]; then
  T_EXEC_BITS="$(bash -c 'source tests/template/lib.sh && if t_exec_bits_work; then echo 1; else echo 0; fi' 2>/dev/null)" || T_EXEC_BITS=""
  if [[ "$T_EXEC_BITS" == 0 || "$T_EXEC_BITS" == 1 ]]; then
    export T_EXEC_BITS
    if [[ "$T_EXEC_BITS" == 0 ]]; then
      export T_EXEC_NA=1
      echo "  n/a  executable bits in fixtures: chmod cannot set them on this platform; covered by Linux CI"
    fi
  else
    unset T_EXEC_BITS
  fi
fi

passed=0
failed=0
quarantined=0
failed_names=""
shopt -s nullglob
all=(tests/template/test_*.sh)
tests=()
for t in ${all[@]+"${all[@]}"}; do
  [[ "$picked" == " " || "$picked" == *" $t "* ]] && tests+=("$t")
done
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

# Each test file is one job. Its merged output and exit status go to
# $work/<n>.out and $work/<n>.rc and are reported in file order, so a file's
# output is never interleaved with another's. The .rc is written under another
# name and renamed, so a poll never reads a half-written status.
work="$(mktemp -d "${TMPDIR:-/tmp}/selftest-run.XXXXXX")"
trap 'rm -rf "$work"' EXIT

report() { # n test-path
  local rc out line
  rc="$(cat "$work/$1.rc")"
  out="$(cat "$work/$1.out")"
  if [[ "$rc" == 0 ]]; then
    passed=$((passed + 1))
    echo "PASS  $2"
    if (( verbose )); then
      printf '%s\n' "$out" | sed 's/^/      /'
    else
      while IFS= read -r line; do
        if [[ "$line" == "  n/a  "* ]]; then echo "    $line"; fi
      done <<< "$out"
    fi
  else
    failed=$((failed + 1))
    failed_names="$failed_names $2"
    echo "FAIL  $2 (exit $rc)"
    printf '%s\n' "$out" | sed 's/^/      /'
  fi
}

# Launched jobs are numbered 1..launched. fin[n] is 1 once job n has finished;
# finished jobs are reported in order from the oldest unreported one, and a
# new file starts whenever fewer than $jobs are running.
pids=("")
names=("")
fin=("")
launched=0
reported=0
running=0
wait_n=0
if [[ -z "${SELFTEST_POLL:-}" ]] && (( BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 3) )); then
  wait_n=1
fi

# collect: mark every running job whose status file exists, or whose process
# is gone without one (killed), as finished. Prints nothing; sets $found.
collect() {
  local n
  found=0
  for (( n = reported + 1; n <= launched; n++ )); do
    [[ -n "${pids[$n]}" && -z "${fin[$n]}" ]] || continue
    if [[ ! -e "$work/$n.rc" ]]; then
      kill -0 "${pids[$n]}" 2>/dev/null && continue
      [[ -e "$work/$n.rc" ]] || echo "killed" > "$work/$n.rc"
    fi
    wait "${pids[$n]}" 2>/dev/null || true
    fin[$n]=1
    running=$((running - 1))
    found=1
  done
}
# report_ready: report, in file order, every job finished so far.
report_ready() {
  local n
  while (( reported < launched )); do
    n=$((reported + 1))
    if [[ -z "${pids[$n]}" ]]; then # a quarantined file: nothing ran
      reported=$n
      quarantined=$((quarantined + 1))
      echo "QUARANTINED  ${names[$n]} (tests/quarantine.list)"
    elif [[ -n "${fin[$n]}" ]]; then
      reported=$n
      report "$n" "${names[$n]}"
    else
      return 0
    fi
  done
}
# await_one: block until at least one running job has finished.
await_one() {
  collect
  while (( ! found )); do
    if (( wait_n )); then wait -n 2>/dev/null || true; else sleep 0.1; fi
    collect
  done
}

# stop_jobs SIGNAL: send TERM to every running file and wait for it to clean
# up. Each job's subshell passes the TERM on to its test file.
stop_jobs() {
  local n code=130
  [[ "$1" == TERM ]] && code=143
  trap '' INT TERM
  for (( n = reported + 1; n <= launched; n++ )); do
    [[ -n "${pids[$n]}" && -z "${fin[$n]}" ]] || continue
    kill -TERM "${pids[$n]}" 2>/dev/null || true
  done
  wait 2>/dev/null || true
  echo "selftest: stopped by SIG$1 after $reported of ${#tests[@]} test files; the running files were stopped" >&2
  exit "$code"
}
trap 'stop_jobs INT' INT
trap 'stop_jobs TERM' TERM

for t in "${tests[@]}"; do
  launched=$((launched + 1))
  names[$launched]="$t"
  fin[$launched]=""
  if [[ "$qlist" == *" $t "* ]]; then
    pids[$launched]=""
  else
    # The status goes to a file so that set -e cannot hide a failing test. A
    # TERM to this subshell is passed on to the test file ($! is the test
    # file's pid once it has started, empty before).
    (
      trap 'if [[ -n "$!" ]]; then kill -TERM "$!" 2>/dev/null; wait "$!" 2>/dev/null; fi; exit 143' TERM
      rc=0
      bash "$t" > "$work/$launched.out" 2>&1 &
      wait "$!" || rc=$?
      echo "$rc" > "$work/$launched.rt"
      mv "$work/$launched.rt" "$work/$launched.rc"
    ) &
    pids[$launched]=$!
    running=$((running + 1))
  fi
  report_ready
  if (( running >= jobs )); then
    await_one
    report_ready
  fi
done
while (( reported < launched )); do
  await_one
  report_ready
done

echo "selftest: $passed passed, $failed failed, $quarantined quarantined (${#tests[@]} test files)"
if (( failed > 0 )); then
  echo "selftest: FAILED:$failed_names" >&2
  exit 1
fi
