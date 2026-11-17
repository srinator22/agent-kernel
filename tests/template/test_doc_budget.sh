#!/usr/bin/env bash
# test_doc_budget.sh - scripts/doc-budget.sh: the per-file and total procedure
# word caps and line width, a lost anchor fails while a moved one passes, a
# malformed anchor line fails, an AGENTS.md path outside Project decisions must exist, usage; and in
# the template, every frozen anchor was in its procedure at the freeze commit.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" || { echo "$0: cannot load lib.sh; stopped before writing anything" >&2; exit 2; }

make_fixture
cp_script doc-budget.sh
mkdir -p docs/procedures docs/rules tests/docs
printf '# A\nrun scripts/a.sh --now\nline\n' > docs/procedures/a.md
printf '# B\nkeep the gate\n' > docs/procedures/b.md
A=tests/docs/procedure-anchors.txt
printf '# frozen\ndocs/procedures/a.md\tscripts/a.sh --now\ndocs/procedures/b.md\tkeep the gate\n' > "$A"
printf '# Agents\nSee docs/procedures/a.md.\n## Project decisions\n- Map: docs/MISSING.md\n' > AGENTS.md

run ./scripts/doc-budget.sh check
assert_rc "procedures within budget pass" 0
assert_contains "the total is reported" "docs/procedures 11/10200 words"
DOC_BUDGET_FILE=5 run ./scripts/doc-budget.sh check
assert_rc "a procedure over the per-file word cap fails" 1
assert_contains "the long procedure is named" "docs/procedures/a.md has 6 words; the cap is 5"
DOC_BUDGET_TOTAL=10 run ./scripts/doc-budget.sh check
assert_rc "procedures over the word total fail" 1
assert_contains "the total is named" "docs/procedures total 11 words; the budget is 10"
DOC_BUDGET_WIDTH=12 run ./scripts/doc-budget.sh check
assert_rc "a line over the width cap fails (unwrapping is not cutting)" 1
assert_contains "the wide line is located" "docs/procedures/a.md:2: 22 characters; wrap procedure lines at 12"

printf '# B\nkeep it\n' > docs/procedures/b.md
run ./scripts/doc-budget.sh check
assert_rc "a lost anchor fails" 1
assert_contains "the lost phrase and its source are named" "anchor lost: \"keep the gate\" (from docs/procedures/b.md)"
printf 'Rules: keep the gate.\r\n' > docs/rules/r.md
run ./scripts/doc-budget.sh check
assert_rc "an anchor moved to another docs/ file passes" 0

printf 'docs/procedures/a.md no tab\n' >> "$A"
run ./scripts/doc-budget.sh check
assert_rc "a malformed anchor line fails" 1
assert_contains "the malformed line is located" "procedure-anchors.txt:4: not <path><TAB><phrase>"
printf '# frozen\n' > "$A"

printf '# Agents\nSee docs/procedures/gone.md and scripts/a.sh.\n' > AGENTS.md
run ./scripts/doc-budget.sh check
assert_rc "a missing cited path fails" 1
assert_contains "the missing path is named" "AGENTS.md cites docs/procedures/gone.md"
assert_contains "a missing script is named too" "AGENTS.md cites scripts/a.sh"
assert_not_contains "the Project decisions path was skipped earlier" "docs/MISSING.md"

run ./scripts/doc-budget.sh
assert_rc "no subcommand is a usage error" 2

# The oracle itself: each anchor was in its own procedure when it was frozen,
# so a later edit of the anchors file cannot swap in phrases the cut kept.
FREEZE=9b26990
if [[ -f "$T_ROOT/$A" ]] && git -C "$T_ROOT" cat-file -e "$FREEZE^{commit}" 2>/dev/null; then
  miss="$(cd "$T_ROOT" && grep -v '^#' "$A" | while IFS=$'\t' read -r f p; do
    git show "$FREEZE:$f" 2>/dev/null | grep -qF -- "$p" || echo "$f: $p"
  done)"
  if [[ -z "$miss" ]]; then t_ok "every frozen anchor is in its procedure at $FREEZE"
  else t_bad "anchors not in their procedure at $FREEZE: $miss"; fi
  # Frozen at the old path; moved out of the test-code budget, content kept.
  if git -C "$T_ROOT" show "$FREEZE:tests/template/fixtures/procedure-anchors.txt" | cmp -s - "$T_ROOT/$A"; then t_ok "the anchors file is unchanged since $FREEZE"
  else t_bad "the anchors file changed since $FREEZE (editing the oracle weakens the gate; kernel rule 2)"; fi
else
  t_na "the anchor freeze commit $FREEZE is not in this repository (an adopted project)"
fi

t_finish
