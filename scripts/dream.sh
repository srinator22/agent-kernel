#!/usr/bin/env bash
# dream.sh - wrapper for scripts/dream.py, the offline memory-dream helper.
#   digest [--match PATH]... [--max-bytes N]  reduce new transcript lines to signals
#   done                                      commit the digest's offsets
#   due [--offer] [--quiet]                   is a dream due (file stats only)
#   status                                    last dream, due state, pending files
#   hygiene [--memory-dir DIR]                memory file sizes, ages, dangling links
# Exit codes: 0 ok / due; 1 not due; 2 usage error or no Python; 3 nothing to
# dream (digest found no new signal). Without Python, "due" prints
# "dream: not due (python not found)" (nothing with --quiet) and exits 1.
set -euo pipefail

SELF="${BASH_SOURCE[0]}"
case "$SELF" in */*) DIR="${SELF%/*}" ;; *) DIR="." ;; esac
ROOT="$(cd "$DIR/.." && pwd)"

PY=""
if command -v python3 >/dev/null 2>&1; then PY=python3
elif command -v python >/dev/null 2>&1; then PY=python
fi

if [[ -z "$PY" ]]; then
  if [[ "${1:-}" == "due" ]]; then
    quiet=0
    for a in "$@"; do [[ "$a" == "--quiet" ]] && quiet=1; done
    (( quiet )) || echo "dream: not due (python not found)"
    exit 1
  fi
  echo "dream: python not found" >&2
  exit 2
fi

exec "$PY" -I -B "$ROOT/scripts/dream.py" "$@"
