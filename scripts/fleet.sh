#!/usr/bin/env bash
# fleet.sh - one read-only status row per local project that started from this template.
# Usage: scripts/fleet.sh [--list <file>]
#        scripts/fleet.sh --help | -h
#
# Inputs:  the list file (default fleet.local.list at the repo root): one absolute
#          project path per line; blank lines and lines starting with # are ignored;
#          a trailing CR is stripped. Template tags and history come from this repo
#          (no network); synced paths from scripts/template-sync.sh --list-set.
# Output:  a header row, one row per project (project, template, synced, behind,
#          dirty, branch, upstream, status), then a summary line and the newest
#          template tag. Status, first match wins: MISSING, BAD-LINE, NO-BASE,
#          BEHIND, OK. behind counts commits touching the core and catalog
#          paths between the project's last synced ref and the newest
#          template-v* tag.
# Depends: bash, git, sort -V. Strictly read-only: never writes in a project, never
#          clones or fetches.
# Exit:    0 whenever the list file exists (statuses are information), 2 on usage
#          errors, a missing list file, or when run outside template mode.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat <<'USAGE'
Usage: scripts/fleet.sh [--list <file>]
       scripts/fleet.sh --help | -h
Prints one read-only status row per project listed in fleet.local.list
(one absolute project path per line; # comments and blank lines ignored).
USAGE
}

LIST="$ROOT/fleet.local.list"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --list)
      if [[ $# -lt 2 ]]; then usage >&2; exit 2; fi
      LIST="$2"; shift 2 ;;
    *) usage >&2; exit 2 ;;
  esac
done

if [[ -e "$ROOT/.start-done" ]]; then
  echo "fleet: run this in the template repository (start has run here)" >&2
  exit 2
fi
if [[ ! -f "$LIST" ]]; then
  usage >&2
  echo "fleet: create fleet.local.list with one absolute project path per line" >&2
  exit 2
fi

NEWEST="$(git -C "$ROOT" tag -l 'template-v*' | sort -V | tail -n 1)"

# Only the core and catalog groups count: the lessons files sync their header
# only and AGENTS.md is never applied, so edits there are not "behind".
SPECS=()
while IFS= read -r line; do
  line="${line%$'\r'}"
  case "$line" in
    core\ *|catalog\ *) SPECS+=("${line#* }") ;;
  esac
done < <("$ROOT/scripts/template-sync.sh" --list-set)

FMT='%-28s %-16s %-26s %-7s %-6s %-14s %-8s %s\n'
printf "$FMT" project template synced behind dirty branch upstream status

n=0; c_ok=0; c_behind=0; c_nobase=0; c_bad=0; c_missing=0
while IFS= read -r path || [[ -n "$path" ]]; do
  path="${path%$'\r'}"
  [[ -n "$path" && "${path:0:1}" != "#" ]] || continue
  n=$((n + 1))
  name="$(basename "$path")"
  tmpl="-"; synced="-"; behind="?"; dirty="-"; branch="-"; upstream=0
  status=""

  if [[ ! -d "$path" || ! -f "$path/AGENTS.md" ]]; then
    status=MISSING
  else
    tl="$(grep -m1 '^- Template:' "$path/AGENTS.md" | tr -d '\r' || true)"
    valid=0
    if [[ -n "$tl" ]]; then
      rest="${tl#- Template:}"
      read -r -a toks <<< "$rest" || true
      if [[ ${#toks[@]} -eq 2 ]]; then valid=1; tmpl="${toks[1]}"; fi
    fi
    log="$path/docs/lessons/MAINTENANCE.log"
    if [[ -f "$log" ]]; then
      sl="$(grep '^template-sync: ' "$log" | tr -d '\r' | tail -n 1 || true)"
      if [[ -n "$sl" ]]; then
        read -r -a stoks <<< "$sl" || true
        [[ ${#stoks[@]} -ge 2 ]] && synced="${stoks[1]}"
      fi
    fi
    resolves=0
    if [[ "$synced" != "-" ]] && git -C "$ROOT" rev-parse -q --verify "${synced}^{commit}" >/dev/null 2>&1; then
      resolves=1
    fi
    if [[ $resolves -eq 1 && -n "$NEWEST" ]]; then
      behind="$(git -C "$ROOT" rev-list --count "${synced}..${NEWEST}" -- "${SPECS[@]}" 2>/dev/null || echo '?')"
    fi
    if git -C "$path" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      # --no-optional-locks: a status must not refresh the project's index.
      dirty="$(git -C "$path" --no-optional-locks status --porcelain | wc -l | tr -d '[:space:]')"
      branch="$(git -C "$path" symbolic-ref --short -q HEAD || true)"
      [[ -n "$branch" ]] || branch="detached"
    fi
    if [[ -f "$path/docs/lessons/UPSTREAM.md" ]]; then
      upstream="$(grep -c '^- what happened:[[:space:]]*[^[:space:]]' "$path/docs/lessons/UPSTREAM.md" || true)"
      upstream="${upstream:-0}"
    fi
    if [[ $valid -eq 0 ]]; then status=BAD-LINE; tmpl="-"
    elif [[ $resolves -eq 0 ]]; then status=NO-BASE
    elif [[ "$behind" =~ ^[0-9]+$ && "$behind" -gt 0 ]]; then status=BEHIND
    else status=OK; fi
  fi

  case "$status" in
    OK) c_ok=$((c_ok + 1)) ;;
    BEHIND) c_behind=$((c_behind + 1)) ;;
    NO-BASE) c_nobase=$((c_nobase + 1)) ;;
    BAD-LINE) c_bad=$((c_bad + 1)) ;;
    MISSING) c_missing=$((c_missing + 1)) ;;
  esac
  printf "$FMT" "$name" "$tmpl" "$synced" "$behind" "$dirty" "$branch" "$upstream" "$status"
done < "$LIST"

echo "fleet: $n projects: $c_ok OK, $c_behind BEHIND, $c_nobase NO-BASE, $c_bad BAD-LINE, $c_missing MISSING"
if [[ -n "$NEWEST" ]]; then echo "fleet: newest template tag $NEWEST"; fi
