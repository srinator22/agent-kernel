#!/usr/bin/env bash
# tree-id.sh - prints the git tree id of the working tree as it would be
# committed now: tracked files with their working-tree content, plus untracked
# files that are not ignored, minus deleted files. check.sh prints it as
# "check.sh: verified tree <id>", the reviewer copies it into its verdict as
# "Reviewed tree: <id>", and scripts/tasklint.sh ship compares the two, so a
# change made after the review invalidates the verdict (ADR 0017).
# Usage: scripts/tree-id.sh            (run anywhere inside the repository)
# Output: one line, the tree id (40 hex characters for SHA-1 repositories).
# Excluded from the tree: .work/ (the task record holds the review verdict
# itself, so writing the verdict must not change the reviewed tree) and
# CHANGELOG.md (generated from commits after the review, kernel rule 18).
# The real index is never written: the work happens in a temporary index
# (GIT_INDEX_FILE) seeded from a copy of the real one, inside the git dir so
# Git for Windows reads the path without MSYS conversion. `git add` writes
# blob objects for changed files into the object store; they are unreferenced
# and gc removes them, the same as after an aborted `git add`.
# Exit codes: 0 printed the id, 1 not inside a git work tree or git failed.
set -euo pipefail

top="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "tree-id: not inside a git work tree" >&2; exit 1; }
cd "$top"
gitdir="$(git rev-parse --absolute-git-dir)"
real_index="$(git rev-parse --path-format=absolute --git-path index)"
tmp_index="$gitdir/tree-id-index.$$"
trap 'rm -f "$tmp_index" "$tmp_index.lock"' EXIT

# Seeding from the real index keeps its stat cache, so only changed files are
# hashed again; without an index (a fresh repository) the temporary one starts empty.
if [[ -f "$real_index" ]]; then cp "$real_index" "$tmp_index"; fi

export GIT_INDEX_FILE="$tmp_index"
git -c core.safecrlf=false add -A -- . >/dev/null 2>&1 || { echo "tree-id: git add into the temporary index failed" >&2; exit 1; }
git rm -r -q --cached --ignore-unmatch -- .work CHANGELOG.md >/dev/null 2>&1 || { echo "tree-id: git rm --cached in the temporary index failed" >&2; exit 1; }
tree="$(git write-tree)" || { echo "tree-id: git write-tree failed" >&2; exit 1; }
echo "$tree"
