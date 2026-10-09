#!/usr/bin/env bash
# taskgraph.sh: unknown dependencies, overlapping owner files between nodes of
# one wave, cycles, tier and status values, ready, waves, set, and the legacy
# flat plan.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

make_fixture
cp_script taskgraph.sh
mkdir -p .work

# write_plan ROW...: a TASK.md whose Plan is the task-graph table.
write_plan() {
  {
    echo "# Task: fixture"
    echo
    echo "## Plan"
    echo "| node | depends on | owner files | worker tier | status |"
    echo "|---|---|---|---|---|"
    local r
    for r in "$@"; do echo "$r"; done
    echo
    echo "## Progress log"
  } > .work/TASK.md
}

# Three nodes: A and B independent, C needs both.
write_plan \
  "| A first | - | src/a/**, docs/a.md | standard | todo |" \
  "| B second | - | src/b/** | cheap | todo |" \
  "| C third | A, B | src/c/** | advisor | todo |"
run ./scripts/taskgraph.sh check
assert_rc "valid three-node graph passes" 0
assert_contains "reports nodes and waves" "3 nodes, 2 waves"
run ./scripts/taskgraph.sh waves
assert_rc "waves succeeds" 0
assert_contains "wave 1 holds A and B" "wave 1: A B"
assert_contains "wave 2 holds C" "wave 2: C"
run ./scripts/taskgraph.sh ready
assert_contains "A is ready" "A first"
assert_contains "B is ready" "B second"
assert_not_contains "C waits for its dependencies" "C third"
run ./scripts/taskgraph.sh set A done
assert_rc "set changes a status" 0
assert_file_has "status cell rewritten" .work/TASK.md "| A first | - | src/a/**, docs/a.md | standard | done |"
assert_file_has "other rows untouched" .work/TASK.md "| B second | - | src/b/** | cheap | todo |"
run ./scripts/taskgraph.sh ready
assert_not_contains "C still waits for B" "C third"
./scripts/taskgraph.sh set B done >/dev/null 2>&1
run ./scripts/taskgraph.sh ready
assert_contains "C is ready once A and B are done" "C third"
assert_not_contains "done nodes are not ready" "A first"
run ./scripts/taskgraph.sh set C wip
assert_rc "set rejects an unknown status" 2
run ./scripts/taskgraph.sh set Z done
assert_rc "set rejects an unknown node" 1
assert_contains "names the node" "node Z not found"

# Unknown dependency.
write_plan \
  "| A | Q | src/a | standard | todo |"
run ./scripts/taskgraph.sh check
assert_rc "unknown dependency fails" 1
assert_contains "names the unknown node" "depends on unknown node Q"

# Overlapping owner files in one wave.
write_plan \
  "| A | - | src/ | standard | todo |" \
  "| B | - | src/x.c | standard | todo |"
run ./scripts/taskgraph.sh check
assert_rc "directory vs file overlap in one wave fails" 1
assert_contains "names both nodes" "nodes A and B can run in the same wave"
write_plan \
  "| A | - | docs/** | standard | todo |" \
  "| B | - | docs/x.md | standard | todo |"
run ./scripts/taskgraph.sh check
assert_rc "glob vs file overlap fails" 1
write_plan \
  "| A | - | docs/a.md, b.md | standard | todo |" \
  "| B | - | docs/b.md | standard | todo |"
run ./scripts/taskgraph.sh check
assert_rc "bare file name inherits the preceding directory" 1
write_plan \
  "| A | - | docs/rules/a.md | standard | todo |" \
  "| B | - | docs/rules/b.md, docs/procedures/c.md | standard | todo |" \
  "| C | - | docs/decisions/0003-*.md | standard | todo |"
run ./scripts/taskgraph.sh check
assert_rc "disjoint files in one wave pass" 0
write_plan \
  "| A | - | src/x.c | standard | todo |" \
  "| B | A | src/x.c | standard | todo |" \
  "| C | B | src/x.c | standard | todo |"
run ./scripts/taskgraph.sh check
assert_rc "same file across ordered nodes (including transitive) passes" 0

# Cycles.
write_plan \
  "| A | B | src/a | standard | todo |" \
  "| B | A | src/b | standard | todo |"
run ./scripts/taskgraph.sh check
assert_rc "dependency cycle fails" 1
assert_contains "cycle is named" "dependency cycle"
run ./scripts/taskgraph.sh waves
assert_rc "waves refuses a cycle" 1
write_plan \
  "| A | A | src/a | standard | todo |"
run ./scripts/taskgraph.sh check
assert_rc "self dependency fails" 1

# Duplicate ids, tiers, statuses.
write_plan \
  "| A | - | src/a | standard | todo |" \
  "| A | - | src/b | standard | todo |"
run ./scripts/taskgraph.sh check
assert_rc "duplicate node fails" 1
write_plan \
  "| A | - | src/a | wizard | todo |"
run ./scripts/taskgraph.sh check
assert_rc "unknown tier fails" 1
assert_contains "tier is named" "worker tier"
write_plan \
  "| A | - | src/a | standard | wip |"
run ./scripts/taskgraph.sh check
assert_rc "unknown status fails" 1
assert_contains "status is named" "has status"
write_plan \
  "| A | - | src/a | reviewer then advisor | blocked |" \
  "| B | - | src/b | strong | doing |"
run ./scripts/taskgraph.sh check
assert_rc "all tiers and statuses accepted, then-sequence included" 0
write_plan \
  "| A | - | src/a | standard |"
run ./scripts/taskgraph.sh check
assert_rc "a row with the wrong number of cells fails" 1

# The tier "inherit" is accepted (docs/rules/models.md).
write_plan   "| A | - | src/a | inherit | todo |"   "| B | - | src/b | inherit then strong | todo |"
run ./scripts/taskgraph.sh check
assert_rc "tier inherit is accepted" 0

# The blueprint's unfilled placeholder row is a template row and is skipped.
write_plan   "| {{node}} | {{- or node names}} | {{paths}} | {{cheap/standard/strong/advisor}} | todo |"
run ./scripts/taskgraph.sh check
assert_rc "a plan holding only the placeholder row passes" 0
assert_contains "no real nodes are counted" "0 nodes"
write_plan   "| A | - | src/a | standard | todo |"   "| {{node}} | {{- or node names}} | {{paths}} | {{cheap/standard/strong/advisor}} | todo |"
run ./scripts/taskgraph.sh check
assert_rc "a placeholder row beside real rows is skipped" 0
assert_contains "only the real node is counted" "1 nodes"

# The pristine new-task template row is valid.
write_plan \
  "| N1 | - | path/one, path/two | standard | todo |"
run ./scripts/taskgraph.sh check
assert_rc "example row from new-task.sh passes" 0

# Legacy flat plan.
cat > .work/TASK.md <<'TK'
# Task: legacy

## Plan
1. Do the first thing.
2. Do the second thing.

## Progress log
TK
run ./scripts/taskgraph.sh check
assert_rc "flat plan passes" 0
assert_contains "flat plan is noted" "flat plan"
run ./scripts/taskgraph.sh ready
assert_rc "ready needs a table" 1

rm -f .work/TASK.md
run ./scripts/taskgraph.sh check
assert_rc "missing TASK.md fails" 1

run ./scripts/taskgraph.sh bogus
assert_rc "unknown subcommand is a usage error" 2

t_finish
