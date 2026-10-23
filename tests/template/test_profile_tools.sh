#!/usr/bin/env bash
# The tools and hooks that profiles and the library ship (ADR 0004) keep their
# own tests green in the template, not only after a project adopts them: every
# tests/ folder under docs/profiles/*/tools/, docs/library/tools/ and
# docs/library/hooks/ runs here. Python test folders run with unittest
# discovery (isolated mode, no bytecode written); test_*.sh files run with bash.
# Without python the Python folders are reported and skipped; CI has python3.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

cd "$T_ROOT" || exit 1
PY=""
command -v python3 >/dev/null 2>&1 && PY=python3
[[ -n "$PY" ]] || { command -v python >/dev/null 2>&1 && PY=python; } || true

shopt -s nullglob
dirs=(docs/profiles/*/tools/tests docs/library/tools/tests docs/library/hooks/tests)
if (( ${#dirs[@]} == 0 )); then
  t_ok "no shipped tool tests to run"
fi
for d in "${dirs[@]}"; do
  pyt=("$d"/test_*.py)
  if (( ${#pyt[@]} > 0 )); then
    if [[ -z "$PY" ]]; then
      echo "  WARNING: python not found; $d not run here (CI runs it)"
    else
      run env PYTHONDONTWRITEBYTECODE=1 "$PY" -I -B -m unittest discover -s "$d" -t "$d" -p 'test_*.py'
      assert_rc "python tests pass: $d" 0
    fi
  fi
  for t in "$d"/test_*.sh; do
    run bash "$t"
    assert_rc "bash test passes: $t" 0
  done
done

t_finish
