#!/usr/bin/env bash
# scripts/selftest.sh: tests/quarantine.list (docs/procedures/tests.md step 5)
# skips each listed tests/template file and names it on every run; a listed
# file that does not exist fails the run; an unlisted failing test still
# fails; n/a lines of passing tests show in the normal output; the summary
# line counts passed, failed and quarantined files; the lib.sh fixtures the
# tests build leave no temp folders behind. Parallel runs: files run
# SELFTEST_JOBS at a time (default the core count capped at 4, --serial one),
# a finished slot is refilled at once (wait -n and the SELFTEST_POLL=1 poll),
# results print in file order; INT and TERM stop every running file; test
# files named on the command line run alone; T_EXEC_CHECK=1 and the one
# executable-bit probe reach every file. Cases that need two files at once
# wait on marker files with a bounded loop, never on a fixed delay. Timing:
# the slowest-files and wall lines, SELFTEST_TIMES. --shard K/N: greedy deal by
# weight, disjoint and complete, median for a missing weight, usage errors.
# --write-weights: format, and the output feeds --shard.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" || { echo "$0: cannot load lib.sh; stopped before writing anything" >&2; exit 2; }

unset SELFTEST_TIMES # an outer run's times file must not be overwritten by these inner runs
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
# Two jobs pinned: with SELFTEST_JOBS=1 or one core, a would never see b run.
run env SELFTEST_JOBS=2 ./scripts/selftest.sh
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

# --serial and SELFTEST_JOBS=1 run one file at a time. test_a waits a bounded
# time for b's start marker and logs "a saw b" when b ran meanwhile or "a alone"
# when it did not, so the same two files tell a serial run (a finishes before b
# starts) from a parallel one. The wait ends on the marker, not on a fixed delay.
rm -f "$SELFTEST_DIR/a.started" "$SELFTEST_DIR/b.started" "$SELFTEST_LOG"
cat > tests/template/test_a.sh <<'TA'
#!/usr/bin/env bash
echo "start a" >> "$SELFTEST_LOG"
touch "$SELFTEST_DIR/a.started"
for _ in $(seq 1 40); do [[ -e "$SELFTEST_DIR/b.started" ]] && break; sleep 0.1; done
if [[ -e "$SELFTEST_DIR/b.started" ]]; then echo "a saw b" >> "$SELFTEST_LOG"; else echo "a alone" >> "$SELFTEST_LOG"; fi
echo "end a" >> "$SELFTEST_LOG"
TA
cat > tests/template/test_b.sh <<'TB'
#!/usr/bin/env bash
echo "start b" >> "$SELFTEST_LOG"
touch "$SELFTEST_DIR/b.started"
echo "end b" >> "$SELFTEST_LOG"
TB
run ./scripts/selftest.sh --serial
assert_rc "--serial runs and passes" 0
assert_eq "--serial runs one file at a time" "start a,a alone,end a,start b,end b" "$(paste -sd, "$SELFTEST_LOG")"
rm -f "$SELFTEST_DIR/a.started" "$SELFTEST_DIR/b.started" "$SELFTEST_LOG"
run env SELFTEST_JOBS=1 ./scripts/selftest.sh
assert_rc "SELFTEST_JOBS=1 runs and passes" 0
assert_eq "SELFTEST_JOBS=1 runs one file at a time" "start a,a alone,end a,start b,end b" "$(paste -sd, "$SELFTEST_LOG")"
rm -f "$SELFTEST_DIR/a.started" "$SELFTEST_DIR/b.started" "$SELFTEST_LOG"
run env SELFTEST_JOBS=2 ./scripts/selftest.sh
assert_rc "SELFTEST_JOBS=2 runs and passes" 0
assert_eq "SELFTEST_JOBS=2 runs the same files at once" "a saw b" "$(grep '^a ' "$SELFTEST_LOG")"
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

# ---- test files named on the command line ----
make_fixture
cp_script selftest.sh
mkdir -p tests/template other sub
printf '#!/usr/bin/env bash\necho "  ok   a passes"\nexit 0\n' > tests/template/test_a.sh
printf '#!/usr/bin/env bash\necho "  FAIL b fails"\nexit 1\n' > tests/template/test_b.sh
printf '#!/usr/bin/env bash\necho "  ok   c passes"\nexit 0\n' > tests/template/test_c.sh
printf '#!/usr/bin/env bash\nexit 0\n' > other/test_a.sh
chmod +x tests/template/test_*.sh other/test_a.sh
run ./scripts/selftest.sh tests/template/test_a.sh
assert_rc "one named file runs alone and passes" 0
assert_contains "only the named file is counted" "selftest: 1 passed, 0 failed, 0 quarantined (1 test files)"
assert_not_contains "an unnamed failing file does not run" "test_b.sh"
run ./scripts/selftest.sh "$FIX/tests/template/test_c.sh" ./tests/template/test_b.sh tests/template/test_c.sh
assert_rc "a named failing file fails the run" 1
assert_contains "absolute, ./ and repeated names: each file runs once" "selftest: 1 passed, 1 failed, 0 quarantined (2 test files)"
pos_b="$(printf '%s\n' "$OUT" | grep -n 'tests/template/test_b.sh' | head -n 1 | cut -d: -f1)"
pos_c="$(printf '%s\n' "$OUT" | grep -n 'tests/template/test_c.sh' | head -n 1 | cut -d: -f1)"
assert_eq "named files report in file order, not argument order" "yes" "$([[ -n "$pos_b" && -n "$pos_c" && "$pos_b" -lt "$pos_c" ]] && echo yes || echo no)"
assert_not_contains "the unnamed file does not run" "test_a.sh"
OUT="$(cd sub && ../scripts/selftest.sh -v ../tests/template/test_a.sh 2>&1)"; RC=$?
assert_rc "a path relative to the caller's folder is found" 0
assert_contains "-v works with named files" "a passes"
run env SELFTEST_JOBS=1 ./scripts/selftest.sh tests/template/test_a.sh tests/template/test_c.sh
assert_contains "named files run under SELFTEST_JOBS=1" "selftest: 2 passed, 0 failed, 0 quarantined (2 test files)"
run ./scripts/selftest.sh tests/template/test_zz.sh
assert_rc "a named file that does not exist is refused" 2
assert_contains "the missing file is named" "no such test file: tests/template/test_zz.sh"
run ./scripts/selftest.sh scripts/selftest.sh
assert_rc "a named file that is not a test file is refused" 2
assert_contains "the non-test file is named" "scripts/selftest.sh is not a tests/template/test_*.sh file"
run ./scripts/selftest.sh other/test_a.sh
assert_rc "a test_*.sh outside tests/template is refused" 2
assert_contains "the outside file is named" "other/test_a.sh is not a tests/template/test_*.sh file"
run ./scripts/selftest.sh tests/template
assert_rc "a folder is refused" 2
echo 'tests/template/test_b.sh # owner: fix-b date: 2026-11-08' > tests/quarantine.list
run ./scripts/selftest.sh tests/template/test_b.sh
assert_rc "a named quarantined file is skipped, not run" 0
assert_contains "it is named as quarantined" "selftest: 0 passed, 0 failed, 1 quarantined (1 test files)"
rm -f tests/quarantine.list

# ---- a finished slot is refilled at once ----
# Two slots, three files: a holds its slot until c has started, b ends at
# once. c can start only in b's slot while a still runs, so a passes only when
# a slot is refilled as soon as any file finishes, not when the oldest does.
# The bounded wait in a only matters when c never starts (a failure).
make_fixture
cp_script selftest.sh
mkdir -p tests/template
cat > tests/template/test_a.sh <<'TA'
#!/usr/bin/env bash
for _ in $(seq 1 200); do [[ -e "$SELFTEST_DIR/c.started" ]] && break; sleep 0.1; done
[[ -e "$SELFTEST_DIR/c.started" ]] || { echo "  FAIL a never saw c start"; exit 1; }
echo "  ok   a saw c start"
TA
printf '#!/usr/bin/env bash\necho "  ok   b ends at once"\n' > tests/template/test_b.sh
printf '#!/usr/bin/env bash\ntouch "$SELFTEST_DIR/c.started"\necho "  ok   c started"\n' > tests/template/test_c.sh
chmod +x tests/template/test_*.sh
export SELFTEST_DIR="$FIX/sync"
for mode in wait-n poll; do
  rm -rf "$SELFTEST_DIR"; mkdir -p "$SELFTEST_DIR"
  if [[ "$mode" == poll ]]; then run env SELFTEST_JOBS=2 SELFTEST_POLL=1 ./scripts/selftest.sh
  else run env -u SELFTEST_POLL SELFTEST_JOBS=2 ./scripts/selftest.sh; fi
  assert_rc "$mode: three files in two slots pass" 0
  assert_contains "$mode: c started in b's slot while a still ran" "PASS  tests/template/test_a.sh"
  assert_contains "$mode: summary" "selftest: 3 passed, 0 failed, 0 quarantined (3 test files)"
  assert_eq "$mode: results stay in file order" "a b c" "$(printf '%s\n' "$OUT" | sed -n 's/^PASS  tests\/template\/test_\(.\)\.sh$/\1/p' | paste -sd' ' -)"
done

# ---- INT and TERM stop every running file ----
# Two long files record their pid, and an EXIT trap marks that they cleaned
# up. The run is stopped once both have started; nothing may still run, both
# must have cleaned up well before their bounded wait ends, and TMPDIR is left
# empty. A file that ran its full wait leaves a .late marker.
make_fixture
cp_script selftest.sh
mkdir -p tests/template
for x in a b; do
  cat > "tests/template/test_$x.sh" <<'TL'
#!/usr/bin/env bash
n="$(basename "$0" .sh)"
trap 'touch "$SELFTEST_DIR/$n.cleaned"' EXIT
echo "$$" > "$SELFTEST_DIR/$n.pid"
for _ in $(seq 1 300); do sleep 0.1; done
touch "$SELFTEST_DIR/$n.late"
TL
done
chmod +x tests/template/test_*.sh
# stop_case SIGNAL EXPECTED-EXIT [ENV-OPTION...]
stop_case() {
  local sig="$1" want="$2" sp x alive=""
  shift 2
  rm -rf "$SELFTEST_DIR" "$FIX/tmpstop"; mkdir -p "$SELFTEST_DIR" "$FIX/tmpstop"
  env "$@" TMPDIR="$FIX/tmpstop" SELFTEST_JOBS=2 ./scripts/selftest.sh > "$FIX/stop.out" 2>&1 &
  sp=$!
  for _ in $(seq 1 200); do [[ -s "$SELFTEST_DIR/test_a.pid" && -s "$SELFTEST_DIR/test_b.pid" ]] && break; sleep 0.1; done
  kill "-$sig" "$sp"
  wait "$sp"; RC=$?
  OUT="$(cat "$FIX/stop.out")"
  assert_rc "$sig: the run exits with the signal's status" "$want"
  assert_contains "$sig: the stop is named" "selftest: stopped by SIG$sig"
  for x in a b; do
    if [[ -s "$SELFTEST_DIR/test_$x.pid" ]] && kill -0 "$(cat "$SELFTEST_DIR/test_$x.pid")" 2>/dev/null; then alive="$alive test_$x"; fi
  done
  assert_eq "$sig: no test file still runs" "" "${alive# }"
  assert_file "$sig: test_a was stopped and cleaned up" "$SELFTEST_DIR/test_a.cleaned"
  assert_file "$sig: test_b was stopped and cleaned up" "$SELFTEST_DIR/test_b.cleaned"
  assert_no_file "$sig: test_a did not run to its end" "$SELFTEST_DIR/test_a.late"
  assert_eq "$sig: nothing is left in TMPDIR" "" "$(ls -A "$FIX/tmpstop")"
}
stop_case TERM 143
# A background job of a shell without job control starts with INT ignored,
# and bash cannot trap a signal ignored at entry; env --default-signal (GNU
# coreutils 8.31+) restores it, as a terminal's Ctrl-C finds it.
if env --default-signal=INT true 2>/dev/null; then
  stop_case INT 130 --default-signal=INT
else
  t_na "INT stops every running file: env --default-signal is missing here; the TERM case covers the same stop path"
fi

# ---- the executable-bit wiring ----
# selftest.sh exports T_EXEC_CHECK=1 to every file, probes the bits once
# through lib.sh and exports the result; where chmod cannot set them the run
# prints one n/a line, not one per file.
make_fixture
cp_script selftest.sh
mkdir -p tests/template
cp "$T_ROOT/tests/template/lib.sh" tests/template/lib.sh
for x in e1 e2; do
  printf '#!/usr/bin/env bash\nsource "$(dirname "${BASH_SOURCE[0]}")/lib.sh" || exit 2\necho "  ok   check=${T_EXEC_CHECK:-unset} bits=${T_EXEC_BITS:-unset}"\nmake_fixture\nt_finish\n' > "tests/template/test_$x.sh"
done
chmod +x tests/template/test_*.sh
if t_exec_bits_work; then bits=1; na=0; else bits=0; na=1; fi
run env -u T_EXEC_CHECK -u T_EXEC_BITS -u T_EXEC_NA ./scripts/selftest.sh -v
assert_rc "two lib.sh tests pass" 0
assert_eq "every file sees T_EXEC_CHECK=1 and the probed bits" "2" "$(printf '%s\n' "$OUT" | grep -c "ok   check=1 bits=$bits")"
assert_eq "the executable-bit n/a line appears once per run where it applies" "$na" "$(printf '%s\n' "$OUT" | grep -c 'n/a .*executable bits')"

# ---- timing, shards and the weights generator ----
# A fake weights file and eight fake passing tests (weights 8..1, test_a..h).
make_fixture
cp_script selftest.sh
mkdir -p tests/template
for x in a b c d e f g h; do printf '#!/usr/bin/env bash\necho "  ok   %s"\n' "$x" > "tests/template/test_$x.sh"; done
chmod +x tests/template/test_*.sh
{ echo '# fake weights'; echo; i=8; for x in a b c d e f g h; do echo "$i tests/template/test_$x.sh"; i=$((i - 1)); done; } > tests/template/selftest-weights.txt
ALL_FILES="$(printf 'tests/template/test_%s.sh\n' a b c d e f g h | LC_ALL=C sort | tr '\n' ' ')"
# files_of: the files a shard run printed, sorted, space-separated.
files_of() { printf '%s\n' "$OUT" | sed -n 's/^selftest: shard [0-9]*\/[0-9]* file //p' | LC_ALL=C sort | tr '\n' ' '; }

# Timing summary and the SELFTEST_TIMES file (one line per file that ran).
printf 'tests/template/test_h.sh # owner: t date: 2026-11-17\n' > tests/quarantine.list
run env SELFTEST_TIMES="$FIX/times.out" ./scripts/selftest.sh
assert_rc "a timed run passes" 0
assert_contains "the slowest-files line is printed" "selftest: slowest: tests/template/test_"
assert_contains "the wall-clock line is printed" "selftest: wall "
assert_eq "the slowest line names five files" "5" "$(printf '%s\n' "$OUT" | grep '^selftest: slowest:' | grep -o 'test_[a-z]*\.sh [0-9][0-9]*s' | wc -l | tr -d ' ')"
assert_file "SELFTEST_TIMES writes its file" "$FIX/times.out"
assert_eq "the times file has one line per file that ran (quarantined excluded)" "7" "$(grep -c '' "$FIX/times.out")"
assert_eq "every times line is '<seconds> <test path>'" "7" "$(grep -cE '^[0-9]+ tests/template/test_[a-g]\.sh$' "$FIX/times.out")"
echo "stale" > "$FIX/times.out"
run env SELFTEST_TIMES="$FIX/times.out" ./scripts/selftest.sh tests/template/test_a.sh
assert_eq "SELFTEST_TIMES is overwritten, not appended" "1" "$(grep -c '' "$FIX/times.out")"
rm -f tests/quarantine.list
# SELFTEST_TIMES is read once and removed from the environment, so a test file
# (and a selftest.sh run nested in a fixture) never inherits and overwrites it.
printf '#!/usr/bin/env bash\necho "${SELFTEST_TIMES-unset}" > "%s/env.out"\n' "$FIX" > tests/template/test_i.sh
chmod +x tests/template/test_i.sh
run env SELFTEST_TIMES="$FIX/times2.out" ./scripts/selftest.sh tests/template/test_i.sh
assert_rc "the env probe test passes" 0
assert_eq "a test file does not see SELFTEST_TIMES" "unset" "$(cat "$FIX/env.out")"
assert_eq "the run still wrote its times file" "1" "$(grep -c 'test_i.sh' "$FIX/times2.out")"
rm -f tests/template/test_i.sh

# Shards: union equals the full set and shards are disjoint, for several N.
for n in 1 2 3 5; do
  union=""; cnt=0
  for (( k = 1; k <= n; k++ )); do
    run ./scripts/selftest.sh --shard "$k/$n"
    assert_rc "shard $k/$n passes" 0
    union="$union$(files_of)"
    cnt=$((cnt + $(printf '%s\n' "$OUT" | grep -c '^selftest: shard [0-9]*/[0-9]* file ')))
  done
  assert_eq "N=$n: the shards together hold every file" "$ALL_FILES" "$(printf '%s' "$union" | tr ' ' '\n' | sed '/^$/d' | LC_ALL=C sort | tr '\n' ' ')"
  assert_eq "N=$n: the shards deal 8 files in all" "8" "$cnt"
  assert_eq "N=$n: no file appears in two shards" "" "$(printf '%s' "$union" | tr ' ' '\n' | sed '/^$/d' | LC_ALL=C sort | uniq -d)"
done
# The greedy deal itself (hand-computed): a8->1 b7->2 c6->2 d5->1 e4->1 f3->2 g2->2 h1->1.
run ./scripts/selftest.sh --shard 1/2
assert_eq "shard 1/2 holds a, d, e, h" "tests/template/test_a.sh tests/template/test_d.sh tests/template/test_e.sh tests/template/test_h.sh " "$(files_of)"
assert_contains "the shard run names its estimate" "selftest: shard 1/2: 4 files, estimated 18.00s"
assert_contains "the summary counts only the shard's files" "(4 test files)"
first="$OUT"
run ./scripts/selftest.sh --shard 1/2
assert_eq "the same shard prints the same files twice" "$(printf '%s\n' "$first" | grep '^selftest: shard')" "$(printf '%s\n' "$OUT" | grep '^selftest: shard')"
run ./scripts/selftest.sh --shard=2/2
assert_eq "--shard=K/N is accepted; shard 2/2 holds b, c, f, g" "tests/template/test_b.sh tests/template/test_c.sh tests/template/test_f.sh tests/template/test_g.sh " "$(files_of)"
# More shards than files: the extra shards are empty and pass.
run ./scripts/selftest.sh --shard 9/9
assert_rc "an empty shard exits 0" 0
assert_contains "an empty shard says so" "shard 9/9 has no files"
# A quarantined file is in no shard.
printf 'tests/template/test_a.sh # owner: t date: 2026-11-17\n' > tests/quarantine.list
run ./scripts/selftest.sh --shard 1/2
assert_not_contains "a quarantined file is dealt to no shard" "file tests/template/test_a.sh"
rm -f tests/quarantine.list

# A file without a weight gets the median of the known ones (weights 10, 2, 6
# for a, b, c; d unknown -> 6, so c and d tie by path: a->1, c->2, d->2, b->1).
{ echo '10 tests/template/test_a.sh'; echo '2 tests/template/test_b.sh'; echo '6 tests/template/test_c.sh'; } > tests/template/selftest-weights.txt
rm -f tests/template/test_[e-h].sh
run ./scripts/selftest.sh --shard 1/2
assert_eq "median weight for the unweighted file: shard 1 holds a, b" "tests/template/test_a.sh tests/template/test_b.sh " "$(files_of)"
assert_contains "the median counts in the estimate (10 + 2)" "estimated 12.00s"
run ./scripts/selftest.sh --shard 2/2
assert_eq "median weight for the unweighted file: shard 2 holds c, d" "tests/template/test_c.sh tests/template/test_d.sh " "$(files_of)"
# No weights file: every file weighs 1 and the deal still covers all of them.
rm -f tests/template/selftest-weights.txt
run ./scripts/selftest.sh --shard 1/2
assert_rc "no weights file is not an error" 0
assert_contains "no weights: 4 files split 2 and 2" "shard 1/2: 2 files, estimated 2.00s"

# A weights line naming a missing test, or a malformed one, warns once and the run goes on.
{ echo '10 tests/template/test_a.sh'; echo '2 tests/template/test_b.sh'; echo '6 tests/template/test_c.sh'; echo '5 tests/template/test_gone.sh'; echo 'garbage'; } > tests/template/selftest-weights.txt
run ./scripts/selftest.sh --shard 1/2
assert_rc "a weights line naming a missing test does not fail the run" 0
assert_eq "the missing test is warned about once" "1" "$(printf '%s\n' "$OUT" | grep -c 'warning:.*test_gone.sh')"
assert_eq "the malformed line is warned about once" "1" "$(printf '%s\n' "$OUT" | grep -c 'warning:.*malformed.*garbage')"
assert_eq "the deal ignores the stale line" "tests/template/test_a.sh tests/template/test_b.sh " "$(files_of)"

# Usage errors.
run ./scripts/selftest.sh --shard 1/2 tests/template/test_a.sh
assert_rc "--shard with a TEST_FILE is a usage error" 2
assert_contains "the conflict is named" "--shard cannot be combined with TEST_FILE"
for bad in 0/3 4/3 x 3 1/0 1/2/3 -1/2 1/; do
  run ./scripts/selftest.sh --shard "$bad"
  assert_rc "--shard $bad is a usage error" 2
done
run ./scripts/selftest.sh --shard
assert_rc "--shard without a value is a usage error" 2

# --write-weights: format, and the output feeds --shard.
printf '%s\n' '# a times file' '3 tests/template/test_c.sh' '12 tests/template/test_a.sh' '' '7.5 tests/template/test_b.sh' '1 tests/template/test_d.sh' > "$FIX/times.in"
run ./scripts/selftest.sh --write-weights "$FIX/times.in"
assert_rc "--write-weights succeeds" 0
assert_contains "it reports what it wrote" "selftest: wrote tests/template/selftest-weights.txt from"
assert_eq "the generated file starts with the generated-by header" "# selftest-weights.txt - GENERATED by scripts/selftest.sh --write-weights" "$(sed -n 1p tests/template/selftest-weights.txt | cut -c1-73)"
assert_file_has "the header says never hand-edited" tests/template/selftest-weights.txt "Never hand-edited"
assert_eq "the data lines are sorted by path" "12 tests/template/test_a.sh,7.5 tests/template/test_b.sh,3 tests/template/test_c.sh,1 tests/template/test_d.sh" "$(grep -v '^#' tests/template/selftest-weights.txt | tr '\n' ',' | sed 's/,$//')"
run ./scripts/selftest.sh --shard 1/2
assert_eq "the generated weights round-trip into --shard (a12->1, b7.5->2, c3->2, d1->2)" "tests/template/test_a.sh " "$(files_of)"
assert_contains "the estimate comes from the generated weights" "estimated 12.00s"
run ./scripts/selftest.sh --write-weights "$FIX/nope.in"
assert_rc "--write-weights with a missing times file is a usage error" 2
printf 'tests/template/test_a.sh fast\n' > "$FIX/bad.in"
run ./scripts/selftest.sh --write-weights "$FIX/bad.in"
assert_rc "--write-weights with a malformed times line is a usage error" 2
run ./scripts/selftest.sh --write-weights "$FIX/times.in" --shard 1/2
assert_rc "--write-weights with --shard is a usage error" 2
run ./scripts/selftest.sh --write-weights
assert_rc "--write-weights without a file is a usage error" 2

t_finish
