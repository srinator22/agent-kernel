#!/usr/bin/env bash
# check.sh: the "always" section (style, memory caps, task graph, selftest when
# tests/template exists) runs in project mode as well as template mode, and
# --quick never skips it. Project mode is a fixture with a fake .start-done and a
# minimal AGENTS.md; a clean fixture reaches the unwired stack block and fails
# there. Template mode is a fixture with every required file stubbed and exits 0.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

EM="$(printf '\xe2\x80\x94')"
STACK_MSG="the stack gauntlet is not wired"

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

# ---- project mode ----
make_fixture
cp_script check.sh kernel-hash.sh lessons.sh taskgraph.sh
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
t_cleanup

# ---- project mode with tests/template present: selftest runs in the always section ----
make_fixture
cp_script check.sh kernel-hash.sh lessons.sh taskgraph.sh selftest.sh
write_agents
./scripts/kernel-hash.sh --update >/dev/null
touch .start-done
write_task
mkdir -p tests/template
printf '#!/usr/bin/env bash\nexit 0\n' > tests/template/test_ok.sh
commit_fixture
run ./scripts/check.sh
assert_contains "selftest runs in project mode when tests/template exists" "selftest: 1 passed, 0 failed"
printf '#!/usr/bin/env bash\nexit 1\n' > tests/template/test_ok.sh
commit_fixture
run ./scripts/check.sh --quick
assert_rc "a failing selftest fails project mode, even with --quick" 1
assert_contains "the selftest failure is reported" "scripts/selftest.sh failed"
t_cleanup

# ---- template mode: a clean fixture still exits 0 ----
make_fixture
cp_script check.sh kernel-hash.sh lessons.sh taskgraph.sh selftest.sh
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
    scripts/*.sh|tests/template/*.sh) printf '#!/usr/bin/env bash\nexit 0\n' > "$f" ;;
    .claude/agents/*.md|.claude/skills/*/SKILL.md|.agents/skills/*/SKILL.md)
      printf -- '---\nname: x\ndescription: y\n---\n' > "$f" ;;
    .codex/agents/*.toml)
      printf 'name = "x"\ndescription = "y"\ndeveloper_instructions = "z"\n' > "$f" ;;
    .claude/settings.json) echo '{}' > "$f" ;;
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
run ./scripts/check.sh --quick
assert_rc "template mode with --quick exits 0" 0

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
t_cleanup

# ---- a started project: the real tree, check.sh wired to a stack, passes ----
# This scenario copies the whole repository, so the nested selftest must not
# recurse into it again: T_NESTED marks the inner run.
if [[ -z "${T_NESTED:-}" ]]; then
  make_fixture
  (cd "$T_ROOT" && git ls-files -co --exclude-standard -z | grep -zv '^[.]work/template-sync/' | tar --null -T - -cf -) | tar -xf -
  cp "$T_CHECK" scripts/check.sh
  # start.md step 3: fill the stack placeholders and delete the final fail line.
  sed -i.bak -e 's/^#  *[0-9]*[.] .*{{[A-Z_]*FILLED_BY_START.*$/true  # stack step wired by the fixture/' -e '/^fail ".start-done exists but the stack gauntlet is not wired/d' scripts/check.sh && rm -f scripts/check.sh.bak
  # start.md step 4: the Profiles line and the template status line.
  sed -i.bak -e 's/^- Profiles: {{FILLED_BY_START.*$/- Profiles: software/' -e '/^Status: TEMPLATE/d' AGENTS.md && rm -f AGENTS.md.bak
  ./scripts/kernel-hash.sh --update >/dev/null
  touch .start-done
  commit_fixture
  export T_NESTED=1
  run ./scripts/check.sh --quick
  unset T_NESTED
  assert_rc "a started project passes check.sh with tests/template kept" 0
  assert_contains "the nested selftest ran and passed" " passed, 0 failed ("
  assert_not_contains "no nested test file failed" "FAIL  tests/template/"
  assert_not_contains "the stack block is wired" "$STACK_MSG"
  t_cleanup
fi

t_finish
