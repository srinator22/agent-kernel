#!/usr/bin/env bash
# refuse-shell-stdin.sh - launcher for scripts/hooks/refuse_shell_stdin.py, the PreToolUse hook that
# refuses `python -` and here-documents (and, with --warn-long, adds a context line for a long command).
# Inputs: the hook JSON on stdin; arguments pass through to the hook.
# Outputs: the hook's stdout and exit code (0 lets the call run, 2 refuses it).
# Dependency: scripts/find-python.sh, the one probe that picks Python by running it (on Windows
# `python3` is often a Store stub that exists on PATH but does not run).
# Why core and not docs/library: .claude/settings.json and .codex/hooks.json sync to every project,
# docs/library only where a project carries it, so a wired library path broke synced projects.
# With no working Python the hook cannot judge the command: it says so on stderr and exits 1 (a
# non-blocking error), never 2, so a machine without Python keeps a working shell.
# Builtins only before Python is found: a test runs this with nothing but a stub on PATH.
set -u
here="${BASH_SOURCE[0]%/*}"
[[ "$here" == "${BASH_SOURCE[0]}" ]] && here="."
PY=""
. "$here/find-python.sh" 2>/dev/null || PY=""
if [[ -n "$PY" ]]; then
  exec "$PY" -I -B "$here/hooks/refuse_shell_stdin.py" "$@"
fi
echo "refuse-shell-stdin.sh: scripts/find-python.sh found no working Python 3; the shell-stdin hook did not run" >&2
exit 1
