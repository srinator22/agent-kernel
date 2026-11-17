#!/usr/bin/env bash
# rating.sh - the numbers behind a template rating, one labelled line each.
# Usage: scripts/rating.sh [--offline]
#        scripts/rating.sh --help | -h
#
# Inputs:  BACKLOG.md (table rows whose last column is "open"; priority is the
#          leading P0-P3 token of the Priority column, the second-to-last-but-one
#          field, so a "|" inside an item does not shift it), scripts/lessons.sh
#          stats (lesson slots, never-used count, skills against their cap: one
#          definition, so the cap rule of AGENTS.md kernel rule 10 lives in one
#          place), docs/lessons/MAINTENANCE.log (last dated line that is not a
#          template-sync record), template-v* tags, scripts/fleet-status.sh --tsv,
#          and gh for the CI conclusion of main and merged-PR cycle time.
# Output:  "label: value" lines. Anything unknown prints "N/A - <reason>"; nothing
#          is estimated.
# Depends: bash, git, sed, awk, sort; gh only for the CI and cycle-time lines.
#          --offline skips gh without trying it.
# Exit:    0 always after a successful parse; 2 on a usage error.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

usage() {
  echo "Usage: scripts/rating.sh [--offline]" >&2
  echo "       scripts/rating.sh --help | -h" >&2
}
OFFLINE=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --offline) OFFLINE=1; shift ;;
    *) usage; exit 2 ;;
  esac
done

# Backlog: open rows by priority.
if [[ -f BACKLOG.md ]]; then
  counts="$(awk -F'|' '
    /^\|/ && NF >= 5 {
      st = $(NF-1); pr = $(NF-3)
      gsub(/^[ \t]+|[ \t]+$/, "", st); gsub(/^[ \t]+|[ \t]+$/, "", pr)
      if (st != "open") next
      split(pr, t, /[ \t]/)
      if (t[1] ~ /^P[0-3]$/) n[t[1]]++; else other++
    }
    END { printf "%d %d %d %d %d\n", n["P0"], n["P1"], n["P2"], n["P3"], other }' BACKLOG.md)"
  read -r p0 p1 p2 p3 po <<< "$counts"
  echo "backlog open P0: $p0"
  echo "backlog open P1: $p1"
  echo "backlog open P2: $p2"
  echo "backlog open P3: $p3"
  if [[ "$po" -gt 0 ]]; then echo "backlog open without a P0-P3 priority: $po"; fi
else
  echo "backlog open: N/A - BACKLOG.md missing"
fi

# Lessons and skills: scripts/lessons.sh stats.
if [[ -x scripts/lessons.sh ]] && st="$(scripts/lessons.sh stats 2>/dev/null)"; then
  while IFS= read -r l; do
    case "$l" in
      "approved lessons:"*|"skills:"*) echo "$l" ;;
    esac
  done <<< "$st"
else
  echo "approved lessons: N/A - scripts/lessons.sh stats unavailable"
  echo "skills: N/A - scripts/lessons.sh stats unavailable"
fi

# Last maintain pass: the newest dated line of the log that is not a sync record.
last="N/A - no maintain pass recorded"
if [[ -f docs/lessons/MAINTENANCE.log ]]; then
  m="$(grep -E '^[0-9]{4}-[0-9]{2}-[0-9]{2}' docs/lessons/MAINTENANCE.log | tr -d '\r' | sed -n 's/^\([0-9-]\{10\}\).*/\1/p' | sort | tail -n 1 || true)"
  [[ -n "$m" ]] && last="$m"
fi
echo "last maintain pass: $last"

tag="$(git tag -l 'template-v*' | sort -V | tail -n 1)"
echo "latest template tag: ${tag:-N/A - no template-v* tag}"

# json_field NAME JSONLINE: first string value of "NAME".
json_field() { printf '%s' "$2" | sed -n 's/.*"'"$1"'":"\([^"]*\)".*/\1/p' | sed -n 1p; }

# epoch YYYY-MM-DDTHH:MM:SSZ: seconds since 1970 in pure bash (date -d is not on macOS).
epoch() {
  local s="$1" y m d hh mm ss era yoe doy doe days
  y=$((10#${s:0:4})); m=$((10#${s:5:2})); d=$((10#${s:8:2}))
  hh=$((10#${s:11:2})); mm=$((10#${s:14:2})); ss=$((10#${s:17:2}))
  if (( m <= 2 )); then y=$((y - 1)); fi
  era=$((y / 400)); yoe=$((y - era * 400))
  doy=$(( (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1 ))
  doe=$((yoe * 365 + yoe / 4 - yoe / 100 + doy))
  days=$((era * 146097 + doe - 719468))
  echo $((days * 86400 + hh * 3600 + mm * 60 + ss))
}

GH_NA="N/A - gh unavailable/offline"
if [[ $OFFLINE -eq 1 ]] || ! command -v gh >/dev/null 2>&1; then
  echo "CI status of main: $GH_NA"
  echo "agent cycle time (median PR open to merge, last 30 merged): $GH_NA"
else
  if run="$(gh run list --branch main --limit 1 --json conclusion,headSha 2>/dev/null)" && [[ -n "$run" ]]; then
    c="$(json_field conclusion "$run")"; sha="$(json_field headSha "$run")"
    if [[ -z "$sha" ]]; then echo "CI status of main: N/A - no workflow run on main"
    elif [[ -z "$c" ]]; then echo "CI status of main: N/A - latest run not finished (${sha:0:7})"
    else echo "CI status of main: $c (${sha:0:7})"; fi
  else
    echo "CI status of main: $GH_NA"
  fi
  if prs="$(gh pr list --state merged --limit 30 --json createdAt,mergedAt 2>/dev/null)" && [[ -n "$prs" ]]; then
    durs=""; n=0
    while IFS= read -r pair || [[ -n "$pair" ]]; do
      [[ -n "$pair" ]] || continue
      cr="${pair%%,*}"; mg="${pair#*,}"
      [[ "$cr" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$ && "$mg" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$ ]] || continue
      durs="$durs$(( $(epoch "$mg") - $(epoch "$cr") ))"$'\n'; n=$((n + 1))
    done < <(printf '%s' "$prs" | sed 's/},{/}\n{/g' | sed -n 's/.*"createdAt":"\([^"]*\)".*"mergedAt":"\([^"]*\)".*/\1,\2/p')
    if [[ $n -eq 0 ]]; then
      echo "agent cycle time (median PR open to merge, last 30 merged): N/A - no merged PRs"
    else
      med="$(printf '%s' "$durs" | sort -n | awk '{a[NR]=$1} END {if (NR%2) print a[(NR+1)/2]; else printf "%d\n", (a[NR/2]+a[NR/2+1])/2}')"
      echo "agent cycle time (median PR open to merge, last 30 merged): $((med / 3600))h $(( (med % 3600) / 60 ))m (n=$n)"
    fi
  else
    echo "agent cycle time (median PR open to merge, last 30 merged): $GH_NA"
  fi
fi

# Fleet versions.
if [[ -x scripts/fleet-status.sh ]] && fs="$(scripts/fleet-status.sh --tsv 2>/dev/null)"; then
  n=0
  while IFS=$'\t' read -r path ref synced behind dirty state url; do
    [[ "$path" == project ]] && continue
    [[ -n "$path" ]] || continue
    n=$((n + 1))
    echo "fleet: $(basename "$path") ref=$ref synced=$synced behind=$behind state=$state"
  done <<< "$fs"
  echo "fleet projects: $n"
else
  echo "fleet: N/A - scripts/fleet-status.sh failed (no fleet list?)"
fi
