#!/usr/bin/env bash
# check.sh always section, self-test reuse (step 4g, ADR 0019): a green run
# records its pre-run key, CI and CHECK_SELFTEST=full never reuse, a changed
# input reruns.
# Shared fixtures: check_always_lib.sh.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" || { echo "$0: cannot load lib.sh; stopped before writing anything" >&2; exit 2; }
source "$(dirname "${BASH_SOURCE[0]}")/check_always_lib.sh" || { echo "$0: cannot load check_always_lib.sh; stopped before writing anything" >&2; exit 2; }

sec_reuse() {
# ---- step 4g reuses a green self-test result while the inputs are unchanged ----
# CI=true and CHECK_SELFTEST=full refuse reuse by design; every case below
# sets them itself.
unset CI CHECK_SELFTEST SELFTEST_REUSE_ENV_EXTRA
make_fixture
cp_script check.sh kernel-hash.sh lessons.sh profiles.sh taskgraph.sh adr.sh tasklint.sh doc-eval.sh selftest.sh tree-id.sh selftest-reuse.sh
write_agents
./scripts/kernel-hash.sh --update >/dev/null
touch .start-done
write_task
mkdir -p tests/template
printf 'scripts\ntests/template\nAGENTS.md\n' > tests/template/selftest-inputs.list
printf '#!/usr/bin/env bash\nexit 0\n' > tests/template/test_ok.sh
chmod +x tests/template/test_ok.sh
printf '#!/usr/bin/env bash\necho "stack ran"\n' > scripts/stack-check.sh
chmod +x scripts/stack-check.sh
commit_fixture
RAN="selftest: 1 passed, 0 failed, 0 quarantined (1 test files)"

run ./scripts/check.sh
assert_rc "the first full run passes" 0
assert_contains "the first full run runs the self-tests" "$RAN"
assert_not_contains "the first full run reuses nothing" "inputs unchanged since"
assert_contains "the first full run prints the timing line with a stack time" "check.sh: timing: selftest "
assert_contains "the timing line names the stack and the total" "s, stack "
assert_contains "the timing line ends with the total" "s, total "
run ./scripts/check.sh
assert_rc "the second full run passes" 0
assert_contains "the second full run reuses the result and says so" "selftest-reuse: inputs unchanged since "
assert_contains "the reuse line names the override" "(CHECK_SELFTEST=full forces a run)"
assert_not_contains "the second full run does not run the self-tests" "$RAN"
assert_contains "the timing line says reused" "check.sh: timing: selftest reused, stack "
CHECK_SELFTEST=full run ./scripts/check.sh
assert_rc "CHECK_SELFTEST=full run passes" 0
assert_contains "CHECK_SELFTEST=full runs the self-tests" "$RAN"
assert_not_contains "CHECK_SELFTEST=full prints no reuse line" "inputs unchanged since"
CI=true run ./scripts/check.sh
assert_contains "CI=true runs the self-tests" "$RAN"
assert_not_contains "CI=true prints no reuse line" "inputs unchanged since"
printf '#!/usr/bin/env bash\n# changed\nexit 0\n' > tests/template/test_ok.sh
run ./scripts/check.sh
assert_contains "a changed input runs the self-tests again" "$RAN"
run ./scripts/check.sh
assert_contains "and the result is reused after that" "inputs unchanged since"
printf '#!/usr/bin/env bash\nexit 1\n' > tests/template/test_ok.sh
run ./scripts/check.sh
assert_rc "a failing self-test fails the run" 1
assert_contains "the failure is reported" "scripts/selftest.sh failed"
run ./scripts/check.sh
assert_not_contains "a failed run recorded nothing to reuse" "inputs unchanged since"
printf '#!/usr/bin/env bash\nexit 0\n' > tests/template/test_ok.sh
# An input edited while the suite runs (the detached stop gate lets the agent
# keep working) must not be recorded as tested: the next run tests it.
printf '#!/usr/bin/env bash\n[[ -f edit.mark ]] || { : > edit.mark; printf "%s\\n" "# edited mid-run" >> tests/template/test_ok.sh; }\nexit 0\n' > tests/template/test_edit.sh
chmod +x tests/template/test_edit.sh
RAN2="selftest: 2 passed, 0 failed, 0 quarantined (2 test files)"
run ./scripts/check.sh
assert_contains "a run whose input is edited mid-run still runs the self-tests" "$RAN2"
run ./scripts/check.sh
assert_contains "an input edited mid-run is tested again on the next run" "$RAN2"
assert_not_contains "an input edited mid-run is never reused" "inputs unchanged since"
rm -f tests/template/test_edit.sh edit.mark
printf '#!/usr/bin/env bash\nexit 0\n' > tests/template/test_ok.sh
git rm -q -f --cached scripts/selftest-reuse.sh >/dev/null 2>&1
rm -f scripts/selftest-reuse.sh
run ./scripts/check.sh
assert_contains "without scripts/selftest-reuse.sh (an older sync) the self-tests just run" "$RAN"
t_check_exec "reuse"
t_cleanup
}

sec_reuse
t_finish
