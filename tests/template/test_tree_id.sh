#!/usr/bin/env bash
# tree-id.sh: outside a repository, a clean tree equals HEAD's tree, working-tree
# content wins over staged content, untracked files count and ignored ones do
# not, deletions count, .work/ and CHANGELOG.md never count, the same id from a
# subfolder, an empty repository, and the real index left byte-identical with
# no temporary index behind.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" || { echo "$0: cannot load lib.sh; stopped before writing anything" >&2; exit 2; }

EMPTY_TREE=4b825dc642cb6eb9a060e54bf8d69288fbee4904

# Outside a git work tree: an actionable refusal, not an empty line.
make_fixture
cp_script tree-id.sh
rm -rf .git
run env GIT_CEILING_DIRECTORIES="$(dirname "$FIX")" ./scripts/tree-id.sh
assert_rc "outside a git work tree fails" 1
assert_contains "names the cause" "tree-id: not inside a git work tree"

# Empty repository: no commit and no index yet.
make_fixture
cp_script tree-id.sh
mv scripts/tree-id.sh "$FIX.tree-id.sh"
rmdir scripts
run "$FIX.tree-id.sh"
assert_rc "an empty repository works" 0
assert_eq "an empty repository has the empty tree" "$EMPTY_TREE" "$OUT"
rm -f "$FIX.tree-id.sh"

# A committed fixture.
make_fixture
cp_script tree-id.sh
mkdir -p src .work/done
echo "one" > src/a.txt
echo "two" > src/b.txt
printf 'ignored.log\n' > .gitignore
printf '# Task: x\n' > .work/TASK.md
printf 'old\n' > CHANGELOG.md
git add -A >/dev/null 2>&1 && git commit -qm init >/dev/null 2>&1
head_tree="$(git rev-parse 'HEAD^{tree}')"
git rm -r -q --cached .work CHANGELOG.md >/dev/null 2>&1
want_clean="$(git write-tree)"
git reset -q >/dev/null 2>&1
index_sum() { cksum < .git/index; }

run ./scripts/tree-id.sh
assert_rc "a clean tree passes" 0
assert_eq "the id is 40 hex characters" 1 "$([[ "$OUT" =~ ^[0-9a-f]{40}$ ]] && echo 1 || echo 0)"
assert_eq "a clean tree is HEAD's tree without .work and CHANGELOG.md" "$want_clean" "$OUT"
clean="$OUT"
if [[ "$clean" != "$head_tree" ]]; then t_ok "HEAD's tree holds .work, the id does not"; else t_bad "HEAD's tree should differ from the id"; fi

# The task record and the changelog never move the id.
printf '## Review verdict\nPASS\nReviewed tree: %s\n' "$clean" >> .work/TASK.md
echo "archived" > .work/done/2026-01-01-x.md
echo "new" >> CHANGELOG.md
run ./scripts/tree-id.sh
assert_eq "edits under .work/ and to CHANGELOG.md keep the id" "$clean" "$OUT"
git checkout -q -- .work CHANGELOG.md && rm -f .work/done/2026-01-01-x.md

# An ignored file never counts; an untracked one does.
echo "noise" > ignored.log
run ./scripts/tree-id.sh
assert_eq "an ignored file keeps the id" "$clean" "$OUT"
echo "fresh" > src/new.txt
run ./scripts/tree-id.sh
if [[ "$OUT" != "$clean" ]]; then t_ok "an untracked file changes the id"; else t_bad "an untracked file should change the id"; fi
untracked="$OUT"
before="$(index_sum)"
run ./scripts/tree-id.sh
assert_eq "the same tree gives the same id" "$untracked" "$OUT"
assert_eq "the real index is byte-identical after a run" "$before" "$(index_sum)"
run git status --porcelain
assert_contains "the untracked file is still untracked" "?? src/new.txt"
ls .git | grep -q '^tree-id-index' && t_bad "a temporary index was left in .git" || t_ok "no temporary index is left in .git"
rm -f src/new.txt

# Working-tree content wins over staged content, and matches what staging would record.
echo "staged" > src/a.txt
git add src/a.txt
echo "working" > src/a.txt
run ./scripts/tree-id.sh
modified="$OUT"
run git diff --cached --name-only
assert_eq "the staged entry is untouched" "src/a.txt" "$OUT"
assert_eq "the staged blob is untouched" "staged" "$(git show :src/a.txt)"
git add -A >/dev/null 2>&1
git rm -r -q --cached .work CHANGELOG.md >/dev/null 2>&1
assert_eq "the id equals the tree staging everything would write" "$(git write-tree)" "$modified"
git reset -q --hard >/dev/null 2>&1

# A deleted tracked file counts.
rm -f src/b.txt
run ./scripts/tree-id.sh
deleted="$OUT"
if [[ "$deleted" != "$clean" ]]; then t_ok "a deleted file changes the id"; else t_bad "a deleted file should change the id"; fi
run git ls-files src/b.txt
assert_eq "the deleted file is still in the real index" "src/b.txt" "$OUT"

# The id does not depend on the folder it runs from.
(cd src && "$FIX/scripts/tree-id.sh") > "$FIX.sub.out" 2>&1
assert_eq "a run from a subfolder gives the same id" "$deleted" "$(cat "$FIX.sub.out")"
rm -f "$FIX.sub.out"

t_finish
