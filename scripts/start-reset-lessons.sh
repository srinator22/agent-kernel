#!/usr/bin/env bash
# start-reset-lessons.sh - resets the lessons files a new project must not
# inherit from the template to their format headers.
# Purpose: a project copied from the template otherwise carries the template's
#   own approved, pending, quarantined and upstream lessons, and reads them as
#   its own memory (two derived projects were found with them word for word).
# Usage: bash scripts/start-reset-lessons.sh [--check]
#   (none)   rewrite each file to its format header
#   --check  change nothing; exit 1 when any file differs from its reset form
# Input: docs/lessons/INDEX.md, PENDING.md, QUARANTINE.md and UPSTREAM.md under
#   the repository root (the folder above this script).
# Output: one line per file. Exit 0 reset (or already reset); 1 when a file is
#   missing, has no format block or has uncommitted changes (nothing is
#   written then), or with --check when a file still holds entries; 2 on a
#   usage error or when .start-done exists.
# Format header: every line up to the end of the format block, which is the
#   first run of non-blank lines after the line that opens with "Format" or
#   "Entry format" and ends in a colon. QUARANTINE.md also keeps its
#   empty-state line. template-sync syncs only the first lines of these files,
#   so the header kept here is the part the template still owns.
# Dependencies: bash, awk, git, cmp.
# Assumptions: docs/procedures/start.md runs this before it writes .start-done;
#   refusing uncommitted changes keeps every dropped line recoverable from git.
#   docs/DEFECT_MEMORY.md is not reset: template-sync syncs it whole, and the
#   template copy holds only its format and EXAMPLE rows.
set -euo pipefail

FILES=(docs/lessons/INDEX.md docs/lessons/PENDING.md docs/lessons/QUARANTINE.md docs/lessons/UPSTREAM.md)
QUARANTINE_EMPTY="No quarantined tests."

CHECK=0
case "$#:${1:-}" in
  0:) ;;
  1:--check) CHECK=1 ;;
  *) echo "start-reset-lessons: usage: start-reset-lessons.sh [--check]" >&2; exit 2 ;;
esac

cd "$(dirname "${BASH_SOURCE[0]}")/.."

if [[ -f .start-done ]]; then
  echo "start-reset-lessons: .start-done exists; start already ran and these files now hold this project's lessons. Nothing changed." >&2
  exit 2
fi

# header FILE: print the format header; exit 3 when there is no format block.
# awk only counts the header lines and head copies them: gawk on Git Bash
# reads in text mode and would drop the CRs of a CRLF file.
header() {
  local n
  n="$(awk '
    { l = $0; sub(/\r$/, "", l) }
    st == 0 { if (l ~ /^(Format|Entry format)( [^:]*)?:[ \t]*$/) st = 1; next }
    st == 1 { if (l !~ /^[ \t]*$/) st = 2; next }
    st == 2 { if (l ~ /^[ \t]*$/) { print NR - 1; done = 1; exit } }
    END { if (done) exit 0; if (st < 2) exit 3; print NR }' "$1")" || return 3
  head -n "$n" "$1"
}

WORK="$(mktemp -d "${TMPDIR:-/tmp}/start-reset-lessons.XXXXXX")"
trap 'case "$WORK" in */start-reset-lessons.*) rm -rf "$WORK" ;; esac' EXIT

errors=0
for f in "${FILES[@]}"; do
  if [[ ! -f "$f" ]]; then
    echo "start-reset-lessons: $f is missing; restore it from the template before start continues" >&2
    errors=$((errors + 1)); continue
  fi
  out="$WORK/${f##*/}"
  rc=0
  header "$f" > "$out" || rc=$?
  if (( rc != 0 )); then
    echo "start-reset-lessons: $f has no format block (a line 'Format:' or 'Entry format ...:' followed by the field lines); fix the file by hand" >&2
    errors=$((errors + 1)); continue
  fi
  if [[ "$f" == */QUARANTINE.md ]]; then printf '\n%s\n' "$QUARANTINE_EMPTY" >> "$out"; fi
done
(( errors == 0 )) || exit 1

if (( CHECK )); then
  held=0
  for f in "${FILES[@]}"; do
    if cmp -s "$f" "$WORK/${f##*/}"; then
      echo "start-reset-lessons: $f: format header only"
    else
      echo "start-reset-lessons: $f: holds lines beyond its format header"
      held=$((held + 1))
    fi
  done
  (( held == 0 )) || exit 1
  exit 0
fi

dirty="$(git status --porcelain -- "${FILES[@]}" 2>&1)" || {
  echo "start-reset-lessons: git status failed: $dirty" >&2; exit 1; }
if [[ -n "$dirty" ]]; then
  echo "start-reset-lessons: uncommitted changes in the lessons files; commit or restore them first so the dropped lines stay recoverable:" >&2
  printf '%s\n' "$dirty" >&2
  exit 1
fi

for f in "${FILES[@]}"; do
  before=$(( $(wc -l < "$f") ))
  if cmp -s "$f" "$WORK/${f##*/}"; then
    echo "start-reset-lessons: $f: already the format header"
    continue
  fi
  cp "$WORK/${f##*/}" "$f"
  echo "start-reset-lessons: $f: reset to the format header ($before -> $(( $(wc -l < "$f") )) lines)"
done
