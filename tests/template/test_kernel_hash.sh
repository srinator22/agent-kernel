#!/usr/bin/env bash
# kernel-hash.sh: verify passes on a pristine kernel, fails after an edit, and
# passes again after --update; edits outside the kernel and CRLF do not drift.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

make_fixture
cp_script kernel-hash.sh
cat > AGENTS.md <<'AG'
# Project

<!-- KERNEL:BEGIN -->
## Kernel
1. Rule one.
2. Rule two.
<!-- KERNEL:END -->

## Project decisions
- Purpose: test
AG

run ./scripts/kernel-hash.sh --verify
assert_rc "verify without .kernel.hash fails" 1
assert_contains "missing hash is named" ".kernel.hash is missing"

run ./scripts/kernel-hash.sh --update
assert_rc "update writes the hash" 0
assert_file "hash file exists" .kernel.hash

run ./scripts/kernel-hash.sh --verify
assert_rc "verify passes on the pristine kernel" 0
assert_contains "verify prints OK" "kernel-hash: OK"

sed -i.bak 's/Rule two\./Rule two, edited./' AGENTS.md && rm -f AGENTS.md.bak
run ./scripts/kernel-hash.sh --verify
assert_rc "verify fails after a kernel edit" 1
assert_contains "drift is announced" "KERNEL DRIFT DETECTED"

run ./scripts/kernel-hash.sh --update
run ./scripts/kernel-hash.sh --verify
assert_rc "verify passes after --update" 0

echo "- Ownership: edited outside the kernel" >> AGENTS.md
run ./scripts/kernel-hash.sh --verify
assert_rc "edits outside the kernel do not drift" 0

sed 's/$/\r/' AGENTS.md > AGENTS.crlf && mv AGENTS.crlf AGENTS.md
run ./scripts/kernel-hash.sh --verify
assert_rc "CRLF line endings do not drift" 0

run ./scripts/kernel-hash.sh
assert_rc "no argument is a usage error" 2

t_finish
