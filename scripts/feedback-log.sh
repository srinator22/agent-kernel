#!/usr/bin/env bash
# feedback-log.sh - UserPromptSubmit hook: log the owner's prompt and its
# situation via scripts/dream/feedback.py. Reads the hook JSON on stdin.
# Always exits 0; without Python it does nothing, silently. FEEDBACK_LOG=0 turns
# it off.
SELF="${BASH_SOURCE[0]}"
case "$SELF" in */*) DIR="${SELF%/*}" ;; *) DIR="." ;; esac
ROOT="$(cd "$DIR/.." 2>/dev/null && pwd)" || exit 0

PY=""
if command -v python3 >/dev/null 2>&1; then PY=python3
elif command -v python >/dev/null 2>&1; then PY=python
fi
[[ -n "$PY" ]] || exit 0

"$PY" -I -B "$ROOT/scripts/dream/feedback.py" 2>/dev/null
exit 0
