#!/usr/bin/env bash
# adr.sh - numbering and format of the decision records in docs/decisions/
# (docs/procedures/adr.md).
#   check          exit 1 on any problem listed below
#   new <title>    create the next-numbered ADR from the template; print its path
# check enforces, for every docs/decisions/*.md except README.md:
#   the file name is NNNN-slug.md (four digits, lowercase kebab-case slug);
#   the numbers run 0001, 0002, ... with no gap and no duplicate;
#   the first line is "# NNNN - Title" with NNNN equal to the file's number;
#   before the first "## " heading there is a "Date: YYYY-MM-DD" line and a
#   non-empty "Status:" line; a "superseded by NNNN" status names an ADR that
#   exists;
#   the sections "## Context", "## Decision" and "## Consequences" are present,
#   in that order (other sections may follow or sit between them); lines
#   inside ``` or ~~~ fenced blocks are not headings;
#   no "{{" template placeholder is left in the file.
# No docs/decisions/ folder, or an empty one, passes.
# Test hook: ADR_TODAY=YYYY-MM-DD overrides today's date for new.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
DIR="docs/decisions"

usage() {
  echo "usage: scripts/adr.sh check | new <title>" >&2
  exit 2
}

# ADR files, one per line, sorted; README.md is the folder's own index.
adr_files() {
  [[ -d "$DIR" ]] || return 0
  find "$DIR" -maxdepth 1 -type f -name '*.md' ! -name README.md | sed 's|^\./||' | LC_ALL=C sort
}

cmd_check() {
  local errs=() f base num prev=0 expect title header date status target seen=" " c d q
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    base="$(basename "$f")"
    if [[ ! "$base" =~ ^([0-9]{4})-[a-z0-9]+(-[a-z0-9]+)*\.md$ ]]; then
      errs+=("$f: file name must be NNNN-slug.md (four digits, lowercase kebab-case slug)")
      continue
    fi
    num="${BASH_REMATCH[1]}"
    if [[ "$seen" == *" $num "* ]]; then
      errs+=("$f: duplicate number $num")
    else
      expect=$((prev + 1))
      if (( 10#$num != expect )); then
        errs+=("$f: number $num breaks the sequence; expected $(printf '%04d' "$expect")")
      fi
      prev=$((10#$num))
    fi
    seen="$seen$num "
    title="$(head -n 1 "$f" | tr -d '\r')"
    if [[ ! "$title" =~ ^#\ ([0-9]{4})\ -\ [^[:space:]].*$ ]]; then
      errs+=("$f: first line must be '# $num - Title', found '$title'")
    elif [[ "${BASH_REMATCH[1]}" != "$num" ]]; then
      errs+=("$f: title number ${BASH_REMATCH[1]} does not match the file number $num")
    fi
    header="$(awk 'NR > 1 && /^## / { exit } { sub(/\r$/, ""); print }' "$f")"
    date="$(printf '%s\n' "$header" | sed -n 's/^Date: *//p' | head -n 1)"
    status="$(printf '%s\n' "$header" | sed -n 's/^Status: *//p' | head -n 1)"
    if [[ ! "$date" =~ ^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$ ]]; then
      errs+=("$f: needs a 'Date: YYYY-MM-DD' line before the first section, found '${date:-none}'")
    fi
    if [[ -z "${status//[[:space:]]/}" ]]; then
      errs+=("$f: needs a non-empty 'Status:' line before the first section")
    elif [[ "$status" =~ [Ss]uperseded\ by\ ([0-9]{4}) ]]; then
      target="${BASH_REMATCH[1]}"
      if ! ls "$DIR/$target"-*.md >/dev/null 2>&1; then
        errs+=("$f: status names ADR $target, which does not exist")
      fi
    fi
    read -r c d q < <(awk '{ sub(/\r$/, "") }
      /^ ? ? ?(```|~~~)/ { fence = !fence; next }
      fence { next }
      $0 == "## Context" && !c { c = NR }
      $0 == "## Decision" && !d { d = NR }
      $0 == "## Consequences" && !q { q = NR }
      END { print c + 0, d + 0, q + 0 }' "$f")
    if (( c == 0 || d == 0 || q == 0 )); then
      errs+=("$f: needs the sections '## Context', '## Decision' and '## Consequences'")
    elif (( c > d || d > q )); then
      errs+=("$f: the sections must run '## Context', '## Decision', '## Consequences' in that order")
    fi
    if grep -q '{{' "$f"; then
      errs+=("$f: still holds a {{ template placeholder; fill it in")
    fi
  done < <(adr_files)

  if (( ${#errs[@]} > 0 )); then
    local e
    for e in "${errs[@]}"; do echo "adr: $e" >&2; done
    echo "adr: check FAILED (${#errs[@]} problem(s))" >&2
    exit 1
  fi
  echo "adr: OK ($prev decision records, numbered 0001 to $(printf '%04d' "$prev"))"
}

cmd_new() {
  local title="$*" slug max=0 f n next path today
  title="$(printf '%s' "$title" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  [[ -n "$title" ]] || usage
  slug="$(printf '%s' "$title" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//' | cut -c1-60 | sed -E 's/-+$//')"
  if [[ -z "$slug" ]]; then
    echo "adr: the title '$title' gives an empty file name slug; use letters or digits" >&2
    exit 2
  fi
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    n="$(basename "$f" | sed -n 's/^\([0-9]\{4\}\)-.*/\1/p')"
    [[ -n "$n" ]] || continue
    if (( 10#$n > max )); then max=$((10#$n)); fi
  done < <(adr_files)
  next="$(printf '%04d' $((max + 1)))"
  path="$DIR/$next-$slug.md"
  today="${ADR_TODAY:-$(date -u +%F)}"
  mkdir -p "$DIR"
  if [[ -e "$path" ]]; then
    echo "adr: $path already exists" >&2
    exit 1
  fi
  {
    echo "# $next - $title"
    echo
    echo "Date: $today"
    echo "Status: accepted"
    echo
    echo "## Context"
    echo
    echo "{{The situation and the forces at play, with the numbers that made the"
    echo "decision necessary. Each alternative seriously considered and the specific"
    echo "reason it lost; if nothing else was considered, say so and why.}}"
    echo
    echo "## Decision"
    echo
    echo "{{What was chosen, stated plainly in a few sentences.}}"
    echo
    echo "## Consequences"
    echo
    echo "{{What gets easier, what gets harder, what we are now committed to, and"
    echo "any open question the decision leaves.}}"
  } > "$path"
  echo "$path"
}

case "${1:-}" in
  check) cmd_check ;;
  new) shift; cmd_new "$@" ;;
  *) usage ;;
esac
