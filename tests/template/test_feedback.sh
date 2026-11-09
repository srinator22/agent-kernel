#!/usr/bin/env bash
# feedback hook: scripts/feedback-log.sh (UserPromptSubmit) logs each owner prompt
# with its situation to the main checkout's .work/feedback/log.jsonl, guesses its
# kind by word lists, prints one context line, never rotates, and always exits 0.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" || { echo "$0: cannot load lib.sh; stopped before writing anything" >&2; exit 2; }

# winpath P: the native form of a path where git bash can give one (python is a
# native program on Windows and cannot open an msys /tmp path).
winpath() { (cd "$1" && { pwd -W 2>/dev/null || pwd; }); }

setup() {
  make_fixture
  cp_script feedback-log.sh dream/dream.py dream/feedback.py
  mkdir -p src
  git add scripts && git commit -q -m "chore: scripts"
  git checkout -q -b task/demo
  FIXW="$(winpath "$FIX")"
  LOG="$FIX/.work/feedback/log.jsonl"
  TP="$FIX/transcript.jsonl"
  TPW="$FIXW/transcript.jsonl"
  : > "$TP"
}

# hook TEXT: run the hook the way Claude Code does, with the prompt on stdin.
hook() {
  OUT="$(printf '{"prompt":"%s","session_id":"abcdef123456789","cwd":"%s","transcript_path":"%s"}' \
    "$1" "$FIXW" "${2:-$TPW}" | bash scripts/feedback-log.sh 2>&1)"
  RC=$?
}
lines() { if [[ -f "$LOG" ]]; then wc -l < "$LOG" | tr -d ' '; else echo 0; fi; }
last() { tail -n 1 "$LOG" 2>/dev/null; }
assert_last_has() { # name needle
  if last | grep -qF -- "$2"; then t_ok "$1"; else t_bad "$1 (last log line lacks: $2)"; last | sed 's/^/       | /'; fi
}
assert_last_lacks() { # name needle
  if ! last | grep -qF -- "$2"; then t_ok "$1"; else t_bad "$1 (last log line has: $2)"; last | sed 's/^/       | /'; fi
}
edit_line() { # tool path
  printf '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"%s","input":{"%s":"%s"}}]}}\n' "$1" "${3:-file_path}" "$2"
}
say_line() {
  printf '{"type":"assistant","message":{"content":[{"type":"text","text":"%s"}]}}\n' "$1"
}

# --- A1: schema and filters ---
setup
printf '# Task: demo-task\nMode: autopilot\n' > .work_task_tmp && mkdir -p .work && mv .work_task_tmp .work/TASK.md
hook "no, that is wrong"
assert_rc "hook exits 0" 0
assert_file "log is written" "$LOG"
assert_eq "one line logged" 1 "$(lines)"
for key in '"v":1' '"ts":"' '"session":"abcdef12"' '"branch":"task/demo"' '"task":"demo-task"' \
           '"kind":"correction"' '"text":"no, that is wrong"' '"files":[' '"said":'; do
  assert_last_has "schema has $key" "$key"
done
hook "Task (from the session that started this one) do a thing"
assert_eq "machine-written prompt is not logged" 1 "$(lines)"
hook "Another Claude session sent a message"
assert_eq "peer-session prompt is not logged" 1 "$(lines)"
hook "/commit now"
assert_eq "slash command is not logged" 1 "$(lines)"
hook "<command-name>x</command-name>"
assert_eq "tag-leading prompt is not logged" 1 "$(lines)"
long="$(head -c 3000 /dev/zero | tr '\0' 'a')"
hook "$long"
assert_last_lacks "a 2000+ character prompt is clipped" "$(head -c 2001 /dev/zero | tr '\0' 'a')"
assert_last_has "a clipped prompt keeps its first 2000 characters" "$(head -c 2000 /dev/zero | tr '\0' 'a')"

# --- A2: transcript situation ---
setup
{
  edit_line Edit "$FIXW/src/e1.txt"
  edit_line Write "$FIXW/src/e2.txt"
  edit_line Read "$FIXW/src/read-only.txt"
  edit_line MultiEdit "$FIXW/src/e3.txt"
  edit_line NotebookEdit "$FIXW/src/e4.ipynb" notebook_path
  edit_line Edit "$FIXW/src/e5.txt"
  edit_line Edit "$FIXW/src/e6.txt"
  edit_line Edit "/somewhere/else/outside.txt"
  say_line "first words"
  say_line "I changed   the file"
} > "$TP"
hook "looks great"
assert_last_has "five files, newest first" '"files":["src/e6.txt","src/e5.txt","src/e4.ipynb","src/e3.txt","src/e2.txt"]'
assert_last_lacks "the sixth file is dropped" "e1.txt"
assert_last_lacks "a Read call is not an edit" "read-only"
assert_last_lacks "a path outside the repository is not reported" "outside.txt"
assert_last_has "the last assistant text is kept, whitespace collapsed" '"said":"I changed the file"'
assert_last_has "no TASK.md gives task -" '"task":"-"'
mkdir -p .work && printf '# Task: {{title}}\n' > .work/TASK.md
hook "looks great"
assert_last_has "template TASK.md gives task -" '"task":"-"'

setup
{
  edit_line Edit "$FIXW/src/head-only.txt"
  yes '{"type":"user","message":{"content":"padding padding padding padding padding padding"}}' | head -c 600000
  echo
  edit_line Edit "$FIXW/src/tail.txt"
} > "$TP"
hook "perfect"
assert_rc "large transcript: exits 0" 0
assert_last_has "large transcript: tail edit reported" '"files":["src/tail.txt"]'
assert_last_lacks "large transcript: head-only edit is not reported" "head-only"

setup
{ say_line "$(head -c 900 /dev/zero | tr '\0' 'z')"; } > "$TP"
hook "perfect"
assert_last_lacks "said is clipped to 300" "$(head -c 301 /dev/zero | tr '\0' 'z')"

# --- A3: printed lines and robustness ---
setup
hook "no, that is wrong"
assert_contains "correction prints the feedback line" "Owner feedback logged (correction"
assert_not_contains "template mode asks for no register row" "preferences.md"
hook "perfect"
assert_contains "approval prints the feedback line" "Owner feedback logged (approval"
hook "always use tabs"
assert_contains "preference prints the feedback line" "Owner feedback logged (preference"
hook "do that later"
assert_contains "deferral prints the deferral line" "Owner deferral logged"
assert_contains "deferral line says to record a note" "do not start the work"
assert_not_contains "deferral prints no feedback line" "Owner feedback logged"
hook "run the tests"
assert_eq "a plain message prints nothing" "" "$OUT"
touch .start-done
hook "always use tabs"
assert_contains "started project: row request" "docs/procedures/preferences.md"
rm -f .start-done

n="$(lines)"
hook "run the tests" "$FIXW/no-such-transcript.jsonl"
assert_rc "missing transcript: exits 0" 0
assert_eq "missing transcript: still logs" $((n + 1)) "$(lines)"
assert_last_has "missing transcript: empty files" '"files":[]'
printf 'not json at all\n{"type":"assistant"\n[1,2]\n' > "$TP"
hook "run the tests"
assert_rc "malformed transcript: exits 0" 0
assert_last_has "malformed transcript: line still logged" '"kind":"message"'

OUT="$(printf 'not json' | bash scripts/feedback-log.sh 2>&1)"; RC=$?
assert_rc "bad stdin: exits 0" 0
OUT="$(bash scripts/feedback-log.sh < /dev/null 2>&1)"; RC=$?
assert_rc "empty stdin: exits 0" 0
OUT="$(printf '{"prompt":"x"}' | bash scripts/feedback-log.sh 2>&1)"; RC=$?
assert_rc "no transcript_path: exits 0" 0

n="$(lines)"
OUT="$(printf '{"prompt":"no way","session_id":"s","transcript_path":""}' | FEEDBACK_LOG=0 bash scripts/feedback-log.sh 2>&1)"; RC=$?
assert_rc "FEEDBACK_LOG=0: exits 0" 0
assert_eq "FEEDBACK_LOG=0: nothing printed" "" "$OUT"
assert_eq "FEEDBACK_LOG=0: nothing logged" "$n" "$(lines)"
OUT="$(printf '{"prompt":"no way","session_id":"s"}' | env PATH=/nonexistent "$BASH" scripts/feedback-log.sh 2>&1)"; RC=$?
assert_rc "no python: exits 0" 0
assert_eq "no python: silent" "" "$OUT"
assert_eq "no python: nothing logged" "$n" "$(lines)"

rm -rf .work
echo "in the way" > .work
hook "no, that is wrong"
assert_rc "unwritable log folder: exits 0" 0
rm -f .work

# --- A4: location and no rotation ---
setup
git add -A >/dev/null 2>&1; git commit -q -m "chore: base" --allow-empty
git worktree add -q "$FIX/wt" -b task/other >/dev/null 2>&1
WT="$FIX/wt"
OUT="$(cd "$WT" && printf '{"prompt":"no, wrong","session_id":"s1","cwd":"%s","transcript_path":""}' "$(winpath "$WT")" | bash scripts/feedback-log.sh 2>&1)"; RC=$?
assert_rc "linked worktree: exits 0" 0
assert_file "linked worktree logs into the main checkout" "$LOG"
assert_no_file "linked worktree has no log of its own" "$WT/.work/feedback/log.jsonl"
assert_last_has "linked worktree: its own branch is logged" '"branch":"task/other"'
assert_eq "feedback folder ignores itself" "*" "$(cat "$FIX/.work/feedback/.gitignore" 2>/dev/null)"
git worktree remove --force "$WT" >/dev/null 2>&1

yes '{"v":1,"ts":"2026-01-01T00:00:00Z","kind":"message","text":"filler filler filler filler filler filler"}' | head -c 6000000 > "$LOG"
before="$(wc -c < "$LOG" | tr -d ' ')"
nl="$(lines)"
hook "no, wrong again"
assert_rc "over 5 MB: exits 0" 0
assert_no_file "the hook never rotates" "$FIX/.work/feedback/log.1.jsonl"
assert_eq "over 5 MB: one line appended" $((nl + 1)) "$(lines)"
if (( $(wc -c < "$LOG" | tr -d ' ') > before )); then t_ok "over 5 MB: log grew"; else t_bad "over 5 MB: log did not grow"; fi

# --- A5: classifier ---
setup
check_kind() { # kind text...
  local want="$1"; shift
  hook "$*"
  if last | grep -qF "\"kind\":\"$want\""; then t_ok "$want <- $*"; else t_bad "$want <- $* (got: $(last | sed 's/.*"kind":"\([a-z]*\)".*/\1/'))"; fi
}
check_kind deferral "do that later"
check_kind deferral "not now"
check_kind deferral "just record it"
check_kind deferral "don't build it yet"
check_kind deferral "don$(printf '\342\200\231')t build it yet"
check_kind deferral "do not change it now"
check_kind deferral "no, later"
check_kind message "do that"
check_kind correction "no, that is not it"
check_kind correction "stop doing that"
check_kind correction "this is wrong"
check_kind correction "revert the last change"
check_kind correction "why did you add that"
check_kind correction "that is not what i asked"
check_kind correction "it is still broken"
check_kind correction "the bug is back again"
check_kind message "keep going"
check_kind preference "always use tabs"
check_kind preference "from now on be brief"
check_kind preference "i want shorter answers"
check_kind preference "i don't like the font"
check_kind preference "make sure it runs on windows"
check_kind preference "every time you finish, say so"
check_kind approval "perfect"
check_kind approval "this looks great"
check_kind approval "that's exactly what i wanted"
check_kind approval "love it"
check_kind approval "approved"
check_kind message "run the tests again"
check_kind message "what exactly does this do"
check_kind message "please add a readme"

t_finish
