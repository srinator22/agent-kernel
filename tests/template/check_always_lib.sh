#!/usr/bin/env bash
# check_always_lib.sh - shared fixtures for the test_check_always*.sh files,
# which test the "always" section of check.sh (style, memory caps, task graph,
# ADR format, selftest when tests/template exists) in project and template mode.
# The six sections were one file that took 908 s of the 3048 s Windows suite
# (2026-11-18); as separate files the shards can spread them. Sourced, never
# run, after lib.sh (each test loads lib.sh itself with the canonical line).

# A started (adopted) project: .start-done exists, or AGENTS.md no longer
# carries the template's "Status: TEMPLATE" line. Real-tree assertions about
# the template's own tree skip there.
t_started() {
  [[ -f "$T_ROOT/.start-done" ]] && return 0
  [[ -f "$T_ROOT/AGENTS.md" ]] && ! grep '^Status: TEMPLATE' "$T_ROOT/AGENTS.md" >/dev/null 2>&1
}

EM="$(printf '\xe2\x80\x94')"
STACK_MSG="scripts/stack-check.sh is missing"

write_task() { mkdir -p .work; printf '# Task: fixture

## Plan
1. a flat plan
' > .work/TASK.md; }
# Marks every tracked script executable in the index: where git does not track
# file modes (core.fileMode false, the Windows default) a fresh add records
# 100644, which check.sh step 4f2 refuses.
commit_fixture() {
  git add -A >/dev/null 2>&1 || return 1
  git ls-files -z -- 'scripts/*.sh' 'tests/template/*.sh' | xargs -0 git update-index --chmod=+x -- >/dev/null 2>&1
  git commit -q -m fixture >/dev/null 2>&1
}

write_agents() {
  cat > AGENTS.md <<'AG'
# Agents

<!-- KERNEL:BEGIN -->
1. Fixture kernel.
<!-- KERNEL:END -->

## Project decisions
- Profiles: software
AG
  write_verify
}
# A started project installs a filled verify skill (software profile SW-15);
# check.sh refuses project mode without one.
write_verify() {
  local d
  for d in .claude .agents; do
    mkdir -p "$d/skills/verify"
    printf -- '---\nname: verify\ndescription: fixture\n---\nRun the fixture.\n' > "$d/skills/verify/SKILL.md"
  done
}
