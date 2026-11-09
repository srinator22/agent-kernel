# find-python.sh - the one Python probe every script and test uses.
# SOURCED, never executed:  . "$DIR/find-python.sh"
# Purpose: choose a Python 3 by running it. On Windows, python3 can be the
#   Microsoft Store App Execution Alias stub: command -v finds it, running it
#   exits 49 ("Python was not found"). A lookup alone picks the stub.
# Input: PATH.
# Output: PY = the first of python3, python that exists and exits 0 on a
#   Python 3 check; PY="" when none does. No other variable is left set.
# Assumptions: bash 3.2 or newer; only builtins and the candidate itself run.
PY=""
for _fp_c in python3 python; do
  if command -v "$_fp_c" >/dev/null 2>&1 \
     && "$_fp_c" -c 'import sys; sys.exit(sys.version_info < (3,))' >/dev/null 2>&1; then
    PY="$_fp_c"
    break
  fi
done
unset _fp_c
