#!/usr/bin/env bash
# papercut.sh - file a papercut: a small report of friction hit while working
# (a flag the help lists and the tool rejects, an exit 0 on an error, a doc that
# names a missing file, a guard that refused a command).
# Purpose: keep that evidence for the dream digest and the retro. A papercut is
#   never a rule or a lesson by itself; the owner approves those.
# Inputs:
#   add --tool NAME --tried TEXT --expected TEXT --got TEXT --fix TEXT
#       --refusal correct|wrong|none     file one entry (every flag required,
#                                        each text 1 to 300 characters)
#   list                                 groups by tool and result with counts,
#                                        newest first; correct refusals apart
#   help                                 the usage text, with the privacy rule
#   PAPERCUT_NOW (ISO time) replaces the clock.
# Outputs: one JSON line per entry in <main checkout>/.work/papercuts/log.jsonl
#   (local, git-ignored, newest 200 kept; dropping says how many on stderr).
#   Only the given fields and a UTC time are stored.
# Exit codes: 0 ok; 2 usage error, invalid field (nothing written) or no Python.
# Dependencies: bash, scripts/find-python.sh, scripts/dream/papercut.py (which
#   holds the logic; limits and grouping live in scripts/dream/dream.py).
# Assumptions: run on purpose by an agent, so a failure is never silent.
set -euo pipefail

SELF="${BASH_SOURCE[0]}"
case "$SELF" in */*) DIR="${SELF%/*}" ;; *) DIR="." ;; esac
ROOT="$(cd "$DIR/.." && pwd)"

PY=""
. "$ROOT/scripts/find-python.sh" 2>/dev/null || PY=""
if [[ -z "$PY" ]]; then
  echo "papercut: python not found; nothing was filed (bash scripts/doctor.sh names the install command)" >&2
  exit 2
fi
exec "$PY" -I -B "$ROOT/scripts/dream/papercut.py" "$@"
