#!/usr/bin/env bash
# doc-budget.sh - the template's procedures stay short enough for an owner to
# read in one sitting when adopting it (the gap the 2026-11-18 rating named:
# 1389 lines then). check.sh step 5n runs it in template mode.
#   check   docs/procedures/*.md total at most DOC_BUDGET_TOTAL words (10200, from
#           12724) and no file over DOC_BUDGET_FILE words (1700); no line
#           over DOC_BUDGET_WIDTH characters (120); every anchor phrase in
#           tests/template/fixtures/procedure-anchors.txt (frozen from the uncut
#           procedures, one per rule or step) is still found verbatim under
#           docs/, so a cut cannot drop a rule; every docs/ or scripts/ path the
#           AGENTS.md kernel, standards and rules index cite exists (Project
#           decisions is skipped: start fills its paths).
# Words, not lines: a line budget was met once by unwrapping lines, which
# cut 1.8% of the words and none of the reading (2026-11-18); the width cap
# keeps that from moving the cost back into long lines. The total is a
# ratchet: the 2026-11-18 cut aimed at 9500 and stopped at 10164 words, where
# what remained was rule text that exists nowhere else; lower it after a cut,
# never raise it without a dated reason in the commit body.
# The anchors are one awk pass over docs/, not one grep per anchor: 606 greps
# cost tens of seconds on Windows. Exit 0 within budget, 1 a problem, 2 usage.
set -euo pipefail
export LC_ALL=C

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

[[ $# -eq 1 && "$1" == check ]] || { echo "usage: scripts/doc-budget.sh check" >&2; exit 2; }

TOTAL_MAX="${DOC_BUDGET_TOTAL:-10200}"
FILE_MAX="${DOC_BUDGET_FILE:-1700}"
WIDTH_MAX="${DOC_BUDGET_WIDTH:-120}"
ANCHORS=tests/template/fixtures/procedure-anchors.txt
problems=0
bad() { echo "doc-budget: $*"; problems=$((problems + 1)); }

procs=()
for f in docs/procedures/*.md; do
  if [[ -f "$f" ]]; then procs+=("$f"); fi
done
total=0
if (( ${#procs[@]} )); then
  while read -r n f; do
    [[ "$f" == total ]] && continue
    total=$((total + n))
    (( n <= FILE_MAX )) || bad "$f has $n words; the cap is $FILE_MAX per procedure (cut repetition, cite ADRs and kernel rules instead of restating them)"
  done < <(wc -w "${procs[@]}")
  while IFS= read -r msg; do
    if [[ -n "$msg" ]]; then bad "$msg"; fi
  done < <(awk -v w="$WIDTH_MAX" '{ sub(/\r$/, "") } length($0) > w { print FILENAME ":" FNR ": " length($0) " characters; wrap procedure lines at " w }' "${procs[@]}")
fi
(( total <= TOTAL_MAX )) || bad "docs/procedures total $total words; the budget is $TOTAL_MAX"

if [[ -f "$ANCHORS" ]]; then
  docs=()
  while IFS= read -r f; do docs+=("$f"); done < <(find docs -type f -name '*.md' | sort)
  while IFS= read -r msg; do
    if [[ -n "$msg" ]]; then bad "$msg"; fi
  done < <(awk -F '\t' -v anchors="$ANCHORS" '
    FILENAME == anchors {
      sub(/\r$/, "")
      if ($0 ~ /^#/ || $0 == "") next
      if (NF != 2 || $2 == "") { print anchors ":" FNR ": not <path><TAB><phrase>"; next }
      n++; src[n] = $1; ph[n] = $2; left = n
      next
    }
    left > 0 {
      for (i = 1; i <= n; i++) if (!(i in found) && index($0, ph[i])) { found[i] = 1; left-- }
    }
    END {
      for (i = 1; i <= n; i++) if (!(i in found))
        print "anchor lost: \"" ph[i] "\" (from " src[i] ") is no longer under docs/; restore the rule, or reword around the phrase"
    }' "$ANCHORS" ${docs[@]+"${docs[@]}"})
fi

if [[ -f AGENTS.md ]]; then
  while IFS= read -r p; do
    [[ -e "$p" ]] || bad "AGENTS.md cites $p, which does not exist (the kernel names procedure paths; never rename one)"
  done < <(awk '/^## Project decisions/ { exit } { print }' AGENTS.md \
    | grep -o '\(docs\|scripts\)/[A-Za-z0-9_./-]*' | sed 's/[.]$//' | sort -u)
fi

if (( problems )); then
  echo "doc-budget: check FAILED ($problems problem(s))"
  exit 1
fi
echo "doc-budget: OK (docs/procedures $total/$TOTAL_MAX words, each <= $FILE_MAX, lines <= $WIDTH_MAX characters)"
