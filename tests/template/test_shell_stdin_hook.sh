#!/usr/bin/env bash
# shell-stdin hook: scripts/hooks/refuse_shell_stdin.py behind its launcher
# scripts/refuse-shell-stdin.sh, wired into .claude/settings.json (matcher
# Bash|PowerShell, with --warn-long) next to the destructive guard. Covers the
# hook's own unittest folder (scripts/hooks/tests), the wired command run as
# Claude Code runs it (bash -c, payload on stdin) for the forms it refuses
# (python from stdin, here-documents, from both shells) and the forms it allows
# (git commit -F with a file, ordinary commands), the long-command context line,
# and the launcher with a Store-stub python3 first on PATH and with no working
# Python (a non-blocking exit 1, never 2). The Codex wiring is covered in
# test_codex_hooks.sh.
# Recorded: python3 as the Microsoft Store stub -> prints "Python was not found; run without arguments to install from the Microsoft Store" and exits 49 (documented at scripts/find-python.sh lines 4-5; not reproducible on the recording host, Python was installed)
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" || { echo "$0: cannot load lib.sh; stopped before writing anything" >&2; exit 2; }

SETTINGS="$T_ROOT/.claude/settings.json"
LAUNCHER="$T_ROOT/scripts/refuse-shell-stdin.sh"
. "$T_ROOT/scripts/find-python.sh"
if [[ -z "$PY" ]]; then
  t_ok "python not found; shell-stdin hook tests skipped (CI runs them)"
  t_finish
fi

# ---- the hook's own tests ----
run env PYTHONDONTWRITEBYTECODE=1 "$PY" -I -B -m unittest discover -s "$T_ROOT/scripts/hooks/tests" -t "$T_ROOT/scripts/hooks/tests" -p 'test_*.py'
assert_rc "scripts/hooks/tests pass" 0
run "$PY" -I -B "$T_ROOT/scripts/hooks/refuse_shell_stdin.py" --self-test
assert_rc "the hook's self-test passes" 0
assert_no_file "the library copy is gone (it moved to scripts/hooks)" "$T_ROOT/docs/library/hooks/refuse_shell_stdin.py"
assert_file_lacks "the library item table no longer lists the hook" "$T_ROOT/docs/library/README.md" "| refuse_shell_stdin | hook |"

# ---- the launcher ----
assert_file "the launcher exists" "$LAUNCHER"
assert_file_has "the launcher picks Python through find-python.sh" "$LAUNCHER" "find-python.sh"
assert_file_has "the launcher runs the hook from scripts/hooks" "$LAUNCHER" "hooks/refuse_shell_stdin.py"

# ---- settings.json wiring ----
# group_commands MATCHER: the command hooks of the PreToolUse groups whose
# matcher is exactly MATCHER, one per line.
group_commands() {
  "$PY" -I -B -c '
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
for g in d["hooks"]["PreToolUse"]:
    if g.get("matcher") == sys.argv[2]:
        for h in g["hooks"]:
            if h.get("type") == "command":
                print(h["command"])
' "$SETTINGS" "$1"
}
SHELL_CMDS="$(group_commands 'Bash|PowerShell')"
assert_eq "settings.json runs the shell-stdin hook once under Bash|PowerShell" "1" "$(printf '%s\n' "$SHELL_CMDS" | grep -c 'refuse-shell-stdin\.sh')"
WIRED="$(printf '%s\n' "$SHELL_CMDS" | grep 'refuse-shell-stdin\.sh' | head -n 1)"
assert_eq "the wired command" "bash \"\$CLAUDE_PROJECT_DIR/scripts/refuse-shell-stdin.sh\" --warn-long" "$WIRED"
assert_eq "the destructive guard stays wired under Bash|PowerShell" "1" "$(printf '%s\n' "$SHELL_CMDS" | grep -c 'scripts/destructive-guard\.sh')"
assert_eq "no settings entry runs the old library path" "0" "$(grep -c 'docs/library/hooks' "$SETTINGS")"

# wired TOOL COMMAND_JSON: run the wired command as Claude Code does. The
# command text is given already JSON-escaped (\n for a newline).
wired() {
  local payload
  payload="$(printf '{"session_id":"s","hook_event_name":"PreToolUse","tool_name":"%s","tool_input":{"command":"%s"},"cwd":"/"}' "$1" "$2")"
  OUT="$(printf '%s' "$payload" | CLAUDE_PROJECT_DIR="$T_ROOT" bash -c "$WIRED" 2>&1)"; RC=$?
}
# Refuse forms.
wired Bash 'cat > f.py <<'"'"'EOF'"'"'\nprint(1)\nEOF'
assert_rc "refused: a quoted here-document" 2
assert_contains "the refusal names the here-document" "here-document"
wired Bash 'git commit -F - <<MSG\nfix\nMSG'
assert_rc "refused: a commit message from a here-document" 2
wired Bash 'echo 1 | python -'
assert_rc "refused: python from stdin" 2
assert_contains "the refusal names stdin" "stdin"
wired Bash 'py -3 - < a.py'
assert_rc "refused: py from stdin" 2
wired PowerShell 'Get-Content a.py | python -'
assert_rc "refused: python from stdin under PowerShell" 2
# Allow forms.
for c in 'git commit -F .work/jobs/commit-msg.txt' 'git commit -F msg.txt' 'python scripts/x.py --arg' 'python -c \"print(1)\"' 'python -m unittest -q' 'git status --short' 'cat <<< hi' 'ls -la'; do
  wired Bash "$c"
  assert_rc "allowed: $c" 0
done
wired Bash 'git commit -F .work/jobs/commit-msg.txt'
assert_eq "git commit -F prints nothing" "" "$OUT"

# Long commands: still run, and the model gets one additionalContext line.
LONG="echo $(printf 'x%.0s' $(seq 1 4100))"
wired Bash "$LONG"
assert_rc "a 4105-byte command still runs" 0
run "$PY" -I -B -c 'import json,sys; h=json.loads(sys.argv[1])["hookSpecificOutput"]; print(h["hookEventName"], "permissionDecision" in h, "4105 bytes" in h["additionalContext"])' "$OUT"
assert_eq "the long command gets a PreToolUse additionalContext line and no decision" "PreToolUse False True" "$OUT"

# ---- the launcher with a Store stub on PATH ----
make_fixture
REAL="$(command -v "$PY")"
mkdir -p "$FIX/bin/stubonly" "$FIX/bin/both"
printf '#!/bin/sh\necho "Python was not found; run without arguments to install from the Microsoft Store"\nexit 49\n' > "$FIX/bin/stubonly/python3"
cp "$FIX/bin/stubonly/python3" "$FIX/bin/both/python3"
printf '#!/bin/sh\nexec "%s" "$@"\n' "$REAL" > "$FIX/bin/both/python"
chmod +x "$FIX"/bin/*/python*
hook_with() { # PATHDIR COMMAND
  OUT="$(printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' "$2" \
    | PATH="$1" CLAUDE_PROJECT_DIR="$T_ROOT" "$(command -v bash)" "$LAUNCHER" 2>&1)"; RC=$?
}
hook_with "$FIX/bin/both:$PATH" 'echo 1 | python -'
assert_rc "stub first on PATH: python from stdin still refused" 2
hook_with "$FIX/bin/both:$PATH" 'git commit -F msg.txt'
assert_rc "stub first on PATH: git commit -F still runs" 0
hook_with "$FIX/bin/stubonly" 'git status'
assert_rc "only the stub: a non-blocking exit 1, never 2" 1
assert_contains "only the stub: the launcher says the hook did not run" "the shell-stdin hook did not run"

t_finish
