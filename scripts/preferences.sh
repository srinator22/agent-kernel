#!/usr/bin/env bash
# preferences.sh - checks the preference registers in docs/preferences/<area>.md
# (docs/preferences/README.md, docs/procedures/preferences.md).
#   check    every rule row has a date and a Review or named check, every
#            reference exists, IDs are unique, baselines resolve
#   port --from <path> [--area <a>]... [--id <ID>]... [--apply]
#            copies rules rows from another project's registers, only when the
#            owner asked for it. Dry run by default; --id needs --area.
# Exit codes: 0 ok (also with no registers); 1 a register is invalid, a port is
# refused, or Python is missing where it is needed; 2 usage error.
# Prints a "warning:" line (still exit 0) when scripts/feedback-log.sh exists
# and .claude/settings.json does not reference it.
# Only bash builtins run before the Python lookup, so the no-Python paths work
# with an empty PATH.
set -uo pipefail

SELF="${BASH_SOURCE[0]}"
case "$SELF" in */*) DIR="${SELF%/*}" ;; *) DIR="." ;; esac
ROOT="$(cd "$DIR/.." && pwd)"

MODE="${1:-}"
if [[ "$MODE" == "port" ]]; then
  # Usage errors come before the Python lookup; the rest is preferences.py.
  has_from=0; has_area=0; has_id=0
  for a in "${@:2}"; do
    case "$a" in --from) has_from=1 ;; --area) has_area=1 ;; --id) has_id=1 ;; esac
  done
  if (( ! has_from )) || (( has_id && ! has_area )); then
    echo "usage: scripts/preferences.sh port --from <path> [--area <a>]... [--id <ID> (needs --area)]... [--apply]" >&2
    exit 2
  fi
  PY=""
  . "$ROOT/scripts/find-python.sh" 2>/dev/null || PY=""
  if [[ -z "$PY" ]]; then
    echo "preferences: python not found; port cannot run" >&2
    exit 1
  fi
  exec "$PY" -I -B "$ROOT/scripts/dream/preferences.py" port --root "$ROOT" "${@:2}"
fi
if [[ "$MODE" != "check" || $# -ne 1 ]]; then
  echo "usage: scripts/preferences.sh check | port --from <path> [--area <a>]... [--id <ID>]... [--apply]" >&2
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
