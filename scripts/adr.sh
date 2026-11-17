#!/usr/bin/env bash
# adr.sh - numbering and format of the decision records (docs/procedures/adr.md).
#   check          exit 1 on any problem listed below
#   new <title>    create the next-numbered ADR from the template; print its path
# The records folder is the one named on the AGENTS.md Project decisions line
# "- Decision records: <folder>" (backticks, a trailing slash and a note after
# the path are allowed); with no such line, or a {{ placeholder in it, it is
# docs/decisions. A folder that is absolute or leaves the repository exits 2.
# check enforces, for every <folder>/*.md except README.md:
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
# and, around the folder:
#   every "<folder>/NNNN" citation in docs/procedures/, docs/rules/ and
#   docs/profiles/*/ names a record that exists (in template mode and after
#   start alike);
#   no other known ADR folder (KNOWN_DIRS) holds NNNN-*.md records, so records
#   kept elsewhere fail instead of passing with nothing checked;
#   with an "origin" remote, the default branch (refs/remotes/origin/HEAD,
#   else main) is fetched, and a record this checkout has but origin's branch
#   lacks must not reuse a number origin's branch already gives another file.
#   Parallel branches collided on ADR numbers twice before this. No remote, or
#   a failed fetch, prints that the comparison was skipped; it never passes
#   silently as if compared.
# No records folder, or an empty one, passes.
# Test hook: ADR_TODAY=YYYY-MM-DD overrides today's date for new.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
DEFAULT_DIR="docs/decisions"
# Folders other projects and ADR tools use for the same records.
KNOWN_DIRS="docs/decisions docs/adr docs/adrs doc/adr doc/adrs doc/decisions adr adrs decisions docs/architecture/decisions architecture/decisions"
DIR=""

usage() {
  echo "usage: scripts/adr.sh check | new <title>" >&2
  exit 2
}

# The records folder from AGENTS.md Project decisions, else the default.
resolve_dir() {
  local raw=""
  if [[ -f AGENTS.md ]]; then
    raw="$(awk '{ sub(/\r$/, "") }
      /^## / { in_pd = ($0 == "## Project decisions"); next }
      in_pd && /^- Decision records:/ { sub(/^- Decision records:[[:space:]]*/, ""); print; exit }' AGENTS.md)"
  fi
  if [[ -z "${raw//[[:space:]]/}" || "$raw" == *"{{"* ]]; then
    DIR="$DEFAULT_DIR"
    return
  fi
  DIR="${raw%%[[:space:]]*}"
  DIR="${DIR//\`/}"
  DIR="${DIR#./}"
  while [[ "$DIR" == */ ]]; do DIR="${DIR%/}"; done
  if [[ -z "$DIR" || "$DIR" == /* || ! "$DIR" =~ ^[A-Za-z0-9._/-]+$ \
        || "/$DIR/" == */../* || "/$DIR/" == */./* ]]; then
    echo "adr: the AGENTS.md line '- Decision records:' names '$raw'; give a folder inside the repository, such as docs/decisions" >&2
    exit 2
  fi
}

# ADR files, one per line, sorted; README.md is the folder's own index.
adr_files() {
  [[ -d "$DIR" ]] || return 0
  find "$DIR" -maxdepth 1 -type f -name '*.md' ! -name README.md | sed 's|^\./||' | LC_ALL=C sort
}

# Prints one problem per line for citations that name no record.
cited_check() {
  local pat files=() f line src ref
  pat="$(printf '%s' "$DIR" | sed 's/[.]/[.]/g')/[0-9]{4}"
  for f in docs/procedures/*.md docs/rules/*.md docs/profiles/*/*.md; do
    [[ -f "$f" ]] && files+=("$f")
  done
  (( ${#files[@]} > 0 )) || return 0
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    src="${line%%:*}"
    ref="${line#*:}"
    ls "$ref"-*.md >/dev/null 2>&1 || echo "$src cites $ref, which does not exist"
  done < <(grep -oHE -- "$pat" "${files[@]}" | LC_ALL=C sort -u)
}

# Prints one problem per line for records kept in another known folder.
stray_check() {
  local k recs n
  for k in $KNOWN_DIRS; do
    [[ "$k" != "$DIR" && -d "$k" ]] || continue
    recs="$(find "$k" -maxdepth 1 -type f -name '[0-9][0-9][0-9][0-9]-*.md' | sed 's|^\./||' | LC_ALL=C sort)"
    [[ -n "$recs" ]] || continue
    n="$(printf '%s\n' "$recs" | wc -l | tr -d ' ')"
    echo "$k/ holds $n decision record(s) ($(printf '%s\n' "$recs" | head -n 1)) but adr.sh checks $DIR/; name the folder on the AGENTS.md Project decisions line '- Decision records: $k' or move the records into $DIR/"
  done
}

# Appends collisions to cmd_check's errs (bash dynamic scope); notes go to stdout.
origin_check() {
  local head branch ref remote_files f base num other added=0 collide=0 rmax=0 n
  local fetch=(git fetch -q --no-tags)
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "adr: origin check skipped: not a git repository; new numbers were not compared with the default branch"
    return 0
  fi
  if ! git remote get-url origin >/dev/null 2>&1; then
    echo "adr: origin check skipped: no 'origin' remote; new numbers were not compared with the default branch"
    return 0
  fi
  head="$(git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null || true)"
  branch="${head#origin/}"
  [[ -n "$branch" ]] || branch="main"
  ref="refs/remotes/origin/$branch"
  # A credential or host-key prompt must not hang a gate run.
  if command -v timeout >/dev/null 2>&1; then fetch=(timeout 60 "${fetch[@]}"); fi
  if ! GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh} -o BatchMode=yes" \
       "${fetch[@]}" origin "+refs/heads/$branch:$ref" >/dev/null 2>&1; then
    echo "adr: origin check skipped: could not fetch origin/$branch (offline, or no such branch); new numbers were not compared"
    return 0
  fi
  remote_files="$(git ls-tree --name-only "$ref" -- "$DIR/" 2>/dev/null \
    | grep -E "/[0-9]{4}-[^/]*\.md$" | LC_ALL=C sort || true)"
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    n="$(basename "$f" | cut -c1-4)"
    if (( 10#$n > rmax )); then rmax=$((10#$n)); fi
  done <<< "$remote_files"
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    base="$(basename "$f")"
    [[ "$base" =~ ^([0-9]{4})- ]] || continue
    num="${BASH_REMATCH[1]}"
    if ! grep -qxF -- "$f" <<< "$remote_files"; then
      added=$((added + 1))
      other="$(grep -E "/$num-[^/]*\.md$" <<< "$remote_files" | head -n 1 || true)"
      if [[ -n "$other" ]]; then
        collide=$((collide + 1))
        errs+=("$f: number $num is already taken on origin/$branch by $other; number the ADRs this branch adds from $(printf '%04d' $((rmax + 1))) (after origin/$branch's last, $(printf '%04d' "$rmax")): git mv the file and fix its title line")
      fi
    fi
  done < <(adr_files)
  (( collide > 0 )) || echo "adr: origin check: $added ADR(s) added on this branch, none reuses a number on origin/$branch"
}

cmd_check() {
  local errs=() f base num prev=0 expect title header date status target seen=" " c d q p
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
    date="$(printf '%s\n' "$header" | sed -n 's/^Date: *//p' | sed -n 1p)"
    status="$(printf '%s\n' "$header" | sed -n 's/^Status: *//p' | sed -n 1p)"
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

  while IFS= read -r p; do [[ -z "$p" ]] || errs+=("$p"); done < <(cited_check)
  while IFS= read -r p; do [[ -z "$p" ]] || errs+=("$p"); done < <(stray_check)
  origin_check

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
  check) resolve_dir; cmd_check ;;
  new) shift; resolve_dir; cmd_new "$@" ;;
  *) usage ;;
esac
