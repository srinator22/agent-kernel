#!/usr/bin/env bash
# test_ci_gate_files.sh - the gate-file list in ci.yml (ADR 0018) covers every
# test_check_always*.sh file, their shared lib and scripts/private-terms.sh,
# by evaluating the workflow's own case pattern; and gate-label has no skip
# path (always(), failing itself when the paths job did not succeed), since a
# skipped required check counts as passing; adopted-project, the only run of
# the started copy, is unconditional.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" || { echo "$0: cannot load lib.sh; stopped before writing anything" >&2; exit 2; }

CI="$T_ROOT/.github/workflows/ci.yml"
# Adopted projects own their ci.yml (each wires its stack); the list is the
# template's.
if [[ ! -f "$CI" || -f "$T_ROOT/.start-done" ]] || ! grep -q '^Status: TEMPLATE' "$T_ROOT/AGENTS.md" 2>/dev/null; then
  t_na "not the template, or no .github/workflows/ci.yml"
  t_finish
fi

# The case pattern after "# Gate files:", continuation lines joined.
pat="$(awk '/# Gate files: what judges a change/ { f = 1; next }
  f && /case "\$f" in/ { g = 1; next }
  g { print; if ($0 ~ /\)[ \t]*$/) exit }' "$CI" | tr -d ' \\\n' | sed 's/)$//')"
if [[ -z "$pat" ]]; then
  t_bad "the gate-file case pattern was not found in ci.yml"
else
  t_ok "the gate-file case pattern is found"
fi
is_gate() { eval "case \"\$1\" in $pat) return 0 ;; esac"; return 1; }

files=(scripts/private-terms.sh tests/template/check_always_lib.sh)
for f in "$T_ROOT"/tests/template/test_check_always*.sh; do
  if [[ -f "$f" ]]; then files+=("tests/template/${f##*/}"); fi
done
(( ${#files[@]} >= 8 )) && t_ok "the six split check_always files are present" \
  || t_bad "expected six test_check_always*.sh files, found $(( ${#files[@]} - 2 ))"
for f in "${files[@]}"; do
  if is_gate "$f"; then t_ok "$f is a gate file"; else t_bad "$f is not in the ci.yml gate-file list"; fi
done
if is_gate docs/procedures/ship.md; then t_bad "a procedure matched the gate list"; else t_ok "a non-gate file stays out"; fi

job="$(awk '/^  gate-label:/ { f = 1; print; next } f && /^  [a-z0-9-]+:$/ { exit } f' "$CI")"
grep -qF "if: \${{ always() && github.event_name == 'pull_request' }}" <<< "$job" \
  && t_ok "gate-label runs on every pull request" || t_bad "gate-label is not if: always() on pull requests"
grep -qF 'needs.paths.result' <<< "$job" && grep -qF '!= "success"' <<< "$job" \
  && t_ok "gate-label fails itself when paths did not succeed" || t_bad "gate-label does not fail on a failed or skipped paths job"
grep -q '^  private-terms:$' "$CI" && t_ok "the private-terms job exists" || t_bad "no private-terms job in ci.yml"
ad="$(awk '/^  adopted-project:/ { f = 1; next } f && /^  [a-z0-9-]+:$/ { exit } f' "$CI")"
if grep -qxF '    if: ${{ !cancelled() }}' <<< "$ad" && ! grep -q 'needs:' <<< "$ad"; then
  t_ok "adopted-project runs on every pull request and push (the only started-copy run)"
else
  t_bad "adopted-project is conditional; the started copy would go unchecked on some changes"
fi

t_finish
