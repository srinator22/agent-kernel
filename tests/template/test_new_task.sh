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
assert_file_has "Assumptions section" .work/TASK.md "## Assumptions"
assert_file_has "assumption placeholder starts open" .work/TASK.md "- [open] {{assumption}}"
assert_file_has "Plan verdict section" .work/TASK.md "## Plan verdict"
assert_contains "next steps name the autopilot plan review" "Plan verdict section"
assert_file_has "Acceptance criteria kept" .work/TASK.md "## Acceptance criteria"
assert_file_has "Progress log kept" .work/TASK.md "## Progress log"
assert_file_has "Review verdict kept" .work/TASK.md "## Review verdict"
assert_file_has "Retro kept" .work/TASK.md "## Retro"
assert_file_lacks "old flat plan step is gone" .work/TASK.md "1. {{step}}"
cp_script tasklint.sh
run ./scripts/tasklint.sh check
assert_rc "a fresh scaffold passes tasklint check" 0
run ./scripts/tasklint.sh ship
assert_rc "a fresh scaffold is not ship-ready: its assumption is still open" 1
assert_contains "the open assumption is named" "open assumption"

run ./scripts/new-task.sh another-task
assert_rc "refuses while a task is in progress" 1
assert_contains "refusal names the cause" "already in progress"
assert_file_has "TASK.md left untouched" .work/TASK.md "# Task: good-slug"

# The recorded workflow (start.md item 4): new-task.sh stays on the current
# branch only when the "- Git workflow:" value starts with direct-to-main
# followed by end of value, or by optional spaces then ; . : , or (, or by
# " - ". Anything else, a negation included, reads as gated (the safe side).
git checkout -q -b workflow-base
# wf_case NAME VALUE EXPECT: EXPECT is "stay" or "branch".
n=0
wf_case() {
  n=$((n + 1))
  git checkout -q workflow-base
  printf '## Project decisions\n- Git workflow: %s\n' "$2" > AGENTS.md
  echo "# Task: {{title}}" > .work/TASK.md
  git add -A >/dev/null 2>&1 && git commit -q -m "wf $n" >/dev/null 2>&1
  run ./scripts/new-task.sh "wf-$n"
  assert_rc "$1: scaffolds" 0
  if [[ "$3" == stay ]]; then
    assert_eq "$1: stays on the current branch" "workflow-base" "$(git symbolic-ref --short HEAD)"
    assert_contains "$1: says it read direct-to-main" "recorded workflow is direct-to-main"
  else
    assert_eq "$1: creates task/wf-$n" "task/wf-$n" "$(git symbolic-ref --short HEAD)"
    assert_contains "$1: says it read branch + gated merge" "recorded workflow is branch + gated merge"
  fi
  git checkout -q -f workflow-base
}
wf_case "plain with a comma" "direct-to-main, no pull requests (owner standing choice, 2026-10-13)." stay
wf_case "alone" "direct-to-main" stay
wf_case "backticked" '`direct-to-main` (explicit standing choice)' stay
wf_case "bold" "**direct-to-main**; push after the full gate" stay
wf_case "with a parenthesis after a space" "direct-to-main (solo)" stay
wf_case "with a spaced hyphen" "direct-to-main - every push gated locally" stay
wf_case "placeholder" "{{branch+gated merge (default) OR direct-to-main, recorded as an explicit choice}}" branch
wf_case "Branch first, negation later" "Branch plus pull request with gated merge to main; direct-to-main is not a standing choice." branch
wf_case "branch lowercase" "branch + gated merge" branch
wf_case "negated value starting with the token" "direct-to-main is not allowed; use branches" branch
assert_contains "a value starting with the token that fails the rule warns" "WARNING: the - Git workflow: value starts with direct-to-main but reads as branch + gated merge"
wf_case "token followed by a word" "direct-to-main on master" branch
assert_contains "the warning names the accepted form" "direct-to-main, <details>"

t_finish
