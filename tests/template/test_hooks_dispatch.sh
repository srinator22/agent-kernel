#!/usr/bin/env bash
# hooks-dispatch: scripts/hooks-dispatch.sh EVENT runs the project's own hooks
# from scripts/hooks.d/<EVENT>/, so a project adds a hook without editing
# .claude/settings.json (ADR 0015). Covers: no folder and an empty folder exit
# 0; every executable file runs in name order on the same payload; a
# Markdown file, a dotfile and a subfolder are skipped; exit 2 passes
# through for every event; PreToolUse fails closed (exit 2) when a hook exits
# with anything else or cannot run, the other events report it as exit 1;
# an unknown or missing event name; and the settings.json wiring for the four
# events.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" || { echo "$0: cannot load lib.sh; stopped before writing anything" >&2; exit 2; }

SETTINGS="$T_ROOT/.claude/settings.json"
PAYLOAD='{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"git status"}}'

make_fixture
cp_script hooks-dispatch.sh
D="$FIX/scripts/hooks.d"
# hook EVENT NAME BODY: an executable sh hook in the fixture.
hook() {
  mkdir -p "$D/$1"
  printf '#!/bin/sh\n%s\n' "$3" > "$D/$1/$2"
  chmod +x "$D/$1/$2"
}
dispatch() { # EVENT [PAYLOAD]
  OUT="$(bash "$FIX/scripts/hooks-dispatch.sh" "$1" < <(printf '%s' "${2:-$PAYLOAD}") 2>&1)"; RC=$?
}

# ---- nothing to run ----
dispatch PreToolUse
assert_rc "no hooks.d folder: exit 0" 0
assert_eq "no hooks.d folder: no output" "" "$OUT"
mkdir -p "$D/PreToolUse"
dispatch PreToolUse
assert_rc "an empty event folder: exit 0" 0
assert_eq "an empty event folder: no output" "" "$OUT"

# ---- order, payload, skips ----
hook PreToolUse 20-second 'read -r p; echo "second saw $p"'
hook PreToolUse 10-first 'read -r p; echo "first saw $p"'
printf 'echo should not run\n' > "$D/PreToolUse/README.md"
printf '#!/bin/sh\necho dotfile ran\n' > "$D/PreToolUse/.hidden"; chmod +x "$D/PreToolUse/.hidden"
mkdir -p "$D/PreToolUse/sub"
dispatch PreToolUse
assert_rc "two passing hooks: exit 0" 0
assert_eq "both run in name order on the same payload" "first saw $PAYLOAD
second saw $PAYLOAD" "$OUT"
assert_not_contains "a dotfile is skipped" "dotfile ran"
assert_not_contains "a Markdown file is skipped" "should not run"

# ---- PreToolUse: exit 2 blocks, anything else fails closed ----
hook PreToolUse 15-block 'echo "no: blocked by project rule" >&2; exit 2'
dispatch PreToolUse
assert_rc "PreToolUse: a hook's exit 2 blocks" 2
assert_contains "PreToolUse: the hook's reason reaches stderr" "no: blocked by project rule"
assert_contains "PreToolUse: the later hooks still ran" "second saw"
rm -f "$D/PreToolUse/15-block"
hook PreToolUse 15-broken 'exit 3'
dispatch PreToolUse
assert_rc "PreToolUse: a hook that exits 3 fails closed" 2
assert_contains "PreToolUse: the dispatcher names the hook and its code" "15-broken exited 3"
rm -f "$D/PreToolUse/15-broken"
printf '#!/nonexistent/interpreter\n' > "$D/PreToolUse/15-noint"; chmod +x "$D/PreToolUse/15-noint"
dispatch PreToolUse
assert_rc "PreToolUse: a hook that cannot run fails closed" 2
assert_contains "PreToolUse: the dispatcher names the hook that could not run" "15-noint"
rm -f "$D/PreToolUse/15-noint"
# No exec bit and no #! line: not executable on Linux or under Git Bash.
printf 'exit 0\n' > "$D/PreToolUse/15-noexec"
dispatch PreToolUse
assert_rc "PreToolUse: a hook that is not executable fails closed" 2
assert_contains "PreToolUse: the dispatcher says it is not executable" "15-noexec is not executable"
rm -f "$D/PreToolUse/15-noexec"
dispatch PreToolUse
assert_rc "PreToolUse: passing again once the broken hooks are gone" 0

# ---- other events ----
hook Stop 10-continue 'echo "keep going" >&2; exit 2'
dispatch Stop '{"stop_hook_active":false}'
assert_rc "Stop: a hook's exit 2 passes through" 2
assert_contains "Stop: the reason reaches stderr" "keep going"
rm -f "$D/Stop/10-continue"
hook Stop 10-broken 'exit 5'
hook Stop 20-ok 'echo fine'
dispatch Stop '{"stop_hook_active":false}'
assert_rc "Stop: another failure is a non-blocking exit 1" 1
assert_contains "Stop: the failure is named" "10-broken exited 5"
assert_contains "Stop: the next hook still ran" "fine"
hook SessionStart 10-context 'echo "[project] context line"'
dispatch SessionStart '{"source":"startup"}'
assert_rc "SessionStart: exit 0" 0
assert_eq "SessionStart: stdout passes through" "[project] context line" "$OUT"
# A hook that never reads stdin closes the pipe; writing a payload larger than
# the pipe buffer then fails with EPIPE every time (CI run on c9068bd showed
# "printf: write error: Broken pipe" in the hook output by chance). The
# dispatcher's own write error must not reach the output.
big="$(printf '{"pad":"%0200000d"}' 0)"
dispatch SessionStart "$big"
assert_rc "SessionStart, large payload, hook ignores stdin: exit 0" 0
assert_eq "SessionStart, large payload: only the hook's output" "[project] context line" "$OUT"
hook UserPromptSubmit 10-log 'cat > /dev/null; exit 0'
dispatch UserPromptSubmit '{"prompt":"hi"}'
assert_rc "UserPromptSubmit: exit 0" 0

# ---- event names ----
dispatch Bogus
assert_rc "an unknown event exits 0" 0
assert_contains "an unknown event says so" "unknown event Bogus"
OUT="$(bash "$FIX/scripts/hooks-dispatch.sh" < /dev/null 2>&1)"; RC=$?
assert_rc "no event name exits 0" 0
assert_contains "no event name prints usage" "usage"
mkdir -p "$D/../hooks.d/x"
dispatch '../x'
assert_contains "a path is not an event name" "unknown event"

# ---- settings.json wiring ----
. "$T_ROOT/scripts/find-python.sh"
if [[ -z "$PY" ]]; then
  t_na "settings.json wiring: python not found (CI checks it)"
else
  for ev in SessionStart UserPromptSubmit PreToolUse Stop; do
    run "$PY" -I -B -c '
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
want = "bash \"$CLAUDE_PROJECT_DIR/scripts/hooks-dispatch.sh\" " + sys.argv[2]
hits = [g.get("matcher", "") for g in d["hooks"][sys.argv[2]] for h in g["hooks"] if h.get("command") == want]
print(len(hits), hits[0] if hits else "")
' "$SETTINGS" "$ev"
    case "$ev" in
      PreToolUse) assert_eq "settings.json: $ev runs the dispatcher once, for the shells and the edit tools" "1 Bash|PowerShell|Edit|Write|NotebookEdit" "$OUT" ;;
      *) assert_eq "settings.json: $ev runs the dispatcher once" "1 " "$OUT" ;;
    esac
  done
fi
assert_file_has "the stop gate stays wired next to the dispatcher" "$SETTINGS" 'scripts/stop-gate.sh'

t_finish
