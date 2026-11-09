#!/usr/bin/env bash
# selftest.sh - runs every tests/template/test_*.sh (plain bash, hermetic temp
# git repos, no network) and reports pass/fail counts. These tests exercise the
# template's own tooling; they are not the project's test suite.
# Usage: scripts/selftest.sh [-v] [--serial]
#   -v        print every test's output, not only failures.
#   --serial  run the test files one at a time (the same as SELFTEST_JOBS=1).
# Test files run in parallel, SELFTEST_JOBS at a time (default: the core count
# or 4, whichever is smaller). A file starts many short processes, so on Git
# Bash 24 files at once starve each other and finish no sooner than a few at a
# time; CI runners have 4 cores. Each file's output is kept together and
# printed in file order as the files finish, so the report reads like a serial
# run. The files share no temp paths: every fixture is its own mktemp -d folder
# (lib.sh).
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
jobs="${SELFTEST_JOBS:-}"
for arg in "$@"; do
  case "$arg" in
    -v) verbose=1 ;;
    --serial) jobs=1 ;;
    *) echo "selftest: unknown argument $arg (usage: selftest.sh [-v] [--serial])" >&2; exit 2 ;;
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

# Each test file is one job. Its merged output and exit status go to
# $work/<n>.out and $work/<n>.rc and are reported in file order, so a file's
# output is never interleaved with another's.
work="$(mktemp -d "${TMPDIR:-/tmp}/selftest-run.XXXXXX")"
trap 'rm -rf "$work"' EXIT

report() { # n test-path
  local rc out line
  rc="$(cat "$work/$1.rc")"
  out="$(cat "$work/$1.out")"
  if (( rc == 0 )); then
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

# Launched jobs are numbered 1..launched; the oldest unreported one is awaited
# and reported first, which keeps at most $jobs running.
pids=("")
names=("")
launched=0
reported=0
report_oldest() {
  reported=$((reported + 1))
  if [[ -z "${pids[$reported]}" ]]; then # a quarantined file: nothing ran
    quarantined=$((quarantined + 1))
    echo "QUARANTINED  ${names[$reported]} (tests/quarantine.list)"
    return 0
  fi
  wait "${pids[$reported]}" || true
  report "$reported" "${names[$reported]}"
}
for t in "${tests[@]}"; do
  launched=$((launched + 1))
  names[$launched]="$t"
  if [[ "$qlist" == *" $t "* ]]; then
    pids[$launched]=""
  else
    # The status goes to a file so that set -e cannot hide a failing test.
    ( rc=0; bash "$t" > "$work/$launched.out" 2>&1 || rc=$?; echo "$rc" > "$work/$launched.rc" ) &
    pids[$launched]=$!
  fi
  (( launched - reported < jobs )) || report_oldest
done
while (( reported < launched )); do report_oldest; done

echo "selftest: $passed passed, $failed failed, $quarantined quarantined (${#tests[@]} test files)"
if (( failed > 0 )); then
  echo "selftest: FAILED:$failed_names" >&2
  exit 1
fi
