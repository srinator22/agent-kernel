#!/usr/bin/env bash
# hooks-dispatch.sh EVENT - runs the project's own hooks for one harness event.
# Purpose: a project adds a hook as a file in scripts/hooks.d/<EVENT>/ instead of
#   editing .claude/settings.json, which the template also changes; every derived
#   project had customized that file, so each template change to it conflicted
#   (ADR 0015). The template's own hooks stay wired directly in settings.json.
# Inputs: EVENT, one of SessionStart, UserPromptSubmit, PreToolUse, Stop (the
#   events settings.json wires to this script); the hook JSON on stdin.
# Runs: every file in scripts/hooks.d/<EVENT>/ in name order, each with the same
#   stdin. Skipped: dotfiles, *.md and subfolders. Any other file must be
#   executable (chmod +x, or a #! line on Windows).
# Outputs: each hook's stdout and stderr, passed through. Exit:
#   2 when any hook exits 2 (the harness's blocking code for that event);
#   PreToolUse: also 2 when a hook exits with any other non-zero code, cannot
#     run or is not executable (fail closed: a broken guard must not let a
#     tool call through);
#   other events: 1 (a non-blocking error) for those cases, so a broken hook
#     never blocks a prompt or a session;
#   0 otherwise, including no folder, an empty folder and an unknown event.
#   Every hook runs even after one fails, so each failure is reported.
# Limits: stdout is concatenated, so in an event whose stdout is read as JSON
#   only one hook may print JSON. The harness's timeout covers the whole folder.
# Assumptions: bash 3.2 or newer; the project root is this script's parent.
set -u
ev="${1:-}"
case "$ev" in
  SessionStart|UserPromptSubmit|PreToolUse|Stop) ;;
  "") echo "usage: scripts/hooks-dispatch.sh SessionStart|UserPromptSubmit|PreToolUse|Stop" >&2; exit 0 ;;
  *) echo "hooks-dispatch: unknown event $ev; nothing run" >&2; exit 0 ;;
esac
here="${BASH_SOURCE[0]%/*}"
[[ "$here" == "${BASH_SOURCE[0]}" ]] && here="."
dir="$here/hooks.d/$ev"
# The common case is no folder: leave before any fork, since this runs on
# every shell and edit call and a fork costs tens of milliseconds on Windows.
[[ -d "$dir" ]] || exit 0
files=()
for f in "$dir"/*; do
  [[ -f "$f" ]] || continue
  case "${f##*/}" in .*|*.md) continue ;; esac
  files+=("$f")
done
(( ${#files[@]} )) || exit 0

payload="$(cat)"
blocked=0
failed=0
for f in "${files[@]}"; do
  if [[ ! -x "$f" ]]; then
    echo "hooks-dispatch: $f is not executable (chmod +x it, with a #! line); not run" >&2
    failed=1
    continue
  fi
  printf '%s' "$payload" | "$f"
  rc=$?
  if (( rc == 2 )); then
    blocked=1
  elif (( rc != 0 )); then
    echo "hooks-dispatch: $f exited $rc" >&2
    failed=1
  fi
done
if (( blocked )); then exit 2; fi
if (( failed )); then
  if [[ "$ev" == PreToolUse ]]; then
    echo "hooks-dispatch: a PreToolUse hook in $dir failed; the call is refused until it is fixed" >&2
    exit 2
  fi
  exit 1
fi
exit 0
