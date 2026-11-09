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
printf '#!/usr/bin/env bash\n' > scripts/feedback-log.sh; chmod +x scripts/feedback-log.sh
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


# ---- write_rows: the one writer behind the taste pass and port ----
JF="$(mktemp "${TMPDIR:-/tmp}/template-selftest.wr.XXXXXX")"
wr() { # area floor json: write_rows through the hidden CLI entry
  printf '%s' "$3" > "$JF"
  run "$PY" -I -B scripts/dream/preferences.py write-rows --root "$FIX" --area "$1" --floor "$2" --json "$JF"
}
ADD1='{"adds":[{"rule":"Labels stay short.","source":"2026-11-09: \"short labels\"","check":"Review"}]}'

fresh
wr film 0 "$ADD1"
assert_rc "write_rows: a new file is created" 0
assert_contains "write_rows: the first ID uses the area prefix" '"added": ["FILM-001"]'
assert_eq "write_rows: a new file opens with a title line" "# Film" "$(sed -n 1p docs/preferences/film.md)"
assert_file_has "write_rows: a new file has the rules header" docs/preferences/film.md '| ID | Rule | Source | Check | Repeats |'
assert_file_has "write_rows: the row is written" docs/preferences/film.md '| FILM-001 | Labels stay short. |'
chk
assert_rc "write_rows: the new file passes the check" 0
wr film 0 '{"adds":[{"rule":"Cuts land on the beat.","source":"2026-11-09: \"beat\"","check":"Review"}]}'
assert_contains "write_rows: the next ID follows" '"added": ["FILM-002"]'
assert_eq "write_rows: a row lands after the last data row" "FILM-002" "$(tail -n 1 docs/preferences/film.md | cut -d'|' -f2 | tr -d ' ')"

fresh
reg ui "# UI
$HDR
| U-001 | Keep labels short. | 2026-11 | Review |

## Baselines

| Kind | Reference | Owns | Check |
|---|---|---|---|
| poster | \`tools/gate.sh\` 2026-11-08 | layout | Review |"
wr ui 0 '{"adds":[{"rule":"Buttons use the brand colour.","source":"2026-11-09: \"brand\"","check":"Review"}]}'
assert_rc "write_rows: an add beside a baselines table" 0
new_ln="$(grep -n 'Buttons use the brand colour' docs/preferences/ui.md | cut -d: -f1)"
base_ln="$(grep -n '^| Kind' docs/preferences/ui.md | cut -d: -f1)"
if [[ -n "$new_ln" && -n "$base_ln" && "$new_ln" -lt "$base_ln" ]]; then t_ok "write_rows: the row lands in the rules table, above the baselines"; else t_bad "write_rows: the row lands in the rules table, above the baselines ($new_ln vs $base_ln)"; fi
assert_file_has "write_rows: the baselines table is intact" docs/preferences/ui.md '| poster |'
chk
assert_rc "write_rows: a file with baselines still passes" 0

fresh
reg ui "# UI

## Baselines

| Kind | Reference | Owns | Check |
|---|---|---|---|
| poster | \`tools/gate.sh\` 2026-11-08 | layout | Review |"
wr ui 0 "$ADD1"
assert_rc "write_rows: a baselines-only file gets a rules table" 0
hdr_ln="$(grep -n '^| ID | Rule' docs/preferences/ui.md | cut -d: -f1)"
head_ln="$(grep -n '^## Baselines' docs/preferences/ui.md | cut -d: -f1)"
if [[ -n "$hdr_ln" && -n "$head_ln" && "$hdr_ln" -lt "$head_ln" ]]; then t_ok "write_rows: the new rules table sits before the baselines section"; else t_bad "write_rows: the new rules table sits before the baselines section ($hdr_ln vs $head_ln)"; fi
chk
assert_rc "write_rows: a baselines-only file passes after the add" 0

fresh
wr ui 0 '{"adds":[{"rule":"Use a|b alike.","source":"2026-11-09: \"pipes\"","check":"Review"}]}'
assert_rc "write_rows: a pipe in a rule is accepted" 0
assert_file_has "write_rows: the pipe is escaped" docs/preferences/ui.md 'Use a\|b alike.'
chk
assert_rc "write_rows: an escaped pipe passes the check" 0
wr ui 0 '{"adds":[{"rule":"Use A|B  alike.","source":"2026-11-09: \"pipes\"","check":"Review"}]}'
assert_contains "write_rows: a pipe rule folds like its stored text" '"added": []'

fresh
wr ui 0 '{"adds":[{"rule":"two\nlines","source":"2026-11-09: \"x\"","check":"Review"}]}'
assert_rc "write_rows: a newline in a cell is refused" 1
assert_contains "write_rows: the newline error is clear" "newline"
assert_no_file "write_rows: a refused call writes nothing" docs/preferences/ui.md

fresh
wr working-style 0 "$ADD1"
assert_contains "write_rows: a hyphenated area gives a plain prefix" '"added": ["WORKINGSTYLE-001"]'
assert_file_has "write_rows: the hyphenated area file is named by the area" docs/preferences/working-style.md 'WORKINGSTYLE-001'

fresh
reg ui "$HDR
| U-001 | One. | 2026-11 | Review |
| U-004 | Four. | 2026-11 | Review |"
wr ui 0 "$ADD1"
assert_contains "write_rows: the prefix and highest number come from the file" '"added": ["U-005"]'
reg ui "$HDR
| A-001 | One. | 2026-11 | Review |
| B-001 | Two. | 2026-11 | Review |
| B-002 | Three. | 2026-11 | Review |"
wr ui 0 "$ADD1"
assert_contains "write_rows: the prefix used by most rows wins" '"added": ["B-003"]'
reg ui "$HDR
| U-001 | One. | 2026-11 | Review |"
wr ui 7 "$ADD1"
assert_contains "write_rows: the caller's floor is respected" '"added": ["U-008"]'
reg ui "$HDR
| U-001 | One. | 2026-11 | Review |
| U-002 | Two. | 2026-11 | Review |
| U-003 | Three. | 2026-11 | Review |"
wr ui 0 '{"removes":[{"id":"U-003"}],"adds":[{"rule":"Fresh.","source":"2026-11-09: \"f\"","check":"Review"}]}'
assert_contains "write_rows: a removed number is not reused" '"added": ["U-004"]'
assert_contains "write_rows: the removal is reported" '"removed": ["U-003"]'

fresh
reg ui "$HDR
| U-001 | Keep labels short. | 2026-11 | Review |"
wr film 0 '{"adds":[{"rule":"keep   LABELS short.","source":"2026-11-09: \"s\"","check":"Review"}]}'
assert_rc "write_rows: a duplicate of another file's rule is not an error" 0
assert_contains "write_rows: the duplicate is reported with its owner" 'ui:U-001'
assert_contains "write_rows: nothing is added for it" '"added": []'
assert_no_file "write_rows: a skipped-only call creates no file" docs/preferences/film.md
wr film 0 '{"adds":[{"rule":"Same text.","source":"2026-11-09: \"a\"","check":"Review"},{"rule":"same  TEXT.","source":"2026-11-09: \"b\"","check":"Review"}]}'
assert_contains "write_rows: one of two same-text adds is added" '"added": ["FILM-001"]'
assert_contains "write_rows: the other is reported as existing" 'this call'
assert_eq "write_rows: only one row exists for it" "1" "$(grep -c 'Same text' docs/preferences/film.md)"

fresh
reg ui "$HDR_R
| U-001 | Keep labels short. | 2026-11-08: \"short\" | Review (by eye) | 2 |"
wr ui 0 '{"revises":[{"id":"U-001","rule":"Keep labels very short.","words":"shorter please","date":"2026-11-10"}]}'
assert_rc "write_rows: a revise succeeds" 0
assert_contains "write_rows: the revise is reported" '"revised": ["U-001"]'
assert_file_has "write_rows: the rule text is replaced" docs/preferences/ui.md 'Keep labels very short.'
assert_file_has "write_rows: the Source gains the dated words" docs/preferences/ui.md '2026-11-08: "short"; 2026-11-10: "shorter please"'
assert_file_has "write_rows: the Check and Repeats stay" docs/preferences/ui.md '| Review (by eye) | 2 |'
chk
assert_rc "write_rows: a revised register passes" 0
wr ui 0 '{"revises":[{"id":"U-099","rule":"x","words":"y","date":"2026-11-10"}]}'
assert_rc "write_rows: a revise of an unknown ID fails" 1
assert_contains "write_rows: the unknown ID is named" "U-099"

fresh
reg ui "$HDR
| U-001 | One. | 2026-11 | Review |
| U-002 | Two. | 2026-11 | \`tests/test_alpha.py::test_alpha\` |"
wr ui 0 '{"removes":[{"id":"U-001"}]}'
assert_rc "write_rows: a remove succeeds" 0
assert_file_lacks "write_rows: the row is gone" docs/preferences/ui.md 'U-001'
assert_not_contains "write_rows: removing a Review row does not warn" "warning:"
wr ui 0 '{"removes":[{"id":"U-002"}]}'
assert_contains "write_rows: removing a tested row warns" "warning:"
assert_contains "write_rows: the warning names the test" "tests/test_alpha.py::test_alpha"
reg ui "$HDR
| U-002 | Two. | 2026-11 | \`tests/test_alpha.py::test_alpha\` |"
wr ui 0 '{"revises":[{"id":"U-002","rule":"Twice.","words":"w","date":"2026-11-10"}]}'
assert_contains "write_rows: revising a tested row warns and names it" "tests/test_alpha.py::test_alpha"

fresh
printf '# UI\r\n\r\n| ID | Rule | Source | Check |\r\n|---|---|---|---|\r\n| U-001 | One. | 2026-11 | Review |\r\n' > docs/preferences/ui.md
wr ui 0 "$ADD1"
assert_rc "write_rows: a CRLF file is written" 0
assert_eq "write_rows: every line of a CRLF file keeps its CR" "$(wc -l < docs/preferences/ui.md | tr -d ' ')" "$(tr -cd '\r' < docs/preferences/ui.md | wc -c | tr -d ' ')"
chk
assert_rc "write_rows: a CRLF file passes the check" 0

fresh
rm -f .start-done
wr ui 0 "$ADD1"
assert_rc "write_rows: template mode refuses" 1
assert_contains "write_rows: template mode says why" "template mode"
assert_no_file "write_rows: template mode writes nothing" docs/preferences/ui.md
rm -f "$JF"

# ---- port: copy rules from another project on request ----
SRC="$(mktemp -d "${TMPDIR:-/tmp}/template-selftest.src.XXXXXX")"
mkdir -p "$SRC/film-proj/docs/preferences"
cat > "$SRC/film-proj/docs/preferences/film.md" <<'REG'
# Film

| ID | Rule | Source | Check |
|---|---|---|---|
| FILM-001 | Titles stay on screen two seconds. | 2026-11-08: "hold titles" | Review (by eye) |
| FILM-002 | Cuts land on the beat. | 2026-11-02: "cut on the beat" | `tests/test_cuts.sh::test_beat` |
| FILM-003 | KEEP labels   short. | 2026-11-03: "short" | Review |
| FILM-004 | Use a\|b alike. | 2026-11-04: "pipes" | Review |

## Baselines

| Kind | Reference | Owns | Check |
|---|---|---|---|
| trailer | `tests/test_cuts.sh` 2026-11-08 | BASELINEOWNS | Review |
REG
cat > "$SRC/film-proj/docs/preferences/ui.md" <<'REG'
# UI

| ID | Rule | Source | Check |
|---|---|---|---|
| UI-001 | Buttons use the brand colour. | 2026-11-05: "brand" | Review |
REG
mkdir -p "$SRC/empty-proj/docs/preferences"
echo "# Preferences" > "$SRC/empty-proj/docs/preferences/README.md"
portfresh() { fresh; reg ui "$HDR
| U-001 | Keep labels short. | 2026-11 | Review |"; git add -A >/dev/null 2>&1; }
TODAY="$(date +%F)"

portfresh
before="$(cksum docs/preferences/ui.md)"
run bash scripts/preferences.sh port --from "$SRC/film-proj"
assert_rc "port: a dry run exits 0" 0
assert_contains "port: the dry run lists a rule's ID" "FILM-001"
assert_contains "port: the dry run lists its text" "Titles stay on screen two seconds."
assert_contains "port: the dry run lists the area" "film"
assert_contains "port: the dry run names the duplicate skip" "duplicate"
assert_no_file "port: a dry run writes no file" docs/preferences/film.md
assert_eq "port: a dry run leaves other registers alone" "$before" "$(cksum docs/preferences/ui.md)"

run bash scripts/preferences.sh port --from "$SRC/film-proj" --apply
assert_rc "port: --apply exits 0" 0
assert_file "port: --apply creates the area file" docs/preferences/film.md
assert_file_has "port: Source names the folder and the original" docs/preferences/film.md "$TODAY: ported from film-proj (2026-11-08: \"hold titles\")"
assert_file_has "port: a Review original becomes plain Review" docs/preferences/film.md '| Review |  |'
assert_file_has "port: a test original is kept as text after Review" docs/preferences/film.md 'Review (was `tests/test_cuts.sh::test_beat` in film-proj)'
assert_file_has "port: a pipe in a rule is kept" docs/preferences/film.md 'Use a\|b alike.'
assert_file_lacks "port: a duplicate rule is skipped" docs/preferences/film.md 'KEEP labels'
assert_file_lacks "port: baselines are not copied" docs/preferences/film.md 'BASELINEOWNS'
assert_file_has "port: other areas are copied too" docs/preferences/ui.md 'Buttons use the brand colour.'
git add -A >/dev/null 2>&1
run bash scripts/preferences.sh check
assert_rc "port: the result passes the check" 0
lines_before="$(cat docs/preferences/*.md | wc -l | tr -d ' ')"
run bash scripts/preferences.sh port --from "$SRC/film-proj" --apply
assert_rc "port: a second --apply exits 0" 0
assert_eq "port: a second --apply adds nothing" "$lines_before" "$(cat docs/preferences/*.md | wc -l | tr -d ' ')"

portfresh
run bash scripts/preferences.sh port --from "$SRC/film-proj" --area ui --apply
assert_rc "port: --area limits the copy" 0
assert_file_has "port: the chosen area is copied" docs/preferences/ui.md 'Buttons use the brand colour.'
assert_no_file "port: other areas are not copied" docs/preferences/film.md
run bash scripts/preferences.sh port --from "$SRC/film-proj" --area film --id FILM-002 --apply
assert_rc "port: --area with --id copies one row" 0
assert_file_has "port: the chosen row is copied" docs/preferences/film.md 'Cuts land on the beat.'
assert_file_lacks "port: other rows are not copied" docs/preferences/film.md 'Titles stay'
run bash scripts/preferences.sh port --from "$SRC/film-proj" --id FILM-002
assert_rc "port: --id without --area is a usage error" 2
run bash scripts/preferences.sh port --apply
assert_rc "port: a missing --from is a usage error" 2

run bash scripts/preferences.sh port --from "$FIX"
assert_rc "port: this project's own root is refused" 1
assert_contains "port: the own-root refusal says why" "own"
run bash scripts/preferences.sh port --from "$SRC/empty-proj"
assert_rc "port: a path with no registers is refused" 1
assert_contains "port: the no-registers refusal says why" "no registers"
run bash scripts/preferences.sh port --from "$SRC/does-not-exist"
assert_rc "port: a missing path is refused" 1

portfresh
rm -f .start-done
run bash scripts/preferences.sh port --from "$SRC/film-proj"
assert_rc "port: template mode refuses a dry run" 1
assert_contains "port: template mode says why" "template mode"
run bash scripts/preferences.sh port --from "$SRC/film-proj" --apply
assert_rc "port: template mode refuses --apply" 1
assert_no_file "port: template mode writes nothing" docs/preferences/film.md
case "$SRC" in */template-selftest.src.*) rm -rf "$SRC" ;; esac

t_finish
