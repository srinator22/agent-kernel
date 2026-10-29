#!/usr/bin/env bash
# stop-gate.sh: the Stop hook allows when there is no live task or the hook
# already continued once, blocks on broken task state, runs the quick gate only
# when every criterion is ticked, caches a green run by working-tree state,
# and allows when no quick lane is wired. A fake quickgate.sh records its runs.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# stop [PAYLOAD]: run the hook with PAYLOAD on stdin (default: a plain Stop).
stop() {
  local p="${1:-{\"hook_event_name\":\"Stop\",\"stop_hook_active\":false\}}"
  OUT="$(printf '%s' "$p" | bash scripts/stop-gate.sh 2>&1)"; RC=$?
}
qg_runs() { if [[ -f .work/jobs/qg.log ]]; then wc -l < .work/jobs/qg.log | tr -d ' '; else echo 0; fi; }
# task CRITERIA_LINES [MODE] [PLAN_STATUS]: write a live TASK.md.
task() {
  mkdir -p .work
  cat > .work/TASK.md <<TK
# Task: demo
Mode: ${2:-standard}

## Assumptions
- [confirmed] fixture

## Acceptance criteria
<!-- - [x] example inside a comment -> judgment: ignored -->
$1

## Plan
| node | depends on | owner files | worker tier | status |
|---|---|---|---|---|
| A | - | src.txt | standard | ${3:-todo} |
TK
}

make_fixture
cp_script stop-gate.sh taskgraph.sh tasklint.sh
cat > scripts/quickgate.sh <<'QG'
#!/usr/bin/env bash
mkdir -p .work/jobs && echo run >> .work/jobs/qg.log
echo "QG-OUTPUT-LINE"
exit "${QG_RC:-0}"
QG
printf '#!/usr/bin/env bash\n# accepts --quick\n' > scripts/check.sh
printf '.work/jobs/*\n' > .gitignore
echo src > src.txt
git add -A && git commit -q -m fixture

stop
assert_rc "no TASK.md: allow" 0
mkdir -p .work && echo "# Task: {{title}}" > .work/TASK.md
stop
assert_rc "pristine template: allow" 0

task "- [ ] works -> src.txt" standard
sed -i 's/| standard | todo |/| wizard | todo |/' .work/TASK.md
stop
assert_rc "a broken task graph blocks" 2
assert_contains "the block names the failed checks" "the task-state checks failed"
assert_contains "the taskgraph message is passed on" "worker tier"
assert_contains "the block explains the one-time escape" "does not block twice in a row"
stop '{"hook_event_name":"Stop","stop_hook_active": true}'
assert_rc "stop_hook_active true: allow even on broken state" 0

task "- [x] works -> diff inspection"
stop
assert_rc "a ticked criterion without evidence blocks" 2
assert_contains "the tasklint message is passed on" "evidence names no existing path"

task "- [x] works -> src.txt
- [ ] other -> judgment: later"
export QG_RC=1
stop
assert_rc "criteria not all ticked: allow without the quick gate" 0
assert_eq "the quick gate did not run" "0" "$(qg_runs)"

task "- [ ] only commented example is ticked -> src.txt"
stop
assert_rc "a ticked line inside a comment does not count" 0
assert_eq "the quick gate still did not run" "0" "$(qg_runs)"

task "- [x] works -> src.txt
- [X] other -> judgment: reviewed"
stop
assert_rc "all ticked and the quick gate red: block" 2
assert_contains "the block names the quick gate" "scripts/quickgate.sh failed (exit 1)"
assert_contains "the quick gate output is passed on" "QG-OUTPUT-LINE"
assert_eq "the quick gate ran once" "1" "$(qg_runs)"

export QG_RC=0
stop
assert_rc "all ticked and the quick gate green: allow" 0
assert_eq "the quick gate ran again after the red run" "2" "$(qg_runs)"
assert_file "the green state is cached" .work/jobs/stop-gate.green
stop
assert_rc "unchanged tree: allow" 0
assert_eq "an unchanged tree reuses the green run" "2" "$(qg_runs)"
echo more >> src.txt
stop
assert_eq "a tracked change re-runs the quick gate" "3" "$(qg_runs)"
echo new > untracked.txt
stop
assert_eq "a new untracked file re-runs the quick gate" "4" "$(qg_runs)"
assert_eq "the real index is untouched" "" "$(git diff --cached --name-only)"

rm -f .work/jobs/stop-gate.green
export QG_RC=2
stop
assert_rc "a wired lane that exits 2 is a real failure: block" 2
assert_contains "the exit status is named" "scripts/quickgate.sh failed (exit 2)"
unset QG_RC

printf '#!/usr/bin/env bash\n# no quick lane here\n' > scripts/check.sh
before="$(qg_runs)"
stop
assert_rc "no quick lane wired (check.sh lacks the quick flag): allow" 0
assert_eq "an unwired lane is not run" "$before" "$(qg_runs)"

rm scripts/quickgate.sh
stop
assert_rc "no quickgate.sh at all: allow" 0
t_cleanup

# Wiring: the Stop hook runs this script with a timeout long enough for the gate.
SETTINGS="$T_ROOT/.claude/settings.json"
assert_file_has "settings.json declares a Stop hook" "$SETTINGS" '"Stop"'
assert_file_has "the Stop hook runs the gate script" "$SETTINGS" 'scripts/stop-gate.sh'
assert_file_has "the Stop hook sets a timeout" "$SETTINGS" '"timeout": 1200'

t_finish
