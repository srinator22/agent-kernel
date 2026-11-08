#!/usr/bin/env bash
# The tests/template test files themselves. Each test_*.sh loads lib.sh with
# the one guarded line this file uses (its own source line below is the
# canonical text), so a test that cannot load lib.sh stops before it builds
# fixture files in the folder it was started from. Every tracked
# tests/template/*.sh keeps the executable bit in the git index, which
# projects with an exec-bits gate require.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" || { echo "$0: cannot load lib.sh; stopped before writing anything" >&2; exit 2; }

GUARD="$(grep -m1 '^source .*/lib\.sh"' "${BASH_SOURCE[0]}")"
TESTS=("$T_ROOT"/tests/template/test_*.sh)

# Every test loads lib.sh with exactly the canonical guarded line.
unguarded=()
for t in "${TESTS[@]}"; do
  grep -qxF -- "$GUARD" "$t" || unguarded+=("$(basename "$t")")
done
assert_eq "every test loads lib.sh with the canonical guarded line" "" "${unguarded[*]:-}"

# Every test copied alone, without lib.sh, and started from an empty folder
# exits non-zero, names lib.sh, and leaves that folder empty.
make_fixture
mkdir -p iso run
leaked=()
silent=()
passed_rc=()
for t in "${TESTS[@]}"; do
  n="$(basename "$t" .sh)"
  mkdir -p "iso/$n" "run/$n"
  cp "$t" "iso/$n/"
  rc=0
  out="$(cd "run/$n" && bash "$FIX/iso/$n/$n.sh" 2>&1)" || rc=$?
  (( rc != 0 )) || passed_rc+=("$n")
  [[ "$out" == *"cannot load lib.sh"* ]] || silent+=("$n")
  [[ -z "$(ls -A "run/$n")" ]] || leaked+=("$n: $(ls -A "run/$n" | tr '\n' ' ')")
done
assert_eq "without lib.sh every test exits non-zero" "" "${passed_rc[*]:-}"
assert_eq "without lib.sh every test says it cannot load lib.sh" "" "${silent[*]:-}"
assert_eq "without lib.sh no test writes into the folder it started from" "" "${leaked[*]:-}"

# Every tracked tests/template/*.sh is 100755 in the git index.
modes="$(git -C "$T_ROOT" ls-files -s -- tests/template 2>/dev/null)"
if [[ -z "$modes" ]]; then
  t_na "exec bits: tests/template is not tracked in a git checkout here; covered by CI"
else
  nonexec="$(printf '%s\n' "$modes" | awk '$4 ~ /^tests\/template\/[^\/]+\.sh$/ && $1 != "100755" { printf "%s ", $4 }')"
  assert_eq "every tracked tests/template/*.sh is executable in git" "" "${nonexec% }"
fi

t_finish
