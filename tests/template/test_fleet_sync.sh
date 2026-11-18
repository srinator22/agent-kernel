#!/usr/bin/env bash
# fleet-sync.sh: a sync worktree and branch per fleet project, never committed
# or pushed, main checkouts untouched; --accept-kernel only for a project whose
# Standing overrides line records "template kernel accepted verbatim"; the other
# project stops at KERNEL CHANGE while its non-kernel files still sync; --dry-run
# changes nothing; non-git paths are skipped; a second run refuses to reuse a
# worktree.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" || { echo "$0: cannot load lib.sh; stopped before writing anything" >&2; exit 2; }

make_fixture
TPL="$FIX/template"
export TEMPLATE_SYNC_TODAY=2026-10-09
put_agents() { # kernel-text
  cat > AGENTS.md <<AG
# Agents

<!-- KERNEL:BEGIN -->
1. $1
<!-- KERNEL:END -->

## Rules index (triggered)
- rules

## Project decisions
- Template: $TPL v1
- Profiles: software
AG
}

mkdir -p "$TPL" && cd "$TPL" || exit 1
git init -q . >/dev/null 2>&1
git config user.email t@example.invalid; git config user.name t; git config core.autocrlf false
mkdir -p scripts docs/profiles/software
cp "$T_ROOT/scripts/kernel-hash.sh" "$T_ROOT/scripts/template-sync.sh" "$T_ROOT/scripts/profiles.sh" scripts/
echo "echo a v1" > scripts/a.sh; echo "software" > docs/profiles/software/PROFILE.md
put_agents "Kernel v1."
git add -A >/dev/null 2>&1 && git commit -q -m v1 && git tag v1
echo "echo a v2" > scripts/a.sh; put_agents "Kernel v2."
git add -A >/dev/null 2>&1 && git commit -q -m v2 && git tag v2

mkproj() { # name override-line-or-empty
  mkdir -p "$FIX/$1" && cd "$FIX/$1" || exit 1
  git init -q . >/dev/null 2>&1
  git config user.email p@example.invalid; git config user.name p; git config core.autocrlf false
  git -C "$TPL" archive --format=tar v1 | tar -x
  [[ -z "$2" ]] || echo "$2" >> AGENTS.md
  mkdir -p docs/lessons && echo "template-sync: v1 2026-09-01" > docs/lessons/MAINTENANCE.log
  chmod +x scripts/*.sh && ./scripts/kernel-hash.sh --update >/dev/null
  git add -A >/dev/null 2>&1 && git commit -q -m "project at v1" && git checkout -q -B main
}
mkproj yes "- Standing overrides recorded by the human: template kernel accepted verbatim"
mkproj no ""
mkdir -p "$FIX/plain"
{ echo "# a comment"; echo; echo "$FIX/yes"; echo "$FIX/no"; echo "$FIX/plain"; } > "$FIX/fleet.list"
head_of() { git -C "$FIX/$1" rev-parse HEAD; }
cd "$FIX" || exit 1
YES_HEAD="$(head_of yes)"; NO_HEAD="$(head_of no)"

run "$T_ROOT/scripts/fleet-sync.sh" --list "$FIX/fleet.list" --ref v2 --dry-run
assert_rc "--dry-run exits 0" 0
assert_contains "--dry-run names the worktree it would make" "git worktree add -b chore/template-v2 $FIX/yes-template-v2"
assert_no_file "--dry-run created no worktree" "$FIX/yes-template-v2"
assert_eq "--dry-run created no branch" "" "$(git -C "$FIX/yes" branch --list 'chore/*')"

run "$T_ROOT/scripts/fleet-sync.sh" --list "$FIX/fleet.list" --ref v2
assert_rc "a project at KERNEL CHANGE makes the run exit 1" 1
assert_contains "the override project is applied" "$FIX/yes  applied  $FIX/yes-template-v2"
assert_contains "the other project reports KERNEL CHANGE" "$FIX/no  KERNEL CHANGE (owner)  $FIX/no-template-v2"
assert_contains "a folder that is not a git repository is skipped" "$FIX/plain  skipped: not a git repository"
assert_file_has "the override project got the template kernel" "$FIX/yes-template-v2/AGENTS.md" "Kernel v2."
run bash "$FIX/yes-template-v2/scripts/kernel-hash.sh" --verify
assert_rc "the kernel hash was updated in its worktree" 0
assert_file_lacks "the other project keeps its kernel" "$FIX/no-template-v2/AGENTS.md" "Kernel v2."
assert_eq "the other project's non-kernel files still synced" "echo a v2" "$(cat "$FIX/no-template-v2/scripts/a.sh")"
assert_eq "no commit was made on the sync branch" "$YES_HEAD" "$(git -C "$FIX/yes-template-v2" rev-parse HEAD)"
assert_eq "the main checkout kept its HEAD" "$NO_HEAD" "$(head_of no)"
assert_eq "the main checkout is clean" "" "$(git -C "$FIX/yes" status --porcelain)"
assert_eq "nothing was pushed (no remote exists)" "" "$(git -C "$FIX/yes" remote)"

run "$T_ROOT/scripts/fleet-sync.sh" --list "$FIX/fleet.list" --ref v2
assert_contains "a second run refuses to reuse the worktree" "skipped: worktree folder already exists"
run "$T_ROOT/scripts/fleet-sync.sh" --list "$FIX/missing.list"
assert_rc "a missing list file is a usage error" 2

t_finish
