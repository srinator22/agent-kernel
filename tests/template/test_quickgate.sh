#!/usr/bin/env bash
# quickgate.sh: exit 2 when check.sh has no --quick lane; otherwise delegate,
# pass the budget through, and return check.sh's own status.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

make_fixture
cp_script quickgate.sh

run ./scripts/quickgate.sh
assert_rc "exit 2 with no check.sh" 2

cat > scripts/check.sh <<'CK'
#!/usr/bin/env bash
# full gate only; knows no fast flag
echo "full gate"
CK
chmod +x scripts/check.sh
run ./scripts/quickgate.sh
assert_rc "exit 2 when check.sh lacks --quick" 2
assert_contains "says the lane is not wired" "has not wired a quick lane"

cat > scripts/check.sh <<'CK'
#!/usr/bin/env bash
if [[ "${1:-}" == "--quick" ]]; then echo "quick lane budget=${QUICKGATE_BUDGET:-unset} args=$*"; exit "${QUICK_RC:-0}"; fi
echo "full gate"
CK
run ./scripts/quickgate.sh
assert_rc "delegates when --quick exists" 0
assert_contains "default budget is 60" "budget=60"
assert_contains "says the quick lane never skips the always section" "never skips the always section"

QUICKGATE_BUDGET=7 run ./scripts/quickgate.sh
assert_contains "budget is configurable" "budget=7"

QUICK_RC=3 run ./scripts/quickgate.sh
assert_rc "returns check.sh's own status" 3

t_finish
