#!/usr/bin/env bash
# scripts/selftest.sh: tests/quarantine.list (docs/procedures/tests.md step 5)
# skips each listed tests/template file and names it on every run; a listed
# file that does not exist fails the run; an unlisted failing test still
# fails; n/a lines of passing tests show in the normal output; the summary
# line counts passed, failed and quarantined files; the lib.sh fixtures the
# tests build leave no temp folders behind.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

make_fixture
cp_script selftest.sh
mkdir -p tests/template
printf '#!/usr/bin/env bash\necho "  ok   a passes"\nexit 0\n' > tests/template/test_a.sh
printf '#!/usr/bin/env bash\necho "  FAIL b fails"\nexit 1\n' > tests/template/test_b.sh
printf '#!/usr/bin/env bash\necho "  ok   c passes"\necho "  n/a  case x: not here; covered by gate y"\nexit 0\n' > tests/template/test_c.sh

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
printf '#!/usr/bin/env bash\nexit 3\n' > tests/template/test_d.sh
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

t_finish
