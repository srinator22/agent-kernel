#!/usr/bin/env bash
# check.sh: the "always" section (style, memory caps, task graph, ADR format,
# selftest when tests/template exists) runs in project mode as well as template mode, and
# --quick never skips it. Project mode is a fixture with a fake .start-done and a
# minimal AGENTS.md; a clean fixture reaches the unwired stack block and fails
# there. Template mode is a fixture with every required file stubbed and exits 0.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" || { echo "$0: cannot load lib.sh; stopped before writing anything" >&2; exit 2; }

EM="$(printf '\xe2\x80\x94')"
STACK_MSG="scripts/stack-check.sh is missing"

write_task() { mkdir -p .work; printf '# Task: fixture

## Plan
1. a flat plan
' > .work/TASK.md; }
commit_fixture() { git add -A >/dev/null 2>&1 && git update-index --chmod=+x scripts/*.sh >/dev/null 2>&1 && git commit -q -m fixture >/dev/null 2>&1; }

write_agents() {
  cat > AGENTS.md <<'AG'
# Agents

<!-- KERNEL:BEGIN -->
1. Fixture kernel.
<!-- KERNEL:END -->

## Project decisions
- Profiles: software
AG
}

sec_project() {
# ---- project mode ----
make_fixture
cp_script check.sh kernel-hash.sh lessons.sh taskgraph.sh adr.sh tasklint.sh doc-eval.sh
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

sec_selftest() {
# ---- project mode with tests/template present: selftest runs in the always section ----
make_fixture
cp_script check.sh kernel-hash.sh lessons.sh taskgraph.sh adr.sh tasklint.sh doc-eval.sh selftest.sh
write_agents
./scripts/kernel-hash.sh --update >/dev/null
touch .start-done
write_task
mkdir -p tests/template
printf '#!/usr/bin/env bash\nexit 0\n' > tests/template/test_ok.sh
chmod +x tests/template/test_ok.sh
commit_fixture
run ./scripts/check.sh
assert_contains "selftest runs in project mode when tests/template exists" "selftest: 1 passed, 0 failed, 0 quarantined (1 test files)"
printf '#!/usr/bin/env bash\nexit 1\n' > tests/template/test_ok.sh
chmod +x tests/template/test_ok.sh
commit_fixture
run ./scripts/check.sh --quick
assert_rc "a failing selftest fails project mode, even with --quick" 1
assert_contains "the selftest failure is reported" "scripts/selftest.sh failed"
t_check_exec "project mode with tests/template"
t_cleanup
}

sec_template() {
# ---- template mode: a clean fixture still exits 0 ----
make_fixture
cp_script check.sh kernel-hash.sh lessons.sh taskgraph.sh adr.sh selftest.sh tasklint.sh
# The required list is read from the real check.sh so the fixture cannot drift.
mapfile -t REQUIRED < <(sed -n '/^  required=(/,/^  )/p' "$T_CHECK" | sed '1d;$d' | tr -s ' ' '\n' | sed '/^$/d')
BP="docs/BLUEPRINT.md"
mkdir -p docs
{
  echo "# Blueprint"
  echo
  echo "## 2. Repository tree"
  echo
  echo '```'
  for f in "${REQUIRED[@]}"; do echo "$f"; done
  echo '```'
  echo
  echo "## 3. File specifications"
} > "$BP"
for f in "${REQUIRED[@]}"; do
  [[ -e "$f" ]] && continue
  mkdir -p "$(dirname "$f")"
  case "$f" in
    # Executable on disk, not only in the index: check.sh runs some of these
    # stubs directly, and Linux refuses a file without the x bit (Git Bash on
    # Windows does not, which hid this until CI).
    scripts/*.sh|tests/template/*.sh) printf '#!/usr/bin/env bash\nexit 0\n' > "$f"; chmod +x "$f" ;;
    .claude/agents/*.md|.claude/skills/*/SKILL.md|.agents/skills/*/SKILL.md)
      printf -- '---\nname: x\ndescription: y\n---\n' > "$f" ;;
    .codex/agents/*.toml)
      printf 'name = "x"\ndescription = "y"\ndeveloper_instructions = "z"\n' > "$f" ;;
    .claude/settings.json) echo '{}' > "$f" ;;
    docs/decisions/*.md)
      printf '# %s - Stub\n\nDate: 2026-01-01\nStatus: accepted\n\n## Context\n\n## Decision\n\n## Consequences\n' "$(basename "$f" | cut -c1-4)" > "$f" ;;
    .work/TASK.md) printf '# Task: fixture\n\n## Budget\n' > "$f" ;;
    CLAUDE.md) echo '@AGENTS.md' > "$f" ;;
    *) echo "stub" > "$f" ;;
  esac
done
cp "$T_CHECK" scripts/check.sh
mkdir -p tests/template/fixtures && cp "$T_CHECK" tests/template/fixtures/check.sh
printf 'models\nexplore: no Codex counterpart\n' > docs/rules/models.md
cat > AGENTS.md <<'AG'
# Agents

<!-- KERNEL:BEGIN -->
1. Fixture kernel.
<!-- KERNEL:END -->

Status: TEMPLATE
- Profiles: {{FILLED_BY_START}}
AG
./scripts/kernel-hash.sh --update >/dev/null
commit_fixture

run ./scripts/check.sh
assert_rc "template mode exits 0 on a clean fixture" 0
assert_contains "template mode reports success" "template self-test: OK"
assert_contains "template mode ran the always section" "lessons: OK"
# No self-test may reach a real ruff runner or the network (lib.sh exports the fake).
assert_contains "the ruff step names the fake runner and its version" "template ruff: TEMPLATE_RUFF ($TEMPLATE_RUFF), ruff 0.16.10 (fake-ruff.sh)"
run ./scripts/check.sh --quick
assert_rc "template mode with --quick exits 0" 0

# ---- 4i in template mode, and the register files in the required list ----
for f in scripts/feedback-log.sh scripts/preferences.sh scripts/dream/feedback.py scripts/dream/preferences.py          docs/preferences/README.md docs/procedures/preferences.md tests/template/test_feedback.sh tests/template/test_preferences.sh; do
  req=0
  for r in "${REQUIRED[@]}"; do [[ "$r" == "$f" ]] && req=1; done
  assert_eq "$f is in the required list" "1" "$req"
done
printf '#!/usr/bin/env bash
echo "preferences stub ran: $*"
exit "${PREFS_RC:-0}"
' > scripts/preferences.sh
commit_fixture
run ./scripts/check.sh --quick
assert_rc "template mode with a passing register check exits 0" 0
assert_contains "template mode runs the register check" "preferences stub ran: check"
PREFS_RC=1 run ./scripts/check.sh --quick
assert_rc "a failing register check fails template mode" 1
assert_contains "template mode names the register failure" "scripts/preferences.sh check failed"
printf '#!/usr/bin/env bash
exit 0
' > scripts/preferences.sh
commit_fixture

# A13: the shipped settings wire the feedback hook for UserPromptSubmit with a
# 5 second budget. Read from the real tree: a started project customises its
# own settings and merges the entry by hand (docs/procedures/upstream.md).
if [[ -f "$T_ROOT/.start-done" ]]; then
  t_na "the real settings.json wires the feedback hook with timeout 5: this repository is a started project (.start-done); its settings are its own"
else
  wired="$(awk '/"UserPromptSubmit"/{u=1} /"PreToolUse"/{u=0} u && /scripts\/feedback-log\.sh/{f=1} f && /"timeout": 5,?$/{print "wired"; exit}' "$T_ROOT/.claude/settings.json")"
  assert_eq "the real settings.json runs scripts/feedback-log.sh on UserPromptSubmit with timeout 5" "wired" "$wired"
fi

# ---- 5k: template Python, under a folder ruff.toml, passes the pinned ruff ----
RLOG="$FIX/ruff.log"
FAKE_RUFF_LOG="$RLOG" run ./scripts/check.sh --quick
assert_file_has "ruff check runs on the folders with a ruff.toml" "$RLOG" "|check --no-cache --quiet docs/library docs/profiles scripts/dream"
assert_file_has "ruff format --check guards the format exclusion" "$RLOG" "|format --no-cache --check --quiet docs/library docs/profiles scripts/dream"
assert_eq "both also run from a scratch root with a strict config" "2" "$(grep -c '/template-ruff\.[^|]*|' "$RLOG")"
FAKE_RUFF_CHECK_RC=1 run ./scripts/check.sh --quick
assert_rc "a ruff finding fails template mode" 1
assert_contains "the ruff check failure is named" "ruff check failed on the template's Python"
FAKE_RUFF_FORMAT_RC=2 run ./scripts/check.sh --quick
assert_rc "a ruff config error fails template mode" 1
assert_contains "the ruff format failure is named" "ruff format --check failed on the template's Python"
FAKE_RUFF_SCRATCH_RC=1 run ./scripts/check.sh --quick
assert_rc "a strict root config that wins over the folder config fails" 1
assert_contains "the override failure is named" "a strict project-root ruff config overrides a folder ruff.toml"
FAKE_RUFF_VERSION_RC=1 run ./scripts/check.sh --quick
assert_rc "a runner that fails fails the step" 1
assert_contains "the runner failure is named" "could not run ruff 0.16.10 through TEMPLATE_RUFF"
mkdir -p tools && echo "x = 1" > tools/loose.py && echo "x = 1" > top.py && echo "stub" > ruff.toml
commit_fixture
run ./scripts/check.sh --quick
assert_rc "template Python outside a folder ruff.toml fails" 1
assert_contains "the uncovered file is named" "tools/loose.py is template Python outside a folder with its own ruff.toml"
assert_contains "a root ruff.toml does not cover a root file" "top.py is template Python outside a folder with its own ruff.toml"
git rm -q -f tools/loose.py top.py ruff.toml && git commit -q -m "remove loose python" >/dev/null 2>&1

# ---- 5l: no script pipes into head (exit 141 once the writer outlives head) ----
printf '#!/usr/bin/env bash\nset -o pipefail\nls | head -n 1\n# a comment | head is fine\n' > scripts/pipes.sh
commit_fixture
run ./scripts/check.sh --quick
assert_rc "a script that pipes into head fails template mode" 1
assert_contains "the script and line are named" "scripts/pipes.sh:3:"
assert_not_contains "a comment that mentions it is not flagged" "scripts/pipes.sh:4:"
git rm -q -f scripts/pipes.sh && git commit -q -m "remove pipes" >/dev/null 2>&1

printf 'bad %s dash\n' "$EM" > notes.txt
commit_fixture
run ./scripts/check.sh
assert_rc "a dash fails template mode" 1
assert_contains "template mode reports the dash" "em or en dash found"
assert_contains "template mode also reports the template self-test failure" "template self-test found the problems"
git rm -q -f notes.txt && git commit -q -m "remove notes" >/dev/null 2>&1
echo "drift" >> tests/template/fixtures/check.sh
commit_fixture
run ./scripts/check.sh
assert_rc "a drifted check.sh fixture fails template mode" 1
assert_contains "the drift is named" "tests/template/fixtures/check.sh is not identical to scripts/check.sh"
t_check_exec "template mode"
t_cleanup
}

sec_started() {
# ---- a started project: the template tree, check.sh wired to a stack, passes ----
# A fact about the template's own tree, so it runs only in template mode. In a
# started project this repository IS the started project, and its own
# ./scripts/check.sh run is the proof; copying it again would recurse and test
# the project's tree against the template's expectations.
if [[ -f "$T_ROOT/.start-done" ]]; then
  t_na "a started project passes check.sh with tests/template kept: this repository is a started project (.start-done); covered by its own ./scripts/check.sh run"
else
  # Both branches of the real-tree parity case are asserted: here, on the
  # template tree, it runs; in the started copy below it prints n/a.
  run bash "$T_ROOT/tests/template/test_blueprint_parity.sh"
  assert_contains "on the template tree the real parity case runs" "ok   the real blueprint and required list agree"
  assert_not_contains "on the template tree no case is n/a" "n/a  "
  make_fixture
  # Real started projects lack the template's catalogs and question file.
  (cd "$T_ROOT" && git ls-files -co --exclude-standard -z | grep -zv '^[.]work/template-sync/\|^docs/library/\|^docs/roster/\|^tests/docs/questions\.md$' | tar --null -T - -cf -) | tar -xf -
  cp "$T_CHECK" scripts/check.sh
  # start.md step 3: the stack steps go into the project-owned stack-check.sh.
  printf '#!/usr/bin/env bash\necho "stack steps wired by the fixture"\n' > scripts/stack-check.sh
  chmod +x scripts/stack-check.sh
  # start.md step 4: the Profiles, Template and status lines, and the sync record.
  sed -i.bak -e 's/^- Profiles: {{FILLED_BY_START.*$/- Profiles: software\n- Template: https:\/\/example.invalid\/template.git template-v0.1.0/' -e '/^Status: TEMPLATE/d' AGENTS.md && rm -f AGENTS.md.bak
  echo "template-sync: template-v0.1.0 2026-11-07" > docs/lessons/MAINTENANCE.log
  ./scripts/kernel-hash.sh --update >/dev/null
  touch .start-done
  # Keep the template's index modes: where git does not track file modes
  # (core.fileMode false, the Windows default) a fresh add records 100644 and
  # the copy's test_test_files.sh would see every test as not executable.
  git add -A >/dev/null 2>&1
  while IFS= read -r -d '' p; do
    [[ -e "$p" ]] && git update-index --chmod=+x -- "$p" >/dev/null 2>&1
  done < <(cd "$T_ROOT" && git ls-files -s -z | sed -z -n 's/^100755 [0-9a-f]* [0-9]*\t//p')
  commit_fixture
  run ./scripts/check.sh --quick
  assert_rc "a started project passes check.sh with tests/template kept" 0
  assert_contains "the nested selftest ran and passed" " passed, 0 failed, 0 quarantined ("
  assert_not_contains "no nested test file failed" "FAIL  tests/template/"
  assert_not_contains "the stack block is wired" "$STACK_MSG"
  assert_contains "the nested parity test says its real-tree case does not apply" "n/a  the real blueprint and required list agree: this repository is a started project"
  assert_contains "the nested check-always test says its started-project case does not apply" "n/a  a started project passes check.sh with tests/template kept: this repository is a started project"
  t_check_exec "started project"
  t_cleanup
fi
}

# The four sections build their own fixtures and share nothing, so they run
# side by side; the slow check.sh runs in each overlap.
t_parallel "project mode" sec_project
t_parallel "project mode with tests/template" sec_selftest
t_parallel "template mode" sec_template
t_parallel "started project" sec_started
t_parallel_wait

t_finish
