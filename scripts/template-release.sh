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
# commit kinds from "scripts/template-sync.sh --synced-commits".
# Version bump: --minor (default), --major, --patch. No previous tag: proposes
# template-v0.1.0 and the notes cover all commits.
# Kernel: when the KERNEL block differs from the last tag and --major was not
# given, a KERNEL CHANGED line suggests --major.
# Notes: each commit appears once. The classification is the kind that
# "scripts/template-sync.sh --synced-commits <range>" prints per commit (the
# first that applies in the order core, header, agents, catalog):
#   1. core, header or agents -> "Synced to projects": it touches a core path;
#      or a header path (lessons files, of which only the first HEADER_LINES
#      lines sync) and those lines differ between <sha>^ and <sha> (a file
#      absent on one side differs; a root commit compares against empty); or
#      AGENTS.md and the KERNEL block or the rules index (from "## Rules index"
#      up to the next "## " line) differs between <sha>^ and <sha>, CR stripped.
#   2. else catalog (it touches a catalog path) -> "Library and roster".
#   3. else "Not synced".
# Output: the notes on stdout. Without --tag it is a dry run; it warns when
# .work/TASK.md at HEAD is a live task.
# --tag guards (exit 2 on failure): branch is main, clean tree, origin/main
# exists and equals HEAD, .work/TASK.md at HEAD is absent or pristine (holds
# the title placeholder), the tag does not exist. It creates an annotated tag
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

# The commits that change what projects receive come from the sync script, the
# one definition fleet.sh also uses: "<full sha> <kind>" lines, kind core,
# header, agents or catalog. Core, header and agents are "Synced to projects";
# catalog is "Library and roster". Newline-framed for the lookup below.
synced_shas="$(bash scripts/template-sync.sh --synced-commits "$range")"
synced_shas="
$synced_shas
"

# commit_kind SHA: the kind the sync script gave the commit, or empty.
commit_kind() {
  local full
  full="$(git rev-parse "$1")"
  printf '%s' "$synced_shas" | sed -n "s/^$full //p" | head -n 1
}

synced=""; library=""; other=""
while IFS= read -r line; do
  [ -n "$line" ] || continue
  sha="${line%% *}"
  kind="$(commit_kind "$sha")"
  case "$kind" in
    core|header|agents) synced="$synced- $line
" ;;
    catalog) library="$library- $line
" ;;
    *) other="$other- $line
" ;;
  esac
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

# A live task record at HEAD would ship inside the tag (template-v0.3.0
# carried one). Pristine means the file is absent or still holds the title
# placeholder, the test scripts/new-task.sh and scripts/stop-gate.sh use.
live_task=0
if git cat-file -e "HEAD:.work/TASK.md" 2>/dev/null; then
  case "$(git show "HEAD:.work/TASK.md")" in
    *'{{title}}'*) ;;
    *) live_task=1 ;;
  esac
fi
if [ "$live_task" = 1 ]; then
  echo "template-release: WARNING: .work/TASK.md at HEAD is a live task; a tag now would ship it"
fi

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
if [ "$live_task" = 1 ]; then
  echo "template-release: refusing to tag: .work/TASK.md at HEAD is a live task; finish the task with docs/procedures/retro.md (it archives the record to .work/done/), merge, then tag" >&2
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
