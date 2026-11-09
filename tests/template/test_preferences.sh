#!/usr/bin/env bash
# preferences.sh check: the preference registers (docs/preferences/<area>.md).
# Covers: a valid register in the real cell formats (month date, "Review (note)",
# a bare test file name, a command with arguments, several references in one
# cell, ::name), no registers, a fenced README example, every failure naming
# file and row (missing date, empty rule, unknown path, missing ::name,
# non-integer Repeats, duplicate ID, missing baseline reference, a non-README
# file in template mode), the unwired-hook warning, and no Python.
# Rule text is invented: this repo is public.
# Without python the test is skipped (CI has python3).
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" || { echo "$0: cannot load lib.sh; stopped before writing anything" >&2; exit 2; }

. "$T_ROOT/scripts/find-python.sh"
if [[ -z "$PY" ]]; then
  t_ok "python not found; preferences tests skipped (CI runs them)"
  t_finish
fi

HDR='| ID | Rule | Source | Check |
|---|---|---|---|'
HDR_R='| ID | Rule | Source | Check | Repeats |
|---|---|---|---|---|'

fresh() { # a started fixture with the register tooling and two tracked targets
  make_fixture
  cp_script preferences.sh find-python.sh dream/preferences.py dream/dream.py
  mkdir -p docs/preferences tests tools
  printf 'def test_alpha():\n    pass\n' > tests/test_alpha.py
  printf '#!/bin/sh\n' > tools/gate.sh
  : > .start-done
}
reg() { printf '%s\n' "$2" > "docs/preferences/$1.md"; }
chk() { git add -A >/dev/null 2>&1; run bash scripts/preferences.sh check; }

# ---- no registers ----
fresh
chk
assert_rc "no registers: exits 0" 0
assert_contains "no registers: says so" "preferences: no registers"
printf '# Preferences\n' > docs/preferences/README.md
chk
assert_rc "README only: exits 0" 0
assert_contains "README only: says no registers" "preferences: no registers"

# ---- a valid register in the real cell formats ----
fresh
reg ui "# UI
$HDR_R
| U-001 | Keep labels short. | 2026-11: \"short labels please\" | Review (checked by eye) | 2 |
| U-002 | Buttons use the brand colour. | 2026-11-02: \"brand colour\" | \`test_alpha.py::test_alpha\` | |
| U-003 | Gate passes. | 2026-10-30: \"keep the gate green\" | \`tools/gate.sh check --all\` and \`tests/test_alpha.py\` | 0 |
| U-004 | Mixed. | 2026-09 owner | Review; also \`gate.sh\` | |

## Baselines

| Kind | Reference | Owns | Check |
|---|---|---|---|
| landing page | \`tools/gate.sh\` 2026-11-08 | layout and palette | Review |"
chk
assert_rc "valid register passes" 0
assert_contains "valid register is counted" "preferences: ok"

# ---- an escaped pipe inside a cell is text, not a column ----
fresh
reg shell "$HDR
| SH-001 | Run hooks for Bash\\|PowerShell alike | 2026-11-09 owner | \`tests/test_alpha.py::test_alpha\` |"
chk
assert_rc "an escaped pipe in a rule keeps the row's columns" 0

# ---- a fenced README example is skipped ----
fresh
reg README '# Preferences

```
| ID | Rule | Source | Check |
|---|---|---|---|
| X-001 | Example only. | no date | `nowhere/missing.py::nothing` |
```'
reg ui "$HDR
| U-001 | Keep labels short. | 2026-11 | Review |"
chk
assert_rc "fenced README example passes" 0
assert_contains "fenced example passes with a register present" "preferences: ok"

# ---- each failure names the file and the row ----
fresh
reg ui "$HDR
| U-001 | Keep labels short. | the owner said so | Review |"
chk
assert_rc "missing date fails" 1
assert_contains "missing date names the file" "docs/preferences/ui.md"
assert_contains "missing date names the row" "U-001"
assert_contains "missing date is explained" "date"

fresh
reg ui "$HDR
| U-002 |  | 2026-11 | Review |"
chk
assert_rc "empty rule fails" 1
assert_contains "empty rule names the row" "U-002"
assert_contains "empty rule is explained" "rule"

fresh
reg ui "$HDR
| U-003 | A rule. | 2026-11 | \`tests/no_such_file.py\` |"
chk
assert_rc "unknown path fails" 1
assert_contains "unknown path names the row" "U-003"
assert_contains "unknown path is named" "no_such_file.py"

fresh
reg ui "$HDR
| U-004 | A rule. | 2026-11 | \`tests/test_alpha.py::test_missing\` |"
chk
assert_rc "missing ::name fails" 1
assert_contains "missing ::name names the row" "U-004"
assert_contains "missing ::name is named" "test_missing"

fresh
reg ui "$HDR_R
| U-005 | A rule. | 2026-11 | Review | many |"
chk
assert_rc "non-integer Repeats fails" 1
assert_contains "non-integer Repeats names the row" "U-005"
assert_contains "non-integer Repeats is explained" "Repeats"

fresh
reg ui "$HDR
| U-006 | A rule. | 2026-11 | Review |
| U-006 | Another rule. | 2026-11 | Review |"
chk
assert_rc "duplicate ID fails" 1
assert_contains "duplicate ID names the row" "U-006"
assert_contains "duplicate ID is explained" "duplicate"

fresh
reg ui "$HDR
| U-007 | A rule. | 2026-11 | Review |

| Kind | Reference | Owns | Check |
|---|---|---|---|
| poster | \`docs/gone/poster.md\` 2026-11-08 | layout | Review |"
chk
assert_rc "missing baseline reference fails" 1
assert_contains "missing baseline names the file" "docs/preferences/ui.md"
assert_contains "missing baseline names the reference" "docs/gone/poster.md"

fresh
reg ui "$HDR
| U-008 | A rule. | 2026-11 | Review |

| Kind | Reference | Owns | Check |
|---|---|---|---|
| poster | \`tools/gate.sh\` | layout | Review |"
chk
assert_rc "baseline without a date fails" 1
assert_contains "baseline without a date is explained" "date"

fresh
reg ui "$HDR
| U-009 | A rule. | 2026-11 | Review |

| Kind | Reference | Owns | Check |
|---|---|---|---|
| poster | \`tools/gate.sh\` 2026-11-08 | layout | Review |"
git add -A >/dev/null 2>&1
git -c user.email=a@b.invalid -c user.name=t commit -q -m c >/dev/null 2>&1
sha="$(git rev-parse --short HEAD)"
reg ui "$HDR
| U-009 | A rule. | 2026-11 | Review |

| Kind | Reference | Owns | Check |
|---|---|---|---|
| poster | $sha 2026-11-08 | layout | Review |"
chk
assert_rc "a baseline that is a resolvable commit passes" 0

fresh
reg ui "$HDR
| U-001 | A rule. | 2026-11 | Review |"
rm -f .start-done
chk
assert_rc "template mode: a non-README register fails" 1
assert_contains "template mode: the file is named" "docs/preferences/ui.md"
assert_contains "template mode: the reason is given" "template mode"

fresh
mkdir -p docs/preferences/old
printf 'owner words\n' > docs/preferences/film.txt
rm -f .start-done
chk
assert_rc "template mode: a non-md file in docs/preferences fails" 1
assert_contains "template mode: the non-md file is named" "docs/preferences/film.txt"
rm -f docs/preferences/film.txt
reg old/film "$HDR
| F-001 | A rule. | 2026-11 | Review |"
chk
assert_rc "template mode: a register in a subfolder fails" 1
assert_contains "template mode: the subfolder file is named" "docs/preferences/old/film.md"

# ---- a rules table with an extra column is checked, not skipped ----
fresh
reg ui "| ID | Rule | Source | Check | Notes |
|---|---|---|---|---|
| U-001 |  | no date | \`tests/no_such_file.py\` | x |"
chk
assert_rc "an extra column does not hide a rules table" 1
assert_contains "the extra-column row is named" "U-001"

# ---- the unwired-hook warning ----
fresh
printf '#!/usr/bin/env bash\n' > scripts/feedback-log.sh
mkdir -p .claude
printf '{"hooks": {}}\n' > .claude/settings.json
reg ui "$HDR
| U-001 | A rule. | 2026-11 | Review |"
chk
assert_rc "unwired hook still exits 0" 0
assert_contains "unwired hook warns" "warning:"
assert_contains "the warning names the hook" "feedback-log.sh"
printf '{"hooks": {"UserPromptSubmit": [{"hooks": [{"command": "scripts/feedback-log.sh"}]}]}}\n' > .claude/settings.json
chk
assert_rc "wired hook exits 0" 0
assert_not_contains "wired hook does not warn" "warning:"
rm -f .claude/settings.json
chk
assert_contains "a missing settings.json warns" "warning:"

# ---- no python ----
fresh
reg ui "$HDR
| U-001 | A rule. | 2026-11 | Review |"
git add -A >/dev/null 2>&1
run env PATH=/nonexistent "$BASH" "$FIX/scripts/preferences.sh" check
assert_rc "registers but no python: exits 1" 1
assert_contains "registers but no python: says so" "python not found"
rm -f docs/preferences/ui.md
run env PATH=/nonexistent "$BASH" "$FIX/scripts/preferences.sh" check
assert_rc "no registers and no python: exits 0" 0
assert_contains "no registers and no python: says so" "preferences: no registers"

t_finish
