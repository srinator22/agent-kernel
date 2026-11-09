#!/usr/bin/env bash
# fleet.sh: the read-only fleet table on a fixture template (two tags plus a
# non-synced commit) and fixture projects covering OK, BEHIND, BAD-LINE,
# NO-BASE, MISSING, filled UPSTREAM entries and a folder name with a space.
# Also: CRLF list files, comments, --list, the exit codes, and that no file is
# created inside any project.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" || { echo "$0: cannot load lib.sh; stopped before writing anything" >&2; exit 2; }

make_fixture
cp_script fleet.sh template-sync.sh
printf '# Agents\n' > AGENTS.md
printf 'echo a\n' > scripts/a.sh; chmod +x scripts/a.sh
git add -A >/dev/null 2>&1 && git commit -q -m one && git tag template-v0.1.0
printf 'echo b\n' > scripts/b.sh; chmod +x scripts/b.sh
git add -A >/dev/null 2>&1 && git commit -q -m two && git tag template-v0.2.0
printf 'x\n' > notes.txt
git add -A >/dev/null 2>&1 && git commit -q -m notes

PRJ="$FIX/projects"
mkproj() { # dir templateline synced
  mkdir -p "$1/docs/lessons"
  git init -q "$1" >/dev/null 2>&1
  git -C "$1" config user.email t@example.invalid
  git -C "$1" config user.name t
  git -C "$1" config core.autocrlf false
  printf '# P\n%s\n' "$2" > "$1/AGENTS.md"
  if [[ -n "${3:-}" ]]; then printf 'template-sync: old 2026-01-01\ntemplate-sync: %s 2026-10-01\n' "$3" > "$1/docs/lessons/MAINTENANCE.log"; fi
  git -C "$1" add -A >/dev/null 2>&1
  git -C "$1" commit -q -m init >/dev/null 2>&1
}
mkproj "$PRJ/okproj" "- Template: https://x/t.git template-v0.2.0" template-v0.2.0
echo dirty > "$PRJ/okproj/untracked.txt"
mkproj "$PRJ/behindproj" "- Template: https://x/t.git template-v0.1.0" template-v0.1.0
mkproj "$PRJ/badproj" "- Template: https://x/t.git template-v0.2.0 extra prose" template-v0.2.0
mkproj "$PRJ/nobaseproj" "- Template: https://x/t.git template-v0.2.0"
mkproj "$PRJ/upproj" "- Template: https://x/t.git template-v0.2.0" template-v0.2.0
printf -- '- what happened:\n- what happened: one\n- what happened: two\n' > "$PRJ/upproj/docs/lessons/UPSTREAM.md"
mkproj "$PRJ/Project With Space" "- Template: https://x/t.git template-v0.2.0" template-v0.2.0

LIST="$FIX/fleet.local.list"
{
  printf '# my projects\r\n\r\n'
  for p in okproj behindproj badproj nobaseproj gone upproj "Project With Space"; do printf '%s\r\n' "$PRJ/$p"; done
} > "$LIST"

before="$(cd "$PRJ" && find . | sort)"
run scripts/fleet.sh
assert_rc "fleet runs" 0
after="$(cd "$PRJ" && find . | sort)"
assert_eq "no files created in projects" "$before" "$after"
assert_contains "header" "project"
assert_contains "ok row" "okproj"
row() { printf '%s\n' "$OUT" | grep -F -- "$1" | head -n 1; }
case "$(row okproj)" in *template-v0.2.0*OK) t_ok "okproj OK"; ;; *) t_bad "okproj OK: $(row okproj)" ;; esac
r="$(row okproj)"; read -r -a f <<< "$r"
assert_eq "okproj behind 0" 0 "${f[3]}"
assert_eq "okproj dirty 1" 1 "${f[4]}"
r="$(row behindproj)"; read -r -a f <<< "$r"
assert_eq "behindproj behind 1" 1 "${f[3]}"
assert_eq "behindproj status" BEHIND "${f[7]}"
r="$(row badproj)"; read -r -a f <<< "$r"
assert_eq "badproj status" BAD-LINE "${f[7]}"
r="$(row nobaseproj)"; read -r -a f <<< "$r"
assert_eq "nobaseproj status" NO-BASE "${f[7]}"
r="$(row gone)"; read -r -a f <<< "$r"
assert_eq "gone status" MISSING "${f[7]}"
r="$(row upproj)"; read -r -a f <<< "$r"
assert_eq "upproj upstream 2" 2 "${f[6]}"
assert_eq "upproj status" OK "${f[7]}"
r="$(row 'Project With Space')"
case "$r" in *"Project With Space"*OK) t_ok "space in name OK" ;; *) t_bad "space in name: $r" ;; esac
assert_contains "summary" "fleet: 7 projects: 3 OK, 1 BEHIND, 1 NO-BASE, 1 BAD-LINE, 1 MISSING"
assert_contains "newest tag" "fleet: newest template tag template-v0.2.0"

printf '%s\n' "$PRJ/okproj" > "$FIX/other.list"
run scripts/fleet.sh --list "$FIX/other.list"
assert_rc "--list works" 0
assert_contains "--list summary" "fleet: 1 projects: 1 OK"

run scripts/fleet.sh --bogus
assert_rc "unknown option" 2
run scripts/fleet.sh --help
assert_rc "help" 0
assert_contains "help usage" "Usage:"

run scripts/fleet.sh --list "$FIX/absent.list"
assert_rc "missing list" 2
assert_contains "missing list message" "fleet: create fleet.local.list"


# ---- behind counts a release whose only synced change is a lessons header or
# the AGENTS.md kernel block / rules index; lessons data below the header and
# Project decisions are not synced ----
cd "$FIX" || exit 1
lessons12() { # first-line data: a 12-line format header, then one data line
  mkdir -p docs/lessons
  printf '%s\n' "$1" l2 l3 l4 l5 l6 l7 l8 l9 l10 l11 l12 "$2" > docs/lessons/INDEX.md
}
agents_v() { # kernel-text rules-text decisions-text
  printf '# Agents\n\n<!-- KERNEL:BEGIN -->\n1. %s\n<!-- KERNEL:END -->\n\n## Rules index (triggered)\n- %s\n\n## Project decisions\n- %s\n' "$1" "$2" "$3" > AGENTS.md
}
tpl_commit() { git add -A >/dev/null 2>&1 && git commit -q -m "$1" >/dev/null 2>&1 && git tag "$2"; }
agents_v k1 r1 d1; lessons12 "# header A" data1
tpl_commit base-hdr template-v0.3.0
lessons12 "# header B" data1
tpl_commit header-only template-v0.4.0
lessons12 "# header B" data2
tpl_commit lessons-data-only template-v0.5.0
agents_v k1 r1 d2
tpl_commit decisions-only template-v0.6.0
agents_v k2 r1 d2
tpl_commit kernel-only template-v0.7.0
agents_v k2 r2 d2
tpl_commit rules-index-only template-v0.8.0
mkproj "$PRJ/hdrproj" "- Template: https://x/t.git template-v0.3.0" template-v0.3.0
mkproj "$PRJ/dataproj" "- Template: https://x/t.git template-v0.4.0" template-v0.4.0
mkproj "$PRJ/kernproj" "- Template: https://x/t.git template-v0.6.0" template-v0.6.0
printf '%s\n%s\n%s\n' "$PRJ/hdrproj" "$PRJ/dataproj" "$PRJ/kernproj" > "$FIX/synced.list"
run scripts/fleet.sh --list "$FIX/synced.list"
assert_rc "synced-change fleet runs" 0
r="$(row hdrproj)"; read -r -a f <<< "$r"
assert_eq "header, kernel and rules-index changes count; data and decisions do not" 3 "${f[3]}"
assert_eq "hdrproj status" BEHIND "${f[7]}"
r="$(row dataproj)"; read -r -a f <<< "$r"
assert_eq "dataproj behind: kernel and rules-index only" 2 "${f[3]}"
r="$(row kernproj)"; read -r -a f <<< "$r"
assert_eq "kernproj behind: kernel then rules index" 2 "${f[3]}"


touch .start-done
run scripts/fleet.sh
assert_rc "start-done refused" 2
assert_contains "start-done message" "fleet: run this in the template repository"

t_finish
