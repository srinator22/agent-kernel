#!/usr/bin/env bash
# doc-eval.sh - the mechanical half of docs/procedures/doc-eval.md: a question
# set that tests whether a fresh agent can find answers in the docs by
# navigation and declines what the docs do not cover.
# Usage:
#   scripts/doc-eval.sh check   validate the question table (exit 1 on any problem)
#   scripts/doc-eval.sh brief   print the brief for the answering agent: the
#                               questions only, never the answer key or sources
# Set DOCEVAL_FILE to read another file (default tests/docs/questions.md).
# Table header: | id | kind | question | answer key | sources |
#   id          a letter and two or more digits, unique (q01, q02); neither the
#               id nor the row order may reveal the kind, since brief prints both
#   kind        answerable | trap
#   question    non-empty, ends with ?
#   answer key  non-empty (for a trap: why the right answer is to decline)
#   sources     answerable: paths separated by commas, each must exist (so a
#               moved or deleted doc fails here, not silently in the next
#               evaluation); trap: exactly -
# At least 5 answerable and 3 trap rows. A missing file passes with a note
# (the template's required-file list keeps it present before start).
# Exit: 0 ok, 1 problems found, 2 usage.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
FILE="${DOCEVAL_FILE:-tests/docs/questions.md}"
MIN_ANSWERABLE=5
MIN_TRAP=3

usage() { echo "usage: scripts/doc-eval.sh check | brief" >&2; exit 2; }

# rows: print id, kind, question, key and sources joined by the unit separator
# (US, \x1f) for each table row after the header, or ERR, US and a message for
# a malformed row. Not a tab: tab is IFS whitespace, so read would collapse an
# empty cell and shift the next cell into its place.
US=$'\x1f'
rows() {
  awk -v US="$US" '
function trim(s) { sub(/^[ \t\r]+/, "", s); sub(/[ \t\r]+$/, "", s); return s }
{ sub(/\r$/, "") }
/^[ \t]*\|/ {
  line = trim($0); sub(/^\|/, "", line); sub(/\|$/, "", line)
  nc = split(line, c, "|")
  for (i = 1; i <= nc; i++) c[i] = trim(c[i])
  if (!hdr) {
    if (nc == 5 && tolower(c[1]) == "id" && tolower(c[2]) == "kind" && tolower(c[3]) == "question" && \
        tolower(c[4]) == "answer key" && tolower(c[5]) == "sources") hdr = 1
    next
  }
  sep = 1
  for (i = 1; i <= nc; i++) if (c[i] !~ /^:?-+:?$/) sep = 0
  if (sep) next
  if (nc != 5) { print "ERR" US "line " NR ": row has " nc " cells, expected 5"; next }
  print c[1] US c[2] US c[3] US c[4] US c[5]
  next
}
END { if (!hdr) print "NOHEADER" }' "$FILE"
}

cmd_check() {
  local out id kind q key src problems=0 na=0 nt=0 p seen=" "
  err() { echo "doc-eval: $*" >&2; problems=$((problems + 1)); }
  out="$(rows)"
  if [[ "$out" == *NOHEADER* ]]; then
    err "$FILE has no '| id | kind | question | answer key | sources |' table"
  fi
  while IFS="$US" read -r id kind q key src; do
    [[ -n "$id" && "$id" != NOHEADER ]] || continue
    if [[ "$id" == ERR ]]; then err "$kind"; continue; fi
    if [[ ! "$id" =~ ^[a-z][0-9]{2,}$ ]]; then err "id '$id' must be a letter and two or more digits"; fi
    if [[ "$seen" == *" $id "* ]]; then err "duplicate id $id"; fi
    seen="$seen$id "
    if [[ "$q$key$src" == *'{{'* ]]; then err "$id: unfilled placeholder"; fi
    [[ -n "$q" && "$q" == *'?' ]] || err "$id: the question must be non-empty and end with ?"
    [[ -n "$key" ]] || err "$id: empty answer key"
    case "$kind" in
      answerable)
        na=$((na + 1))
        if [[ -z "$src" || "$src" == - ]]; then
          err "$id: an answerable question needs its source paths"
        else
          IFS=',' read -r -a parts <<< "$src"
          for p in "${parts[@]}"; do
            p="${p//\`/}"; p="${p#"${p%%[![:space:]]*}"}"; p="${p%"${p##*[![:space:]]}"}"
            [[ -z "$p" ]] && continue
            [[ -e "$p" ]] || err "$id: source does not exist: $p"
          done
        fi
        ;;
      trap)
        nt=$((nt + 1))
        [[ "$src" == - ]] || err "$id: a trap question's sources cell must be -"
        ;;
      *) err "$id: kind '$kind' must be answerable or trap" ;;
    esac
  done <<< "$out"
  (( na >= MIN_ANSWERABLE )) || err "only $na answerable questions; keep at least $MIN_ANSWERABLE"
  (( nt >= MIN_TRAP )) || err "only $nt trap questions; keep at least $MIN_TRAP"
  if (( problems > 0 )); then
    echo "doc-eval: check FAILED ($problems problem(s))" >&2
    exit 1
  fi
  echo "doc-eval: OK ($na answerable, $nt trap questions)"
}

cmd_brief() {
  local out id kind q key src
  out="$(rows)"
  cat <<'BRIEF'
Answer each question below using only the files of this repository. Start
from AGENTS.md and its rules index and open only the files you need. Do not
open anything under tests/docs/ (it holds the answer key).
For each question reply with three lines:
  <id>: <answer in one to three sentences, or DECLINE: not covered>
  files: <the paths you read that state the answer, or ->
  confidence: high | low
Decline when the docs do not state the answer; never guess or fill a gap
from general knowledge. A wrong answer counts worse than a decline.

BRIEF
  while IFS="$US" read -r id kind q key src; do
    [[ -n "$id" && "$id" != ERR && "$id" != NOHEADER ]] || continue
    echo "$id: $q"
  done <<< "$out"
}

(( $# == 1 )) || usage
case "$1" in
  check|brief)
    if [[ ! -f "$FILE" ]]; then
      if [[ "$1" == check ]]; then echo "doc-eval: no question file at $FILE; nothing to check"; exit 0; fi
      echo "doc-eval: $FILE not found" >&2; exit 1
    fi
    ;;
  *) usage ;;
esac

case "$1" in
  check) cmd_check ;;
  brief) cmd_brief ;;
esac
