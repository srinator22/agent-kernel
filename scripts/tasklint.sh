#!/usr/bin/env bash
# tasklint.sh - lints the prose contracts of .work/TASK.md that no other gate
# reads: evidence behind ticked criteria, Assumptions status lines, and the
# reviewer's plan verdict for autopilot tasks (kernel rules 4, 5 and 16).
# Usage:
#   scripts/tasklint.sh check    problems that are wrong at any time
#   scripts/tasklint.sh ship     check, plus problems that block calling the task done
# Set TASKLINT_FILE to read another file (default .work/TASK.md, resolved from
# the repo root). Evidence paths also resolve from the repo root.
#
# Conventions the parser accepts (HTML comments, including multi-line ones, are
# stripped first; CRLF is tolerated; a section runs from "## Name" to the next "## "):
#   Mode:        first line starting "Mode:"; standard|quick|autopilot (any case).
#                Absent, or a value holding "|" (the unfilled template line), is standard.
#   Criteria     in "## Acceptance criteria", each "- [x]" or "- [X]" line is ticked.
#                Evidence is the text after the last "->". It is either
#                "judgment: <reason>" or names at least one path that exists
#                (a token is path-like when it has "/" or ends in a known file
#                extension, is not a URL, and may carry a ::test_name or :line
#                suffix; a token with "*" must match something). Unticked lines
#                are never checked.
#   Assumptions  optional "## Assumptions"; each "- " line starts with
#                [confirmed], [verified] or [open]. [verified] needs "-> evidence".
#   Plan verdict "## Plan verdict" whose first non-blank line starts with PASS
#                (also "**PASS**" or "Verdict: PASS"). Autopilot only: check
#                requires it once a Plan node is doing or done; ship always.
# ship also fails every [open] assumption unless the mode is quick.
# A pristine template (it still holds "{{title}}") has nothing to lint and passes.
# Exit codes: 0 pass, 1 problems found or file missing, 2 usage error.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
FILE="${TASKLINT_FILE:-.work/TASK.md}"

usage() {
  echo "usage: scripts/tasklint.sh check | ship" >&2
  exit 2
}

[[ $# -eq 1 ]] || usage
case "$1" in
  check|ship) MODE="$1" ;;
  *) usage ;;
esac

[[ -f "$FILE" ]] || { echo "tasklint: $FILE not found" >&2; exit 1; }

if grep -qF '{{title}}' "$FILE"; then
  echo "tasklint: pristine task template; nothing to check"
  exit 0
fi

# Strip CR and HTML comments (a comment may span lines) so commented-out example
# lines never count. Line structure is kept.
read -r -d '' AWK_STRIP <<'AWK' || true
{
  sub(/\r$/, "")
  line = $0; out = ""
  while (line != "") {
    if (incomment) {
      p = index(line, "-->")
      if (p == 0) { line = "" } else { line = substr(line, p + 3); incomment = 0 }
    } else {
      p = index(line, "<!--")
      if (p == 0) { out = out line; line = "" }
      else { out = out substr(line, 1, p - 1); line = substr(line, p + 4); incomment = 1 }
    }
  }
  print out
}
AWK

# Analysis output, one record per line, fields joined by the unit separator:
#   PROB<SEP>message      a problem
#   NOTE<SEP>message      an informational note (stdout)
#   EV<SEP>excerpt<SEP>path-like tokens   evidence whose paths the shell must check
#   INFO<SEP>taskmode<SEP>ticked<SEP>assumptions
read -r -d '' AWK_ANALYZE <<'AWK' || true
function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
function emit(kind, a, b) {
  if (b == "") printf "%s%s%s\n", kind, SEP, a
  else printf "%s%s%s%s%s\n", kind, SEP, a, SEP, b
}
# Text after the last "->"; sets ARROW to 1 when one exists.
function lastarrow(s,   p) {
  ARROW = 0
  while ((p = index(s, "->")) > 0) { ARROW = 1; s = substr(s, p + 2) }
  return s
}
function pathtokens(ev,   s, n, a, i, t, ok, ext, out) {
  s = ev
  gsub(/[ \t,;+()]+/, " ", s)
  n = split(s, a, " ")
  out = ""
  for (i = 1; i <= n; i++) {
    t = a[i]
    gsub(/[`"\047]/, "", t)
    sub(/[.:,]+$/, "", t)
    if (index(t, "://") > 0) continue
    sub(/::.*$/, "", t)
    sub(/:[0-9]+.*$/, "", t)
    sub(/[.:,]+$/, "", t)
    sub(/^\.\//, "", t)
    if (t == "") continue
    ok = 0
    if (index(t, "/") > 0) ok = 1
    else if (match(t, /\.[A-Za-z0-9]+$/)) {
      ext = tolower(substr(t, RSTART + 1))
      ok = (index(" md sh py ps1 cmd json toml yml yaml txt csv js mjs ts tsx cfg ini lock xml html pdf xlsx ", " " ext " ") > 0)
    }
    if (ok) out = out (out == "" ? "" : " ") t
  }
  return out
}
# pass | fail | none for the first line of the Plan verdict section.
function verdict(l) {
  if (match(l, /^[^A-Za-z]*(Verdict:[ \t]*)?[^A-Za-z]*PASS/)) {
    if (substr(l, RSTART + RLENGTH, 1) !~ /[A-Za-z0-9_]/) return "pass"
  }
  if (l ~ /(^|[^A-Za-z])FAIL([^A-Za-z]|$)/) return "fail"
  return "none"
}
BEGIN { SEP = "\037"; sec = ""; hasmode = 0; hasassume = 0; ticked = 0; nas = 0; nopen = 0; vseen = 0; startedid = "" }
/^## / {
  sec = tolower(trim(substr($0, 4)))
  if (sec == "assumptions") hasassume = 1
  next
}
!hasmode && /^Mode:/ { hasmode = 1; modeval = trim(substr($0, 6)) }
sec == "acceptance criteria" && /^[ \t]*- \[[xX]\]/ {
  ticked++
  ln = trim($0)
  ev = lastarrow(ln)
  if (!ARROW) { emit("PROB", "ticked criterion has no evidence (-> path or judgment: reason): " substr(ln, 1, 60)); next }
  ev = trim(ev); gsub(/`/, "", ev); ev = trim(ev)
  if (tolower(ev) ~ /^judgment:/) {
    if (trim(substr(ev, 10)) == "") emit("PROB", "ticked criterion has `judgment:` with no reason: " substr(ln, 1, 60))
    next
  }
  emit("EV", substr(ln, 1, 60), pathtokens(ev))
  next
}
sec == "assumptions" && /^[ \t]*-([ \t]|$)/ {
  nas++
  ln = trim($0); lo = tolower(ln)
  if (lo ~ /^-[ \t]+\[(confirmed|verified|open)\]/) {
    if (lo ~ /^-[ \t]+\[verified\]/) {
      ev = trim(lastarrow(ln))
      if (!ARROW || ev == "") emit("PROB", "verified assumption has no evidence (-> file or command): " substr(ln, 1, 60))
    } else if (lo ~ /^-[ \t]+\[open\]/) {
      nopen++; openl[nopen] = substr(ln, 1, 60)
    }
  } else {
    emit("PROB", "assumption has no status [confirmed|verified|open]: " substr(ln, 1, 60))
  }
  next
}
sec == "plan" && /^[ \t]*\|/ {
  row = trim($0); sub(/^\|/, "", row); sub(/\|$/, "", row)
  nc = split(row, c, "|")
  for (i = 1; i <= nc; i++) c[i] = trim(c[i])
  if (tolower(c[1]) == "node") next
  sepr = 1
  for (i = 1; i <= nc; i++) if (c[i] !~ /^:?-+:?$/) sepr = 0
  if (sepr) next
  if (c[1] ~ /^\{\{/) next
  st = ""
  for (i = nc; i >= 1; i--) if (c[i] != "") { st = tolower(c[i]); break }
  id = c[1]; sub(/[ \t].*$/, "", id)
  if ((st == "doing" || st == "done") && startedid == "") { startedid = id; startedst = st }
  next
}
sec == "plan verdict" && !vseen && /[^ \t]/ { vseen = 1; vline = $0 }
END {
  taskmode = "standard"
  if (hasmode && modeval !~ /\|/) {
    m = tolower(modeval)
    if (m == "standard" || m == "quick" || m == "autopilot") taskmode = m
    else emit("PROB", "Mode must be standard, quick or autopilot: " substr(modeval, 1, 60))
  }
  if (lintmode == "ship" && taskmode != "quick") {
    for (i = 1; i <= nopen; i++) emit("PROB", "open assumption (settle it: confirmed or verified): " openl[i])
    if (!hasassume) emit("NOTE", "no Assumptions section (older task file)")
  }
  if (taskmode == "autopilot") {
    v = vseen ? verdict(vline) : "none"
    if (v != "pass") {
      pre = (v == "fail") ? "plan verdict is FAIL; " : ""
      if (startedid != "")
        emit("PROB", pre "autopilot task has started (node " startedid " is " startedst ") without a PASS plan verdict; get the reviewer's plan review first")
      else if (lintmode == "ship")
        emit("PROB", pre "autopilot task has no PASS plan verdict; add a \"## Plan verdict\" section whose first line starts with PASS (the reviewer's plan review)")
    }
  }
  printf "INFO%s%s%s%d%s%d\n", SEP, taskmode, SEP, ticked, SEP, nas
}
AWK

path_exists() {
  case "$1" in
    *\**|*\?*) compgen -G "$1" >/dev/null ;;
    *) [[ -e "$1" ]] ;;
  esac
}

SEP=$'\037'
probs=0
taskmode=standard
ticked=0
assumed=0

problem() {
  echo "tasklint: $1" >&2
  probs=$((probs + 1))
}

analysis="$(awk "$AWK_STRIP" "$FILE" | awk -v lintmode="$MODE" "$AWK_ANALYZE")"

while IFS= read -r rec; do
  IFS="$SEP" read -r kind a b c <<< "$rec"
  case "$kind" in
    PROB) problem "$a" ;;
    NOTE) echo "tasklint: $a" ;;
    EV)
      if [[ -z "$b" ]]; then
        problem "evidence names no existing path; write the file or test, or \`judgment: <reason>\`: $a"
      else
        read -r -a toks <<< "$b"
        for tok in "${toks[@]}"; do
          path_exists "$tok" || problem "evidence path does not exist: $tok"
        done
      fi
      ;;
    INFO) taskmode="$a"; ticked="$b"; assumed="$c" ;;
  esac
done <<< "$analysis"

if (( probs > 0 )); then
  echo "tasklint: $MODE FAILED ($probs problem(s))" >&2
  exit 1
fi
echo "tasklint: OK ($MODE; mode $taskmode; $ticked ticked criteria; $assumed assumptions)"
