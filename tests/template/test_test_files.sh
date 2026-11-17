#!/usr/bin/env bash
# The tests/template test files themselves. Each test_*.sh loads lib.sh with
# the one guarded line this file uses (its own source line below is the
# canonical text), so a test that cannot load lib.sh stops before it builds
# fixture files in the folder it was started from. Every tracked
# tests/template/*.sh keeps the executable bit in the git index, which
# projects with an exec-bits gate require. The lib.sh helpers: t_check_exec
# names fixture scripts without the bit, and t_cleanup runs it when
# T_EXEC_CHECK=1; t_parallel sections run side by side with their counts
# added, and a section that exits early, or a test stopped by TERM, leaves no
# fixture behind.
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

# A section that exits early still removes its fixture, and the test names it.
cat > "$FIX/parexit.sh" <<PAR
#!/usr/bin/env bash
source "$T_ROOT/tests/template/lib.sh"
sec_quits() { make_fixture; t_ok "quits first"; exit 3; }
sec_fine() { make_fixture; t_ok "fine"; }
t_parallel "quits" sec_quits
t_parallel "fine" sec_fine
t_parallel_wait
t_finish
PAR
run env T_EXEC_CHECK= TMPDIR="$PARTMP" bash "$FIX/parexit.sh"
assert_rc "a section that exits early fails the test" 1
assert_contains "it is named as ended early" "section quits ended before it finished"
assert_contains "the other section still counts" "ok   fine"
assert_eq "a section that exits early leaves nothing in TMPDIR" "" "$(ls -A "$PARTMP")"

# A test stopped by TERM while a section runs removes the section's fixture
# and the helper folder. The section marks that its fixture exists, then
# waits on a marker that never comes (bounded).
cat > "$FIX/parterm.sh" <<PAR
#!/usr/bin/env bash
source "$T_ROOT/tests/template/lib.sh"
sec_long() { make_fixture; touch "$PARTMP.ready"; for _ in \$(seq 1 300); do sleep 0.1; done; t_ok "long"; }
t_parallel "long" sec_long
t_parallel_wait
t_finish
PAR
rm -f "$PARTMP.ready"
env T_EXEC_CHECK= TMPDIR="$PARTMP" bash "$FIX/parterm.sh" > "$FIX/parterm.out" 2>&1 &
pt=$!
for _ in $(seq 1 200); do [[ -e "$PARTMP.ready" ]] && break; sleep 0.1; done
assert_file "the section started" "$PARTMP.ready"
kill -TERM "$pt"; wait "$pt"
assert_eq "a test stopped by TERM leaves nothing of its sections in TMPDIR" "" "$(ls -A "$PARTMP")"
rm -f "$PARTMP.ready"

# The fixture check is wired: with T_EXEC_CHECK=1 (selftest.sh exports it)
# t_cleanup checks the fixture before removing it, so a script the test left
# without the executable bit fails the test; without it nothing is checked.
# Where chmod cannot set bits, the wiring shows as the n/a line instead.
cat > "$FIX/hook.sh" <<HOOK
#!/usr/bin/env bash
source "$T_ROOT/tests/template/lib.sh"
make_fixture
printf '#!/usr/bin/env bash\n' > scripts/plain.sh
chmod -x scripts/plain.sh
t_ok "wrote a script without the bit"
t_finish
HOOK
run env -u T_EXEC_BITS -u T_EXEC_NA T_EXEC_CHECK=1 bash "$FIX/hook.sh"
if t_exec_bits_work; then
  assert_rc "T_EXEC_CHECK=1: a fixture script without the bit fails the test" 1
  assert_contains "T_EXEC_CHECK=1: the script is named" "scripts/plain.sh"
else
  assert_rc "T_EXEC_CHECK=1 on a platform without bits: the test passes" 0
  assert_contains "T_EXEC_CHECK=1 on a platform without bits: the check ran and says n/a" "n/a  hook.sh fixture: executable bits"
fi
run env -u T_EXEC_BITS -u T_EXEC_NA -u T_EXEC_CHECK bash "$FIX/hook.sh"
assert_rc "without T_EXEC_CHECK the fixture is not checked" 0
assert_not_contains "without T_EXEC_CHECK no executable-bit line" "executable"

t_finish
