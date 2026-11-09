#!/usr/bin/env bash
# refuse_shell_stdin.sh - launcher for refuse_shell_stdin.py, the PreToolUse hook that refuses
# `python -` and here-documents. Inputs: the hook JSON on stdin; arguments pass through to the hook.
# Outputs: the hook's exit code (0 lets the call run, 2 refuses it). Dependency: a working Python 3.
# Why a launcher: on Windows `python3` is often a Store stub that exists on PATH but does not run, so the
# interpreter is chosen by RUNNING each candidate, not by finding it. With no working Python the hook cannot
# judge the command: it reports that on stderr and exits 1 (a non-blocking error), never 2.
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for py in python3 python py; do
  if command -v "$py" >/dev/null 2>&1 && "$py" -c 'import sys; sys.exit(0 if sys.version_info[0] == 3 else 1)' >/dev/null 2>&1 </dev/null; then
    exec "$py" -I "$here/refuse_shell_stdin.py" "$@"
  fi
done
echo "refuse_shell_stdin.sh: no working python3 or python on PATH; the shell-stdin hook did not run" >&2
exit 1
