#!/usr/bin/env bash
# preferences.sh - checks the preference registers in docs/preferences/<area>.md
# (docs/preferences/README.md, docs/procedures/preferences.md).
#   check    every rule row has a date and a Review or named check, every
#            reference exists, IDs are unique, baselines resolve
# Exit codes: 0 ok (also with no registers); 1 a register is invalid, or
# registers exist and Python is missing; 2 usage error.
# Prints a "warning:" line (still exit 0) when scripts/feedback-log.sh exists
# and .claude/settings.json does not reference it.
# Only bash builtins run before the Python lookup, so the no-Python paths work
# with an empty PATH.
set -uo pipefail

SELF="${BASH_SOURCE[0]}"
case "$SELF" in */*) DIR="${SELF%/*}" ;; *) DIR="." ;; esac
ROOT="$(cd "$DIR/.." && pwd)"

if [[ "${1:-}" != "check" || $# -ne 1 ]]; then
  echo "usage: scripts/preferences.sh check" >&2
  exit 2
fi

if [[ -f "$ROOT/scripts/feedback-log.sh" ]]; then
  settings=""
  if [[ -f "$ROOT/.claude/settings.json" ]]; then settings="$(<"$ROOT/.claude/settings.json")"; fi
  if [[ "$settings" != *feedback-log.sh* ]]; then
    echo "warning: scripts/feedback-log.sh exists but .claude/settings.json does not reference it; owner feedback is not logged (wire it as a UserPromptSubmit hook)"
  fi
fi

registers=0
# Any file below docs/preferences but its top README.md counts (bash globbing,
# so it needs no find on PATH); template mode then reaches the Python check.
shopt -s globstar nullglob dotglob
for f in "$ROOT"/docs/preferences/**/*; do
  [[ -f "$f" ]] || continue
  [[ "$f" == "$ROOT/docs/preferences/README.md" ]] && continue
  registers=$((registers + 1))
done
shopt -u globstar nullglob dotglob
if (( registers == 0 )); then
  echo "preferences: no registers"
  exit 0
fi

PY=""
. "$ROOT/scripts/find-python.sh" 2>/dev/null || PY=""
if [[ -z "$PY" ]]; then
  echo "preferences: python not found; $registers register file(s) cannot be checked" >&2
  exit 1
fi

exec "$PY" -I -B "$ROOT/scripts/dream/preferences.py" --root "$ROOT"
