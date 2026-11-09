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
# An empty GUARD would match any blank line and pass every file.
assert_eq "this file holds the canonical guarded line" "yes" "$([[ "$GUARD" == *"cannot load lib.sh"* ]] && echo yes || echo no)"

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
  # stderr only: the message must reach a terminal even when stdout is piped.
  out="$(cd "run/$n" && bash "$FIX/iso/$n/$n.sh" 2>&1 >/dev/null)" || rc=$?
  (( rc != 0 )) || passed_rc+=("$n")
  [[ "$out" == *"cannot load lib.sh"* ]] || silent+=("$n")
  [[ -z "$(ls -A "run/$n")" ]] || leaked+=("$n: $(ls -A "run/$n" | tr '\n' ' ')")
done
assert_eq "without lib.sh every test exits non-zero" "" "${passed_rc[*]:-}"
assert_eq "without lib.sh every test says on stderr it cannot load lib.sh" "" "${silent[*]:-}"
assert_eq "without lib.sh no test writes into the folder it started from" "" "${leaked[*]:-}"

# Every tracked tests/template/*.sh is 100755 in the git index.
modes="$(git -C "$T_ROOT" ls-files -s -- tests/template 2>/dev/null)"
if [[ -z "$modes" ]]; then
  t_na "exec bits: tests/template is not tracked in a git checkout here; covered by CI"
else
  nonexec="$(printf '%s\n' "$modes" | awk '$4 ~ /^tests\/template\/[^\/]+\.sh$/ && $1 != "100755" { printf "%s ", $4 }')"
  assert_eq "every tracked tests/template/*.sh is executable in git" "" "${nonexec% }"
fi


# t_check_exec: a script without the executable bit is named; an exempt path
# is not. Git Bash on Windows reports a shebang script as executable whatever
# its mode, so there the bit cannot be removed and the case does not apply.
make_fixture
printf '#!/usr/bin/env bash
' > scripts/fine.sh; chmod +x scripts/fine.sh
printf '#!/usr/bin/env bash
' > scripts/plain.sh; chmod -x scripts/plain.sh
mkdir -p tests/template
printf '#!/usr/bin/env bash
' > tests/template/test_plain.sh; chmod -x tests/template/test_plain.sh
if [[ -x scripts/plain.sh ]]; then
  t_na "t_check_exec names a script without the executable bit: this platform reports every shebang script as executable; covered by Linux CI"
else
  OUT="$( T_PASS=0; T_FAIL=0; t_check_exec "case" ; echo "fail=$T_FAIL" )"
  assert_contains "t_check_exec fails a fixture holding non-executable scripts" "fail=1"
  assert_contains "it names a scripts/ file" "scripts/plain.sh"
  assert_contains "it names a tests/template file" "tests/template/test_plain.sh"
  assert_not_contains "it does not name an executable script" "scripts/fine.sh"
  OUT="$( T_PASS=0; T_FAIL=0; t_check_exec "case" scripts/plain.sh tests/template/test_plain.sh ; echo "fail=$T_FAIL" )"
  assert_contains "exempt paths pass" "fail=0"
  # the fixture's own end-of-test check must not fail on the deliberate misses
  chmod +x scripts/plain.sh tests/template/test_plain.sh
fi

# t_parallel runs sections side by side: output in call order, counts added,
# a failing section fails the test, and the helper folder does not outlive it.
PARTMP="$FIX/partmp"
mkdir -p "$PARTMP"
cat > "$FIX/par.sh" <<PAR
#!/usr/bin/env bash
source "$T_ROOT/tests/template/lib.sh"
sec_one() { make_fixture; t_ok "one first"; t_ok "one second"; }
sec_two() { make_fixture; t_bad "two fails"; }
t_parallel "one" sec_one
t_parallel "two" sec_two
t_parallel_wait
t_ok "after the sections"
t_finish
PAR
# T_EXEC_CHECK is off here: the counts asserted below are the sections' own.
run env T_EXEC_CHECK= TMPDIR="$PARTMP" bash "$FIX/par.sh"
assert_rc "a failing section fails the test" 1
assert_contains "the counts of every section are added" "par.sh: 3 passed, 1 failed"
assert_contains "a section's lines are kept" "ok   one second"
assert_eq "sections print in call order" "yes" "$([[ "$OUT" == *"one first"*"two fails"*"after the sections"* ]] && echo yes || echo no)"
assert_eq "sections and the helper folder leave nothing in TMPDIR" "" "$(ls -A "$PARTMP")"

t_finish
