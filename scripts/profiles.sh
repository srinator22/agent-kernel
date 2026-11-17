#!/usr/bin/env bash
# profiles.sh - the one parser of the AGENTS.md "- Profiles:" line, shared by
# scripts/template-sync.sh and scripts/lessons.sh so both adopt the same set.
# Usage: scripts/profiles.sh adopted [FILE]   (FILE defaults to AGENTS.md)
#        scripts/profiles.sh --help | -h
#
# Output: the adopted profile names, one per line, in line order, no
# duplicates. Nothing (exit 0) when FILE does not exist, has no "- Profiles:"
# line at the start of a line, or the value still holds a {{...}} placeholder
# (template mode). Only the first "- Profiles:" line counts.
#
# The value is a comma list of names, often followed by notes. Parsing rules:
# - backticks and CR are dropped; names are lowercased;
# - bracketed remarks "( ... )" are dropped;
# - the list ends at the first period or semicolon, so a trailing sentence
#   ("software, data-analysis. hardware-pcb deferred") adopts nothing;
# - " and " separates like a comma ("scientific and data-analysis");
# - the list stops at the first item that is not a single name (a lowercase
#   letter or digit, then letters, digits and hyphens), so prose never
#   becomes a profile; the word "none" adopts nothing.
# Whether a name has a profile folder is the caller's question.
#
# Exit: 0 parsed (possibly empty), 2 usage.
set -euo pipefail

# adopted_profile_names FILE: the names, one per line.
adopted_profile_names() {
  local file="$1" line item seen=" "
  [[ -f "$file" ]] || return 0
  line="$(grep -m1 -E '^- Profiles:' "$file" 2>/dev/null | tr -d '\r' || true)"
  [[ -n "$line" ]] || return 0
  line="${line#- Profiles:}"
  line="${line//\`/}"
  [[ "$line" == *"{{"* ]] && return 0
  line="$(printf '%s' "$line" | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/\([^)]*\)//g; s/[.;].*$//; s/[[:space:]]+and[[:space:]]+/,/g')"
  local IFS=','
  for item in $line; do
    item="${item#"${item%%[![:space:]]*}"}"
    item="${item%"${item##*[![:space:]]}"}"
    [[ "$item" =~ ^[a-z0-9][a-z0-9-]*$ ]] || break
    [[ "$item" == none ]] && continue
    [[ "$seen" == *" $item "* ]] && continue
    seen+="$item "
    echo "$item"
  done
  return 0
}

usage() {
  echo "usage: scripts/profiles.sh adopted [FILE]   (FILE defaults to AGENTS.md)" >&2
  exit 2
}

case "${1:-}" in
  adopted)
    (( $# <= 2 )) || usage
    adopted_profile_names "${2:-AGENTS.md}" ;;
  -h|--help)
    echo "usage: scripts/profiles.sh adopted [FILE]   (FILE defaults to AGENTS.md)"
    echo "  prints the profile names the '- Profiles:' line adopts, one per line" ;;
  *) usage ;;
esac
