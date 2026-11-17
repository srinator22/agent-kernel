#!/usr/bin/env bash
# start-reset-lessons.sh: the template's lessons files reset to their format
# headers (docs/procedures/start.md step 6), --check, idempotence, CRLF, and
# the refusals that leave every file untouched (.start-done, uncommitted
# changes, a missing file, a file with no format block, usage).
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" || { echo "$0: cannot load lib.sh; stopped before writing anything" >&2; exit 2; }

L=docs/lessons
FILES=(INDEX.md PENDING.md QUARANTINE.md UPSTREAM.md)

# fixture_from_template: a fixture repo holding the template's real lessons
# files, committed, so the reset is exercised on the content that leaked.
fixture_from_template() {
  make_fixture
  cp_script start-reset-lessons.sh lessons.sh
  mkdir -p "$L"
  local f
  for f in "${FILES[@]}"; do cp "$T_ROOT/$L/$f" "$L/$f"; done
  git add -A && git commit -qm fixture
}

# hashes: one line per lessons file, to prove a refusal wrote nothing.
hashes() { local f; for f in "${FILES[@]}"; do if [[ -f "$L/$f" ]]; then cksum < "$L/$f"; else echo missing; fi; done; }

# is_prefix NAME FILE ORIGINAL: the reset file is the first lines of ORIGINAL.
is_prefix() {
  local n
  n=$(( $(wc -l < "$2") ))
  assert_eq "$1" "$(cat "$2")" "$(head -n "$n" "$3")"
}

# --- Real template content ---------------------------------------------------
fixture_from_template
mkdir -p "$FIX.orig" && cp "$L"/*.md "$FIX.orig/"
run ./scripts/start-reset-lessons.sh --check
if grep -q '^- \[L[0-9][0-9]*\] [^<]' "$L/INDEX.md"; then
  assert_rc "--check fails while INDEX.md holds the template's lessons" 1
  assert_contains "--check names INDEX.md" "$L/INDEX.md: holds lines beyond its format header"
else
  t_na "--check on template lessons: this template holds no approved lessons; covered by the synthetic cases below"
fi
assert_eq "--check writes nothing" "$(cd "$FIX.orig" && for f in "${FILES[@]}"; do cksum < "$f"; done)" "$(hashes)"

run ./scripts/start-reset-lessons.sh
assert_rc "reset on the template files passes" 0
for f in "${FILES[@]}"; do is_prefix "$f keeps a leading part of the template file" "$L/$f" "$FIX.orig/$f"; done
assert_eq "INDEX.md keeps no lesson line except the format example" "1" "$(grep -c '^- \[L[0-9]' "$L/INDEX.md")"
assert_file_has "INDEX.md keeps the format example" "$L/INDEX.md" "retire-when: <condition>)"
assert_eq "PENDING.md keeps no entry heading" "0" "$(grep -c '^### ' "$L/PENDING.md")"
assert_eq "PENDING.md ends with the last format field" "- retire-when:" "$(tail -n 1 "$L/PENDING.md")"
assert_eq "UPSTREAM.md keeps no entry heading" "0" "$(grep -c '^### ' "$L/UPSTREAM.md")"
assert_eq "UPSTREAM.md ends with the last format field" "- applies to: core | <profile name>" "$(tail -n 1 "$L/UPSTREAM.md")"
assert_eq "QUARANTINE.md ends with its empty-state line" "No quarantined tests." "$(tail -n 1 "$L/QUARANTINE.md")"
assert_file_has "QUARANTINE.md keeps its last format field" "$L/QUARANTINE.md" "- owner task (BACKLOG.md item or task slug):"
run ./scripts/lessons.sh check
assert_contains "lessons.sh reads the reset INDEX.md without a lesson problem" "lessons"
assert_not_contains "lessons.sh finds no malformed lesson in the reset files" "INDEX.md:"
run ./scripts/start-reset-lessons.sh --check
assert_rc "--check passes after the reset" 0
before="$(hashes)"
git add -A && git commit -qm reset
run ./scripts/start-reset-lessons.sh
assert_rc "a second reset passes" 0
assert_contains "a second reset says so" "$L/INDEX.md: already the format header"
assert_eq "a second reset changes no byte" "$before" "$(hashes)"
case "$FIX.orig" in */template-selftest.*) rm -rf "$FIX.orig" ;; esac

# --- Synthetic files: exact header ---------------------------------------------
make_fixture
cp_script start-reset-lessons.sh
mkdir -p "$L"
printf '# Index\n\nIntro line.\n\nFormat:\n\n- [L001] <example> - <lesson\n  wrapped> (used: 0)\n\n- [L001] Real lesson - do it (used: 3, last: 2026-01-01, retire-when: x)\n- [L002] Another (used: 1, last: -, retire-when: y)\n' > "$L/INDEX.md"
printf '# Pending\n\nEntry format (all four fields required):\n\n- what happened:\n- retire-when:\n\n### An entry\n\n- what happened: x\n- retire-when: y\n' > "$L/PENDING.md"
printf '# Quarantine\n\nEntry format:\n\n- test path:\n- owner task:\n\n- test path: tests/a.sh\n- owner task: fix-a\n' > "$L/QUARANTINE.md"
printf '# Upstream\r\n\r\nEntry format:\r\n\r\n- what happened:\r\n- applies to: core\r\n\r\n### Entry\r\n\r\n- what happened: z\r\n' > "$L/UPSTREAM.md"
git add -A && git commit -qm fixture
run ./scripts/start-reset-lessons.sh
assert_rc "reset on synthetic files passes" 0
assert_eq "INDEX.md is exactly its header" "$(printf '# Index\n\nIntro line.\n\nFormat:\n\n- [L001] <example> - <lesson\n  wrapped> (used: 0)')" "$(cat "$L/INDEX.md")"
assert_eq "PENDING.md is exactly its header" "$(printf '# Pending\n\nEntry format (all four fields required):\n\n- what happened:\n- retire-when:')" "$(cat "$L/PENDING.md")"
assert_eq "QUARANTINE.md is its header and the empty-state line" "$(printf '# Quarantine\n\nEntry format:\n\n- test path:\n- owner task:\n\nNo quarantined tests.')" "$(cat "$L/QUARANTINE.md")"
# Bytes compared with cmp: Git Bash drops CRs inside command substitution.
printf '# Upstream\r\n\r\nEntry format:\r\n\r\n- what happened:\r\n- applies to: core\r\n' > "$FIX.crlf"
if cmp -s "$FIX.crlf" "$L/UPSTREAM.md"; then t_ok "a CRLF file keeps its CRs and loses its entries"; else t_bad "a CRLF file keeps its CRs and loses its entries"; od -c "$L/UPSTREAM.md" | sed 's/^/       | /'; fi
case "$FIX.crlf" in */template-selftest.*) rm -f "$FIX.crlf" ;; esac
assert_contains "the line counts are reported" "$L/INDEX.md: reset to the format header (11 -> 8 lines)"

# --- Refusals: nothing is written ------------------------------------------------
refusal_fixture() {
  make_fixture
  cp_script start-reset-lessons.sh
  mkdir -p "$L"
  local f
  for f in "${FILES[@]}"; do printf '# %s\n\nFormat:\n\n- field:\n\n- field: an entry\n' "$f" > "$L/$f"; done
  git add -A && git commit -qm fixture
}

refusal_fixture
echo "2026-11-17 started" > .start-done
before="$(hashes)"
run ./scripts/start-reset-lessons.sh
assert_rc ".start-done refuses with exit 2" 2
assert_contains ".start-done refusal says start already ran" "start already ran"
assert_eq ".start-done refusal writes nothing" "$before" "$(hashes)"
run ./scripts/start-reset-lessons.sh --check
assert_rc ".start-done refuses --check too" 2

refusal_fixture
echo "- field: uncommitted entry" >> "$L/PENDING.md"
before="$(hashes)"
run ./scripts/start-reset-lessons.sh
assert_rc "uncommitted changes refuse with exit 1" 1
assert_contains "the uncommitted file is named" "$L/PENDING.md"
assert_eq "an uncommitted change in one file leaves every file untouched" "$before" "$(hashes)"

refusal_fixture
printf '# Lessons\n\nNo format block here.\n- [L001] x\n' > "$L/INDEX.md"
git add -A && git commit -qm noformat
before="$(hashes)"
run ./scripts/start-reset-lessons.sh
assert_rc "a file with no format block refuses with exit 1" 1
assert_contains "the file with no format block is named" "$L/INDEX.md has no format block"
assert_eq "a file with no format block leaves every file untouched" "$before" "$(hashes)"

refusal_fixture
printf '# Lessons\n\nFormat:\n\n' > "$L/INDEX.md"
git add -A && git commit -qm emptyformat
before="$(hashes)"
run ./scripts/start-reset-lessons.sh
assert_rc "a Format line with no field lines refuses with exit 1" 1
assert_eq "an empty format block leaves every file untouched" "$before" "$(hashes)"

refusal_fixture
git rm -q "$L/UPSTREAM.md" && git commit -qm drop
before="$(hashes)"
run ./scripts/start-reset-lessons.sh
assert_rc "a missing file refuses with exit 1" 1
assert_contains "the missing file is named" "$L/UPSTREAM.md is missing"
assert_eq "a missing file leaves the others untouched" "$before" "$(hashes)"

run ./scripts/start-reset-lessons.sh --apply
assert_rc "an unknown argument is a usage error" 2
run ./scripts/start-reset-lessons.sh --check extra
assert_rc "an extra argument is a usage error" 2

t_finish
