#!/usr/bin/env bash
# check.sh always section, template mode: a fixture with every required file
# stubbed exits 0, and each template-only step fails on its own defect.
# Shared fixtures: check_always_lib.sh.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" || { echo "$0: cannot load lib.sh; stopped before writing anything" >&2; exit 2; }
source "$(dirname "${BASH_SOURCE[0]}")/check_always_lib.sh" || { echo "$0: cannot load check_always_lib.sh; stopped before writing anything" >&2; exit 2; }

sec_template() {
# ---- template mode: a clean fixture still exits 0 ----
make_fixture
cp_script check.sh kernel-hash.sh lessons.sh profiles.sh taskgraph.sh adr.sh selftest.sh tasklint.sh
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
assert_contains "a clean full run names the tree it verified" "check.sh: verified tree "
assert_contains "template mode ran the always section" "lessons: OK"
# No self-test may reach a real ruff runner or the network (lib.sh exports the fake).
assert_contains "the ruff step names the fake runner and its version" "template ruff: TEMPLATE_RUFF ($TEMPLATE_RUFF), ruff 0.16.10 (fake-ruff.sh)"
run ./scripts/check.sh --quick
assert_rc "template mode with --quick exits 0" 0

# ---- 4i in template mode, and the register files in the required list ----
for f in scripts/feedback-log.sh scripts/preferences.sh scripts/dream/feedback.py scripts/dream/preferences.py          docs/preferences/README.md docs/procedures/preferences.md tests/template/test_feedback.sh tests/template/test_preferences.sh .codex/hooks.json scripts/codex-hook.cmd tests/template/test_codex_hooks.sh; do
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
for f in scripts/private-terms.sh tests/template/test_private_terms.sh; do
  req=0
  for r in "${REQUIRED[@]}"; do [[ "$r" == "$f" ]] && req=1; done
  assert_eq "$f is in the required list" "1" "$req"
done

# A13: the shipped settings wire the feedback hook for UserPromptSubmit with a
# 5 second budget. Read from the real tree: a started project customises its
# own settings and merges the entry by hand (docs/procedures/upstream.md).
if t_started; then
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

# ---- 5l: no script pipes into an early-exit grep, same SIGPIPE mechanism ----
# Lines 3 to 8 are refused forms; lines 9 to 14 are allowed forms.
cat > scripts/pipes.sh <<'PS'
#!/usr/bin/env bash
set -o pipefail
ls | grep -q x
ls | grep -Fxq -- x
ls | grep -E --quiet x
ls |grep -m 1 x
ls | grep --max-count=1 x
ls | grep -i --silent x
ls | grep -c x
grep -q x notes.txt
true || grep -q x notes.txt
grep -qx x <<< "$PATH"
# ls | grep -q x in a comment
ls | grep -v -e y
PS
commit_fixture
run ./scripts/check.sh --quick
assert_rc "a script that pipes into an early-exit grep fails template mode" 1
assert_contains "the early-exit grep failure is named" "a script pipes into an early-exit grep"
# Not "n": t_parallel's local n names this section's counts file.
for ln in 3 4 5 6 7 8; do assert_contains "refused form on line $ln is named" "scripts/pipes.sh:$ln:"; done
for ln in 9 10 11 12 13 14; do assert_not_contains "allowed form on line $ln is not flagged" "scripts/pipes.sh:$ln:"; done
git rm -q -f scripts/pipes.sh && git commit -q -m "remove pipes" >/dev/null 2>&1

# ---- 4f2: the executable bit in the git index covers tests/template here too ----
git update-index --chmod=-x tests/template/test_selftest.sh && git commit -q -m "test without x" >/dev/null 2>&1
run ./scripts/check.sh --quick
assert_rc "a test file without the executable bit in the index fails template mode" 1
assert_contains "template mode names the test file" "scripts lost the executable bit in the git index (git update-index --chmod=+x <file>): tests/template/test_selftest.sh"
commit_fixture

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

sec_template
t_finish
