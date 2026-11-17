#!/usr/bin/env bash
# start-reset-lessons.sh - resets the lessons files a new project must not
# inherit from the template to their format headers.
# Purpose: a project copied from the template otherwise carries the template's
#   own approved, pending, quarantined and upstream lessons, and reads them as
#   its own memory (two derived projects were found with them word for word).
# Usage: bash scripts/start-reset-lessons.sh [--check]
#   (none)   rewrite each file to its format header
#   --check  change nothing; exit 1 when any file differs from its reset form
# Input: docs/lessons/INDEX.md, PENDING.md, QUARANTINE.md, UPSTREAM.md and MAINTENANCE.log under
#   the repository root (the folder above this script).
# Output: one line per file. Exit 0 reset (or already reset); 1 when a file is
#   missing, has no format block or has uncommitted changes (nothing is
#   written then), or with --check when a file still holds entries; 2 on a
#   usage error or when .start-done exists.
# Archive: the lines a reset drops are first written to
#   .archive/lessons/template-<YYYY-MM-DD>.md (kernel rule 11: move, never
#   delete; a second reset on the same day writes template-<date>-2.md and so
#   on). START_RESET_TODAY=YYYY-MM-DD overrides the date for tests.
# Format header: every line up to the end of the format block, which is the
#   first run of non-blank lines after the line that opens with "Format" or
#   "Entry format" and ends in a colon. QUARANTINE.md also keeps its
#   empty-state line. template-sync syncs only the first lines of these files,
#   so the header kept here is the part the template still owns.
# Dependencies: bash, awk, git, cmp, head, tail.
# Assumptions: docs/procedures/start.md runs this before it writes .start-done;
#   refusing uncommitted changes keeps every dropped line recoverable from git.
#   docs/DEFECT_MEMORY.md is not reset: template-sync syncs it whole, and the
#   template copy holds only its format and EXAMPLE rows.
set -euo pipefail

FILES=(docs/lessons/INDEX.md docs/lessons/PENDING.md docs/lessons/QUARANTINE.md docs/lessons/UPSTREAM.md)
# The template's own maintenance record: no format header, so its whole content
# is dropped and the file removed (absent is a valid state: template-sync and
# docs/procedures/start.md only ever append to it, and session-context.sh reads
# a missing log as "no pass recorded").
MLOG=docs/lessons/MAINTENANCE.log
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
  if [[ -s "$MLOG" ]]; then
    echo "start-reset-lessons: $MLOG: holds the template's entries"
    held=$((held + 1))
  else
    echo "start-reset-lessons: $MLOG: absent or empty"
  fi
  (( held == 0 )) || exit 1
  exit 0
fi

dirty="$(git status --porcelain -- "${FILES[@]}" "$MLOG" 2>&1)" || {
  echo "start-reset-lessons: git status failed: $dirty" >&2; exit 1; }
if [[ -n "$dirty" ]]; then
  echo "start-reset-lessons: uncommitted changes in the lessons files; commit or restore them first so the dropped lines stay recoverable:" >&2
  printf '%s\n' "$dirty" >&2
  exit 1
fi

# dropped_to FILE OUT: write the lines after FILE's format header to OUT,
# minus the QUARANTINE empty-state line (a CR at a line end is ignored when
# comparing). OUT stays empty when nothing was dropped. awk only filters;
# tail keeps the bytes of every other line.
dropped_to() {
  local n
  n="$(header "$1" | wc -l)"
  tail -n +"$(( n + 1 ))" "$1" | awk -v e="$QUARANTINE_EMPTY" '{ l = $0; sub(/\r$/, "", l) } l != e { print }' > "$2"
  if [[ -z "$(tr -d '[:space:]' < "$2")" ]]; then : > "$2"; fi
}

ARCHIVE=""
# write_section NAME PART: append the file PART to the archive file under a
# "## NAME" heading, creating the archive file on first use.
write_section() {
  local f="$1" part="$2" today dir=".archive/lessons" i=1
  if [[ -z "$ARCHIVE" ]]; then
    today="${START_RESET_TODAY:-$(date -u +%F)}"
    mkdir -p "$dir"
    ARCHIVE="$dir/template-$today.md"
    while [[ -e "$ARCHIVE" ]]; do i=$((i + 1)); ARCHIVE="$dir/template-$today-$i.md"; done
    printf '# Template lessons dropped by start-reset-lessons.sh on %s\n' "$today" > "$ARCHIVE"
  fi
  printf '\n## %s\n\n' "$f" >> "$ARCHIVE"
  cat "$part" >> "$ARCHIVE"
}

archive_dropped() {
  local f="$1" part="$WORK/dropped.part"
  dropped_to "$f" "$part"
  [[ -s "$part" ]] || return 0
  write_section "$f" "$part"
}

for f in "${FILES[@]}"; do
  before=$(( $(wc -l < "$f") ))
  if cmp -s "$f" "$WORK/${f##*/}"; then
    echo "start-reset-lessons: $f: already the format header"
    continue
  fi
  archive_dropped "$f"
  cp "$WORK/${f##*/}" "$f"
  echo "start-reset-lessons: $f: reset to the format header ($before -> $(( $(wc -l < "$f") )) lines)"
done

# The template's MAINTENANCE.log: its whole content goes to the same archive
# file under its own section, then the file is removed.
if [[ -s "$MLOG" ]] && [[ -n "$(tr -d '[:space:]' < "$MLOG")" ]]; then
  write_section "$MLOG" "$MLOG"
  rm -f -- "$MLOG"
  echo "start-reset-lessons: $MLOG: template entries archived and the file removed"
elif [[ -f "$MLOG" ]]; then
  rm -f -- "$MLOG"
fi
if [[ -n "$ARCHIVE" ]]; then
  echo "start-reset-lessons: the dropped lines are archived in $ARCHIVE"
fi
