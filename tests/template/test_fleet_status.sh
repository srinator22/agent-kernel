#!/usr/bin/env bash
# fleet-status.sh: per-project template ref, last sync date and releases behind on a
# fixture template (tags 0.1.0, 0.2.0, 0.10.0 plus untagged commits, so version
# sort is exercised) and fixture projects: tagged, untagged-known, untagged-unknown,
# missing folder, no Template line, old URL, dirty, folder name with a space. Also:
# --tsv, CRLF list, comments, list from the main checkout seen from a linked
# worktree, exit codes, and that nothing is written inside any project.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" || { echo "$0: cannot load lib.sh; stopped before writing anything" >&2; exit 2; }

make_fixture
cp_script fleet-status.sh
git remote add origin https://github.com/example/tmpl.git
printf '# Agents\n' > AGENTS.md
commit() { git add -A >/dev/null 2>&1 && git commit -q -m "$1"; }
printf 'z\n' > z.txt; commit zero; PRE="$(git rev-parse HEAD)"
printf 'a\n' > a.txt; commit one; git tag template-v0.1.0
printf 'b\n' > b.txt; commit two; git tag template-v0.2.0
printf 'c\n' > c.txt; commit three; MID="$(git rev-parse HEAD)"
printf 'd\n' > d.txt; commit four; git tag template-v0.10.0
printf 'e\n' > e.txt; commit five

PRJ="$FIX/projects"
mkproj() { # dir templateline synced-ref
  mkdir -p "$1/docs/lessons"
  git init -q "$1" >/dev/null 2>&1
  git -C "$1" config user.email t@example.invalid
  git -C "$1" config user.name t
  git -C "$1" config core.autocrlf false
  printf '# P\n%s\n' "$2" > "$1/AGENTS.md"
  if [[ -n "${3:-}" ]]; then printf 'template-sync: old 2026-01-01\ntemplate-sync: %s 2026-10-0%s\n' "$3" "${4:-1}" > "$1/docs/lessons/MAINTENANCE.log"; fi
  git -C "$1" add -A >/dev/null 2>&1
  git -C "$1" commit -q -m init >/dev/null 2>&1
}
U=https://github.com/example/tmpl.git
mkproj "$PRJ/p_old" "- Template: $U template-v0.1.0" template-v0.1.0 3
mkproj "$PRJ/p_mid" "- Template: https://github.com/example/tmpl template-v0.2.0" template-v0.2.0
mkproj "$PRJ/p_cur" "- Template: $U template-v0.10.0" template-v0.10.0
echo dirty > "$PRJ/p_cur/untracked.txt"; echo more > "$PRJ/p_cur/untracked2.txt"
mkproj "$PRJ/p_known" "- Template: $U $MID"
mkproj "$PRJ/p_unknown" "- Template: $U deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
mkproj "$PRJ/p_noline" "# nothing here"
mkproj "$PRJ/p_badtag" "- Template: https://github.com/example/New-Project template-v0.2.0 plus source commit abc1234 (2026-10-29)."
mkproj "$PRJ/p_badsha" "- Template: $U $MID plus prose"
mkproj "$PRJ/p_badurl" "- Template: $U"
SIDE="$(git commit-tree "$(git rev-parse "$PRE^{tree}")" -p "$PRE" -m side)"
mkproj "$PRJ/p_side" "- Template: $U $SIDE"
mkproj "$PRJ/p_pretag" "- Template: $U $PRE plus prose"
mkproj "$PRJ/p_oldurl" "- Template: https://github.com/example/New-Project template-v0.2.0"
mkproj "$PRJ/p space" "- Template: $U template-v0.2.0"

LIST="$FIX/fleet.local.list"
{
  printf '# my projects\r\n\r\n'
  for p in p_old p_mid p_cur p_known p_unknown gone p_noline p_badtag p_badsha p_badurl p_pretag p_side p_oldurl "p space"; do printf '%s\r\n' "$PRJ/$p"; done
} > "$LIST"

before="$(cd "$PRJ" && find . -type f -o -type d | sort | tr '\n' ' ')"
run scripts/fleet-status.sh --tsv
assert_rc "tsv runs, exit 0 although projects lag" 0
after="$(cd "$PRJ" && find . -type f -o -type d | sort | tr '\n' ' ')"
assert_eq "no files created in projects" "$before" "$after"
TSV="$OUT"
col() { # project-suffix column-number
  printf '%s\n' "$TSV" | awk -F'\t' -v p="$1" -v c="$2" 'index($1, p) && NR > 1 && substr($1, length($1) - length(p) + 1) == p {print $c}'
}
assert_eq "tsv header" "project	ref	synced	behind	dirty	state	url" "$(printf '%s\n' "$TSV" | sed -n 1p)"
assert_eq "tagged oldest behind 2 (0.2.0, 0.10.0)" 2 "$(col p_old 4)"
assert_eq "last sync date of the last template-sync line" 2026-10-03 "$(col p_old 3)"
assert_eq "ref column" template-v0.1.0 "$(col p_old 2)"
assert_eq "no maintenance log gives -" "-" "$(col p_known 3)"
assert_eq "version sort: 0.2.0 behind 1 (0.10.0 is newer)" 1 "$(col p_mid 4)"
assert_eq "newest tag behind 0" 0 "$(col p_cur 4)"
assert_eq "dirty counts untracked files" 2 "$(col p_cur 5)"
assert_eq "untagged known sha counts from nearest tag" 1 "$(col p_known 4)"
assert_eq "untagged unknown sha" unknown "$(col p_unknown 4)"
assert_eq "missing folder state" missing "$(col gone 6)"
assert_eq "missing folder behind" "-" "$(col gone 4)"
assert_eq "no Template line state" no-template-line "$(col p_noline 6)"
assert_eq "extra tokens: state bad-line" bad-line "$(col p_badtag 6)"
assert_eq "extra tokens: ref still read" template-v0.2.0 "$(col p_badtag 2)"
assert_eq "extra tokens: behind from the ref" 1 "$(col p_badtag 4)"
assert_eq "extra tokens: old url shown" https://github.com/example/New-Project "$(col p_badtag 7)"
assert_eq "extra tokens: dirty still counted" 0 "$(col p_badtag 5)"
assert_eq "extra tokens, sha ref: bad-line" bad-line "$(col p_badsha 6)"
assert_eq "extra tokens, sha ref: nearest tag" 1 "$(col p_badsha 4)"
assert_eq "url only: bad-line" bad-line "$(col p_badurl 6)"
assert_eq "commit before the first tag: all 3 tags newer" 3 "$(col p_pretag 4)"
assert_eq "side commit no tag contains: tags containing its fork" 3 "$(col p_side 4)"
assert_eq "url only: no ref" "-" "$(col p_badurl 2)"
assert_eq "url only: behind -" "-" "$(col p_badurl 4)"
assert_eq "ok state" ok "$(col p_cur 6)"
assert_eq "same origin without .git suffix shows no url" "-" "$(col p_mid 7)"
assert_eq "origin url shows no url" "-" "$(col p_cur 7)"
assert_eq "old repo name shows its url" https://github.com/example/New-Project "$(col p_oldurl 7)"
assert_eq "folder name with a space" 1 "$(col 'p space' 4)"
assert_eq "tsv rows: header + 14 projects" 15 "$(printf '%s\n' "$TSV" | wc -l | tr -d '[:space:]')"

run scripts/fleet-status.sh
assert_rc "table runs" 0
assert_contains "table header" "project"
assert_contains "table newest tag line" "newest template tag: template-v0.10.0"
assert_contains "table missing row" "missing"
assert_contains "table unknown" "unknown"

run scripts/fleet-status.sh --list "$LIST"
assert_rc "--list" 0
printf '%s\n' "$PRJ/p_cur" > "$FIX/one.list"
run scripts/fleet-status.sh --tsv --list "$FIX/one.list"
assert_eq "--list limits rows" 2 "$(printf '%s\n' "$OUT" | wc -l | tr -d '[:space:]')"

# The list of the main checkout is found from a linked worktree.
commit scripts >/dev/null 2>&1 || true
git worktree add -q "$FIX-wt" -b wtb >/dev/null 2>&1
if [[ -x "$FIX-wt/scripts/fleet-status.sh" || -f "$FIX-wt/scripts/fleet-status.sh" ]]; then
  chmod +x "$FIX-wt/scripts/fleet-status.sh"
  run "$FIX-wt/scripts/fleet-status.sh" --tsv
  assert_rc "worktree uses the main checkout list" 0
  assert_contains "worktree list has the projects" "p_cur"
else
  t_bad "worktree copy of fleet-status.sh missing"
fi
git worktree remove --force "$FIX-wt" >/dev/null 2>&1 || true

rm -f "$LIST"
run scripts/fleet-status.sh
assert_rc "no list file exits 1" 1
assert_contains "no list file message" "no list file"
run scripts/fleet-status.sh --bogus
assert_rc "unknown option exits 1" 1
run scripts/fleet-status.sh --list
assert_rc "--list without a value exits 1" 1
run scripts/fleet-status.sh --list "$FIX/absent.list"
assert_rc "missing --list file exits 1" 1
run scripts/fleet-status.sh --help
assert_rc "--help exits 0" 0
touch .start-done
run scripts/fleet-status.sh --list "$FIX/one.list"
assert_rc "refuses after start" 1
rm -f .start-done

t_check_exec fleet-status
t_finish
