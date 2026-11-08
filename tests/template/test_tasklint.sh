#!/usr/bin/env bash
# tasklint.sh: usage and missing-file handling, the pristine template, evidence
# for ticked criteria (paths, globs, judgment), Assumptions status lines,
# open assumptions at ship, the autopilot plan verdict, Mode parsing, comment
# stripping and CRLF files.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

make_fixture
cp_script tasklint.sh
mkdir -p .work tests docs
echo "x" > tests/x_test.sh
echo "x" > docs/a.md
echo "x" > docs/b.md
echo "x" > manifest.md

# task_crit LINE...: a standard task whose Acceptance criteria are the given lines.
task_crit() {
  {
    printf '# Task: fixture\nMode: standard\n\n## Acceptance criteria\n'
    printf '%s\n' "$@"
    printf '\n## Progress log\n'
  } > .work/TASK.md
}

# task_assume MODE LINE...: a task whose Assumptions are the given lines.
task_assume() {
  local m="$1"; shift
  {
    printf '# Task: fixture\nMode: %s\n\n## Assumptions\n' "$m"
    printf '%s\n' "$@"
    printf '\n## Acceptance criteria\n- [ ] C1 pending -> tests/x_test.sh\n'
  } > .work/TASK.md
}

# task_auto VERDICT STATUS...: an autopilot task with one plan node per status;
# VERDICT is the first line of a Plan verdict section, or empty for no section.
task_auto() {
  local v="$1" s i=0; shift
  {
    printf '# Task: fixture\nMode: autopilot\n\n## Assumptions\n- [confirmed] fine\n\n'
    printf '## Acceptance criteria\n- [ ] C1 pending -> tests/x_test.sh\n\n'
    printf '## Plan\n| node | depends on | owner files | worker tier | status |\n|---|---|---|---|---|\n'
    for s in "$@"; do i=$((i + 1)); printf '| N%d step | - | src/n%d | standard | %s |\n' "$i" "$i" "$s"; done
    printf '\n'
    if [[ -n "$v" ]]; then printf '## Plan verdict\n%s\n\n' "$v"; fi
    printf '## Progress log\n'
  } > .work/TASK.md
}

to_crlf() { awk '{ printf "%s\r\n", $0 }' "$1" > "$1.crlf" && mv "$1.crlf" "$1"; }

# Usage and missing file.
run ./scripts/tasklint.sh
assert_rc "no argument is a usage error" 2
assert_contains "usage names the subcommands" "check | ship"
run ./scripts/tasklint.sh bogus
assert_rc "unknown argument is a usage error" 2
run ./scripts/tasklint.sh check extra
assert_rc "extra argument is a usage error" 2
rm -f .work/TASK.md
run ./scripts/tasklint.sh check
assert_rc "missing task file fails" 1
assert_contains "names the missing file" "tasklint: .work/TASK.md not found"
run env TASKLINT_FILE=elsewhere/T.md ./scripts/tasklint.sh ship
assert_rc "missing TASKLINT_FILE fails" 1
assert_contains "names the other file" "elsewhere/T.md not found"

# Pristine template: nothing to check, in both modes, even with a bad tick inside.
printf '# Task: {{title}}\nMode: standard | quick | autopilot\n\n## Acceptance criteria\n- [x] C1 {{criterion}}\n' > .work/TASK.md
run ./scripts/tasklint.sh check
assert_rc "pristine template passes check" 0
assert_contains "pristine template is named" "pristine task template; nothing to check"
run ./scripts/tasklint.sh ship
assert_rc "pristine template passes ship" 0
cp .work/TASK.md other.md
rm -f .work/TASK.md
run env TASKLINT_FILE=other.md ./scripts/tasklint.sh check
assert_rc "TASKLINT_FILE selects the file" 0
assert_contains "the selected file was read" "pristine task template"

# Evidence for ticked criteria.
task_crit "- [x] C1 done"
run ./scripts/tasklint.sh check
assert_rc "ticked criterion without an arrow fails" 1
assert_contains "names the missing evidence" "ticked criterion has no evidence"
assert_contains "quotes the line" "C1 done"
assert_contains "reports the count" "check FAILED (1 problem(s))"

task_crit "- [x] C1 done -> judgment: reviewed the rendered page by eye"
run ./scripts/tasklint.sh check
assert_rc "judgment with a reason passes" 0
assert_contains "counts the ticked criterion" "1 ticked criteria"
task_crit "- [x] C1 done -> JUDGMENT: upper case works"
run ./scripts/tasklint.sh check
assert_rc "judgment keyword is case-insensitive" 0
task_crit "- [x] C1 done -> judgment:" "- [x] C2 done -> \`judgment:   \`"
run ./scripts/tasklint.sh check
assert_rc "judgment with no reason fails" 1
assert_contains "names the empty judgment" "judgment:\` with no reason"
assert_contains "both empty judgments are counted" "(2 problem(s))"

task_crit "- [x] C1 done -> tests/x_test.sh"
run ./scripts/tasklint.sh check
assert_rc "an existing path passes" 0
task_crit "- [x] C1 done -> \`tests/x_test.sh:12\`"
run ./scripts/tasklint.sh check
assert_rc "backticked path with a line suffix passes" 0
task_crit "- [x] C1 done -> tests/x_test.sh:12-30, see also docs/a.md."
run ./scripts/tasklint.sh check
assert_rc "line range and trailing period are stripped" 0
task_crit "- [x] C1 done -> tests/x_test.sh::test_name"
run ./scripts/tasklint.sh check
assert_rc "path::test_name passes" 0
task_crit "- [x] C1 done -> ./tests/x_test.sh (all cases), docs/a.md; docs/b.md + manifest.md"
run ./scripts/tasklint.sh check
assert_rc "separators and a leading ./ are handled" 0

task_crit "- [x] C1 done -> docs/missing.md"
run ./scripts/tasklint.sh check
assert_rc "a missing path fails" 1
assert_contains "names the missing path" "evidence path does not exist: docs/missing.md"
task_crit "- [x] C1 done -> tests/x_test.sh, docs/missing.md"
run ./scripts/tasklint.sh check
assert_rc "one existing and one missing path fails" 1
assert_contains "names the missing one" "evidence path does not exist: docs/missing.md"
assert_not_contains "does not name the existing one" "does not exist: tests/x_test.sh"
task_crit "- [x] C1 done -> diff inspection"
run ./scripts/tasklint.sh check
assert_rc "prose-only evidence fails" 1
assert_contains "asks for a path or judgment" "evidence names no existing path"
task_crit "- [x] C1 done -> manifest.md"
run ./scripts/tasklint.sh check
assert_rc "a bare file name with an extension passes when it exists" 0
task_crit "- [x] C1 done -> nothing.md"
run ./scripts/tasklint.sh check
assert_rc "a bare file name that does not exist fails" 1
assert_contains "names the bare file" "does not exist: nothing.md"
task_crit "- [x] C1 done -> https://example.com/docs/page.md"
run ./scripts/tasklint.sh check
assert_rc "a URL is not path-like" 1
assert_contains "a URL alone names no path" "evidence names no existing path"
task_crit "- [x] C1 done -> https://example.com/docs/page.md and docs/a.md"
run ./scripts/tasklint.sh check
assert_rc "a URL beside an existing path passes" 0
task_crit "- [x] C1 done -> docs/*.md"
run ./scripts/tasklint.sh check
assert_rc "a glob that matches passes" 0
task_crit "- [x] C1 done -> docs/*.nomatch"
run ./scripts/tasklint.sh check
assert_rc "a glob that matches nothing fails" 1
assert_contains "names the glob" "does not exist: docs/*.nomatch"
task_crit "- [x] C1 first -> tests/x_test.sh" "- [x] C2 second -> judgment: eyeballed" "- [x] C3 a -> b -> docs/a.md"
run ./scripts/tasklint.sh check
assert_rc "evidence is the text after the last arrow" 0
assert_contains "all three are counted" "3 ticked criteria"

task_crit "- [ ] C1 pending" "- [ ] C2 pending -> docs/missing.md" "  - [ ] C3 nested"
run ./scripts/tasklint.sh check
assert_rc "unticked criteria are never checked" 0
assert_contains "no ticked criteria are counted" "0 ticked criteria"
task_crit "- [X] C1 capital X done"
run ./scripts/tasklint.sh check
assert_rc "capital [X] counts as ticked" 1
assert_contains "capital [X] needs evidence" "ticked criterion has no evidence"
task_crit "<!-- - [x] C1 hidden -->" "- [ ] C2 real"
run ./scripts/tasklint.sh check
assert_rc "a ticked line inside a one-line comment is ignored" 0
task_crit $'<!-- example:\n- [x] C1 hidden, no evidence\n-->' "- [ ] C2 real"
run ./scripts/tasklint.sh check
assert_rc "a ticked line inside a multi-line comment is ignored" 0
assert_contains "and is not counted" "0 ticked criteria"

# Ticked lines outside the Acceptance criteria section are not criteria.
printf '# Task: fixture\n\n## Progress log\n- [x] a progress item without evidence\n' > .work/TASK.md
run ./scripts/tasklint.sh check
assert_rc "ticks outside Acceptance criteria are ignored" 0

# Assumptions.
task_assume standard "- [confirmed] The human said so." "- [Verified] Ran it -> tests/x_test.sh" "- [OPEN] Not yet."
run ./scripts/tasklint.sh check
assert_rc "status words are case-insensitive and open passes check" 0
assert_contains "counts the assumptions" "3 assumptions"
task_assume standard "- a plain assumption" "- [confirmed] fine"
run ./scripts/tasklint.sh check
assert_rc "an assumption without a status fails" 1
assert_contains "names the missing status" "assumption has no status [confirmed|verified|open]"
assert_contains "quotes the line" "a plain assumption"
task_assume standard "- [verified] Looked at it"
run ./scripts/tasklint.sh check
assert_rc "verified without an arrow fails" 1
assert_contains "names the missing evidence" "verified assumption has no evidence"
task_assume standard "- [verified] Looked at it ->   "
run ./scripts/tasklint.sh check
assert_rc "verified with an empty evidence fails" 1
task_assume standard "- [verified] Looked at it -> any text, no file needed"
run ./scripts/tasklint.sh check
assert_rc "verified evidence needs no existing path" 0
task_assume standard "<!-- - [open] example inside a comment -->" "- [confirmed] fine"
run ./scripts/tasklint.sh ship
assert_rc "an open line inside a comment is ignored" 0

# Open assumptions: pass check, fail ship, except in quick mode.
task_assume standard "- [confirmed] fine" "- [open] Which port does it use?"
run ./scripts/tasklint.sh check
assert_rc "open assumption passes check" 0
run ./scripts/tasklint.sh ship
assert_rc "open assumption fails ship" 1
assert_contains "names the open assumption" "open assumption (settle it: confirmed or verified)"
assert_contains "quotes the line" "Which port does it use?"
assert_contains "ship mode is named in the summary" "ship FAILED (1 problem(s))"
task_assume quick "- [open] Which port does it use?"
run ./scripts/tasklint.sh ship
assert_rc "open assumption passes ship in quick mode" 0
assert_contains "quick mode is reported" "mode quick"
task_assume standard "- [confirmed] fine" "- [verified] ran it -> tests/x_test.sh"
run ./scripts/tasklint.sh ship
assert_rc "settled assumptions pass ship" 0
assert_contains "ship success line" "tasklint: OK (ship; mode standard; 0 ticked criteria; 2 assumptions)"

# No Assumptions section: a note at ship, never a problem.
task_crit "- [ ] C1 pending"
run ./scripts/tasklint.sh ship
assert_rc "a task without Assumptions passes ship" 0
assert_contains "ship notes the older task file" "tasklint: no Assumptions section (older task file)"
run ./scripts/tasklint.sh check
assert_rc "a task without Assumptions passes check" 0
assert_not_contains "check does not print the note" "no Assumptions section"

# Autopilot plan verdict.
task_auto "" done todo
run ./scripts/tasklint.sh check
assert_rc "autopilot with a done node and no verdict fails check" 1
assert_contains "names the started node" "autopilot task has started (node N1 is done) without a PASS plan verdict"
task_auto "" todo doing
run ./scripts/tasklint.sh check
assert_rc "autopilot with a doing node and no verdict fails check" 1
assert_contains "names the doing node" "(node N2 is doing)"
task_auto "" todo todo
run ./scripts/tasklint.sh check
assert_rc "autopilot with only todo nodes passes check" 0
assert_contains "autopilot mode is reported" "mode autopilot"
run ./scripts/tasklint.sh ship
assert_rc "autopilot with only todo nodes fails ship" 1
assert_contains "ship names the missing verdict" "autopilot task has no PASS plan verdict"
task_auto "" blocked
run ./scripts/tasklint.sh check
assert_rc "a blocked node has not started" 0
task_auto "**PASS** plan is minimal" done todo
run ./scripts/tasklint.sh check
assert_rc "bold PASS verdict passes check" 0
run ./scripts/tasklint.sh ship
assert_rc "bold PASS verdict passes ship" 0
task_auto "PASS" todo
run ./scripts/tasklint.sh ship
assert_rc "bare PASS passes ship" 0
task_auto "Verdict: PASS - criteria are testable" doing
run ./scripts/tasklint.sh ship
assert_rc "Verdict: PASS passes ship" 0
task_auto "FAIL - criteria untestable" done
run ./scripts/tasklint.sh check
assert_rc "a FAIL verdict fails check once the work started" 1
assert_contains "names the FAIL verdict" "plan verdict is FAIL"
task_auto "FAIL - criteria untestable" todo
run ./scripts/tasklint.sh check
assert_rc "a FAIL verdict beside only todo nodes passes check" 0
run ./scripts/tasklint.sh ship
assert_rc "a FAIL verdict fails ship" 1
assert_contains "ship names the FAIL verdict" "plan verdict is FAIL"
task_auto "PASSED, probably" todo
run ./scripts/tasklint.sh ship
assert_rc "PASSED is not PASS" 1
task_auto "Plan reviewed, nothing to add" todo
run ./scripts/tasklint.sh ship
assert_rc "a verdict line that does not start with PASS fails ship" 1
printf '# Task: fixture\nMode: autopilot\n\n## Plan\n| node | depends on | owner files | worker tier | status |\n|---|---|---|---|---|\n| N1 a | - | src/a | standard | done |\n\n## Plan verdict\n<!-- written by the reviewer -->\n\nPASS - ok\n' > .work/TASK.md
run ./scripts/tasklint.sh ship
assert_rc "the verdict is the first non-blank line after comments" 0
task_assume standard "- [confirmed] fine"
printf '\n## Plan\n| node | depends on | owner files | worker tier | status |\n|---|---|---|---|---|\n| N1 a | - | src/a | standard | done |\n' >> .work/TASK.md
run ./scripts/tasklint.sh ship
assert_rc "a standard task does not need a plan verdict" 0
task_auto "" "todo"
printf '| {{node}} | {{deps}} | {{paths}} | {{tier}} | done |\n' >> .work/TASK.md
run ./scripts/tasklint.sh check
assert_rc "a template placeholder row is not a started node" 0

# Mode.
printf '# Task: fixture\nMode: standard | quick | autopilot\n\n## Assumptions\n- [open] x\n' > .work/TASK.md
run ./scripts/tasklint.sh ship
assert_rc "the unfilled template Mode line counts as standard" 1
assert_contains "so an open assumption fails ship" "open assumption"
printf '# Task: fixture\n\n## Assumptions\n- [open] x\n' > .work/TASK.md
run ./scripts/tasklint.sh ship
assert_rc "an absent Mode line counts as standard" 1
printf '# Task: fixture\nMode: Quick\n\n## Assumptions\n- [open] x\n' > .work/TASK.md
run ./scripts/tasklint.sh ship
assert_rc "Mode is case-insensitive" 0
printf '# Task: fixture\nMode: wizard\n' > .work/TASK.md
run ./scripts/tasklint.sh check
assert_rc "an unknown Mode fails" 1
assert_contains "names the allowed modes" "Mode must be standard, quick or autopilot"

# Several problems are all listed, with the count.
{
  printf '# Task: fixture\nMode: standard\n\n## Assumptions\n- no status here\n- [verified] no evidence here\n\n'
  printf '## Acceptance criteria\n- [x] C1 no arrow\n- [x] C2 -> docs/missing.md\n- [x] C3 -> prose only\n'
} > .work/TASK.md
run ./scripts/tasklint.sh check
assert_rc "several problems fail" 1
assert_contains "lists the assumption status problem" "assumption has no status"
assert_contains "lists the verified problem" "verified assumption has no evidence"
assert_contains "lists the missing arrow" "C1 no arrow"
assert_contains "lists the missing path" "does not exist: docs/missing.md"
assert_contains "lists the prose-only evidence" "evidence names no existing path"
assert_contains "counts every problem" "check FAILED (5 problem(s))"

# CRLF files behave like LF files.
task_crit "- [x] C1 done -> tests/x_test.sh" "- [x] C2 done -> judgment: eyeballed"
to_crlf .work/TASK.md
run ./scripts/tasklint.sh check
assert_rc "CRLF passing task passes" 0
assert_contains "CRLF success line matches" "tasklint: OK (check; mode standard; 2 ticked criteria; 0 assumptions)"
task_crit "- [x] C1 done -> docs/missing.md" "- [x] C2 no arrow"
to_crlf .work/TASK.md
run ./scripts/tasklint.sh check
assert_rc "CRLF failing task fails" 1
assert_contains "CRLF path is named without a carriage return" "does not exist: docs/missing.md"
assert_contains "CRLF problem count" "(2 problem(s))"
task_auto "**PASS** ok" done
to_crlf .work/TASK.md
run ./scripts/tasklint.sh ship
assert_rc "CRLF autopilot with a PASS verdict passes ship" 0
task_assume standard "- [open] still open"
to_crlf .work/TASK.md
run ./scripts/tasklint.sh ship
assert_rc "CRLF open assumption fails ship" 1

t_finish
