#!/usr/bin/env bash
# test_style_scan.sh: check.sh step 4a (dash and character scans).
# Inputs: the template check.sh copied into hermetic fixture repos.
# Covers: untracked files are scanned (ignored ones are not), tests/style-exempt.list
# exempts files and folders, a stale entry and a wildcard entry fail, the
# portable fallback finds both dashes and a typographic character when PCRE is
# forced off, and a host with no scanner fails red outside CI and defers in CI.
# Non-ASCII characters are built at run time, never typed.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" || { echo "$0: cannot load lib.sh; stopped before writing anything" >&2; exit 2; }

EN="$(printf '\xe2\x80\x93')"
EM="$(printf '\xe2\x80\x94')"
CURLY="$(printf '\xe2\x80\x9c')"
DASH_MSG="em or en dash found; plain hyphens only"
CHAR_MSG="typographic or mis-encoded character found"

# A project-mode fixture reaches the unwired stack block and fails there, so
# the cases below read the step 4a messages, never the exit code of the whole
# run: DASH_MSG and CHAR_MSG appear exactly when step 4a failed.
build() {
  make_fixture
  cp_script check.sh kernel-hash.sh lessons.sh profiles.sh taskgraph.sh adr.sh tasklint.sh doc-eval.sh
  cat > AGENTS.md <<'AG'
# Agents

<!-- KERNEL:BEGIN -->
1. Fixture kernel.
<!-- KERNEL:END -->

## Project decisions
- Profiles: software
AG
  local d
  for d in .claude .agents; do
    mkdir -p "$d/skills/verify"
    printf -- '---\nname: verify\ndescription: fixture\n---\nRun the fixture.\n' > "$d/skills/verify/SKILL.md"
  done
  ./scripts/kernel-hash.sh --update >/dev/null
  mkdir -p .work tests
  printf '# Task: fixture\n\n## Plan\n1. a flat plan\n' > .work/TASK.md
  echo "src" > src.txt
  touch .start-done
  git add -A >/dev/null 2>&1
  git ls-files -z -- 'scripts/*.sh' | xargs -0 git update-index --chmod=+x -- >/dev/null 2>&1
  git commit -q -m fixture >/dev/null 2>&1
}

build
run ./scripts/check.sh
assert_not_contains "a clean tree passes the dash scan" "$DASH_MSG"
assert_not_contains "a clean tree passes the character scan" "$CHAR_MSG"

# ---- untracked, not ignored: scanned ----
printf 'a %s b\n' "$EN" > new.txt
run ./scripts/check.sh
assert_contains "an untracked file with an en dash fails" "$DASH_MSG"
assert_contains "the untracked file is named" "new.txt"
echo "new.txt" > .gitignore
git add .gitignore && git commit -q -m ignore >/dev/null 2>&1
run ./scripts/check.sh
assert_not_contains "an ignored untracked file is not scanned" "$DASH_MSG"
rm -f new.txt .gitignore; git add -A >/dev/null 2>&1; git commit -q -m clean >/dev/null 2>&1

# ---- exemption list ----
mkdir -p vendor
printf 'x %s y\n' "$EM" > vendor/lib.txt
printf 'x %s y\n' "$CURLY" > vendor/lib2.txt
git add -A >/dev/null 2>&1; git commit -q -m vendor >/dev/null 2>&1
run ./scripts/check.sh
assert_contains "a tracked file with an em dash fails" "$DASH_MSG"
assert_contains "a tracked file with a curly quote fails" "$CHAR_MSG"
printf '# comment\n\nvendor/\n' > tests/style-exempt.list
git add -A >/dev/null 2>&1; git commit -q -m exempt >/dev/null 2>&1
run ./scripts/check.sh
assert_not_contains "an exempted folder skips the dash scan" "$DASH_MSG"
assert_not_contains "an exempted folder skips the character scan" "$CHAR_MSG"
assert_not_contains "no stale exemption is reported" "stale exemption"
printf 'vendor/lib.txt\n' > tests/style-exempt.list
run ./scripts/check.sh
assert_not_contains "an exempted file skips the dash scan" "$DASH_MSG"
assert_contains "the file not on the list still fails the character scan" "$CHAR_MSG"

printf 'vendor/\nvendor/gone.txt\n' > tests/style-exempt.list
run ./scripts/check.sh
assert_contains "a stale exemption fails" "stale exemption 'vendor/gone.txt'"
printf 'vendor/*\n' > tests/style-exempt.list
run ./scripts/check.sh
assert_contains "a wildcard entry is refused" "is a wildcard or pathspec magic"
# "." or "./" would exclude the whole tree and switch the scan off silently.
for whole in . ./ /; do
  printf '%s\n' "$whole" > tests/style-exempt.list
  run ./scripts/check.sh
  assert_contains "an entry naming the whole tree ($whole) is refused" "names the whole tree"
done
printf 'vendor/\n' > tests/style-exempt.list
# The list exempts only what it names: an untracked file elsewhere is still scanned.
printf 'x %s y\n' "$EN" > loose.txt
run ./scripts/check.sh
assert_contains "an untracked file outside the exemption still fails" "$DASH_MSG"
rm -f loose.txt

# ---- the portable fallback (PCRE forced off) ----
printf '# none\n' > tests/style-exempt.list
export CHECK_FORCE_NO_PCRE=1
run ./scripts/check.sh
assert_contains "the fallback finds the tracked em dash" "$DASH_MSG"
assert_contains "the fallback finds the curly quote" "$CHAR_MSG"
assert_not_contains "the fallback does not defer" "deferred"
printf 'vendor/\n' > tests/style-exempt.list
run ./scripts/check.sh
assert_not_contains "the fallback honours the exemption list" "$DASH_MSG"
rm -rf vendor; git add -A >/dev/null 2>&1; git commit -q -m novendor >/dev/null 2>&1
printf '# none\n' > tests/style-exempt.list
printf 'a %s b\n' "$EN" > en.txt
run ./scripts/check.sh
assert_contains "the fallback finds an untracked en dash" "$DASH_MSG"
rm -f en.txt
printf 'a %s b\n' "$EM" > em.txt
run ./scripts/check.sh
assert_contains "the fallback finds an untracked em dash" "$DASH_MSG"
rm -f em.txt
run ./scripts/check.sh
assert_not_contains "the fallback passes a clean tree (dash)" "$DASH_MSG"
assert_not_contains "the fallback passes a clean tree (characters)" "$CHAR_MSG"

# ---- no scanner at all: red outside CI, deferred in CI ----
export CHECK_FORCE_NO_FALLBACK=1
unset CI
run ./scripts/check.sh
assert_contains "no scanner outside CI fails red" "cannot scan for dashes"
CI=true run ./scripts/check.sh
assert_contains "no scanner in CI defers with a warning" "check deferred"
assert_not_contains "no scanner in CI does not fail on it" "cannot scan for"
unset CHECK_FORCE_NO_PCRE CHECK_FORCE_NO_FALLBACK

t_finish
