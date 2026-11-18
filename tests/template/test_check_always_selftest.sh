#!/usr/bin/env bash
# check.sh always section, project mode with tests/template: the always
# section runs the self-tests (step 4g) in a started project too.
# Shared fixtures: check_always_lib.sh.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" || { echo "$0: cannot load lib.sh; stopped before writing anything" >&2; exit 2; }
source "$(dirname "${BASH_SOURCE[0]}")/check_always_lib.sh" || { echo "$0: cannot load check_always_lib.sh; stopped before writing anything" >&2; exit 2; }

sec_selftest() {
# ---- project mode with tests/template present: selftest runs in the always section ----
make_fixture
cp_script check.sh kernel-hash.sh lessons.sh profiles.sh taskgraph.sh adr.sh tasklint.sh doc-eval.sh selftest.sh tree-id.sh
write_agents
./scripts/kernel-hash.sh --update >/dev/null
touch .start-done
write_task
mkdir -p tests/template
printf '#!/usr/bin/env bash\nexit 0\n' > tests/template/test_ok.sh
chmod +x tests/template/test_ok.sh
commit_fixture
run ./scripts/check.sh
assert_contains "selftest runs in project mode when tests/template exists" "selftest: 1 passed, 0 failed, 0 quarantined (1 test files)"
printf '#!/usr/bin/env bash\nexit 1\n' > tests/template/test_ok.sh
chmod +x tests/template/test_ok.sh
commit_fixture
run ./scripts/check.sh --quick
assert_rc "a failing selftest fails project mode, even with --quick" 1
assert_contains "the selftest failure is reported" "scripts/selftest.sh failed"

# ---- 4f2: the executable bit in the git index, project mode, before 4g ----
printf '#!/usr/bin/env bash\nexit 0\n' > tests/template/test_ok.sh
mkdir -p tests/template/fixtures
printf '#!/usr/bin/env bash\nexit 0\n' > tests/template/fixtures/check.sh
printf '#!/usr/bin/env bash\nexit 0\n' > tests/template/fixtures/helper.sh
printf '#!/usr/bin/env bash\nexit 0\n' > scripts/tool.sh
chmod +x scripts/tool.sh tests/template/fixtures/helper.sh
commit_fixture
run ./scripts/check.sh --quick
assert_not_contains "every script executable in the index passes the index check" "lost the executable bit"
for p in tests/template/test_ok.sh tests/template/fixtures/helper.sh scripts/tool.sh tests/template/fixtures/check.sh; do
  git update-index --chmod=-x -- "$p"
done
git commit -q -m "scripts without the executable bit" >/dev/null 2>&1
run ./scripts/check.sh --quick
assert_rc "a script without the executable bit in the index fails project mode" 1
assert_contains "the missing bits are named with the fix" "scripts lost the executable bit in the git index (git update-index --chmod=+x <file>): scripts/tool.sh tests/template/fixtures/helper.sh tests/template/test_ok.sh"
assert_eq "the index check reports before the self-tests run" "" "$(o="${OUT%%scripts lost the executable bit*}"; [[ "$o" == *"selftest: "* ]] && echo "selftest ran first")"
assert_contains "the self-tests still run after the index failure" "selftest: 1 passed"
commit_fixture
t_check_exec "project mode with tests/template"
t_cleanup
}

sec_selftest
t_finish
