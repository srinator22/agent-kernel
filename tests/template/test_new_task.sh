#!/usr/bin/env bash
# new-task.sh: slug and mode validation, refusal while a task is in progress,
# and the scaffolded TASK.md (Budget section, task-graph Plan table).
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

make_fixture
cp_script new-task.sh
mkdir -p .work
echo "# Task: {{title}}" > .work/TASK.md
cat > AGENTS.md <<'AG'
## Project decisions
- Git workflow: {{branch+gated merge (default) OR direct-to-main}}
AG

run ./scripts/new-task.sh
assert_rc "no slug is a usage error" 2

run ./scripts/new-task.sh "Bad Slug"
assert_rc "slug with a space and capitals is rejected" 2
assert_contains "slug rule is explained" "lowercase letters, digits, and hyphens"

run ./scripts/new-task.sh -bad
assert_rc "slug starting with a hyphen is rejected" 2

run ./scripts/new-task.sh good-slug wizard
assert_rc "unknown mode is rejected" 2

run ./scripts/new-task.sh good-slug
assert_rc "valid slug scaffolds" 0
assert_eq "branch task/good-slug created" "task/good-slug" "$(git symbolic-ref --short HEAD)"
assert_file_has "title line" .work/TASK.md "# Task: good-slug"
assert_file_has "mode line" .work/TASK.md "Mode: standard"
assert_file_has "Budget section" .work/TASK.md "## Budget"
assert_file_has "Budget wall-clock line" .work/TASK.md "- Wall-clock:"
assert_file_has "Plan section" .work/TASK.md "## Plan"
assert_file_has "task-graph header" .work/TASK.md "| node | depends on | owner files | worker tier | status |"
assert_file_has "task-graph example row" .work/TASK.md "| N1 | - | path/one, path/two | standard | todo |"
assert_file_has "Acceptance criteria kept" .work/TASK.md "## Acceptance criteria"
assert_file_has "Progress log kept" .work/TASK.md "## Progress log"
assert_file_has "Review verdict kept" .work/TASK.md "## Review verdict"
assert_file_has "Retro kept" .work/TASK.md "## Retro"
assert_file_lacks "old flat plan step is gone" .work/TASK.md "1. {{step}}"

run ./scripts/new-task.sh another-task
assert_rc "refuses while a task is in progress" 1
assert_contains "refusal names the cause" "already in progress"
assert_file_has "TASK.md left untouched" .work/TASK.md "# Task: good-slug"

t_finish
