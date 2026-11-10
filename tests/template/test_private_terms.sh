#!/usr/bin/env bash
# private-terms.sh: check (staged content, tracked paths, unpushed commits)
# and history (every ref with diffs, merges and annotated tags) against a
# gitignored terms file; every printed name is masked and the term text is
# never printed.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" || { echo "$0: cannot load lib.sh; stopped before writing anything" >&2; exit 2; }

# no_term LABEL: the last output holds neither casing of the fixture's terms.
no_term() {
  assert_not_contains "$1 (fixture casing)" "Zelda"
  assert_not_contains "$1 (lower case)" "zelda"
  assert_not_contains "$1 (email)" "mail.example"
  assert_not_contains "$1 (path term)" "Users\\zq"
}

on_windows() { case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) return 0 ;; *) return 1 ;; esac; }

new_repo() {
  make_fixture
  cp_script private-terms.sh
  printf '.work/private-terms.txt\n' > .gitignore
  mkdir -p .work docs
}

new_repo

# A3: a repository with no commits scans only the index.
printf 'Zelda Quixote\n' > .work/private-terms.txt
run ./scripts/private-terms.sh check
assert_rc "a repository with no commits passes check" 0
printf 'Zelda Quixote\n' > docs/first.md
git add docs/first.md
run ./scripts/private-terms.sh check
assert_rc "a repository with no commits scans the index" 1
assert_contains "the staged file is named before the first commit" "docs/first.md: 1 line(s) (term 1)"
git rm -q --cached docs/first.md && rm docs/first.md
rm .work/private-terms.txt

echo "Plain text." > docs/a.md
git add -A && git commit -qm "init"

# A1 no terms file.
run ./scripts/private-terms.sh check
assert_rc "no terms file passes check" 0
assert_contains "no terms file is named" ".work/private-terms.txt"
run ./scripts/private-terms.sh history
assert_rc "no terms file passes history" 0

# A1/A2 parsing.
printf '# comment\r\n\r\n   \r\n' > .work/private-terms.txt
run ./scripts/private-terms.sh check
assert_rc "a terms file with only comments and blanks passes" 0
printf 'okay-term\nqz\n' > .work/private-terms.txt
run ./scripts/private-terms.sh check
assert_rc "a term shorter than 3 bytes is a usage error" 2
assert_contains "the short term's line is named" "line 2"
assert_not_contains "the short term is not printed" "qz"

# Terms: line 2 a name, line 4 an email with regex specials, line 5 a
# Windows path with backslashes, line 6 a duplicate of line 2.
printf '# private\r\n  Zelda Quixote  \r\n\r\nzq.home+x@mail.example\r\nC:\\Users\\zq\r\nZELDA QUIXOTE\r\n' > .work/private-terms.txt
run ./scripts/private-terms.sh check
assert_rc "a clean repository passes" 0
assert_contains "the count of distinct terms is reported" "3 term(s)"
no_term "a clean run"

# A3 contents, any letter case; a duplicate term reports once.
printf 'one\nwritten by ZELDA QUIXOTE here\nand zelda quixote again\n' > docs/b.md
git add docs/b.md
run ./scripts/private-terms.sh check
assert_rc "a staged file holding a term fails" 1
assert_contains "the file, count and term number are named" "docs/b.md: 2 line(s) (term 2)"
assert_not_contains "the duplicate term is not reported" "(term 6)"
no_term "a content match"
git rm -q --cached docs/b.md && rm docs/b.md

# A5 a staged file whose name and content both hold a term is named masked.
printf 'by Zelda Quixote\n' > "docs/zelda quixote notes.md"
git add "docs/zelda quixote notes.md"
run ./scripts/private-terms.sh check
assert_contains "a content match names its file masked" "docs/*** notes.md: 1 line(s) (term 2)"
assert_contains "the same file's path match is masked" "docs/*** notes.md (term 2)"
no_term "a named-file content match"
git rm -q --cached "docs/zelda quixote notes.md" && rm "docs/zelda quixote notes.md"

# A3 binary content is scanned.
printf 'PDF\000\001/Author (Zelda Quixote)\000' > docs/c.bin
git add docs/c.bin
run ./scripts/private-terms.sh check
assert_rc "a staged binary holding a term fails" 1
assert_contains "the binary file is named" "docs/c.bin: 1 line(s) (term 2)"
git rm -q --cached docs/c.bin && rm docs/c.bin

# A2 regex specials and backslashes are literal.
echo "zqXhome+x@mail.example and C:/Users/zq" > docs/near.md
git add docs/near.md
run ./scripts/private-terms.sh check
assert_rc "near misses of literal terms do not match" 0
echo 'path C:\USERS\ZQ\desk' > docs/near.md
git add docs/near.md
run ./scripts/private-terms.sh check
assert_contains "a backslash term matches in another case" "docs/near.md: 1 line(s) (term 5)"
no_term "a backslash match"
git rm -q --cached docs/near.md && rm docs/near.md

# Untracked and ignored files are not scanned.
echo "Zelda Quixote" > docs/untracked.md
echo "Zelda Quixote" > .work/ignored.txt
printf '.work/private-terms.txt\n.work/ignored.txt\n' > .gitignore
git add .gitignore && git commit -qm "ignore"
run ./scripts/private-terms.sh check
assert_rc "untracked and ignored files are not scanned" 0
rm -f docs/untracked.md .work/ignored.txt

# A3/A5 paths are named masked.
mkdir -p "docs/Zelda Quixote"
echo "x" > "docs/Zelda Quixote/n.md"
git add -A
run ./scripts/private-terms.sh check
assert_rc "a tracked path holding a term fails" 1
assert_contains "the path is named masked with the term number" "docs/***/n.md (term 2)"
no_term "a path match"
git rm -rq --cached "docs/Zelda Quixote" && rm -rf "docs/Zelda Quixote"

# A3 a file name holding a colon is named whole (not possible on Windows).
if on_windows; then
  t_na "a colon in a file name: Windows file systems refuse the name"
else
  printf 'by zelda quixote\n' > "docs/a:b.md"
  git add "docs/a:b.md"
  run ./scripts/private-terms.sh check
  assert_contains "a file name with a colon is named whole" "docs/a:b.md: 1 line(s) (term 2)"
  git rm -q --cached "docs/a:b.md" && rm "docs/a:b.md"
  # A line break inside a staged file name keeps every part masked.
  NLNAME="docs/Zelda Quixote
x.md"
  printf 'by zelda quixote\n' > "$NLNAME"
  git add "$NLNAME"
  run ./scripts/private-terms.sh check
  assert_rc "a file name with a line break holding a term fails" 1
  assert_contains "a file name with a line break is named masked" "docs/*** x.md: 1 line(s) (term 2)"
  no_term "a file name with a line break"
  git rm -q --cached "$NLNAME" && rm "$NLNAME"
fi

# A5 a broken ref whose name holds a term: git's own error text is not shown.
mkdir -p .git/refs/heads
echo "1111111111111111111111111111111111111111" > ".git/refs/heads/Zelda-Quixote-x"
run ./scripts/private-terms.sh check
no_term "check with a broken ref"
run ./scripts/private-terms.sh history
assert_rc "history fails when git cannot read a broken ref" 1
no_term "history with a broken ref"
rm -f ".git/refs/heads/Zelda-Quixote-x"

# A3 commits: message, author email, committer name; a forged marker line.
echo "m" > docs/m.md && git add docs/m.md
git commit -qm "notes from c:\\users\\ZQ\\desk"
MSG_SHA="$(git rev-parse HEAD | cut -c1-12)"
echo "e" > docs/e.md && git add docs/e.md
git -c user.email="zq.home+x@mail.example" commit -qm "by email"
EMAIL_SHA="$(git rev-parse HEAD | cut -c1-12)"
echo "n" > docs/n.md && git add docs/n.md
GIT_COMMITTER_NAME="Zelda Quixote" git commit -qm "by committer"
COMM_SHA="$(git rev-parse HEAD | cut -c1-12)"
echo "f" > docs/f.md && git add docs/f.md
git commit -qm "subject" -m "commit by zelda quixote"
FORGE_SHA="$(git rev-parse HEAD | cut -c1-12)"
run ./scripts/private-terms.sh check
assert_rc "commits holding terms fail" 1
assert_contains "the message match names its commit and term" "commit $MSG_SHA (term 5)"
assert_contains "the author email match names its commit and term" "commit $EMAIL_SHA (term 4)"
assert_contains "the committer name match names its commit and term" "commit $COMM_SHA (term 2)"
assert_contains "a body line starting with commit stays with its own commit" "commit $FORGE_SHA (term 2)"
assert_not_contains "a body line is never taken as a commit" "commit by"
no_term "a commit match"
assert_not_contains "no commit match prints the message" "desk"

# A3 pushed commits are not scanned by check; history scans them.
BARE="$(mktemp -d "${TMPDIR:-/tmp}/template-selftest-bare.XXXXXX")"
git init -q --bare "$BARE"
git remote add origin "$BARE"
git push -q origin HEAD 2>/dev/null
git fetch -q origin
run ./scripts/private-terms.sh check
assert_rc "pushed commits are not scanned by check" 0
run ./scripts/private-terms.sh history
assert_rc "history scans pushed commits" 1
assert_contains "history names a pushed commit" "commit $MSG_SHA (term 5)"
no_term "history output"
rm -rf "$BARE"

# A4 history: a term only in a removed diff, only on another branch, only in
# a merge resolution, and only in an annotated tag.
new_repo
printf 'Zelda Quixote\nZelda-Quixote\n' > .work/private-terms.txt
echo "base" > docs/f.txt
echo "clean" > docs/a.md
git add -A && git commit -qm "init"
MAIN="$(git symbolic-ref --short HEAD)"
run ./scripts/private-terms.sh history
assert_rc "a clean history passes" 0
echo "Zelda Quixote wrote this" > docs/gone.md
git add docs/gone.md && git commit -qm "add"
ADD_SHA="$(git rev-parse HEAD | cut -c1-12)"
git rm -q docs/gone.md && git commit -qm "remove"
run ./scripts/private-terms.sh check
assert_rc "check finds a term added and removed in unpushed commits" 1
assert_contains "check names the unpushed commit that added it" "commit $ADD_SHA (term 1)"
no_term "an unpushed diff match"
run ./scripts/private-terms.sh history
assert_rc "history finds a term in a removed diff" 1
assert_contains "history names the commit that added it" "commit $ADD_SHA (term 1)"
no_term "a removed-diff match"
git switch -q -c side
echo "zelda quixote" > docs/side.md
git add docs/side.md && git commit -qm "side"
SIDE_SHA="$(git rev-parse HEAD | cut -c1-12)"
echo "side line" > docs/f.txt && git commit -qam "side f"
git switch -q "$MAIN"
run ./scripts/private-terms.sh history
assert_contains "history finds a term only on another branch" "commit $SIDE_SHA (term 1)"
echo "main line" > docs/f.txt && git commit -qam "main f"
git merge -q side >/dev/null 2>&1
echo "resolved by Zelda Quixote" > docs/f.txt
git rm -qf docs/side.md
git add docs/f.txt && git commit -qm "merge side"
MERGE_SHA="$(git rev-parse HEAD | cut -c1-12)"
run ./scripts/private-terms.sh history
assert_contains "history finds a term added in a merge resolution" "commit $MERGE_SHA (term 1)"
git tag -a v1 -m "release notes by Zelda Quixote"
git tag -a zelda-quixote-tag -m "plain"
run ./scripts/private-terms.sh history
assert_contains "history names an annotated tag by its message" "tag v1 (term 1)"
assert_contains "a tag name holding a term is masked" "tag ***-tag (term 2)"
no_term "a tag match"

# A3/A4 ref names: a local branch is found by check and by history, masked.
git branch Zelda-Quixote-wip
run ./scripts/private-terms.sh check
assert_contains "check names a local branch holding a term, masked" "refs/heads/***-wip (term 2)"
run ./scripts/private-terms.sh history
assert_contains "history names a branch holding a term, masked" "refs/heads/***-wip (term 2)"
assert_contains "history names a tag ref holding a term, masked" "refs/tags/***-tag (term 2)"
no_term "a ref name match"
git branch -q -d Zelda-Quixote-wip

# A3 a non-ASCII term matches in its exact case.
printf 'na\303\257ve-user\n' > .work/private-terms.txt
printf 'by na\303\257ve-user\n' > docs/u.md
git add docs/u.md
run ./scripts/private-terms.sh check
assert_contains "a non-ASCII term matches in its exact case" "docs/u.md: 1 line(s) (term 1)"
git rm -q --cached docs/u.md && rm docs/u.md

# A6 a terms file git does not ignore is refused; one outside is accepted.
printf 'Zelda Quixote\n' > .work/private-terms.txt
git add -f .work/private-terms.txt && git commit -qm "oops"
run ./scripts/private-terms.sh check
assert_rc "a tracked terms file is refused" 1
assert_contains "the refusal says to untrack it" "untrack"
no_term "the tracked refusal"
git rm -q --cached .work/private-terms.txt && git commit -qm "untrack"
printf 'other.txt\n' > .gitignore && git add .gitignore && git commit -qm "lose the ignore line"
run ./scripts/private-terms.sh check
assert_rc "a terms file without an ignore line is refused" 1
assert_contains "the refusal says to ignore it" ".gitignore"
no_term "the unignored refusal"
OUTSIDE="$(mktemp -d "${TMPDIR:-/tmp}/template-selftest-terms.XXXXXX")"
printf 'nothing-here-at-all\n' > "$OUTSIDE/terms.txt"
PRIVATE_TERMS_FILE="$OUTSIDE/terms.txt" run ./scripts/private-terms.sh check
assert_rc "a terms file outside the repository is accepted" 0
PRIVATE_TERMS_FILE="$OUTSIDE/missing.txt" run ./scripts/private-terms.sh check
assert_contains "the override path is named when missing" "missing.txt"
rm -rf "$OUTSIDE"

# A7 usage.
run ./scripts/private-terms.sh
assert_rc "no command is a usage error" 2
run ./scripts/private-terms.sh bogus
assert_rc "an unknown command is a usage error" 2
no_term "usage output"

t_finish
