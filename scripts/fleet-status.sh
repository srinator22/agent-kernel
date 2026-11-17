#!/usr/bin/env bash
# fleet-status.sh - the fleet's template versions on one screen: per local project
# its synced template ref, last sync date and how many releases it is behind.
# Usage: scripts/fleet-status.sh [--list <file>] [--tsv]
#        scripts/fleet-status.sh --help | -h
#
# Inputs:  the list file, resolved as scripts/fleet.sh and scripts/dream/fleet.py
#          resolve it: --list, else fleet.local.list at the repo root, else at the
#          main checkout of this repo (a linked worktree has none of its own). One
#          absolute project path per line; blank lines and # comments ignored; a
#          trailing CR stripped. The "- Template: <url> <ref>" line is read as
#          fleet.sh reads it (first such line in AGENTS.md, exactly two tokens) and
#          the last sync date from the last "template-sync: <ref> <date>" line of
#          docs/lessons/MAINTENANCE.log. Template tags come from THIS repo.
# Output:  an aligned table (project, ref, synced, behind, dirty, state, url), or
#          with --tsv a tab-separated header row plus one row per project. behind
#          counts template-v* tags newer (sort -V) than the project's ref; an
#          untagged ref that is a commit here counts from the nearest tag at or
#          before it (git describe); a commit with no tag in its history counts the tags that contain its fork point from HEAD; any other ref gives "unknown". state is "ok",
#          "missing" (folder or AGENTS.md absent), "no-template-line" or "bad-line"
#          (extra or missing tokens; the readable url and ref are still shown). url
#          is shown only when it differs from this repo's origin (an old repo name).
# Depends: bash, git, sort -V. Read-only and offline: never writes in a project and
#          runs only git rev-parse, git status --no-optional-locks --porcelain and
#          reads in this repo (tag, describe, remote get-url); no network.
#          scripts/fleet.sh counts synced-set commits instead of tags; this script
#          answers "which version", not "what changed".
# Exit:    0 whenever the list exists (lagging projects are information), 1 on a
#          usage error or when no list file exists, or when run after start.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat <<'USAGE'
Usage: scripts/fleet-status.sh [--list <file>] [--tsv]
       scripts/fleet-status.sh --help | -h
Prints, per project in the fleet list, its template ref, last sync date and the
number of template releases it is behind. Read-only, no network.
USAGE
}

LIST=""
TSV=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --tsv) TSV=1; shift ;;
    --list)
      if [[ $# -lt 2 ]]; then usage >&2; exit 1; fi
      LIST="$2"; shift 2 ;;
    *) usage >&2; exit 1 ;;
  esac
done

if [[ -e "$ROOT/.start-done" ]]; then
  echo "fleet-status: run this in the template repository (start has run here)" >&2
  exit 1
fi

if [[ -z "$LIST" ]]; then
  LIST="$ROOT/fleet.local.list"
  if [[ ! -f "$LIST" ]]; then
    common="$(git -C "$ROOT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
    if [[ -n "$common" && "$(basename "$common")" == ".git" && -f "$(dirname "$common")/fleet.local.list" ]]; then
      LIST="$(dirname "$common")/fleet.local.list"
    fi
  fi
fi
if [[ ! -f "$LIST" ]]; then
  usage >&2
  echo "fleet-status: no list file $LIST; create fleet.local.list with one absolute project path per line" >&2
  exit 1
fi

TAGS="$(git -C "$ROOT" tag -l 'template-v*' | sort -V)"
NTAGS=0
if [[ -n "$TAGS" ]]; then NTAGS="$(printf '%s\n' "$TAGS" | grep -c . || true)"; fi

# norm_url URL: compare URLs without a trailing slash or .git suffix.
norm_url() { local u="${1%/}"; printf '%s' "${u%.git}"; }
ORIGIN="$(git -C "$ROOT" remote get-url origin 2>/dev/null || true)"
[[ -n "$ORIGIN" ]] && ORIGIN="$(norm_url "$ORIGIN")"

# tag_index TAG: 1-based position of TAG in the version-sorted tag list, or 0.
tag_index() {
  printf '%s\n' "$TAGS" | grep -nxF -- "$1" | sed -n 's/:.*//p' | sed -n 1p
}

# behind_of REF: tags newer than REF, or "unknown".
behind_of() {
  local ref="$1" idx base fork
  if [[ -z "$TAGS" ]]; then echo unknown; return; fi
  idx="$(tag_index "$ref" || true)"
  if [[ -z "$idx" ]]; then
    if git -C "$ROOT" rev-parse -q --verify "${ref}^{commit}" >/dev/null 2>&1; then
      base="$(git -C "$ROOT" describe --tags --abbrev=0 --match 'template-v*' "${ref}^{commit}" 2>/dev/null || true)"
      if [[ -z "$base" ]]; then
        # No tag lies in the commit's history, so it predates the tagged line (or
        # sits on a side branch of it): the tags that contain where it meets HEAD's
        # history are all newer.
        fork="$(git -C "$ROOT" merge-base "${ref}^{commit}" HEAD 2>/dev/null || true)"
        if [[ -n "$fork" ]]; then
          git -C "$ROOT" tag -l 'template-v*' --contains "$fork" | grep -c . || true
          return
        fi
      fi
      [[ -n "$base" ]] && idx="$(tag_index "$base" || true)"
    fi
  fi
  if [[ -z "$idx" ]]; then echo unknown; else echo $((NTAGS - idx)); fi
}

HDR=(project ref synced behind dirty state url)
ROWS=()
add_row() { ROWS+=("$1"$'\t'"$2"$'\t'"$3"$'\t'"$4"$'\t'"$5"$'\t'"$6"$'\t'"$7"); }

while IFS= read -r path || [[ -n "$path" ]]; do
  path="${path%$'\r'}"
  [[ -n "$path" && "${path:0:1}" != "#" ]] || continue
  ref="-"; synced="-"; behind="-"; dirty="-"; state=missing; url="-"
  if [[ -d "$path" && -f "$path/AGENTS.md" ]]; then
    state=no-template-line
    tl="$(grep -m1 '^- Template:' "$path/AGENTS.md" | tr -d '\r' || true)"
    if [[ -n "$tl" ]]; then
      read -r -a toks <<< "${tl#- Template:}" || true
      # Exactly two tokens is a valid line; anything else is bad-line (as in
      # fleet.sh) but the url and ref tokens that can be read are still shown.
      if [[ ${#toks[@]} -eq 2 ]]; then state=ok; else state=bad-line; fi
      if [[ ${#toks[@]} -ge 1 && -n "$ORIGIN" && "$(norm_url "${toks[0]}")" != "$ORIGIN" ]]; then url="${toks[0]}"; fi
      if [[ ${#toks[@]} -ge 2 ]]; then ref="${toks[1]}"; fi
    fi
    if [[ "$ref" != "-" ]]; then
      log="$path/docs/lessons/MAINTENANCE.log"
      if [[ -f "$log" ]]; then
        sl="$(grep '^template-sync: ' "$log" | tr -d '\r' | tail -n 1 || true)"
        if [[ -n "$sl" ]]; then
          read -r -a stoks <<< "$sl" || true
          [[ ${#stoks[@]} -ge 3 ]] && synced="${stoks[2]}"
        fi
      fi
      behind="$(behind_of "$ref")"
    fi
    if git -C "$path" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      dirty="$(git -C "$path" --no-optional-locks status --porcelain | wc -l | tr -d '[:space:]')"
    fi
  fi
  add_row "$path" "$ref" "$synced" "$behind" "$dirty" "$state" "$url"
done < "$LIST"

if [[ $TSV -eq 1 ]]; then
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "${HDR[@]}"
  for r in ${ROWS[@]+"${ROWS[@]}"}; do printf '%s\n' "$r"; done
  exit 0
fi

# Aligned table: width per column is the longest cell.
w=(0 0 0 0 0 0 0)
rows_all=("$(IFS=$'\t'; echo "${HDR[*]}")")
for r in ${ROWS[@]+"${ROWS[@]}"}; do rows_all+=("$r"); done
for r in "${rows_all[@]}"; do
  IFS=$'\t' read -r -a c <<< "$r" || true
  for i in 0 1 2 3 4 5 6; do
    cell="${c[$i]:-}"
    if [[ ${#cell} -gt ${w[$i]} ]]; then w[$i]=${#cell}; fi
  done
done
for r in "${rows_all[@]}"; do
  IFS=$'\t' read -r -a c <<< "$r" || true
  printf '%-*s  %-*s  %-*s  %-*s  %-*s  %-*s  %s\n' \
    "${w[0]}" "${c[0]:-}" "${w[1]}" "${c[1]:-}" "${w[2]}" "${c[2]:-}" "${w[3]}" "${c[3]:-}" \
    "${w[4]}" "${c[4]:-}" "${w[5]}" "${c[5]:-}" "${c[6]:-}"
done
NEWEST="$(printf '%s\n' "$TAGS" | tail -n 1)"
if [[ -n "$NEWEST" ]]; then echo "newest template tag: $NEWEST"; fi
exit 0
