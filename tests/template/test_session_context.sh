#!/usr/bin/env bash
# session-context.sh: the mode line, the rule-7 reminder, the git priming
# block (branch, capped status, last 10 commits), the in-progress task, and
# graceful output outside a git repository.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

make_fixture
cp_script session-context.sh
git add scripts && git commit -q -m "chore: scripts"
git checkout -q -b task/demo
for i in $(seq 1 12); do echo "$i" > "f$i.txt"; git add "f$i.txt"; git commit -q -m "feat: commit number $i"; done

run bash scripts/session-context.sh
assert_rc "exits 0" 0
assert_contains "template mode line" "TEMPLATE MODE"
assert_contains "rule 7 reminder" "Kernel rule 7"
assert_contains "branch line" "[session-context] Branch: task/demo"
assert_contains "clean tree is said so" "Working tree: clean"
assert_contains "last commits header" "Last commits"
assert_contains "the newest commit is listed" "feat: commit number 12"
assert_contains "the tenth newest commit is listed" "feat: commit number 3"
assert_not_contains "only ten commits are listed" "feat: commit number 2"

echo changed > f1.txt
for i in $(seq 1 25); do echo x > "new$i.txt"; done
run bash scripts/session-context.sh
assert_contains "changed-file count" "Working tree (26 changed or untracked):"
assert_contains "a modified file is listed" " M f1.txt"
assert_contains "the status list is capped" "... 6 more (git status --short)"

mkdir -p .work
echo "# Task: {{title}}" > .work/TASK.md
run bash scripts/session-context.sh
assert_not_contains "a pristine TASK.md is not printed" "In-progress task state"
printf '# Task: demo\nMode: standard\n' > .work/TASK.md
run bash scripts/session-context.sh
assert_contains "a live TASK.md is printed" "In-progress task state"
assert_contains "its content follows" "# Task: demo"
touch .start-done
run bash scripts/session-context.sh
assert_contains "project mode line after start" "Project mode (start has run)"
t_cleanup

# Outside a git repository: no git block, still exit 0.
FIX="$(mktemp -d "${TMPDIR:-/tmp}/template-selftest.XXXXXX")"
mkdir -p "$FIX/scripts" && cp "$T_ROOT/scripts/session-context.sh" "$FIX/scripts/"
run env GIT_CEILING_DIRECTORIES="$FIX" bash "$FIX/scripts/session-context.sh"
assert_rc "outside git it still exits 0" 0
assert_contains "outside git the reminder still prints" "Kernel rule 7"
assert_not_contains "outside git there is no branch line" "Branch:"

t_finish
