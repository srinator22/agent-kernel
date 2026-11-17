#!/usr/bin/env bash
# profiles.sh: the one "- Profiles:" parser. Forms adopted (allow) and forms
# that adopt nothing or stop the list (refuse), per lesson L012; template-sync
# and lessons.sh must print the same set for the same line.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" || { echo "$0: cannot load lib.sh; stopped before writing anything" >&2; exit 2; }

make_fixture
cp_script profiles.sh

# adopted LINE: the parsed names for one Profiles line, space-joined.
adopted() {
  printf '# Agents\n\n## Project decisions\n\n%s\n- Other: x\n' "$1" > AGENTS.md
  scripts/profiles.sh adopted | tr '\n' ' ' | sed 's/ $//'
}

# ---- allow: forms that adopt names ----
assert_eq "one name" "software" "$(adopted '- Profiles: software')"
assert_eq "comma list" "software data-analysis" "$(adopted '- Profiles: software, data-analysis')"
assert_eq "a trailing sentence after a period adopts nothing more" "software data-analysis" \
  "$(adopted '- Profiles: software, data-analysis. hardware-pcb deferred')"
assert_eq "a semicolon ends the list" "software hardware-pcb" \
  "$(adopted '- Profiles: software, hardware-pcb; scientific later')"
assert_eq "bracketed remarks are dropped, even with a period inside" "software embedded-firmware" \
  "$(adopted '- Profiles: software (always, see docs/profiles/README.md), embedded-firmware')"
assert_eq "backticks are dropped" "software scientific" "$(adopted '- Profiles: `software`, `scientific`')"
assert_eq "and separates like a comma" "software scientific data-analysis" \
  "$(adopted '- Profiles: software, scientific and data-analysis')"
assert_eq "names are lowercased" "software data-analysis" "$(adopted '- Profiles: Software, Data-Analysis')"
assert_eq "duplicates print once" "software" "$(adopted '- Profiles: software, software')"
printf '# Agents\r\n- Profiles: software, scientific\r\n' > AGENTS.md
assert_eq "CRLF line" "software scientific" "$(scripts/profiles.sh adopted | tr '\n' ' ' | sed 's/ $//')"
printf -- '- Profiles: software\n- Profiles: scientific\n' > AGENTS.md
assert_eq "only the first Profiles line counts" "software" "$(scripts/profiles.sh adopted | tr '\n' ' ' | sed 's/ $//')"
printf -- '- Profiles: data-analysis\n' > other.md
assert_eq "FILE argument" "data-analysis" "$(scripts/profiles.sh adopted other.md)"

# ---- refuse: forms that adopt nothing or stop the list ----
assert_eq "template placeholder adopts nothing" "" \
  "$(adopted '- Profiles: {{FILLED_BY_START - software always; add scientific as adopted}}')"
assert_eq "none adopts nothing" "" "$(adopted '- Profiles: none')"
assert_eq "prose stops the list at the first non-name item" "software" \
  "$(adopted '- Profiles: software, hardware-pcb deferred until the board exists')"
assert_eq "a sentence as the first item adopts nothing" "" \
  "$(adopted '- Profiles: to be decided at start')"
assert_eq "an empty value adopts nothing" "" "$(adopted '- Profiles:')"
assert_eq "an indented Profiles line is not the line" "" "$(adopted '  - Profiles: software')"
printf '# Agents\n' > AGENTS.md
assert_eq "no Profiles line adopts nothing" "" "$(scripts/profiles.sh adopted)"
run scripts/profiles.sh adopted missing.md
assert_rc "a missing file exits 0" 0
assert_eq "a missing file prints nothing" "" "$OUT"

# ---- usage ----
run scripts/profiles.sh
assert_rc "no command is a usage error" 2
run scripts/profiles.sh adopted a b
assert_rc "two files are a usage error" 2
run scripts/profiles.sh other
assert_rc "an unknown command is a usage error" 2
run scripts/profiles.sh --help
assert_rc "--help exits 0" 0
assert_contains "--help names the command" "profiles.sh adopted"

# ---- template-sync uses this parser: the same line, the same set ----
# template-sync also requires a profile folder; give each parsed name one.
# The template is a second repository inside the fixture, ignored by the
# project (make_fixture removes the previous fixture, so it cannot live there).
make_fixture
TPLDIR="$FIX/tpl"
mkdir -p "$TPLDIR/scripts"
git -C "$TPLDIR" init -q >/dev/null 2>&1
git -C "$TPLDIR" config user.email selftest@example.invalid
git -C "$TPLDIR" config user.name selftest
git -C "$TPLDIR" config core.autocrlf false
for s in profiles.sh template-sync.sh kernel-hash.sh; do cp "$T_ROOT/scripts/$s" "$TPLDIR/scripts/$s"; chmod +x "$TPLDIR/scripts/$s"; done
for p in software data-analysis hardware-pcb; do mkdir -p "$TPLDIR/docs/profiles/$p"; echo "# $p" > "$TPLDIR/docs/profiles/$p/PROFILE.md"; done
printf '# Agents\n- Profiles: software, data-analysis. hardware-pcb deferred\n' > "$TPLDIR/AGENTS.md"
git -C "$TPLDIR" add -A >/dev/null 2>&1 && git -C "$TPLDIR" commit -q -m tpl >/dev/null 2>&1
cp_script profiles.sh template-sync.sh kernel-hash.sh
cp -r "$TPLDIR/docs" docs
cp "$TPLDIR/AGENTS.md" AGENTS.md
printf 'tpl/\n' > .gitignore
git add -A >/dev/null 2>&1 && git commit -q -m proj >/dev/null 2>&1
run scripts/template-sync.sh --template "$TPLDIR" --dry-run
assert_contains "template-sync adopts what profiles.sh parses" "adopted profiles (reported as DIFF, never applied): software data-analysis "
assert_not_contains "template-sync does not adopt the deferred profile" "data-analysis hardware-pcb"
rm -f scripts/profiles.sh
run scripts/template-sync.sh --template "$TPLDIR" --dry-run
assert_contains "without a project copy template-sync uses the template's parser" "adopted profiles (reported as DIFF, never applied): software data-analysis "

t_finish
