#!/usr/bin/env bash
# template-release.sh - cut a versioned release of this template repository.
# Usage: scripts/template-release.sh [--major|--minor|--patch] [--tag]
#        scripts/template-release.sh --help | -h
#
# Purpose: propose the next template-vMAJOR.MINOR.PATCH tag, print release notes
# grouped by what projects receive, and (with --tag) create the annotated tag.
# Template mode only: refuses (exit 2) when .start-done exists at the repo root.
#
# Inputs: git tags template-v* (newest by version order, not date), the commits
# since that tag, AGENTS.md at the tag and at HEAD (the KERNEL block), and the
# synced set from "scripts/template-sync.sh --list-set" (lines "<group> <path>",
# a trailing "/" marks a directory prefix).
# Version bump: --minor (default), --major, --patch. No previous tag: proposes
# template-v0.1.0 and the notes cover all commits.
# Kernel: when the KERNEL block differs from the last tag and --major was not
# given, a KERNEL CHANGED line suggests --major.
# Notes: each commit appears once, first match wins:
#   1. "Synced to projects": it touches a core path; or a header path (lessons
#      files, of which only the first HEADER_LINES lines sync) and those lines
#      differ between <sha>^ and <sha> (a file absent on one side differs; a
#      root commit compares against empty); or AGENTS.md and the KERNEL block
#      or the rules index (from "## Rules index" up to the next "## " line)
#      differs between <sha>^ and <sha>, CR stripped.
#   2. else it touches a catalog path -> "Library and roster".
#   3. else "Not synced".
# Output: the notes on stdout. Without --tag it is a dry run.
# --tag guards (exit 2 on failure): branch is main, clean tree, origin/main
# exists and equals HEAD, the tag does not exist. It creates an annotated tag
# (version on line 1, blank line, notes) and NEVER pushes.
# Dependencies: bash 3.2+, git, sort -V, scripts/template-sync.sh.
# Exit codes: 0 ok or dry run; 1 nothing to release with --tag;
# 2 usage error or guard failure.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

usage() {
  cat <<'USAGE'
Usage: scripts/template-release.sh [--major|--minor|--patch] [--tag]
       scripts/template-release.sh --help | -h

Dry run by default: prints the last template-v* tag, the proposed next version
and release notes grouped as synced set, library and roster, not synced.
  --minor   next minor version (default)
  --major   next major version
  --patch   next patch version
  --tag     create the annotated tag (main, clean, equal to origin/main); never pushes
USAGE
}

bump=minor
dotag=0
while [ $# -gt 0 ]; do
  case "$1" in
    --major) bump=major ;;
    --minor) bump=minor ;;
    --patch) bump=patch ;;
    --tag) dotag=1 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "template-release: unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

if [ -e .start-done ]; then
  echo "template-release: this is a project (start has run); releases are cut in the template repository" >&2
  exit 2
fi

TMP=""
trap 'case "$TMP" in */template-release.*) rm -f "$TMP" ;; esac' EXIT

last="$(git tag -l 'template-v*' | sort -V | tail -n 1)"
if [ -n "$last" ]; then
  ver="${last#template-v}"
  major="${ver%%.*}"; rest="${ver#*.}"
  minor="${rest%%.*}"; patch="${rest#*.}"
  case "$major.$minor.$patch" in
    *[!0-9.]*|.*|*..*|*.) echo "template-release: cannot parse tag $last as template-vMAJOR.MINOR.PATCH" >&2; exit 2 ;;
  esac
  case "$bump" in
    major) major=$((major + 1)); minor=0; patch=0 ;;
    minor) minor=$((minor + 1)); patch=0 ;;
    patch) patch=$((patch + 1)) ;;
  esac
  next="template-v$major.$minor.$patch"
  range="$last..HEAD"
  echo "template-release: last tag $last ($(git rev-parse --short "$last^{commit}"))"
else
  echo "template-release: no previous template-v* tag"
  next="template-v0.1.0"
  range="HEAD"
fi
echo "template-release: next version $next ($bump)"

kernel_block() { # git object -> kernel block, CR stripped
  git show "$1" 2>/dev/null | tr -d '\r' | sed -n '/<!-- KERNEL:BEGIN -->/,/<!-- KERNEL:END -->/p'
}
if [ -n "$last" ] && [ "$bump" != major ]; then
  if [ "$(kernel_block "$last:AGENTS.md")" != "$(kernel_block "HEAD:AGENTS.md")" ]; then
    echo "template-release: KERNEL CHANGED since $last: --major is suggested; projects need owner approval to take this release"
  fi
fi

commits="$(git log --no-merges --reverse --format='%h %s' "$range")"
if [ -z "$commits" ]; then
  echo "template-release: nothing to release since ${last:-the start}"
  if [ "$dotag" = 1 ]; then exit 1; fi
  exit 0
fi

set_lines="$(bash scripts/template-sync.sh --list-set)"

# touches GROUPS FILES: true when any file matches a set path of the given groups
touches() {
  local groups="$1" files="$2" g p f
  while read -r g p; do
    [ -n "$g" ] || continue
    case " $groups " in *" $g "*) ;; *) continue ;; esac
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      case "$p" in
        */) case "$f" in "$p"*) return 0 ;; esac ;;
        *) [ "$f" = "$p" ] && return 0 ;;
      esac
    done <<FILES
$files
FILES
  done <<SET
$set_lines
SET
  return 1
}

# Mirrors HEADER_LINES in scripts/template-sync.sh: only this many leading
# lines of a header file sync to projects.
HEADER_LINES=12

# header_differs SHA PATH: true when the first HEADER_LINES lines of PATH differ
# between SHA^ and SHA; a file absent on one side counts as differing.
header_differs() {
  local sha="$1" path="$2" a b
  if git cat-file -e "$sha^:$path" 2>/dev/null; then
    a="P$(git show "$sha^:$path" | head -n "$HEADER_LINES")"
  else a="absent"; fi
  if git cat-file -e "$sha:$path" 2>/dev/null; then
    b="P$(git show "$sha:$path" | head -n "$HEADER_LINES")"
  else b="absent"; fi
  [ "$a" != "$b" ]
}

rules_index() { # git object -> the Rules index section, CR stripped
  git show "$1" 2>/dev/null | tr -d '\r' | awk '/^## Rules index/{p=1; print; next} /^## /{p=0} p'
}

# is_synced SHA FILES: rule 1 of the notes classification.
is_synced() {
  local sha="$1" files="$2" g p
  if touches "core" "$files"; then return 0; fi
  while read -r g p; do
    [ "$g" = header ] || continue
    case "
$files
" in *"
$p
"*) if header_differs "$sha" "$p"; then return 0; fi ;; esac
  done <<SET
$set_lines
SET
  case "
$files
" in *"
AGENTS.md
"*)
    if [ "$(kernel_block "$sha^:AGENTS.md")" != "$(kernel_block "$sha:AGENTS.md")" ] \
      || [ "$(rules_index "$sha^:AGENTS.md")" != "$(rules_index "$sha:AGENTS.md")" ]; then
      return 0
    fi ;;
  esac
  return 1
}

synced=""; library=""; other=""
while IFS= read -r line; do
  [ -n "$line" ] || continue
  sha="${line%% *}"
  files="$(git diff-tree --no-commit-id --name-only -r --root "$sha")"
  if is_synced "$sha" "$files"; then synced="$synced- $line
"
  elif touches "catalog" "$files"; then library="$library- $line
"
  else other="$other- $line
"
  fi
done <<COMMITS
$commits
COMMITS

section() { # heading body
  printf '%s\n' "$1"
  if [ -n "$2" ]; then printf '%s' "$2"; else echo "- none"; fi
}
notes="$(section "## Synced to projects" "$synced"
section "## Library and roster (synced where a project carries them)" "$library"
section "## Not synced" "$other")"
echo
printf '%s\n' "$notes"
echo

if [ "$dotag" = 0 ]; then
  echo "template-release: dry run; no tag created (rerun with --tag)"
  exit 0
fi

branch="$(git symbolic-ref --short -q HEAD || true)"
if [ "$branch" != main ]; then
  echo "template-release: refusing to tag: current branch is '${branch:-detached}', not main" >&2
  exit 2
fi
if [ -n "$(git status --porcelain)" ]; then
  echo "template-release: refusing to tag: working tree is not clean" >&2
  exit 2
fi
if ! git rev-parse -q --verify refs/remotes/origin/main >/dev/null; then
  echo "template-release: refusing to tag: no origin/main; fetch first" >&2
  exit 2
fi
if [ "$(git rev-parse origin/main)" != "$(git rev-parse HEAD)" ]; then
  echo "template-release: refusing to tag: origin/main is not equal to HEAD; push or fetch first" >&2
  exit 2
fi
if git rev-parse -q --verify "refs/tags/$next" >/dev/null; then
  echo "template-release: refusing to tag: $next already exists" >&2
  exit 2
fi

TMP="$(mktemp "${TMPDIR:-/tmp}/template-release.XXXXXX")"
{ printf '%s\n\n' "$next"; printf '%s\n' "$notes"; } > "$TMP"
git tag -a "$next" -F "$TMP"
echo "template-release: created annotated tag $next at $(git rev-parse --short HEAD)"
echo "template-release: push it with: git push origin $next"
