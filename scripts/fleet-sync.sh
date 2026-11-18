#!/usr/bin/env bash
# fleet-sync.sh - prepare one template-sync branch per local project of the fleet.
# Usage: scripts/fleet-sync.sh [--list FILE] [--ref TAG] [--dry-run]
#        scripts/fleet-sync.sh --help | -h
#
# Inputs:  the list file (default fleet.local.list at the repo root; FLEET_LIST
#          or --list overrides): one absolute project path per line, blank lines
#          and # comments ignored, a trailing CR stripped (the format fleet.sh
#          reads). --ref defaults to the newest template-v* tag of this repo.
# Output:  per project a sibling git worktree "<project>-template-<ref>" on a new
#          branch chore/template-<ref> cut from the project's current HEAD, with
#          the project's own scripts/template-sync.sh run in it. One summary line
#          per project: path, result, worktree path. Results: applied, KERNEL
#          CHANGE (owner), conflicts, skipped: <reason>, error: <reason>.
#          The template-sync output is kept in <worktree>/.work/template-sync/fleet-sync.out.
# Kernel:  --accept-kernel is passed to a project only when a line of its
#          AGENTS.md contains "Standing overrides" and the exact phrase "template
#          kernel accepted verbatim" (kernel rule 15: the human records that in
#          that project; this script never writes it). Any other project stops
#          at KERNEL CHANGE for its owner, while every non-kernel file still syncs.
# Assumes: run in the template repository; each project's scripts/ are committed
#          and it has a "- Template: <url> <tag>" line, so the project's own
#          template-sync.sh finds the template. A project whose script predates
#          --accept-kernel is reported as an error when it needs the flag, since
#          its own script cannot be replaced without dirtying the clean tree the
#          sync requires.
# Never:   commits, pushes, or touches a project's main checkout. The owner
#          reviews each worktree, commits it, and merges it by the project's workflow.
# Exit:    0 when every project applied, was skipped or (dry run) planned; 1
#          otherwise; 2 on usage errors or a missing list file.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  echo "usage: scripts/fleet-sync.sh [--list FILE] [--ref TAG] [--dry-run]" >&2
  echo "  list: fleet.local.list at the repo root (or FLEET_LIST): one absolute project path per line" >&2
}

LIST="${FLEET_LIST:-$ROOT/fleet.local.list}"
REF=""
DRY=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --list) [[ $# -ge 2 ]] || { usage; exit 2; }; LIST="$2"; shift 2 ;;
    --ref) [[ $# -ge 2 ]] || { usage; exit 2; }; REF="$2"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    *) usage; exit 2 ;;
  esac
done

if [[ ! -f "$LIST" ]]; then
  usage
  echo "fleet-sync: list file not found: $LIST (one absolute project path per line)" >&2
  exit 2
fi
if [[ -z "$REF" ]]; then
  REF="$(git -C "$ROOT" tag -l 'template-v*' | sort -V | tail -n 1)"
  [[ -n "$REF" ]] || { echo "fleet-sync: no template-v* tag in $ROOT; pass --ref" >&2; exit 2; }
fi
# A ref becomes part of a branch and folder name; refuse anything that is not
# a plain tag name before it reaches git or the file system.
[[ "$REF" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "fleet-sync: unusable --ref '$REF'" >&2; exit 2; }

BAD=0
report() { # path result worktree
  printf '%s  %s  %s\n' "$1" "$2" "$3"
  case "$2" in applied|skipped:*|"dry run"*) ;; *) BAD=1 ;; esac
}

while IFS= read -r path || [[ -n "$path" ]]; do
  path="${path%$'\r'}"
  [[ -n "$path" && "${path:0:1}" != "#" ]] || continue
  wt="${path%/}-template-$REF"
  branch="chore/template-$REF"

  # A project is a repository root: a plain folder inside some other repository
  # (show-cdup is then not empty) must not get a worktree of that repository.
  if [[ ! -d "$path" ]] || ! cup="$(git -C "$path" rev-parse --show-cdup 2>/dev/null)" || [[ -n "$cup" ]]; then
    report "$path" "skipped: not a git repository" "-"; continue
  fi
  if ! git -C "$path" symbolic-ref -q HEAD >/dev/null 2>&1; then
    report "$path" "skipped: the main checkout is not on a branch" "-"; continue
  fi
  if [[ -e "$wt" ]]; then
    report "$path" "skipped: worktree folder already exists" "$wt"; continue
  fi
  if git -C "$path" rev-parse --verify -q "refs/heads/$branch" >/dev/null 2>&1; then
    report "$path" "skipped: branch $branch already exists" "$wt"; continue
  fi
  if ! git -C "$path" cat-file -e HEAD:scripts/template-sync.sh 2>/dev/null; then
    report "$path" "skipped: no committed scripts/template-sync.sh" "-"; continue
  fi

  accept=()
  overrides="$(git -C "$path" show HEAD:AGENTS.md 2>/dev/null | tr -d '\r' | grep -F "Standing overrides" || true)"
  case "$overrides" in *"template kernel accepted verbatim"*) accept=(--accept-kernel) ;; esac
  if (( DRY )); then
    echo "dry run: $path: git worktree add -b $branch $wt; scripts/template-sync.sh --ref $REF ${accept[*]-}"
    report "$path" "dry run (nothing changed)" "$wt"; continue
  fi

  if ! git -C "$path" worktree add -q -b "$branch" "$wt" HEAD >/dev/null 2>&1; then
    report "$path" "error: git worktree add failed" "$wt"; continue
  fi
  if (( ${#accept[@]} )) && ! grep -q -- '--accept-kernel' "$wt/scripts/template-sync.sh"; then
    report "$path" "error: its scripts/template-sync.sh predates --accept-kernel; run the template's script once by hand" "$wt"; continue
  fi
  rc=0
  out="$(cd "$wt" && bash scripts/template-sync.sh --ref "$REF" ${accept[@]+"${accept[@]}"} 2>&1)" || rc=$?
  mkdir -p "$wt/.work/template-sync"
  printf '%s\n' "$out" > "$wt/.work/template-sync/fleet-sync.out"
  if (( rc == 0 )); then res="applied"
  elif (( rc == 1 )) && grep -q '^KERNEL CHANGE' <<< "$out"; then res="KERNEL CHANGE (owner)"
  elif (( rc == 1 )) && grep -q '^CONFLICT ' <<< "$out"; then res="conflicts"
  else res="error: template-sync exit $rc (see .work/template-sync/fleet-sync.out)"; fi
  report "$path" "$res" "$wt"
done < "$LIST"

exit $BAD
