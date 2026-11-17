#!/usr/bin/env bash
# stop-gate.sh: the Stop hook allows when there is no live task or the hook
# already continued once, blocks on broken task state, starts the quick gate in
# the background only when every criterion is ticked and returns without
# waiting, blocks once on a recorded failing run, caches a recorded pass by
# working-tree state, clears a running file older than an hour, and allows when
# no quick lane is wired. A fake quickgate.sh records its runs and, while
# .work/jobs/qg.release is absent, stays running so a hook that waited for it
# would hang the test instead of passing.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" || { echo "$0: cannot load lib.sh; stopped before writing anything" >&2; exit 2; }

# stop [PAYLOAD]: run the hook with PAYLOAD on stdin (default: a plain Stop).
stop() {
  local p="${1:-{\"hook_event_name\":\"Stop\",\"stop_hook_active\":false\}}"
  OUT="$(printf '%s' "$p" | bash scripts/stop-gate.sh 2>&1)"; RC=$?
}
qg_runs() { if [[ -f .work/jobs/qg.log ]]; then wc -l < .work/jobs/qg.log | tr -d ' '; else echo 0; fi; }
# bg_alive: "alive" when the pid in the running file is a live process.
bg_alive() {
  local pid=""
  [[ -f .work/jobs/stop-gate.running ]] && read -r pid _ < .work/jobs/stop-gate.running
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then echo alive; else echo gone; fi
}
# wait_bg: await the background run the hook started, by its pid.
wait_bg() {
  local pid=""
  [[ -f .work/jobs/stop-gate.running ]] && read -r pid _ < .work/jobs/stop-gate.running
  [[ -n "$pid" ]] || return 0
  while kill -0 "$pid" 2>/dev/null; do sleep 0.1; done
}
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
# Held open until the test releases it; the cap only keeps a broken run from
# outliving the test.
for _ in $(seq 600); do [[ -f .work/jobs/qg.release ]] && break; sleep 0.1; done
echo "QG-OUTPUT-LINE"
exit "${QG_RC:-0}"
QG
printf '#!/usr/bin/env bash\n# accepts --quick\n' > scripts/check.sh; chmod +x scripts/check.sh
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

# A recorded Codex Stop payload (tests/template/fixtures/codex/Stop.json) drives
# the gate like the Claude one: continue once, then allow.
CODEX_STOP="$(cat "$T_ROOT/tests/template/fixtures/codex/Stop.json")"
stop "$CODEX_STOP"
assert_rc "codex payload, broken state: block" 2
assert_contains "codex payload: the block names the task state" "stop-gate:"
stop "${CODEX_STOP/\"stop_hook_active\":false/\"stop_hook_active\":true}"
assert_rc "codex payload, stop_hook_active true: allow" 0

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

# The quick gate runs detached: the hook returns while the fake gate is held
# open by the missing release file, so a hook that waited would hang here.
task "- [x] works -> src.txt
- [X] other -> judgment: reviewed"
export QG_RC=1
rm -f .work/jobs/qg.release
stop
assert_rc "all ticked: the hook allows without waiting for the quick gate" 0
assert_file "a background run is recorded" .work/jobs/stop-gate.running
assert_eq "the recorded run is alive" "alive" "$(bg_alive)"
assert_no_file "no result while the run is going" .work/jobs/stop-gate.result
stop
assert_rc "a live run lets the stop through" 0
touch .work/jobs/qg.release
wait_bg
assert_eq "the live run was not started twice" "1" "$(qg_runs)"
assert_file_has "the result names the exit code" .work/jobs/stop-gate.result " 1"
assert_no_file "the finished run clears its running file" .work/jobs/stop-gate.running
stop
assert_rc "a recorded failing result blocks" 2
assert_contains "the block names the quick gate" "scripts/quickgate.sh failed (exit 1)"
assert_contains "the log tail is passed on" "QG-OUTPUT-LINE"
assert_file "the failure is marked reported" .work/jobs/stop-gate.result.reported
assert_no_file "the failing result is consumed" .work/jobs/stop-gate.result

export QG_RC=0
stop
assert_rc "a reported failure does not block again" 0
wait_bg
assert_eq "the quick gate ran again after the red run" "2" "$(qg_runs)"
assert_no_file "a pass is not cached before a stop reads it" .work/jobs/stop-gate.green
stop
assert_rc "a recorded pass for the same tree: allow" 0
assert_file "the green state is cached" .work/jobs/stop-gate.green
assert_no_file "the passing result is consumed" .work/jobs/stop-gate.result
stop
assert_rc "unchanged tree: allow" 0
assert_no_file "an unchanged tree starts no run" .work/jobs/stop-gate.running
assert_eq "an unchanged tree reuses the green run" "2" "$(qg_runs)"
echo more >> src.txt
stop; wait_bg
assert_eq "a tracked change re-runs the quick gate" "3" "$(qg_runs)"
echo new > untracked.txt
stop
assert_rc "a pass recorded for an older tree: allow" 0
wait_bg
assert_eq "a new untracked file re-runs the quick gate" "4" "$(qg_runs)"
read -r newkey _ < .work/jobs/stop-gate.result
stop
assert_eq "the pass for the current tree is cached" "$newkey" "$(cat .work/jobs/stop-gate.green)"
assert_eq "the real index is untouched" "" "$(git diff --cached --name-only)"

rm -f .work/jobs/stop-gate.green
export QG_RC=2
stop; wait_bg; stop
assert_rc "a wired lane that exits 2 is a real failure: block" 2
assert_contains "the exit status is named" "scripts/quickgate.sh failed (exit 2)"
export QG_RC=0

# A running file older than an hour is cleared even when its pid is alive.
printf '%s %s\n' "$$" "$(( $(date +%s) - 7200 ))" > .work/jobs/stop-gate.running
before="$(qg_runs)"
rm -f .work/jobs/qg.release
stop
assert_rc "a stale running file: allow" 0
assert_eq "a new run replaces the stale one" "alive" "$(bg_alive)"
assert_file_lacks "the stale pid is gone" .work/jobs/stop-gate.running "$$ "
touch .work/jobs/qg.release
wait_bg
assert_eq "a stale running file does not stop a new run" "$((before + 1))" "$(qg_runs)"
unset QG_RC

printf '#!/usr/bin/env bash\n# no quick lane here\n' > scripts/check.sh; chmod +x scripts/check.sh
before="$(qg_runs)"
stop
assert_rc "no quick lane wired (check.sh lacks the quick flag): allow" 0
assert_eq "an unwired lane is not run" "$before" "$(qg_runs)"

rm scripts/quickgate.sh
stop
assert_rc "no quickgate.sh at all: allow" 0

# ---- no live task: offer a dream once when one is due ----
# A fake dream.sh: "due --offer" succeeds once (it records the offer), then
# reports the offer as already made, as the real one does within a day.
cat > scripts/dream.sh <<'DS'
#!/usr/bin/env bash
case "$*" in
  *--offer*)
    if [[ "${DREAM_DUE:-1}" != 1 || -f .work/jobs/offered ]]; then exit 1; fi
    mkdir -p .work/jobs && touch .work/jobs/offered
    echo "dream: due (2 sessions with new activity, 1 task retros since the last dream)"; exit 0 ;;
esac
exit 1
DS
task "- [ ] works -> src.txt" standard
stop
assert_rc "a live task never triggers the dream offer" 0
assert_no_file "the offer was not even asked for" .work/jobs/offered
echo "# Task: {{title}}" > .work/TASK.md
DREAM_DUE=0 stop
assert_rc "no task and no dream due: allow" 0
stop
assert_rc "no task and a dream due: block once" 2
assert_contains "the block says a dream is due" "work is done and a dream is due (2 sessions with new activity, 1 task retros since the last dream)"
assert_contains "the block asks the user" "Start dreaming?"
stop
assert_rc "the same state is not offered twice" 0
rm -f .work/jobs/offered
stop '{"hook_event_name":"Stop","stop_hook_active":true}'
assert_rc "after one continuation the hook never blocks" 0
rm -f .work/TASK.md
stop
assert_rc "no TASK.md at all and a dream due: block once" 2
rm scripts/dream.sh
stop
assert_rc "no dream.sh: allow" 0
t_cleanup

# Wiring: the Stop hook runs this script with a short timeout; the gate runs
# detached, so the hook never needs the gate's minutes.
SETTINGS="$T_ROOT/.claude/settings.json"
assert_file_has "settings.json declares a Stop hook" "$SETTINGS" '"Stop"'
assert_file_has "the Stop hook runs the gate script" "$SETTINGS" 'scripts/stop-gate.sh'
assert_file_has "the Stop hook sets a short timeout" "$SETTINGS" '"timeout": 120'
assert_file_lacks "the Stop hook no longer waits 1200 s" "$SETTINGS" '"timeout": 1200'

t_finish
