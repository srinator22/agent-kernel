#!/usr/bin/env bash
# check.sh always section, project mode: a fake .start-done and a minimal
# AGENTS.md; a clean fixture reaches the unwired stack block and fails there;
# --quick never skips the always section.
# Shared fixtures: check_always_lib.sh.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" || { echo "$0: cannot load lib.sh; stopped before writing anything" >&2; exit 2; }
source "$(dirname "${BASH_SOURCE[0]}")/check_always_lib.sh" || { echo "$0: cannot load check_always_lib.sh; stopped before writing anything" >&2; exit 2; }

sec_project() {
# ---- project mode ----
make_fixture
cp_script check.sh kernel-hash.sh lessons.sh profiles.sh taskgraph.sh adr.sh tasklint.sh doc-eval.sh
write_agents
./scripts/kernel-hash.sh --update >/dev/null
echo "src" > src.txt
write_task
touch .start-done
commit_fixture

run ./scripts/check.sh
assert_rc "a clean project reaches the unwired stack block and fails there" 1
assert_contains "the always section ran: lessons" "lessons: OK"
assert_contains "the always section ran: task graph" "taskgraph:"
assert_contains "the stack block is what failed" "$STACK_MSG"

# ---- SW-15: project mode refuses a missing or unfilled verify skill ----
SW15_MSG="software profile SW-15: .claude/skills/verify/SKILL.md is missing or still holds a {{ wiring placeholder"
# Both copies leave the tree, so the .claude/.agents mirror check stays clean
# and SW-15 is what fails.
mv .claude/skills/verify "$FIX.verify-claude"
mv .agents/skills/verify "$FIX.verify-agents"
run ./scripts/check.sh
assert_rc "a project without the verify skill fails" 1
assert_contains "the missing verify skill is named" "$SW15_MSG"
assert_not_contains "the stack block is not reached without the verify skill" "$STACK_MSG"
mv "$FIX.verify-claude" .claude/skills/verify
mv "$FIX.verify-agents" .agents/skills/verify
cp .claude/skills/verify/SKILL.md "$FIX.verify"
printf -- '- boot: {{VERIFY_BOOT}}\n' >> .claude/skills/verify/SKILL.md
cp .claude/skills/verify/SKILL.md .agents/skills/verify/SKILL.md
run ./scripts/check.sh
assert_rc "a verify skill with a wiring placeholder fails" 1
assert_contains "the unfilled verify skill is named" "$SW15_MSG"
cp "$FIX.verify" .agents/skills/verify/SKILL.md
mv "$FIX.verify" .claude/skills/verify/SKILL.md

# ---- 4h: the Template line names the last recorded sync ----
cp_script template-sync.sh
commit_fixture
run ./scripts/check.sh
assert_rc "a project without a Template line fails" 1
assert_contains "the Template status failure is named" "template-sync.sh --status failed"
printf -- '- Template: https://example.invalid/template.git template-v0.1.0\n' >> AGENTS.md
mkdir -p docs/lessons
echo "template-sync: template-v0.1.0 2026-11-07" > docs/lessons/MAINTENANCE.log
commit_fixture
run ./scripts/check.sh
assert_not_contains "a matching Template line passes 4h" "template-sync.sh --status failed"
assert_contains "the always section then reaches the stack block" "$STACK_MSG"

# ---- the stack steps live in the project-owned scripts/stack-check.sh ----
printf '#!/usr/bin/env bash\necho "stack args: $*"\nexit "${STACK_RC:-0}"\n' > scripts/stack-check.sh
commit_fixture
# commit_fixture marks scripts/*.sh executable; a Windows checkout often has
# no bit at all, so prove check.sh runs the file without one.
git update-index --chmod=-x scripts/stack-check.sh && chmod -x scripts/stack-check.sh
git commit -q -m "stack-check.sh without the executable bit" >/dev/null 2>&1
assert_eq "the fixture's stack-check.sh has no executable bit in git" "100644" "$(git ls-files -s scripts/stack-check.sh | cut -d' ' -f1)"
run ./scripts/check.sh
assert_rc "a project whose stack-check.sh passes is green, executable bit or not" 0
assert_contains "stack-check.sh ran" "stack args:"
assert_contains "the green run says so" "check: OK (always section and scripts/stack-check.sh)"
run ./scripts/check.sh --quick
assert_contains "--quick is passed to stack-check.sh" "stack args: --quick"
run ./scripts/check.sh --full-mutation
assert_contains "--full-mutation is passed to stack-check.sh" "stack args: --full-mutation"
STACK_RC=3 run ./scripts/check.sh
assert_rc "a failing stack-check.sh fails check.sh" 1
assert_contains "the stack failure is named" "scripts/stack-check.sh failed"
git rm -q -f scripts/stack-check.sh scripts/template-sync.sh docs/lessons/MAINTENANCE.log
write_agents
./scripts/kernel-hash.sh --update >/dev/null
commit_fixture

# ---- 4i: the preference register check runs in the always section ----
# A stand-in prints its arguments, so the run is observable, and exits with
# PREFS_RC. Without the script (every fixture above) the step is skipped.
printf '#!/usr/bin/env bash
echo "preferences stub ran: $*"
echo "warning: stub warning line"
exit "${PREFS_RC:-0}"
' > scripts/preferences.sh
commit_fixture
run ./scripts/check.sh --quick
assert_contains "the register check runs in the always section, even with --quick" "preferences stub ran: check"
assert_contains "its warning lines are shown" "warning: stub warning line"
assert_contains "a passing register check reaches the stack block" "$STACK_MSG"
PREFS_RC=1 run ./scripts/check.sh --quick
assert_rc "a failing register check fails project mode" 1
assert_contains "the register failure is named" "scripts/preferences.sh check failed"
assert_not_contains "the stack block is not reached after a register failure" "$STACK_MSG"
git rm -q -f scripts/preferences.sh && git commit -q -m "remove preferences stub" >/dev/null 2>&1

# ---- 4j: the private-terms check runs in the always section ----
printf '#!/usr/bin/env bash
echo "private-terms stub ran: $*"
exit "${TERMS_RC:-0}"
' > scripts/private-terms.sh
commit_fixture
run ./scripts/check.sh --quick
assert_contains "the private-terms check runs in the always section, even with --quick" "private-terms stub ran: check"
assert_contains "a passing private-terms check reaches the stack block" "$STACK_MSG"
TERMS_RC=1 run ./scripts/check.sh --quick
assert_rc "a failing private-terms check fails project mode" 1
assert_contains "the private-terms failure is named" "scripts/private-terms.sh check failed"
assert_not_contains "the stack block is not reached after a private-terms failure" "$STACK_MSG"
git rm -q -f scripts/private-terms.sh && git commit -q -m "remove private-terms stub" >/dev/null 2>&1

printf 'bad %s dash\n' "$EM" > notes.txt
commit_fixture
run ./scripts/check.sh
assert_rc "a dash in a tracked file fails in project mode" 1
assert_contains "the dash failure is reported" "em or en dash found"
assert_not_contains "the stack block is not reached" "$STACK_MSG"
run ./scripts/check.sh --quick
assert_rc "--quick does not skip the dash check" 1
assert_contains "--quick reports the dash failure" "em or en dash found"
git rm -q -f notes.txt && git commit -q -m "remove notes" >/dev/null 2>&1

# A long match list (well over 1 MiB of git grep output) still ends in the
# named failure: a pipe into head under pipefail used to end check.sh with 141
# once the list outgrew the pipe buffer.
# long_list LABEL BYTES NEEDLE: 45000 tracked lines holding BYTES, then --quick.
long_list() {
  seq 1 45000 | sed "s/\$/ bad $2 line/" > notes.txt
  commit_fixture
  run ./scripts/check.sh --quick
  assert_rc "a long $1 list fails with exit 1, not 141" 1
  assert_contains "the long $1 list failure is named" "$3"
  assert_eq "at most 20 $1 match lines are printed" "20" "$(printf '%s\n' "$OUT" | grep -c '^notes\.txt:')"
  git rm -q -f notes.txt && git commit -q -m "remove notes" >/dev/null 2>&1
}
long_list dash "$EM" "em or en dash found"
long_list "curly quote" "$(printf '\xe2\x80\x9c')" "typographic or mis-encoded character found"

# Typographic and mis-encoded characters fail like dashes, --quick included.
# Each spec is label:bytes with the bytes written as escapes, so this file
# stays plain ASCII and passes the gate it tests.
for spec in 'curly quote:\xe2\x80\x9c' 'ellipsis:\xe2\x80\xa6' 'non-breaking space:\xc2\xa0' \
            'replacement character:\xef\xbf\xbd' 'mojibake A-tilde:\xc3\x83\xc2\xa9' 'mojibake a-circumflex-euro:\xc3\xa2\xe2\x82\xac'; do
  label="${spec%%:*}"
  printf 'bad %b char\n' "${spec#*:}" > notes.txt
  commit_fixture
  run ./scripts/check.sh --quick
  assert_rc "a $label in a tracked file fails, even with --quick" 1
  assert_contains "the $label failure is reported" "typographic or mis-encoded character found"
  git rm -q -f notes.txt && git commit -q -m "remove notes" >/dev/null 2>&1
done
printf 'plain ASCII "quotes" and ... dots and e-acute written as an escape
' > notes.txt
commit_fixture
run ./scripts/check.sh --quick
assert_not_contains "plain ASCII punctuation passes the character check" "typographic or mis-encoded"
git rm -q -f notes.txt && git commit -q -m "remove notes" >/dev/null 2>&1

# The task lint runs in the always section; its ship half only in the full gate.
mkdir -p .work
printf '# Task: fixture

## Assumptions
- [open] not settled

## Acceptance criteria
- [x] done -> diff inspection
' > .work/TASK.md
commit_fixture
run ./scripts/check.sh --quick
assert_rc "a ticked criterion without evidence fails, even with --quick" 1
assert_contains "the tasklint check failure is reported" "scripts/tasklint.sh check failed"
assert_not_contains "--quick skips the ship half" "scripts/tasklint.sh ship failed"
printf '# Task: fixture

## Assumptions
- [open] not settled
' > .work/TASK.md
commit_fixture
run ./scripts/check.sh --quick
assert_not_contains "an open assumption passes --quick" "tasklint.sh"
run ./scripts/check.sh
assert_rc "an open assumption fails the full gate" 1
assert_contains "the ship failure is reported" "scripts/tasklint.sh ship failed"
write_task
commit_fixture

# The doc question table is validated in the always section.
mkdir -p tests/docs && echo "no table" > tests/docs/questions.md
commit_fixture
run ./scripts/check.sh --quick
assert_rc "a malformed question table fails, even with --quick" 1
assert_contains "the doc-eval failure is reported" "scripts/doc-eval.sh check failed"
git rm -q -r -f tests/docs && git commit -q -m "remove questions" >/dev/null 2>&1

mkdir -p docs/rules
seq 1 41 > docs/rules/big.md
commit_fixture
run ./scripts/check.sh
assert_rc "an over-cap rules file fails in project mode" 1
assert_contains "the lessons failure is reported" "docs/rules/big.md has 41 lines"
assert_contains "the lessons check is named as failed" "scripts/lessons.sh check failed"
assert_not_contains "the stack block is not reached after a lessons failure" "$STACK_MSG"
run ./scripts/check.sh --quick
assert_rc "--quick does not skip the lessons check" 1
assert_contains "--quick reports the lessons failure" "scripts/lessons.sh check failed"
git rm -q -f docs/rules/big.md && git commit -q -m "remove big rule" >/dev/null 2>&1

mkdir -p .work
cat > .work/TASK.md <<'TK'
# Task: fixture

## Plan
| node | depends on | owner files | worker tier | status |
|---|---|---|---|---|
| A | - | src/a | wizard | todo |
TK
commit_fixture
run ./scripts/check.sh
assert_rc "a bad task graph fails in project mode" 1
assert_contains "the task graph failure is reported" "scripts/taskgraph.sh check failed"
write_task
mkdir -p docs/decisions
printf '# 0002 - Skipped one\n\nDate: 2026-01-01\nStatus: accepted\n\n## Context\n\n## Decision\n\n## Consequences\n' > docs/decisions/0002-skipped-one.md
commit_fixture
run ./scripts/check.sh --quick
assert_rc "a misnumbered ADR fails project mode, even with --quick" 1
assert_contains "the ADR failure is reported" "scripts/adr.sh check failed"
assert_contains "the ADR problem is named" "number 0002 breaks the sequence"
assert_not_contains "the stack block is not reached after an ADR failure" "$STACK_MSG"
t_check_exec "project mode"
t_cleanup
}

sec_project
t_finish
