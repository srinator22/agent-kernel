#!/usr/bin/env bash
# scripts/find-python.sh: the shared Python probe. It chooses the first of
# python3 and python that RUNS as Python 3, because on Windows python3 can be
# the Microsoft Store stub that command -v finds and that exits 49. Covers the
# helper itself (stub first, stub only, working python3, no variable left
# behind), the scripts that source it (dream.sh, feedback-log.sh, check.sh 5f)
# and that no script or test still picks python3 by command -v alone.
# The test never skips: a real Python 3 is found by probing and wrapped.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" || { echo "$0: cannot load lib.sh; stopped before writing anything" >&2; exit 2; }

HELPER="$T_ROOT/scripts/find-python.sh"

# The real interpreter, probed here so the test does not depend on the helper.
REAL=""
for c in python3 python; do
  if command -v "$c" >/dev/null 2>&1 && "$c" -c 'import sys; sys.exit(sys.version_info < (3,))' >/dev/null 2>&1; then
    REAL="$(command -v "$c")"; break
  fi
done
if [[ -z "$REAL" ]]; then
  t_bad "no working Python 3 on PATH; this test needs one and is never skipped"
  t_finish
fi

BIN="$(mktemp -d "${TMPDIR:-/tmp}/template-selftest.XXXXXX")"
# Removed with the fixture cleanup trap's pattern; kept separate from FIX.
trap 'rm -rf "$BIN"; t_cleanup' EXIT
mkdir -p "$BIN/stubonly" "$BIN/both" "$BIN/good"
printf '#!/bin/sh\necho "Python was not found; run without arguments to install from the Microsoft Store"\nexit 49\n' > "$BIN/stubonly/python3"
printf '#!/bin/sh\nexec "%s" "$@"\n' "$REAL" > "$BIN/both/python"
cp "$BIN/stubonly/python3" "$BIN/both/python3"
printf '#!/bin/sh\nexec "%s" "$@"\n' "$REAL" > "$BIN/good/python3"
chmod +x "$BIN"/*/python*

# probe DIR...: PY after sourcing the helper with those dirs first on PATH.
probe() {
  local p=""
  for d in "$@"; do p="$p$d:"; done
  OUT="$(PATH="$p$PATH" bash -c '. "$1" && printf %s "$PY"' _ "$HELPER" 2>&1)"; RC=$?
}

# --- A1: the helper ---
assert_file "the helper exists" "$HELPER"
probe "$BIN/both"
assert_eq "stub python3 first, working python: PY is python" "python" "$OUT"
probe "$BIN/good"
assert_eq "working python3: PY is python3" "python3" "$OUT"
# Only the stub on PATH ahead of a PATH holding no real python: build a PATH of
# the stub dir plus the directories that hold bash and no python.
NOPY=""
IFS=: read -r -a dirs <<< "$PATH"
for d in "${dirs[@]}"; do
  [[ -d "$d" ]] || continue
  if [[ -x "$d/python" || -x "$d/python3" || -x "$d/python.exe" || -x "$d/python3.exe" ]]; then continue; fi
  NOPY="$NOPY:$d"
done
# bash by absolute path: on Linux /usr/bin holds both bash and python3, so the
# PATH above has no bash in it.
BASHX="$(command -v bash)"
OUT="$(PATH="$BIN/stubonly$NOPY" "$BASHX" -c '. "$1" && printf %s "[$PY]"' _ "$HELPER" 2>&1)"
assert_eq "only the stub reachable: PY is empty" "[]" "$OUT"
OUT="$(PATH="$BIN/both:$PATH" bash -c 'compgen -v | sort >"$2/before"; . "$1"; compgen -v | sort >"$2/after"; diff "$2/before" "$2/after"' _ "$HELPER" "$BIN" 2>&1)"
assert_eq "the helper leaves only PY set" "> PY" "$(printf '%s\n' "$OUT" | grep '^[<>]' | grep -v PIPESTATUS | tr '\n' ' ' | sed 's/ $//')"

# --- A2: the scripts that source it ---
make_fixture
cp_script dream.sh find-python.sh feedback-log.sh dream/dream.py dream/feedback.py
mkdir -p src
git add scripts && git commit -q -m "chore: scripts"
git checkout -q -b task/demo
FIXW="$( (pwd -W 2>/dev/null || pwd) )"

run env PATH="$BIN/both:$PATH" bash scripts/dream.sh due
assert_not_contains "dream.sh due finds Python past the stub" "python not found"
assert_not_contains "dream.sh due does not run the stub" "Python was not found"

LOG="$FIX/.work/feedback/log.jsonl"
printf '{"prompt":"no, that is wrong","session_id":"abcdef123456789","cwd":"%s","transcript_path":"%s/t.jsonl"}' "$FIXW" "$FIXW" > "$FIX/hook.json"
: > "$FIX/t.jsonl"
PATH="$BIN/both:$PATH" bash scripts/feedback-log.sh < "$FIX/hook.json" >/dev/null 2>&1
RC=$?
assert_eq "feedback hook exits 0 with the stub first" "0" "$RC"
if [[ -f "$LOG" && "$(wc -l < "$LOG" | tr -d ' ')" -ge 1 ]]; then t_ok "feedback hook writes a log line past the stub"; else t_bad "feedback hook wrote no log line with the stub first"; fi

mv scripts/find-python.sh scripts/find-python.sh.off
run env PATH="$BIN/both:$PATH" bash scripts/feedback-log.sh < "$FIX/hook.json"
assert_rc "feedback hook exits 0 without the helper" 0
EXPR='. scripts/find-python.sh 2>/dev/null; printf %s "${PY:-}"'
OUT="$(bash -e -c 'PY="$(bash -c "$1")"; echo "[$PY]"' _ "$EXPR" 2>&1)"; RC=$?
assert_rc "check.sh 5f expression survives a missing helper" 0
assert_eq "check.sh 5f expression is empty without the helper" "[]" "$OUT"
printf 'exit 0\n' > scripts/find-python.sh; chmod +x scripts/find-python.sh
OUT="$(bash -e -c 'PY="$(bash -c "$1")"; echo "[$PY]"' _ "$EXPR" 2>&1)"; RC=$?
assert_rc "check.sh 5f expression survives a helper that exits" 0
assert_eq "check.sh 5f expression is empty for a helper that exits" "[]" "$OUT"
cd "$T_ROOT" || exit 1

# --- A3: every pick goes through the helper ---
for f in scripts/dream.sh scripts/feedback-log.sh scripts/preferences.sh scripts/check.sh \
         tests/template/fixtures/check.sh tests/template/test_dream.sh tests/template/test_preferences.sh \
         tests/template/test_profile_tools.sh tests/template/test_taste.sh; do
  assert_file_has "$f sources find-python.sh" "$T_ROOT/$f" "find-python.sh"
done
left="$(grep -rn 'command -v python3' scripts tests/template 2>/dev/null \
  | grep -v '^tests/template/test_find_python.sh:' | grep -v '^tests/template/test_session_context.sh:' | grep -v '^scripts/find-python.sh:')"
assert_eq "no other command -v python3 pick remains" "" "$left"

# --- the shell-stdin hook launcher, wired into .claude/settings.json, picks
# Python through the helper too, so the Store stub first on PATH cannot turn
# the hook off ---
LAUNCHER="$T_ROOT/docs/library/hooks/refuse_shell_stdin.sh"
assert_file_has "the hook launcher sources find-python.sh" "$LAUNCHER" "find-python.sh"
hook() { # COMMAND: the hook's exit code for a Bash call, the stub first on PATH
  printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' "$1" \
    | PATH="$BIN/both:$PATH" CLAUDE_PROJECT_DIR="$T_ROOT" bash "$LAUNCHER" >/dev/null 2>&1
}
hook 'echo 1 | python -'; RC=$?
assert_rc "with the stub first, the hook still refuses python from stdin" 2
hook 'git commit -F msg.txt'; RC=$?
assert_rc "with the stub first, git commit -F still runs" 0
OUT="$(printf '{"tool_name":"Bash","tool_input":{"command":"git status"}}' \
  | PATH="$BIN/stubonly" CLAUDE_PROJECT_DIR="$T_ROOT" "$(command -v bash)" "$LAUNCHER" 2>&1)"; RC=$?
assert_rc "with only the stub, the launcher reports a non-blocking error" 1
assert_contains "the launcher says the hook did not run" "the shell-stdin hook did not run"

t_finish
