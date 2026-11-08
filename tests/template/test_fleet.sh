#!/usr/bin/env bash
# fleet.sh: the read-only fleet table on a fixture template (two tags plus a
# non-synced commit) and fixture projects covering OK, BEHIND, BAD-LINE,
# NO-BASE, MISSING, filled UPSTREAM entries and a folder name with a space.
# Also: CRLF list files, comments, --list, the exit codes, and that no file is
# created inside any project.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

make_fixture
cp_script fleet.sh template-sync.sh
printf '# Agents\n' > AGENTS.md
printf 'echo a\n' > scripts/a.sh
git add -A >/dev/null 2>&1 && git commit -q -m one && git tag template-v0.1.0
printf 'echo b\n' > scripts/b.sh
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

touch .start-done
run scripts/fleet.sh
assert_rc "start-done refused" 2
assert_contains "start-done message" "fleet: run this in the template repository"

t_finish
