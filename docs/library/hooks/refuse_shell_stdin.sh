#!/usr/bin/env bash
# refuse_shell_stdin.sh - launcher for refuse_shell_stdin.py, the PreToolUse hook that refuses
# `python -` and here-documents. Inputs: the hook JSON on stdin; arguments pass through to the hook.
# Outputs: the hook's exit code (0 lets the call run, 2 refuses it). Dependency: the project's
# scripts/find-python.sh, the one probe that picks Python by running it (on Windows `python3` is often
# a Store stub that exists on PATH but does not run). With no working Python the hook cannot judge
# the command: it reports that on stderr and exits 1 (a non-blocking error), never 2.
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The harness sets CLAUDE_PROJECT_DIR; run from docs/library/hooks, the project is three folders up.
root="${CLAUDE_PROJECT_DIR:-$here/../../..}"
PY=""
. "$root/scripts/find-python.sh" 2>/dev/null || PY=""
if [[ -n "$PY" ]]; then
  exec "$PY" -I "$here/refuse_shell_stdin.py" "$@"
fi
echo "refuse_shell_stdin.sh: scripts/find-python.sh found no working Python 3; the shell-stdin hook did not run" >&2
exit 1
