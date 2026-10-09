#!/usr/bin/env bash
# check.sh blueprint parity: the section 2 tree of docs/BLUEPRINT.md and the
# required-file list agree in both directions, by full relative path (built by
# walking the tree's indentation), not by file name alone. The function is
# extracted from check.sh between its blueprint-parity markers.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

make_fixture
FUNC="$(sed -n '/^# BEGIN blueprint-parity/,/^# END blueprint-parity/p' "$T_CHECK")"
if [[ -z "$FUNC" ]]; then t_bad "check.sh has no blueprint-parity function"; t_finish; fi
eval "$FUNC"

parity() { OUT="$(blueprint_parity "$@" 2>&1)"; RC=$?; }
write_blueprint() {
  mkdir -p docs
  cat > docs/BLUEPRINT.md <<'BP'
# Blueprint

## 1. Principles

```
ignored/before.md
```

## 2. Repository tree

```
AGENTS.md                     # source of truth
.github/
  workflows/
    ci.yml                    # runs check.sh
docs/
  rules/                      # triggered rules
    a.md
  profiles/
    hardware/PROFILE.md       # two levels on one line
scripts/
  check.sh
.codex/
  agents/                     # summary entry: monitor.toml, worker.toml
dir/file.md                   # full path on one line
```

## 3. File specifications

```
ignored/after.md
```
BP
}
touch_files() {
  local f
  for f in "$@"; do mkdir -p "$(dirname "$f")"; echo x > "$f"; done
}

write_blueprint
touch_files AGENTS.md .github/workflows/ci.yml docs/rules/a.md docs/profiles/hardware/PROFILE.md scripts/check.sh dir/file.md
parity docs/BLUEPRINT.md AGENTS.md .github/workflows/ci.yml docs/rules/a.md docs/profiles/hardware/PROFILE.md scripts/check.sh dir/file.md
assert_eq "an agreeing tree and list report nothing" "" "$OUT"

parity docs/BLUEPRINT.md .codex/agents/monitor.toml .codex/agents/worker.toml
assert_eq "files under a summary directory entry are covered" "" "$OUT"

# Forward: a required file missing from the tree.
parity docs/BLUEPRINT.md docs/rules/b.md
assert_contains "a required file absent from the tree is reported" "does not list docs/rules/b.md by its full path"

# Strict paths: the same file name in another directory is not a match.
parity docs/BLUEPRINT.md scripts/a.md docs/ci.yml
assert_contains "a file name listed under another directory is not a match (1)" "does not list scripts/a.md"
assert_contains "a file name listed under another directory is not a match (2)" "does not list docs/ci.yml"

# Reverse: the tree lists a file that does not exist.
rm -f docs/rules/a.md
parity docs/BLUEPRINT.md AGENTS.md
assert_contains "a listed file missing from the repository is reported" "lists docs/rules/a.md but it does not exist"
assert_not_contains "an existing listed file is not reported" "lists scripts/check.sh"
assert_not_contains "a summary directory entry is not required to exist as a file" "lists .codex"
touch_files docs/rules/a.md

# Only section 2 counts.
parity docs/BLUEPRINT.md AGENTS.md
assert_not_contains "section 1 fences are not read" "before.md"
assert_not_contains "section 3 fences are not read" "after.md"

# The real blueprint and the real required list agree in both directions, run
# from the repository root.
cd "$T_ROOT" || exit 1
mapfile -t REAL < <(sed -n '/^  required=(/,/^  )/p' "$T_CHECK" | sed '1d;$d' | tr -s ' ' '\n' | sed '/^$/d')
parity docs/BLUEPRINT.md "${REAL[@]}"
assert_eq "the real blueprint and required list agree" "" "$OUT"

t_finish
