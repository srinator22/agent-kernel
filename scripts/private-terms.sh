#!/usr/bin/env bash
# private-terms.sh - keep private words out of the repository
# (docs/rules/security.md). The owner lists one term per line in the
# gitignored .work/private-terms.txt (PRIVATE_TERMS_FILE overrides the path;
# a relative path is read from the repository root). Terms are fixed
# strings, ASCII case-insensitive; a non-ASCII byte matches exactly. Blank
# lines and lines starting with # are ignored; a term needs 3 bytes.
#   check    staged content (text and binary), tracked paths, local branch
#            names, and every commit not on a remote-tracking ref: message,
#            author, committer and diff. Pushed history is left to history,
#            so one old commit cannot turn check.sh red for good.
#   history  every ref name, every commit on every ref with its full diff
#            (merges as combined diffs, binaries as text), every annotated
#            tag's tagger and message. Run it before any visibility change.
# Output names files, refs, commits and tags with each term masked as ***
# and the term's line number in the terms file; the term is never printed.
# Not scanned: submodule contents, untracked files, unstaged edits.
# Exit 0 clean or no terms file; 1 a match, a refusal or a git error;
# 2 usage or a malformed terms file.
set -uo pipefail
export LC_ALL=C

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$ROOT" || exit 1

usage() { echo "usage: scripts/private-terms.sh check | history" >&2; exit 2; }
[[ $# -eq 1 ]] || usage
case "$1" in check|history) MODE="$1" ;; *) usage ;; esac

TERMS="${PRIVATE_TERMS_FILE:-.work/private-terms.txt}"
if [[ ! -f "$TERMS" ]]; then
  echo "private-terms: no $TERMS; nothing to check"
  exit 0
fi

TMP="$(mktemp -d "${TMPDIR:-/tmp}/private-terms.XXXXXX")" || { echo "private-terms: cannot create a temp folder" >&2; exit 1; }
trap 'rm -rf "$TMP"' EXIT
trap 'exit 1' INT TERM
NORM="$TMP/terms"

# lc: ASCII-only lower case. gawk's tolower also folds Latin-1 bytes under
# LC_ALL=C, which would change the bytes of a UTF-8 term; awk without that
# habit takes the fast path for ASCII lines.
LC_AWK='
function lc(s,   out, i, n, c, p) {
  if (s !~ /[^-]/) return tolower(s)
  out = ""; n = length(s)
  for (i = 1; i <= n; i++) {
    c = substr(s, i, 1); p = index("ABCDEFGHIJKLMNOPQRSTUVWXYZ", c)
    out = out (p ? substr("abcdefghijklmnopqrstuvwxyz", p, 1) : c)
  }
  return out
}
'

# Normalise: "N<TAB>lowercased term", first occurrence of each term only.
awk "$LC_AWK"'
  { sub(/\r$/, ""); sub(/^[ \t]+/, ""); sub(/[ \t]+$/, "") }
  $0 == "" || substr($0, 1, 1) == "#" { next }
  length($0) < 3 {
    printf "private-terms: line %d of the terms file: a term needs at least 3 bytes\n", NR > "/dev/stderr"
    bad = 1; next
  }
  { t = lc($0); if (!(t in seen)) { seen[t] = 1; printf "%d\t%s\n", NR, t } }
  END { exit bad ? 2 : 0 }
' "$TERMS" > "$NORM" || exit 2

# A terms file inside the repository must be ignored by git, or the next
# "git add -A" publishes the whole list.
tdir="$(cd "$(dirname "$TERMS")" 2>/dev/null && pwd -P)" || tdir=""
case "$tdir/" in
  "$ROOT/"*)
    if ! git check-ignore -q -- "$TERMS" 2>/dev/null; then
      echo "private-terms: REFUSED: the terms file is tracked or not ignored by git; untrack it (git rm --cached <file>) and add it to .gitignore first" >&2
      exit 1
    fi ;;
esac

if [[ ! -s "$NORM" ]]; then
  echo "private-terms: no terms in the terms file; nothing to check"
  exit 0
fi
COUNT="$(awk 'END { print NR }' "$NORM")"

# The scanner. Terms come from the first file operand, lines from stdin.
# MODE paths: each line is a name, reported masked. content: "path:count"
# lines from git grep for term TN. stream: git log or for-each-ref output,
# where a SOH marker line sets the commit or tag the next lines belong to.
SCAN='
function mask(s,   low, n, i, t, from, p, k, j, out, inrun) {
  low = lc(s); n = length(s); split("", m)
  for (i = 1; i <= nt; i++) {
    t = term[i]; from = 0
    while ((p = index(substr(low, from + 1), t)) > 0) {
      p += from
      for (k = p; k < p + length(t); k++) m[k] = 1
      from = p
    }
  }
  out = ""; inrun = 0
  for (j = 1; j <= n; j++) {
    if (m[j]) { if (!inrun) out = out "***"; inrun = 1 }
    else { out = out substr(s, j, 1); inrun = 0 }
  }
  return out
}
function report(lbl, line,   low, i, key) {
  low = lc(line)
  for (i = 1; i <= nt; i++) {
    if (index(low, term[i])) {
      key = lbl SUBSEP i
      if (!(key in done)) { done[key] = 1; print lbl " (term " num[i] ")"; found = 1 }
    }
  }
}
BEGIN { SOH = sprintf("%c", 1); label = "" }
FNR == NR { tab = index($0, "\t"); nt++; num[nt] = substr($0, 1, tab - 1); term[nt] = substr($0, tab + 1); next }
MODE == "content" {
  for (j = length($0); j > 0 && substr($0, j, 1) != ":"; j--) ;
  print mask(substr($0, 1, j - 1)) ": " substr($0, j + 1) " line(s) (term " TN ")"; found = 1; next
}
MODE == "paths" { report(mask($0), $0); next }
substr($0, 1, 8) == SOH "commit " {
  h = substr($0, 9)
  if ((length(h) == 40 || length(h) == 64) && h !~ /[^0-9a-f]/) { label = "commit " substr(h, 1, 12); next }
}
substr($0, 1, 5) == SOH "tag " { label = "tag " mask(substr($0, 6)); report(label, substr($0, 6)); next }
label != "" { report(label, $0) }
END { exit found ? 1 : 0 }
'
scan() { awk -v MODE="$1" -v TN="${2:-0}" "$LC_AWK$SCAN" "$NORM" -; }

fail=0
# stream_git WHAT MODE GIT-ARGS...: git output through the scanner; a git
# failure is a failure, never a clean result.
stream_git() {
  local what="$1" mode="$2"; shift 2
  git "$@" | scan "$mode"
  local st=("${PIPESTATUS[@]}")
  if (( st[0] != 0 )); then echo "private-terms: git failed while reading $what (exit ${st[0]})" >&2; fail=1; fi
  if (( st[1] == 1 )); then fail=1; elif (( st[1] != 0 )); then echo "private-terms: the scanner failed on $what (exit ${st[1]})" >&2; fail=1; fi
}
LOGFMT='--format=%x01commit %H%n%an <%ae>%n%cn <%ce>%n%B'
DIFF=(-c core.quotepath=off log -p --cc --text --no-ext-diff --no-textconv -U0 --no-color)
HAVE_HEAD=0
git rev-parse -q --verify HEAD >/dev/null 2>&1 && HAVE_HEAD=1

if [[ "$MODE" == check ]]; then
  # Staged content: one git grep per term, so every match has its term.
  TAB="$(printf '\t')"
  while IFS="$TAB" read -r n t; do
    rc=0
    git grep -z --no-color --cached -a -c -i -F -e "$t" > "$TMP/grep" 2>/dev/null || rc=$?
    if (( rc == 0 )); then
      tr '\0' ':' < "$TMP/grep" | scan content "$n"
      fail=1
    elif (( rc != 1 )); then
      echo "private-terms: git grep failed for term $n (exit $rc)" >&2; fail=1
    fi
  done < "$NORM"
  rc=0
  git ls-files -z > "$TMP/ls" 2>/dev/null || rc=$?
  if (( rc != 0 )); then echo "private-terms: git ls-files failed (exit $rc)" >&2; fail=1
  else tr '\0' '\n' < "$TMP/ls" | scan paths || fail=1
  fi
  stream_git "local branch names" paths for-each-ref '--format=%(refname)' refs/heads
  if (( HAVE_HEAD )); then
    stream_git "unpushed commits" stream "${DIFF[@]}" "$LOGFMT" HEAD --not --remotes
  fi
else
  stream_git "ref names" paths for-each-ref '--format=%(refname)'
  if (( HAVE_HEAD )) || [[ -n "$(git for-each-ref --count=1)" ]]; then
    stream_git "history" stream "${DIFF[@]}" "$LOGFMT" --all
  fi
  stream_git "annotated tags" stream for-each-ref '--format=%01tag %(refname:short)%0a%(taggername) %(taggeremail)%0a%(contents)' refs/tags
fi

if (( fail )); then
  echo "private-terms: FAILED ($MODE): the names above hold a private term, masked as ***; the number is the term's line in the terms file (docs/rules/security.md)" >&2
  exit 1
fi
echo "private-terms: OK ($COUNT term(s), $MODE)"
