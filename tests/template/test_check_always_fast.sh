#!/usr/bin/env bash
# check.sh always section, --fast: self-tests only for the changed files, the
# selection reasons, the widening rules, and the notice that it is not the
# full gate.
# Shared fixtures: check_always_lib.sh.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/check_always_lib.sh" || { echo "$0: cannot load check_always_lib.sh; stopped before writing anything" >&2; exit 2; }

sec_fast() {
# ---- --fast: only the self-tests the changed files map to ----
# scripts/selftest.sh here is a stand-in for its contract: "selftest.sh
# FILE..." runs only FILE..., and no argument runs every test file.
make_fixture
cp_script check.sh kernel-hash.sh lessons.sh profiles.sh taskgraph.sh adr.sh tasklint.sh doc-eval.sh
write_agents
./scripts/kernel-hash.sh --update >/dev/null
touch .start-done
write_task
printf '#!/usr/bin/env bash\necho "stack args: $*"\n' > scripts/stack-check.sh
printf '#!/usr/bin/env bash\necho "selftest stub args=[$*]"\nexit "${SELFTEST_RC:-0}"\n' > scripts/selftest.sh
mkdir -p tests/template docs
printf '#!/usr/bin/env bash\n# exercises scripts/alpha.sh\nexit 0\n' > tests/template/test_alpha.sh
printf '#!/usr/bin/env bash\n# exercises scripts/beta.sh\nexit 0\n' > tests/template/test_beta.sh
printf '#!/usr/bin/env bash\necho alpha\n' > scripts/alpha.sh
printf '#!/usr/bin/env bash\necho beta\n' > scripts/beta.sh
printf 'helpers\n' > tests/template/lib.sh
echo "notes" > docs/notes.md
chmod +x scripts/*.sh tests/template/*.sh
commit_fixture
git branch -M main
git checkout -q -b work

run ./scripts/check.sh --fast
assert_rc "--fast with nothing changed passes" 0
assert_contains "--fast says first that it is not the full gate" "check --fast: NOT the full gate"
assert_contains "--fast repeats the notice on exit with the status" "(CI runs the full gate) (exit 0)"
assert_not_contains "--fast names no verified tree (it is not the verify output)" "check.sh: verified tree"
assert_contains "nothing changed: no self-test runs" "no self-test maps to the changed files; none run"
assert_not_contains "nothing changed: the runner is not called" "selftest stub"
assert_contains "--fast is the quick lane for stack-check.sh" "stack args: --quick"

echo "# edit" >> scripts/alpha.sh
run ./scripts/check.sh --fast
assert_contains "an unstaged script change selects the test that names it" "check --fast: self-tests for the changed files: tests/template/test_alpha.sh"
assert_contains "only that test file is passed to selftest.sh" "selftest stub args=[tests/template/test_alpha.sh]"
commit_fixture
run ./scripts/check.sh --fast
assert_contains "a change committed since the merge base with main still selects it" "selftest stub args=[tests/template/test_alpha.sh]"
echo "# edit" >> tests/template/test_beta.sh
run ./scripts/check.sh --fast
assert_contains "a changed test file runs itself, sorted with the rest" "selftest stub args=[tests/template/test_alpha.sh tests/template/test_beta.sh]"
SELFTEST_RC=1 run ./scripts/check.sh --fast
assert_rc "a failing selected self-test fails --fast" 1
assert_contains "the selftest failure is named" "scripts/selftest.sh failed"
assert_contains "the notice is repeated on a failing exit" "(CI runs the full gate) (exit 1)"

printf '#!/usr/bin/env bash\n' > scripts/orphan.sh && chmod +x scripts/orphan.sh
run ./scripts/check.sh --fast
assert_contains "an untracked script no test names runs every self-test" "maps to no single test; running every self-test"
assert_contains "every self-test means selftest.sh without arguments" "selftest stub args=[]"
rm -f scripts/orphan.sh
commit_fixture

echo "more" >> docs/notes.md
CHECK_FAST_BASE=HEAD run ./scripts/check.sh --fast
assert_contains "CHECK_FAST_BASE sets the base; a doc no test names runs none" "no self-test maps to the changed files; none run"
echo "more" >> tests/template/lib.sh
CHECK_FAST_BASE=HEAD run ./scripts/check.sh --fast
assert_contains "a changed test helper no test names runs every self-test" "selftest stub args=[]"
CHECK_FAST_BASE=no-such-ref run ./scripts/check.sh --fast
assert_contains "no diff base runs every self-test" "no diff base (set CHECK_FAST_BASE or fetch main); running every self-test"
commit_fixture

# ---- --fast selection reasons and widening (CHECK_FAST_BASE=HEAD isolates each case) ----
CHECK_FAST_BASE=HEAD run ./scripts/check.sh --fast
assert_not_contains "nothing changed since HEAD: no reason line" "check --fast: select"
echo "# edit" >> tests/template/test_beta.sh
CHECK_FAST_BASE=HEAD run ./scripts/check.sh --fast
assert_contains "a changed test names the reason changed-test" "check --fast: select tests/template/test_beta.sh (changed-test)"
commit_fixture
echo "# edit" >> scripts/alpha.sh
CHECK_FAST_BASE=HEAD run ./scripts/check.sh --fast
assert_contains "a script a test names gets the reason owner:<path>" "(owner:scripts/alpha.sh)"
assert_contains "and selects only that test" "selftest stub args=[tests/template/test_alpha.sh]"
commit_fixture
git rm -q scripts/beta.sh
CHECK_FAST_BASE=HEAD run ./scripts/check.sh --fast
assert_contains "a deleted script widens to every test with its reason" "widen:scripts/beta.sh, deleted or renamed"
assert_contains "a deleted script runs every self-test" "selftest stub args=[]"
git checkout -q HEAD -- scripts/beta.sh
git mv scripts/alpha.sh scripts/alpha2.sh
CHECK_FAST_BASE=HEAD run ./scripts/check.sh --fast
assert_contains "a renamed script widens (the old name is gone)" "widen:scripts/alpha.sh, deleted or renamed"
assert_contains "a renamed script runs every self-test" "selftest stub args=[]"
git mv scripts/alpha2.sh scripts/alpha.sh
# lib.sh: every test names it, so a change to it widens.
echo "# uses lib.sh" >> tests/template/test_alpha.sh
echo "# uses lib.sh" >> tests/template/test_beta.sh
commit_fixture
echo "more" >> tests/template/lib.sh
CHECK_FAST_BASE=HEAD run ./scripts/check.sh --fast
assert_contains "a lib.sh every test names widens, with the reason" "widen:tests/template/lib.sh, every test names it"
assert_contains "a lib.sh change runs every self-test" "selftest stub args=[]"
commit_fixture
# fixtures: a data file one test names selects that test; an unnamed one widens.
mkdir -p tests/template/fixtures
echo "one" > tests/template/fixtures/named.txt
echo "two" > tests/template/fixtures/unnamed.txt
echo "# uses named.txt" >> tests/template/test_alpha.sh
commit_fixture
echo "changed" >> tests/template/fixtures/named.txt
CHECK_FAST_BASE=HEAD run ./scripts/check.sh --fast
assert_contains "a fixture a test names selects that test" "(owner:tests/template/fixtures/named.txt)"
assert_contains "only the test using the fixture runs" "selftest stub args=[tests/template/test_alpha.sh]"
commit_fixture
echo "changed" >> tests/template/fixtures/unnamed.txt
CHECK_FAST_BASE=HEAD run ./scripts/check.sh --fast
assert_contains "a fixture no test names widens, with the reason" "widen:tests/template/fixtures/unnamed.txt, no test names it"
assert_contains "an unnamed fixture runs every self-test" "selftest stub args=[]"
commit_fixture

run ./scripts/check.sh
assert_rc "the full gate passes" 0
assert_contains "the full gate runs every self-test" "selftest stub args=[]"
assert_not_contains "the full gate prints no --fast notice" "check --fast"
run ./scripts/check.sh --bogus
assert_rc "an unknown flag is a usage error" 2
assert_contains "the usage names --fast" "supported: --full-mutation, --quick, --fast"
t_check_exec "--fast"
t_cleanup
}

sec_fast
t_finish
