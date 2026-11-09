#!/usr/bin/env bash
# template-release.sh on fixture template repos: --help, usage errors, the
# template-mode refusal, version ordering and bumps, the first release, note
# grouping, the KERNEL CHANGED line, nothing to release, every --tag guard, and
# a successful --tag that creates an annotated tag and never pushes. The
# "tag already exists" guard is defensive: the proposed version is always above
# the newest tag, so no fixture can reach it.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" || { echo "$0: cannot load lib.sh; stopped before writing anything" >&2; exit 2; }

put_agents() { # kernel-text
  printf '# Agents\n\n<!-- KERNEL:BEGIN -->\n1. %s\n<!-- KERNEL:END -->\n\n## Project decisions\n' "$1" > AGENTS.md
}
# fresh_repo: a fixture on branch main with the scripts and a base AGENTS.md.
fresh_repo() {
  make_fixture
  git symbolic-ref HEAD refs/heads/main
  cp_script template-release.sh template-sync.sh
  put_agents "rule one"
  git add -A >/dev/null 2>&1 && git commit -q -m "chore: base" >/dev/null 2>&1
}
commit_file() { # path subject
  mkdir -p "$(dirname "$1")"
  echo "$2" >> "$1"
  git add -A >/dev/null 2>&1 && git commit -q -m "$2" >/dev/null 2>&1
}
rel() { run bash scripts/template-release.sh "$@"; }

# ---- usage ----
fresh_repo
rel --help;  assert_rc "help exits 0" 0; assert_contains "help shows usage" "Usage: scripts/template-release.sh"
rel --bogus; assert_rc "unknown option exits 2" 2; assert_contains "unknown option named" "unknown option: --bogus"

# ---- project (start has run) ----
touch .start-done
rel
assert_rc "start-done refuses" 2
assert_contains "start-done message" "this is a project (start has run); releases are cut in the template repository"
rm -f .start-done

# ---- first release, no tag ----
commit_file notes/x.md "docs: first"
rel
assert_rc "first release dry run exits 0" 0
assert_contains "no previous tag" "template-release: no previous template-v* tag"
assert_contains "first version" "next version template-v0.1.0 (minor)"
assert_contains "first release notes cover all commits" "chore: base"
assert_contains "dry run last line" "template-release: dry run; no tag created (rerun with --tag)"

# ---- version ordering and bumps ----
git tag template-v0.9.0
commit_file notes/y.md "docs: second"
git tag template-v0.10.0
commit_file notes/z.md "docs: third"
rel
assert_contains "sort -V picks 0.10.0" "last tag template-v0.10.0"
assert_contains "minor default" "next version template-v0.11.0 (minor)"
assert_not_contains "old commit excluded" "docs: second"
assert_contains "new commit included" "docs: third"
rel --major; assert_contains "major bump" "next version template-v1.0.0 (major)"
rel --patch; assert_contains "patch bump" "next version template-v0.10.1 (patch)"

# ---- grouping ----
commit_file scripts/core1.sh "feat: core change"
commit_file docs/library/lib1.md "feat: library change"
commit_file random/other.md "chore: other change"
mkdir -p scripts docs/library
echo a >> scripts/both.sh; echo b >> docs/library/both.md
git add -A >/dev/null 2>&1 && git commit -q -m "feat: both" >/dev/null 2>&1
rel
assert_rc "grouping dry run exits 0" 0
FULL="$OUT"
sec_synced="$(printf '%s\n' "$FULL" | sed -n '/^## Synced/,/^## Library/p')"
sec_lib="$(printf '%s\n' "$FULL" | sed -n '/^## Library/,/^## Not synced/p')"
sec_other="$(printf '%s\n' "$FULL" | sed -n '/^## Not synced/,$p')"
OUT="$sec_synced"; assert_contains "core commit synced" "feat: core change"; assert_contains "mixed commit synced" "feat: both"
OUT="$sec_lib";    assert_contains "catalog commit in library" "feat: library change"; assert_not_contains "mixed not in library" "feat: both"
OUT="$sec_other";  assert_contains "other commit not synced" "chore: other change"; assert_not_contains "mixed not in other" "feat: both"
assert_eq "each commit once" "1" "$(printf '%s\n' "$FULL" | grep -c 'feat: both')"

# ---- header and AGENTS.md partial sync ----
put_full_agents() { # kernel-text rules-text decisions-text
  printf '# Agents\n\n<!-- KERNEL:BEGIN -->\n1. %s\n<!-- KERNEL:END -->\n\n## Rules index\n\n- %s\n\n## Project decisions\n\n- %s\n' "$1" "$2" "$3" > AGENTS.md
}
fresh_repo
put_full_agents "k" "r" "d"
mkdir -p docs/lessons
for n in 1 2 3 4 5 6 7 8 9 10 11 12 13 14; do echo "line $n" >> docs/lessons/INDEX.md; done
git add -A >/dev/null 2>&1 && git commit -q -m "chore: seed lessons" >/dev/null 2>&1
git tag template-v0.1.0
sed -i 's/^line 13$/line 13 edited/' docs/lessons/INDEX.md
git add -A >/dev/null 2>&1 && git commit -q -m "chore: index below header" >/dev/null 2>&1
sed -i 's/^line 5$/line 5 edited/' docs/lessons/INDEX.md
git add -A >/dev/null 2>&1 && git commit -q -m "chore: index within header" >/dev/null 2>&1
put_full_agents "k" "r" "d edited"
git add -A >/dev/null 2>&1 && git commit -q -m "chore: agents decisions only" >/dev/null 2>&1
put_full_agents "k" "r edited" "d edited"
git add -A >/dev/null 2>&1 && git commit -q -m "chore: agents rules index" >/dev/null 2>&1
put_full_agents "k edited" "r edited" "d edited"
git add -A >/dev/null 2>&1 && git commit -q -m "chore: agents kernel block" >/dev/null 2>&1
rel
assert_rc "partial sync dry run exits 0" 0
FULL="$OUT"
sec_synced="$(printf '%s\n' "$FULL" | sed -n '/^## Synced/,/^## Library/p')"
sec_other="$(printf '%s\n' "$FULL" | sed -n '/^## Not synced/,$p')"
OUT="$sec_other";  assert_contains "index below line 12 not synced" "chore: index below header"
assert_contains "agents decisions only not synced" "chore: agents decisions only"
OUT="$sec_synced"; assert_contains "index within first 12 lines synced" "chore: index within header"
assert_contains "agents rules index synced" "chore: agents rules index"
assert_contains "agents kernel block synced" "chore: agents kernel block"
assert_not_contains "index below line 12 not in synced" "chore: index below header"
assert_not_contains "agents decisions only not in synced" "chore: agents decisions only"

# ---- --synced-commits prints "<sha> <kind>"; kind is the first of agents, core, header, catalog ----
fresh_repo
put_full_agents "k" "r" "d"
mkdir -p docs/lessons
for n in 1 2 3 4 5 6 7 8 9 10 11 12 13; do echo "line $n" >> docs/lessons/INDEX.md; done
git add -A >/dev/null 2>&1 && git commit -q -m "chore: seed" >/dev/null 2>&1
git tag base-kinds
commit_file scripts/k_core.sh "feat: kind core"
sed -i 's/^line 3$/line 3 edited/' docs/lessons/INDEX.md
git add -A >/dev/null 2>&1 && git commit -q -m "chore: kind header" >/dev/null 2>&1
put_full_agents "k edited" "r" "d"
git add -A >/dev/null 2>&1 && git commit -q -m "chore: kind agents" >/dev/null 2>&1
commit_file docs/library/k_cat.md "feat: kind catalog"
mkdir -p scripts docs/library
echo a >> scripts/k_both.sh; echo b >> docs/library/k_both.md
git add -A >/dev/null 2>&1 && git commit -q -m "feat: kind both" >/dev/null 2>&1
commit_file random/k_none.md "chore: kind none"
run bash scripts/template-sync.sh --synced-commits base-kinds..HEAD
assert_rc "synced-commits exits 0" 0
kinds="$(printf '%s\n' "$OUT" | while read -r sha kind; do printf '%s=%s\n' "$(git log -1 --format=%s "$sha")" "$kind"; done | sort | tr '\n' ' ')"
assert_eq "kind column: first of core, header, agents, catalog; none for unsynced" "chore: kind agents=agents chore: kind header=header feat: kind both=core feat: kind catalog=catalog feat: kind core=core " "$kinds"
assert_eq "one line per synced commit" "5" "$(printf '%s\n' "$OUT" | grep -c .)"

# ---- empty group prints none; kernel unchanged ----
fresh_repo
git tag template-v0.1.0
commit_file scripts/only.sh "feat: only core"
rel
assert_contains "core commit listed" "feat: only core"
assert_not_contains "no kernel warning when unchanged" "KERNEL CHANGED"
OUT="$(printf '%s\n' "$OUT" | sed -n '/^## Library/,$p')"
assert_contains "empty group says none" "- none"

# ---- kernel change ----
put_agents "rule one changed"
git add -A >/dev/null 2>&1 && git commit -q -m "feat: kernel edit" >/dev/null 2>&1
rel
assert_contains "KERNEL CHANGED present" "KERNEL CHANGED since template-v0.1.0: --major is suggested; projects need owner approval to take this release"
rel --major
assert_not_contains "KERNEL CHANGED absent with --major" "KERNEL CHANGED"

# ---- nothing to release ----
fresh_repo
git tag template-v0.1.0
rel
assert_rc "nothing to release dry run exits 0" 0
assert_contains "nothing to release message" "template-release: nothing to release since template-v0.1.0"
rel --tag
assert_rc "nothing to release --tag exits 1" 1

# ---- --tag guards and success ----
fresh_repo
git tag template-v0.1.0
commit_file scripts/new.sh "feat: releasable"
echo remote.git >> .git/info/exclude
git init -q --bare "$FIX/remote.git"
git remote add origin "$FIX/remote.git"

rel --tag
assert_rc "no origin/main refuses" 2
assert_contains "no origin/main message" "no origin/main; fetch first"
git push -q origin main >/dev/null 2>&1

git checkout -q -b feature
rel --tag
assert_rc "not main refuses" 2
assert_contains "not main message" "not main"
git checkout -q main

echo dirty > dirty.txt
rel --tag
assert_rc "dirty tree refuses" 2
assert_contains "dirty tree message" "not clean"
rm -f dirty.txt

commit_file scripts/ahead.sh "feat: ahead of origin"
rel --tag
assert_rc "origin behind HEAD refuses" 2
assert_contains "origin behind message" "not equal to HEAD"
git push -q origin main >/dev/null 2>&1

# A live task record at HEAD would ship inside the tag (template-v0.3.0 did).
mkdir -p .work
printf '# Task: live-one\nMode: standard\n' > .work/TASK.md
git add -A >/dev/null 2>&1 && git commit -q -m "chore: live task" >/dev/null 2>&1
git push -q origin main >/dev/null 2>&1
rel
assert_rc "a live task does not fail the dry run" 0
assert_contains "the dry run warns about the live task" "WARNING: .work/TASK.md at HEAD is a live task"
rel --tag
assert_rc "a live task at HEAD refuses the tag" 2
assert_contains "the refusal points to the retro" "finish the task with docs/procedures/retro.md"
assert_eq "no tag was created" "" "$(git tag -l template-v0.2.0)"
printf '# Task: {{title}}\nMode: standard | quick | autopilot\n' > .work/TASK.md
git add -A >/dev/null 2>&1 && git commit -q -m "chore: archive the task" >/dev/null 2>&1
git push -q origin main >/dev/null 2>&1
rel
assert_not_contains "a pristine task file raises no warning" "is a live task"

rel --tag
assert_rc "successful --tag exits 0" 0
assert_contains "created message" "created annotated tag template-v0.2.0 at"
assert_contains "push hint" "push it with: git push origin template-v0.2.0"
assert_eq "tag is annotated" "tag" "$(git cat-file -t template-v0.2.0)"
tag_msg="$(git tag -l --format='%(contents)' template-v0.2.0)"
assert_eq "tag message line 1 is the version" "template-v0.2.0" "$(printf '%s\n' "$tag_msg" | sed -n 1p)"
assert_eq "tag message line 2 is blank" "" "$(printf '%s\n' "$tag_msg" | sed -n 2p)"
OUT="$tag_msg"; assert_contains "tag message holds a commit subject" "feat: releasable"
assert_eq "remote does not have the tag" "" "$(git ls-remote --tags origin template-v0.2.0)"

t_finish
