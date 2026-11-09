#!/usr/bin/env bash
# scripts/selftest.sh: tests/quarantine.list (docs/procedures/tests.md step 5)
# skips each listed tests/template file and names it on every run; a listed
# file that does not exist fails the run; an unlisted failing test still
# fails; n/a lines of passing tests show in the normal output; the summary
# line counts passed, failed and quarantined files; the lib.sh fixtures the
# tests build leave no temp folders behind.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" || { echo "$0: cannot load lib.sh; stopped before writing anything" >&2; exit 2; }

make_fixture
cp_script selftest.sh
mkdir -p tests/template
printf '#!/usr/bin/env bash\necho "  ok   a passes"\nexit 0\n' > tests/template/test_a.sh
printf '#!/usr/bin/env bash\necho "  FAIL b fails"\nexit 1\n' > tests/template/test_b.sh
printf '#!/usr/bin/env bash\necho "  ok   c passes"\necho "  n/a  case x: not here; covered by gate y"\nexit 0\n' > tests/template/test_c.sh

chmod +x tests/template/test_*.sh

# No list: every test runs.
run ./scripts/selftest.sh
assert_rc "without a quarantine list a failing test fails the run" 1
assert_contains "the failure is named" "FAIL  tests/template/test_b.sh (exit 1)"
assert_contains "summary counts all three files" "selftest: 2 passed, 1 failed, 0 quarantined (3 test files)"
assert_contains "an n/a line of a passing test shows without -v" "n/a  case x: not here; covered by gate y"
assert_not_contains "a passing test's ok lines stay hidden without -v" "a passes"

# The failing test quarantined: comment and blank lines ignored, CR tolerated,
# the owner and date part stripped, a duplicate counted once, and an entry
# outside tests/template left to the project's own runner.
printf '%s\n' '# Quarantined tests: <test path> # owner: <task> date: YYYY-MM-DD' '' \
  'tests/template/test_b.sh # owner: fix-b date: 2026-11-08' \
  'tests/template/test_b.sh   # owner: fix-b date: 2026-11-08' \
  'tests/unit/test_other.py # owner: fix-other date: 2026-11-08' > tests/quarantine.list
printf 'tests/template/test_b.sh # owner: fix-b date: 2026-11-08\r\n' >> tests/quarantine.list
run ./scripts/selftest.sh
assert_rc "a quarantined failing test does not fail the run" 0
assert_contains "the quarantined file is named on the run" "QUARANTINED  tests/template/test_b.sh"
assert_eq "it is named once, duplicates and CR lines included" "1" "$(printf '%s\n' "$OUT" | grep -c 'QUARANTINED')"
assert_contains "summary counts it as quarantined" "selftest: 2 passed, 0 failed, 1 quarantined (3 test files)"
assert_not_contains "an entry outside tests/template is not this runner's" "test_other.py"

# An unlisted failing test still fails while another is quarantined.
printf '#!/usr/bin/env bash\nexit 3\n' > tests/template/test_d.sh; chmod +x tests/template/test_d.sh
run ./scripts/selftest.sh
assert_rc "an unlisted failing test still fails" 1
assert_contains "the unlisted failure is named" "FAIL  tests/template/test_d.sh (exit 3)"
assert_contains "summary with both" "selftest: 2 passed, 1 failed, 1 quarantined (4 test files)"
rm -f tests/template/test_d.sh

# A listed tests/template file that does not exist fails the run, named.
echo 'tests/template/test_gone.sh # owner: gone date: 2026-11-08' >> tests/quarantine.list
run ./scripts/selftest.sh
assert_rc "a listed missing test file fails the run" 1
assert_contains "the stale entry is named" "tests/quarantine.list names tests/template/test_gone.sh, which does not exist"

# -v still prints every passing test's output.
sed -i.bak '/test_gone/d' tests/quarantine.list && rm -f tests/quarantine.list.bak
run ./scripts/selftest.sh -v
assert_contains "-v shows passing output" "a passes"

# lib.sh fixtures leave no temp folders: make_fixture removes the fixture
# before it, and a test that exits early still removes its own.
LIBTMP="$FIX/libtmp"
mkdir -p "$LIBTMP/t"
printf '#!/usr/bin/env bash\nsource "%s"\nmake_fixture\nmake_fixture\nmake_fixture\nt_finish\n' "$T_ROOT/tests/template/lib.sh" > "$LIBTMP/three.sh"
printf '#!/usr/bin/env bash\nsource "%s"\nmake_fixture\nexit 3\n' "$T_ROOT/tests/template/lib.sh" > "$LIBTMP/early.sh"
left() { find "$LIBTMP/t" -maxdepth 1 -name 'template-selftest.*' | wc -l | tr -d ' '; }
run env TMPDIR="$LIBTMP/t" bash "$LIBTMP/three.sh"
assert_rc "a test with three fixtures finishes" 0
assert_eq "three fixtures in one test leave no temp folder" 0 "$(left)"
run env TMPDIR="$LIBTMP/t" bash "$LIBTMP/early.sh"
assert_rc "an early exit keeps its exit status" 3
assert_eq "a test that exits early leaves no temp folder" 0 "$(left)"

# ---- parallel runs ----
make_fixture
cp_script selftest.sh
mkdir -p tests/template
# test_a waits until test_b has started, so it passes only when both run at
# once; the loop bound only matters when they do not (a failure, not a race).
cat > tests/template/test_a.sh <<'TA'
#!/usr/bin/env bash
echo "start a" >> "$SELFTEST_LOG"
touch "$SELFTEST_DIR/a.started"
for _ in $(seq 1 200); do [[ -e "$SELFTEST_DIR/b.started" ]] && break; sleep 0.1; done
[[ -e "$SELFTEST_DIR/b.started" ]] || { echo "  FAIL a never saw b running"; exit 1; }
echo "  ok   a saw b running"
echo "  ok   a line 2"
echo "end a" >> "$SELFTEST_LOG"
TA
cat > tests/template/test_b.sh <<'TB'
#!/usr/bin/env bash
echo "start b" >> "$SELFTEST_LOG"
touch "$SELFTEST_DIR/b.started"
for _ in $(seq 1 200); do [[ -e "$SELFTEST_DIR/a.started" ]] && break; sleep 0.1; done
echo "  ok   b line 1"
echo "  ok   b line 2"
echo "end b" >> "$SELFTEST_LOG"
exit 4
TB
export SELFTEST_DIR="$FIX/sync" SELFTEST_LOG="$FIX/sync/log"
mkdir -p "$SELFTEST_DIR"
run ./scripts/selftest.sh
assert_rc "two files that need each other pass together, the failing one fails the run" 1
assert_contains "a saw b running, so they ran at the same time" "PASS  tests/template/test_a.sh"
assert_contains "the failing file is named with its status" "FAIL  tests/template/test_b.sh (exit 4)"
assert_contains "the summary is unchanged" "selftest: 1 passed, 1 failed, 0 quarantined (2 test files)"
pos_a="$(printf '%s\n' "$OUT" | grep -n 'tests/template/test_a.sh' | head -n 1 | cut -d: -f1)"
pos_b="$(printf '%s\n' "$OUT" | grep -n 'tests/template/test_b.sh' | head -n 1 | cut -d: -f1)"
assert_eq "results come in file order" "yes" "$([[ -n "$pos_a" && -n "$pos_b" && "$pos_a" -lt "$pos_b" ]] && echo yes || echo no)"
assert_contains "a failing file's output follows its FAIL line unbroken" "FAIL  tests/template/test_b.sh (exit 4)
        ok   b line 1
        ok   b line 2"

# --serial and SELFTEST_JOBS=1 run one file at a time: b's whole run precedes
# a's, so a (which needs b) is the one that must find b already started.
rm -f "$SELFTEST_DIR"/*.started "$SELFTEST_LOG"
cat > tests/template/test_a.sh <<'TA'
#!/usr/bin/env bash
echo "start a" >> "$SELFTEST_LOG"
echo "end a" >> "$SELFTEST_LOG"
TA
cat > tests/template/test_b.sh <<'TB'
#!/usr/bin/env bash
echo "start b" >> "$SELFTEST_LOG"
sleep 1
echo "end b" >> "$SELFTEST_LOG"
TB
run ./scripts/selftest.sh --serial
assert_rc "--serial runs and passes" 0
assert_eq "--serial runs one file at a time" "start a,end a,start b,end b" "$(paste -sd, "$SELFTEST_LOG")"
rm -f "$SELFTEST_LOG"
run env SELFTEST_JOBS=1 ./scripts/selftest.sh
assert_rc "SELFTEST_JOBS=1 runs and passes" 0
assert_eq "SELFTEST_JOBS=1 runs one file at a time" "start a,end a,start b,end b" "$(paste -sd, "$SELFTEST_LOG")"
run env SELFTEST_JOBS=0 ./scripts/selftest.sh
assert_rc "SELFTEST_JOBS=0 is refused" 2
assert_contains "the bad job count is named" "SELFTEST_JOBS must be a positive integer"
run ./scripts/selftest.sh --bogus
assert_rc "an unknown argument is refused" 2
assert_contains "the unknown argument is named" "unknown argument --bogus"
run env SELFTEST_JOBS=64 ./scripts/selftest.sh
assert_rc "more jobs than files is fine" 0
assert_contains "summary with more jobs than files" "selftest: 2 passed, 0 failed, 0 quarantined (2 test files)"

# The default job count is the core count capped at 4. nproc is stubbed to 24
# on PATH; files 01-04 each wait until four files are running, then hold their
# slot for a second, so a runner that started more than four at once would
# show a count above 4 in the log. Each file logs how many are running when it
# arrives (and the first four again once all four are in).
rm -f tests/template/test_*.sh
mkdir -p "$SELFTEST_DIR/run" "$FIX/bin"
printf '#!/usr/bin/env bash
echo 24
' > "$FIX/bin/nproc"; chmod +x "$FIX/bin/nproc"
for i in 01 02 03 04 05 06 07 08; do
  cat > "tests/template/test_$i.sh" <<'TN'
#!/usr/bin/env bash
n="$(basename "$0" .sh)"; n="${n#test_}"
running() { find "$SELFTEST_DIR/run" -type f | wc -l | tr -d ' '; }
touch "$SELFTEST_DIR/run/$n"
echo "arrive $(running)" >> "$SELFTEST_LOG"
if [[ "$n" < 05 ]]; then
  for _ in $(seq 1 300); do (( $(running) >= 4 )) && break; sleep 0.1; done
  echo "together $(running)" >> "$SELFTEST_LOG"
  sleep 1
fi
rm -f "$SELFTEST_DIR/run/$n"
TN
  chmod +x "tests/template/test_$i.sh"
done
rm -f "$SELFTEST_LOG"
run env -u SELFTEST_JOBS PATH="$FIX/bin:$PATH" ./scripts/selftest.sh
assert_rc "eight files run with the default job count" 0
assert_contains "all eight files ran" "selftest: 8 passed, 0 failed, 0 quarantined (8 test files)"
assert_eq "with 24 cores the default runs at most four files at once" "4" "$(sed 's/^[a-z]* //' "$SELFTEST_LOG" | sort -n | tail -n 1)"
assert_eq "four files did run at once" "4" "$(grep '^together' "$SELFTEST_LOG" | sed 's/^together //' | sort -n | tail -n 1)"
# The run leaves the fixture's tests/template without the stubs again.
rm -f tests/template/test_*.sh
printf '#!/usr/bin/env bash
exit 0
' > tests/template/test_a.sh
printf '#!/usr/bin/env bash
exit 0
' > tests/template/test_b.sh
chmod +x tests/template/test_a.sh tests/template/test_b.sh

# The run leaves nothing behind in TMPDIR, pass or fail.
mkdir -p "$FIX/tmpcheck"
run env TMPDIR="$FIX/tmpcheck" ./scripts/selftest.sh
assert_rc "a passing run" 0
assert_eq "a passing run leaves nothing in TMPDIR" "" "$(ls -A "$FIX/tmpcheck")"
printf '#!/usr/bin/env bash\nexit 1\n' > tests/template/test_b.sh
run env TMPDIR="$FIX/tmpcheck" ./scripts/selftest.sh
assert_rc "a failing run still fails" 1
assert_eq "a failing run leaves nothing in TMPDIR" "" "$(ls -A "$FIX/tmpcheck")"
chmod +x tests/template/test_*.sh

t_finish
