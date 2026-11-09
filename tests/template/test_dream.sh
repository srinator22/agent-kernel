#!/usr/bin/env bash
# scripts/dream.sh and scripts/dream/dream.py: the signal digest, the once-only offsets, the
# due decision, the memory hygiene report and the scorecard. Transcripts are synthetic JSONL
# under a fake projects folder; DREAM_PROJECTS_DIR and DREAM_NOW pin the inputs.
# Without python the test is skipped (CI has python3).
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" || { echo "$0: cannot load lib.sh; stopped before writing anything" >&2; exit 2; }

PY=""
command -v python3 >/dev/null 2>&1 && PY=python3
[[ -n "$PY" ]] || { command -v python >/dev/null 2>&1 && PY=python; } || true
if [[ -z "$PY" ]]; then
  t_ok "python not found; dream tests skipped (CI runs them)"
  t_finish
fi

make_fixture
cp_script dream.sh dream/dream.py
NATIVE="$(cygpath -w "$FIX" 2>/dev/null || echo "$FIX")"
SLUG="$("$PY" -c 'import re,sys;print(re.sub(r"[^A-Za-z0-9]","-",sys.argv[1]))' "$NATIVE")"
# Project folders live under a short folder of their own: each holds a folder named
# by the slug of $FIX, so nesting them inside $FIX doubles the path and passes the
# 260-character limit on Windows when TMPDIR is long.
PB="$(mktemp -d /tmp/template-selftest.pb.XXXXXX 2>/dev/null || mktemp -d "${TMPDIR:-/tmp}/template-selftest.pb.XXXXXX")"
[[ -n "$PB" && -d "$PB" ]] || { t_bad "no temp folder for the project folders"; t_finish; }
FIX0="$FIX"
# Folders made beside the fixture go with it on an early exit too, not only at the end.
cleanup_extra() {
  local d
  for d in "$FIX0-wt" "$FIX0-wt2" "$FIX0-wt3" "$FIX0-wt4" "$FIX0-m1" "$FIX0-m2" "$PB"; do
    case "$d" in */template-selftest.*) rm -rf "$d" ;; esac
  done
}
trap 'cleanup_extra; t_cleanup' EXIT
PROJ="$PB/projects"
mkdir -p "$PROJ/$SLUG" "$PROJ/elsewhere"
export DREAM_PROJECTS_DIR="$PROJ"
export DREAM_NOW="2026-11-07T12:00:00Z"
STATE="$FIX/.work/dream"
LOG="$FIX/docs/lessons/MAINTENANCE.log"
S1="$PROJ/$SLUG/aaaaaaaa11.jsonl"
S2="$PROJ/elsewhere/bbbbbbbb22.jsonl"

# Writes one transcript line (or fragment) with python so JSON escaping is real.
cat > "$FIX/mk.py" <<'PYEOF'
import json, sys
f, kind, ts, text, cwd, branch, sess = sys.argv[1:8]
base = {"timestamp": ts, "cwd": cwd, "gitBranch": branch, "sessionId": sess}
if kind == "user":
    o = dict(base, type="user", message={"role": "user", "content": text})
elif kind == "userlist":
    o = dict(base, type="user", message={"role": "user", "content": [{"type": "text", "text": text}]})
elif kind == "meta":
    o = dict(base, type="user", isMeta=True, message={"role": "user", "content": text})
elif kind == "err":
    o = dict(base, type="user", message={"role": "user", "content": [
        {"type": "tool_result", "is_error": True, "content": text}]})
elif kind == "errlist":
    o = dict(base, type="user", message={"role": "user", "content": [
        {"type": "tool_result", "is_error": True, "content": [{"type": "text", "text": text}]}]})
elif kind == "queued":
    o = dict(base, type="attachment", attachment={"type": "queued_command", "prompt": text})
elif kind == "compact":
    o = dict(base, type="user", isCompactSummary=True, message={"role": "user", "content": text})
elif kind == "vis":
    o = dict(base, type="user", isVisibleInTranscriptOnly=True, message={"role": "user", "content": text})
elif kind == "userp":
    o = dict(base, type="user", message={"role": "user", "content": text})
elif kind == "human":
    o = dict(base, type="user", origin={"kind": "human"}, promptSource="sdk", message={"role": "user", "content": text})
elif kind == "peer":
    o = dict(base, type="user", origin={"kind": "peer", "from": "local_x"}, promptSource="system",
             message={"role": "user", "content": text})
elif kind == "brief":
    o = dict(base, type="user", promptSource="sdk", turnOrigin="sdk", message={"role": "user", "content": text})
elif kind == "queuednotif":
    o = dict(base, type="attachment", attachment={"type": "queued_command", "prompt": text,
                                                  "origin": {"kind": "task-notification"}})
elif kind in ("raw", "rawp", "nl"):
    o = None
else:
    raise SystemExit("bad kind " + kind)
with open(f, "a", encoding="utf-8", newline="\n") as fh:
    if kind == "raw":
        fh.write(text + "\n")
    elif kind == "rawp":
        fh.write(text)
    elif kind == "nl":
        fh.write("\n")
    elif kind == "userp":
        fh.write(json.dumps(o))
    else:
        fh.write(json.dumps(o) + "\n")
PYEOF

# mk FILE KIND TS TEXT [CWD] [BRANCH]
mk() { "$PY" "$FIX/mk.py" "$1" "$2" "$3" "$4" "${5:-$NATIVE}" "${6:-main}" "sess"; }
dg() { run bash "$FIX/scripts/dream.sh" digest "$@"; }
D="$STATE/digest.md"

# --- nothing yet ---
run bash scripts/dream.sh due
assert_rc "due: not due without transcripts" 1
assert_contains "due: not due text" "dream: not due (0 sessions"
run bash scripts/dream.sh done
assert_rc "done without a digest exits 2" 2
assert_contains "done without a digest says so" "run digest first"

# --- transcripts ---
LONGMSG="$(printf 'x%.0s' $(seq 1 500))"
LONGERR="$(printf 'y%.0s' $(seq 1 400))"
mk "$S1" user      2026-11-07T10:00:00.000Z "please add a feature"
mk "$S1" userlist  2026-11-07T10:01:00.000Z "no, stop doing that"
mk "$S1" queued    2026-11-07T10:02:00.000Z "also check the docs"
mk "$S1" user      2026-11-07T10:03:00.000Z "[Request interrupted by user]"
mk "$S1" err       2026-11-07T10:04:00.000Z "Permission for this action was denied by the user"
mk "$S1" errlist   2026-11-07T10:05:00.000Z "PreToolUse hook error: BLOCKED by guard"
mk "$S1" err       2026-11-07T10:06:00.000Z "Exit code 1 compile failed"
mk "$S1" err       2026-11-07T10:07:00.000Z "Exit code 1 compile failed"
mk "$S1" meta      2026-11-07T10:08:00.000Z "meta line must not appear"
mk "$S1" user      2026-11-07T10:09:00.000Z "<command-name>wrapper must not appear</command-name>"
mk "$S1" queued    2026-11-07T10:09:30.000Z "<task-notification>queued wrapper must not appear"
mk "$S1" user      2026-11-07T10:10:00.000Z "sibling folder must not appear" "${NATIVE}sibling"
mk "$S1" user      2026-11-07T10:11:00.000Z "$LONGMSG"
mk "$S1" err       2026-11-07T10:12:00.000Z "$LONGERR"
mk "$S1" raw       2026-11-07T10:13:00.000Z "{\"cwd\": \"$(printf '%s' "$NATIVE" | sed 's/\\/\\\\/g')\" broken"
mk "$S1" compact   2026-11-07T10:14:00.000Z "This session is being continued from a previous conversation compact summary"
mk "$S1" vis       2026-11-07T10:15:00.000Z "visible only in the transcript text"
mk "$S1" human     2026-11-07T10:16:00.000Z "typed by the owner in a new client"
mk "$S1" peer      2026-11-07T10:17:00.000Z "another session's words must not appear"
mk "$S1" brief     2026-11-07T10:18:00.000Z "Task (from the session that started this one): a brief must not appear"
mk "$S1" user      2026-11-07T10:19:00.000Z "Background (from the session that started this one): an old brief must not appear"
mk "$S1" queuednotif 2026-11-07T10:20:00.000Z "a queued notification must not appear"
mk "$S2" user      2026-11-07T11:00:00.000Z "from another project folder"
mk "$S2" user      2026-11-07T11:01:00.000Z "other repo must not appear" "$NATIVE-other/dir"
mk "$S1" rawp      2026-11-07T11:30:00.000Z "$(printf '%s' '{"type":"user","timestamp":"2026-11-07T11:30:00.000Z","cwd":"')$(printf '%s' "$NATIVE" | sed 's/\\/\\\\/g')\",\"gitBranch\":\"main\",\"message\":{\"content\":\"the partial line\"}}"

run bash scripts/dream.sh due
assert_rc "due: new activity and no dream for 3 days" 0
assert_contains "due text" "dream: due (1 sessions"
run bash scripts/dream.sh due --offer
assert_rc "due --offer first time succeeds" 0
assert_file "due --offer records the offer" "$STATE/offered"
assert_file_has "state folder ignores itself" "$STATE/.gitignore" "*"
run bash scripts/dream.sh due --offer
assert_rc "due --offer second time is refused" 1
assert_contains "already offered text" "already offered today"
run bash scripts/dream.sh due --quiet
assert_eq "due --quiet prints nothing" "" "$OUT"

dg
assert_rc "digest exits 0" 0
assert_contains "digest summary line" "dream: digest "
FIRST_OUT="$OUT"
assert_file_has "kind U" "$D" "[U] 2026-11-07 10:00 aaaaaaaa main: please add a feature"
assert_file_has "kind C (typed, list content)" "$D" "[C] 2026-11-07 10:01 aaaaaaaa main: no, stop doing that"
assert_file_has "kind M" "$D" "[M] 2026-11-07 10:02 aaaaaaaa main: also check the docs"
assert_file_has "kind I" "$D" "[I] 2026-11-07 10:03 aaaaaaaa main: [Request interrupted by user]"
assert_file_has "kind D" "$D" "[D] 2026-11-07 10:04 aaaaaaaa main: Permission for this action was denied"
assert_file_has "kind H (list content)" "$D" "[H] 2026-11-07 10:05 aaaaaaaa main: PreToolUse hook error: BLOCKED by guard"
assert_file_has "kind E" "$D" "[E] "
assert_file_has "repeated error collapses with a count" "$D" "Exit code 1 compile failed (x2)"
assert_file_lacks "isMeta line excluded" "$D" "meta line must not appear"
assert_file_lacks "compaction summary excluded" "$D" "This session is being continued"
assert_file_lacks "transcript-only line excluded" "$D" "visible only in the transcript text"
assert_file_has "owner line (origin human) included" "$D" "typed by the owner in a new client"
assert_file_lacks "another session's message excluded" "$D" "another session's words must not appear"
assert_file_lacks "a session brief excluded" "$D" "a brief must not appear"
assert_file_lacks "an old-format session brief excluded" "$D" "an old brief must not appear"
assert_file_lacks "a queued notification excluded" "$D" "a queued notification must not appear"
run git -C "$FIX" status --porcelain -uall -- .work/dream
assert_eq "state folder never shows in git status" "" "$OUT"
assert_file_lacks "wrapper text excluded" "$D" "wrapper must not appear"
assert_file_lacks "sibling cwd excluded" "$D" "sibling folder must not appear"
assert_file_lacks "other repository excluded" "$D" "other repo must not appear"
assert_file_has "session from another project folder included" "$D" "bbbbbbbb main: from another project folder"
assert_file_has "message truncated at 400 with ..." "$D" "$(printf 'x%.0s' $(seq 1 400))..."
assert_file_lacks "message not longer than 400" "$D" "$(printf 'x%.0s' $(seq 1 401))"
assert_file_has "error truncated at 300 with ..." "$D" "$(printf 'y%.0s' $(seq 1 300))..."
assert_file_lacks "error not longer than 300" "$D" "$(printf 'y%.0s' $(seq 1 301))"
assert_file_has "malformed line counted" "$D" "malformed: 1"
assert_file_lacks "partial last line not consumed" "$D" "the partial line"
assert_file_has "digest has the hygiene section" "$D" "## Hygiene"
assert_file "digest writes state.next.json" "$STATE/state.next.json"
assert_no_file "digest does not commit state.json" "$STATE/state.json"
SIGLINE1="$(grep -c '^- s[0-9]' "$D")"

# Complete the partial line; with no done in between, the next digest rereads all.
mk "$S1" nl 2026-11-07T11:30:00.000Z ""
dg
assert_rc "second digest exits 0" 0
assert_file_has "completed partial line is read" "$D" "the partial line"
assert_file_has "unfinished dream loses nothing" "$D" "please add a feature"
SIGLINE2="$(grep -c '^- s[0-9]' "$D")"
assert_eq "second digest has one more signal" "$((SIGLINE1 + 1))" "$SIGLINE2"

run bash scripts/dream.sh done
assert_rc "done exits 0" 0
assert_contains "done text" "dream: done"
assert_no_file "done edits no tracked file (no maintenance log)" "$LOG"
assert_file_has "done records the dream date in state" "$STATE/state.json" "2026-11-07T12:00:00Z"
assert_no_file "done clears the offer" "$STATE/offered"
assert_no_file "done consumes state.next.json" "$STATE/state.next.json"
assert_file "done writes state.json" "$STATE/state.json"

dg
assert_rc "digest after done exits 3" 3
assert_contains "nothing to dream" "nothing to dream"
assert_file "offsets stay committed" "$STATE/state.json"

# New activity only: a later digest sees just the new line.
mk "$S1" user 2026-11-08T09:00:00.000Z "a brand new request"
DREAM_NOW="2026-11-08T12:00:00Z" dg
assert_rc "digest of new activity exits 0" 0
assert_file_has "new line read" "$D" "a brand new request"
assert_file_lacks "old lines not read again" "$D" "please add a feature"
assert_file_has "since shows the last dream" "$D" "since: 2026-11-07T12:00:00Z"
rm -f "$STATE/state.next.json" "$D"

# --- due after a dream ---
export DREAM_NOW="2026-11-08T12:00:00Z"
run bash scripts/dream.sh due
assert_rc "not due: activity, no retro, last dream 1 day ago" 1
assert_contains "not due names the last dream" "last dream 2026-11-07"
mkdir -p "$FIX/.work/done"
echo retro > "$FIX/.work/done/task.md"
"$PY" -c "import os,datetime as d,sys; t=d.datetime(2026,11,8,6,0,tzinfo=d.timezone.utc).timestamp(); os.utime(sys.argv[1],(t,t))" "$FIX/.work/done/task.md"
run bash scripts/dream.sh due
assert_rc "due: a retro newer than the last dream" 0
assert_contains "due counts the retro" "1 task retros"
"$PY" -c "import os,datetime as d,sys; t=d.datetime(2026,11,7,6,0,tzinfo=d.timezone.utc).timestamp(); os.utime(sys.argv[1],(t,t))" "$FIX/.work/done/task.md"
run bash scripts/dream.sh due
assert_rc "not due: a retro older than the last dream" 1
# A retro counts by the date its record was committed: a fresh checkout stamps every
# archived record with a new modification time, so mtime alone makes a dream look due.
echo old > "$FIX/.work/done/old.md"
git add .work/done/old.md >/dev/null 2>&1
GIT_AUTHOR_DATE="2026-11-06T12:00:00Z" GIT_COMMITTER_DATE="2026-11-06T12:00:00Z" git commit -q -m old-retro >/dev/null 2>&1
"$PY" -c "import os,datetime as d,sys; t=d.datetime(2026,11,8,6,0,tzinfo=d.timezone.utc).timestamp(); os.utime(sys.argv[1],(t,t))" "$FIX/.work/done/old.md"
run bash scripts/dream.sh due
assert_rc "not due: a record committed before the last dream, with a new file time" 1
assert_contains "due ignores the file time of a committed record" "0 task retros"
echo new > "$FIX/.work/done/new.md"
git add .work/done/new.md >/dev/null 2>&1
GIT_AUTHOR_DATE="2026-11-08T06:00:00Z" GIT_COMMITTER_DATE="2026-11-08T06:00:00Z" git commit -q -m new-retro >/dev/null 2>&1
"$PY" -c "import os,datetime as d,sys; t=d.datetime(2026,11,6,6,0,tzinfo=d.timezone.utc).timestamp(); os.utime(sys.argv[1],(t,t))" "$FIX/.work/done/new.md"
run bash scripts/dream.sh due
assert_rc "due: a record committed after the last dream, with an old file time" 0
assert_contains "due counts a record by its commit date" "1 task retros"
git rm -q -f .work/done/old.md .work/done/new.md >/dev/null 2>&1
git commit -q -m drop-retros >/dev/null 2>&1

# Edge cases of the commit date: an edit that is staged but not committed, and a record
# deleted in a commit and recreated untracked, are dated by their file time.
EDGE="$FIX/.work/done/edge.md"
echo edge > "$EDGE"
git add .work/done/edge.md >/dev/null 2>&1
GIT_AUTHOR_DATE="2026-11-06T12:00:00Z" GIT_COMMITTER_DATE="2026-11-06T12:00:00Z" git commit -q -m edge-retro >/dev/null 2>&1
SETM() { "$PY" -c "import os,datetime as d,sys; t=d.datetime(2026,11,int(sys.argv[2]),6,0,tzinfo=d.timezone.utc).timestamp(); os.utime(sys.argv[1],(t,t))" "$1" "$2"; }
SETM "$EDGE" 8
run bash scripts/dream.sh due
assert_rc "not due: a clean committed record keeps its commit date" 1
assert_contains "clean committed record is not counted" "0 task retros"
echo more >> "$EDGE"
git add .work/done/edge.md >/dev/null 2>&1
SETM "$EDGE" 8
run bash scripts/dream.sh due
assert_rc "due: a record edited and staged is dated by its file time" 0
assert_contains "staged edit is counted" "1 task retros"
GIT_AUTHOR_DATE="2026-11-06T13:00:00Z" GIT_COMMITTER_DATE="2026-11-06T13:00:00Z" git commit -q -m edge-staged >/dev/null 2>&1
git rm -q -f .work/done/edge.md >/dev/null 2>&1
GIT_AUTHOR_DATE="2026-11-08T06:00:00Z" GIT_COMMITTER_DATE="2026-11-08T06:00:00Z" git commit -q -m edge-deleted >/dev/null 2>&1
echo edge > "$EDGE"
SETM "$EDGE" 6
run bash scripts/dream.sh due
assert_rc "not due: a record recreated untracked after a deletion commit" 1
assert_contains "recreated record is dated by its file time, not the deletion" "0 task retros"
rm -f "$EDGE"
export DREAM_NOW="2026-11-11T12:30:00Z"
run bash scripts/dream.sh due
assert_rc "due: last dream 4 days ago" 0
export DREAM_NOW="2026-11-07T12:00:00Z"

# --- no python ---
run env PATH=/nonexistent "$BASH" "$FIX/scripts/dream.sh" due
assert_rc "no python: due exits 1" 1
assert_contains "no python: due text" "python not found"
run env PATH=/nonexistent "$BASH" "$FIX/scripts/dream.sh" due --quiet
assert_rc "no python: due --quiet exits 1" 1
assert_eq "no python: due --quiet prints nothing" "" "$OUT"
run env PATH=/nonexistent "$BASH" "$FIX/scripts/dream.sh" digest
assert_rc "no python: digest exits 2" 2
assert_contains "no python: digest text" "dream: python not found"

# --- the cap (the minimum is 2000 bytes, so this set holds more than that) ---
PROJ3="$PB/projects3"
mkdir -p "$PROJ3/$SLUG"
S3="$PROJ3/$SLUG/cccccccc33.jsonl"
mk "$S3" user    2026-11-07T08:00:00.000Z "plain message oldest-marker $(printf 'p%.0s' $(seq 1 120))"
for n in $(seq 10 40); do
  mk "$S3" user  "2026-11-07T08:$n:00.000Z" "plain message $n $(printf 'p%.0s' $(seq 1 120))"
done
mk "$S3" user    2026-11-07T07:00:00.000Z "no, that is wrong"
mk "$S3" err     2026-11-07T07:01:00.000Z "Permission for this action was denied by the user"
mk "$S3" err     2026-11-07T07:02:00.000Z "PreToolUse hook error: BLOCKED by guard"
mk "$S3" err     2026-11-07T07:03:00.000Z "Exit code 2 build failed"
ST3="$FIX/state3"
dg --projects-dir "$PROJ3" --state-dir "$ST3" --max-bytes 1000000
TOTAL="$(grep -c '^- s[0-9]' "$ST3/digest.md")"
dg --projects-dir "$PROJ3" --state-dir "$ST3" --max-bytes 2000
assert_rc "capped digest exits 0" 0
KEPT="$(grep -c '^- s[0-9]' "$ST3/digest.md")"
if (( KEPT < TOTAL )); then t_ok "cap drops signals ($KEPT of $TOTAL kept)"; else t_bad "cap drops signals ($KEPT of $TOTAL kept)"; fi
assert_file_has "cap keeps the correction" "$ST3/digest.md" "[C] "
assert_file_has "cap keeps the denial" "$ST3/digest.md" "[D] "
assert_file_has "cap keeps the hook block" "$ST3/digest.md" "[H] "
assert_file_has "cap keeps the failed call before plain messages" "$ST3/digest.md" "[E] "
assert_file_has "cap keeps the newest plain messages" "$ST3/digest.md" "plain message 40 "
assert_file_lacks "cap drops the oldest plain messages" "$ST3/digest.md" "oldest-marker"
assert_file_has "cap reports the dropped count" "$ST3/digest.md" "dropped by the 2000 byte cap"
assert_file_lacks "cap reports a nonzero drop" "$ST3/digest.md" " 0 dropped by"
dg --projects-dir "$PROJ3" --state-dir "$ST3" --max-bytes 1999
assert_rc "max-bytes below 2000 exits 2" 2
assert_contains "max-bytes below 2000 says why" "--max-bytes must be at least 2000"
# Exit 3 only when no signal existed before the cap.
PROJ0="$PB/projects0"
mkdir -p "$PROJ0/$SLUG"
mk "$PROJ0/$SLUG/dddddddd44.jsonl" meta 2026-11-07T07:00:00.000Z "only meta"
dg --projects-dir "$PROJ0" --state-dir "$FIX/state0"
assert_rc "no signal before the cap exits 3" 3
assert_contains "no signal says nothing to dream" "nothing to dream"
mk "$PROJ0/$SLUG/dddddddd44.jsonl" user 2026-11-07T07:05:00.000Z "one signal"
dg --projects-dir "$PROJ0" --state-dir "$FIX/state0" --max-bytes 2000
assert_rc "a signal that fits keeps the digest at exit 0" 0

# --- hygiene ---
mkdir -p "$FIX/docs/lessons" "$FIX/mem"
# The documented format line ("<...>" placeholder) and a fenced example are
# not lessons, exactly as scripts/lessons.sh counts them.
printf '%s\n' '# Index' '- [L001] <one-line description> - <the lesson> (used: 0, last: -, retire-when: <condition>)' \
  '```' '- [L099] fenced example - not counted (used: 0, last: -, retire-when: z)' '```' \
  '- [L001] a - b (used: 0, last: -, retire-when: x)' \
  '- [L002] c - d (used: 3, last: 2026-11-01, retire-when: y)' > "$FIX/docs/lessons/INDEX.md"
printf '%s\n' '# Pending' '### Old entry' 'what happened on 2026-09-28' '### Fresh entry' 'seen 2026-11-05' \
  '### Undated entry' 'nothing' > "$FIX/docs/lessons/PENDING.md"
printf '%s\n' 'see [gone](nothere.md) and [web](https://example.invalid/x) and [anchor](#top)' \
  > "$FIX/docs/lessons/UPSTREAM.md"
printf '%s\n' '---' 'name: alpha' '---' 'links [[alpha]] and [[missing]]' > "$FIX/mem/a.md"
printf '%s\n' '- [A](a.md) and [B](gone.md#x)' > "$FIX/mem/MEMORY.md"
run bash scripts/dream.sh hygiene --memory-dir "$FIX/mem"
assert_rc "hygiene exits 0" 0
assert_contains "hygiene: missing files named" "BACKLOG.md: missing"
assert_contains "hygiene: approved lessons" "approved lessons: 2 (1 with used: 0)"
assert_contains "hygiene: pending age counted" "oldest 40 days, 1 older than 30 days"
assert_contains "hygiene: undated entry" "Undated entry: undated"
assert_contains "hygiene: auto-memory" "auto-memory: 2 files"
assert_contains "hygiene: MEMORY.md lines" "MEMORY.md 1 lines"
assert_contains "hygiene: dangling wiki link" "a.md: [[missing]]"
assert_not_contains "hygiene: known wiki link ok" "[[alpha]]"
assert_contains "hygiene: broken lessons link" "docs/lessons/UPSTREAM.md: nothere.md"
assert_contains "hygiene: broken memory link" "MEMORY.md: gone.md"
assert_not_contains "hygiene: web links ignored" "example.invalid"
assert_not_contains "hygiene: existing link ok" "MEMORY.md: a.md"

run bash scripts/dream.sh status
assert_rc "status exits 0" 0
assert_contains "status shows the last dream" "last dream: 2026-11-07T12:00:00Z"

# --- sibling folders never count for due ---
PROJ4="$PB/projects4"
mkdir -p "$PROJ4/${SLUG}-bar"
mk "$PROJ4/${SLUG}-bar/eeeeeeee55.jsonl" user 2026-11-07T07:00:00.000Z "sibling activity" "${NATIVE}-bar"
run env DREAM_PROJECTS_DIR="$PROJ4" bash scripts/dream.sh due --state-dir "$FIX/state4"
assert_rc "due: a sibling folder named root-bar is not this repository" 1
mkdir -p "$PROJ4/$SLUG"
mk "$PROJ4/$SLUG/ffffffff66.jsonl" user 2026-11-07T07:00:00.000Z "own activity"
run env DREAM_PROJECTS_DIR="$PROJ4" bash scripts/dream.sh due --state-dir "$FIX/state4"
assert_rc "due: the same activity in the root folder is due" 0
PROJ5="$PB/projects5"
mkdir -p "$PROJ5/${SLUG}--claude-worktrees-foo"
mk "$PROJ5/${SLUG}--claude-worktrees-foo/gggggggg77.jsonl" user 2026-11-07T07:00:00.000Z "app worktree activity" "$NATIVE/.claude/worktrees/foo"
run env DREAM_PROJECTS_DIR="$PROJ5" bash scripts/dream.sh due --state-dir "$FIX/state5"
assert_rc "due: an app worktree folder counts" 0

# --- a partial line survives done and is read exactly once ---
PROJ6="$PB/projects6"
ST6="$FIX/state6"
mkdir -p "$PROJ6/$SLUG"
S6="$PROJ6/$SLUG/hhhhhhhh88.jsonl"
mk "$S6" user  2026-11-07T07:00:00.000Z "alpha complete line"
OFF1="$(wc -c < "$S6" | tr -d ' ')"
mk "$S6" userp 2026-11-07T07:01:00.000Z "beta partial line"
dg --projects-dir "$PROJ6" --state-dir "$ST6"
assert_rc "partial: first digest exits 0" 0
assert_file_lacks "partial: not consumed" "$ST6/digest.md" "beta partial line"
run bash scripts/dream.sh done --state-dir "$ST6"
assert_rc "partial: done exits 0" 0
OFFSAVED="$("$PY" -c 'import json,sys;print(list(json.load(open(sys.argv[1]))["files"].values())[0]["offset"])' "$ST6/state.json")"
assert_eq "partial: committed offset sits before the partial line" "$OFF1" "$OFFSAVED"
mk "$S6" nl 2026-11-07T07:01:00.000Z ""
dg --projects-dir "$PROJ6" --state-dir "$ST6"
assert_rc "partial: digest after the line completes exits 0" 0
assert_eq "partial: read exactly once" "1" "$(grep -c 'beta partial line' "$ST6/digest.md")"
assert_file_lacks "partial: earlier line not read again" "$ST6/digest.md" "alpha complete line"

# --- a transcript rewritten shorter is read again from the start ---
PROJ9="$PB/projects9"
ST9="$FIX/state9"
mkdir -p "$PROJ9/$SLUG"
S9="$PROJ9/$SLUG/iiiiiiii99.jsonl"
mk "$S9" user 2026-11-07T07:00:00.000Z "first long text of the original transcript $(printf 'z%.0s' $(seq 1 100))"
mk "$S9" user 2026-11-07T07:01:00.000Z "second long text of the original transcript $(printf 'z%.0s' $(seq 1 100))"
dg --projects-dir "$PROJ9" --state-dir "$ST9"
run bash scripts/dream.sh done --state-dir "$ST9"
: > "$S9"
mk "$S9" user 2026-11-07T07:02:00.000Z "short rewrite"
dg --projects-dir "$PROJ9" --state-dir "$ST9"
assert_rc "truncated: digest exits 0" 0
assert_file_has "truncated: re-read from the start" "$ST9/digest.md" "short rewrite"

# --- worktrees, saved roots, --match, subagents, shared state ---
git add scripts/dream.sh scripts/dream/dream.py >/dev/null 2>&1
git commit -q -m fixture >/dev/null 2>&1
WT="$FIX-wt"
WTN="$(cygpath -w "$WT" 2>/dev/null || echo "$WT")"
git worktree add -q --detach "$WT" >/dev/null 2>&1
PROJ7="$PB/projects7"
ST7="$FIX/state7"
mkdir -p "$PROJ7/wtproj" "$PROJ7/matchproj" "$PROJ7/wtproj/sess/subagents"
M1="$FIX-m1"
M1N="$(cygpath -w "$M1" 2>/dev/null || echo "$M1")"
M2="$FIX-m2"
M2N="$(cygpath -w "$M2" 2>/dev/null || echo "$M2")"
mk "$PROJ7/wtproj/w1.jsonl" user 2026-11-07T07:00:00.000Z "worktree line one" "$WTN"
mk "$PROJ7/matchproj/m1.jsonl" user 2026-11-07T07:01:00.000Z "match line absolute" "$M1N"
mk "$PROJ7/matchproj/m2.jsonl" user 2026-11-07T07:02:00.000Z "match line relative" "$M2N"
mk "$PROJ7/wtproj/sess/subagents/agent-x.jsonl" user 2026-11-07T07:03:00.000Z "subagent must not appear"
run bash -c 'cd "$1" && bash "$2" digest --projects-dir "$3" --state-dir "$4" --match "$5" --match "$6"' _ \
  "$(dirname "$FIX")" "$FIX/scripts/dream.sh" "$PROJ7" "$ST7" "$M1" "$(basename "$FIX")-m2"
assert_rc "worktree: digest exits 0" 0
assert_file_has "worktree: a linked worktree cwd is included" "$ST7/digest.md" "worktree line one"
assert_file_has "match: an absolute --match path is included" "$ST7/digest.md" "match line absolute"
assert_file_has "match: a relative --match path resolves against the current directory" "$ST7/digest.md" "match line relative"
assert_file_lacks "subagent transcripts are not read" "$ST7/digest.md" "subagent must not appear"
run bash scripts/dream.sh done --state-dir "$ST7"
git worktree remove --force "$WT" >/dev/null 2>&1
mk "$PROJ7/wtproj/w1.jsonl" user 2026-11-07T07:10:00.000Z "worktree line after removal" "$WTN"
dg --projects-dir "$PROJ7" --state-dir "$ST7"
assert_rc "worktree: digest after removal exits 0" 0
assert_file_has "worktree: a removed worktree stays known" "$ST7/digest.md" "worktree line after removal"

WT2="$FIX-wt2"
WT2N="$(cygpath -w "$WT2" 2>/dev/null || echo "$WT2")"
git worktree add -q --detach "$WT2" >/dev/null 2>&1
PROJ8="$PB/projects8"
mkdir -p "$PROJ8/wt2proj"
mk "$PROJ8/wt2proj/w2.jsonl" user 2026-11-07T07:00:00.000Z "linked worktree activity" "$WT2N"
run bash "$WT2/scripts/dream.sh" digest --projects-dir "$PROJ8"
assert_rc "shared state: digest from a linked worktree exits 0" 0
assert_file_has "shared state: the digest lands in the main checkout" "$FIX/.work/dream/digest.md" "linked worktree activity"
assert_no_file "shared state: the linked worktree keeps no state" "$WT2/.work/dream"
git worktree remove --force "$WT2" >/dev/null 2>&1

# --- outcome and impact ---
# Lesson ages come from the git date of each INDEX.md line, so the lines are
# committed with pinned dates: L001 and L002 on 2026-09-01, L003 on 2026-11-01.
PROJ10="$PB/projects10"
ST10="$FIX/state10"
mkdir -p "$PROJ10/$SLUG"
S10="$PROJ10/$SLUG/jjjjjjjj10.jsonl"
printf '%s\n' '# Index' \
  '- [L001] Rotating secrets - keep tokens inside the vault (used: 0, last: -, retire-when: vault removed)' \
  '- [L002] Guarding commits - block worker commits with the guard hook (used: 2, last: 2026-11-01, retire-when: harness)' \
  > "$FIX/docs/lessons/INDEX.md"
git add docs/lessons/INDEX.md >/dev/null 2>&1
GIT_AUTHOR_DATE=2026-09-01T00:00:00Z GIT_COMMITTER_DATE=2026-09-01T00:00:00Z git commit -q -m old-lessons >/dev/null 2>&1
printf '%s\n' '- [L003] Fresh lesson - recent and never used (used: 0, last: -, retire-when: never)' >> "$FIX/docs/lessons/INDEX.md"
git add docs/lessons/INDEX.md >/dev/null 2>&1
GIT_AUTHOR_DATE=2026-11-01T00:00:00Z GIT_COMMITTER_DATE=2026-11-01T00:00:00Z git commit -q -m new-lesson >/dev/null 2>&1
mk "$S10" user 2026-11-07T08:00:00.000Z "rotating secrets inside the vault tokens is a plain message"
mk "$S10" user 2026-11-07T08:01:00.000Z "no, wrong file"
mk "$S10" err  2026-11-07T08:02:00.000Z "PreToolUse hook error: BLOCKED worker commits by the guard"
dg --projects-dir "$PROJ10" --state-dir "$ST10"
assert_rc "impact: first digest exits 0" 0
D10="$ST10/digest.md"
assert_file_has "impact: the digest has an impact section" "$D10" "## Impact since the last dream"
assert_file_has "impact: trend counts this dream by kind" "$D10" "  this dream: C 1, H 1, U 1"
assert_file_has "impact: the first dream has no earlier trend" "$D10" "  no earlier dream"
assert_file_has "impact: an old unused lesson is a retire candidate" "$D10" "L001 unused for 67 days"
assert_file_lacks "impact: a recent unused lesson is not" "$D10" "L003 unused"
assert_file_lacks "impact: a used lesson is not" "$D10" "L002 unused"
assert_file_has "impact: a lesson whose words recur in a failure is a mechanize candidate" "$D10" "L002 shares words with s3 (commits guard worker)"
assert_file_lacks "impact: plain messages are not mechanize evidence" "$D10" "L001 shares words"

R10="$ST10/2026-11-07-report.md"
printf '%s\n' '# Dream report 2026-11-07' 'Read: 3 signals; INDEX.md' '## Proposals' \
  '1. [new lesson] Record the wrong-file trap' '   Why: s2' '   Evidence: s2' \
  '   Change: add an entry to docs/lessons/PENDING.md under the last entry' \
  '2. [stale] Fix a backlog row' '   Why: s3' '   Evidence: s3' '   Change: edit the row in BACKLOG.md' \
  '## Considered and dropped' '- 9. s1: a plain message' > "$R10"
run bash scripts/dream.sh done --state-dir "$ST10" --report "$R10" --applied 7
assert_rc "outcome: an approved number missing from the report exits 2" 2
assert_contains "outcome: the missing number is named" "proposal 7 is not in"
assert_file "outcome: a refused done keeps the digest state" "$ST10/state.next.json"
run bash scripts/dream.sh done --state-dir "$ST10" --applied 1
assert_rc "outcome: --applied without --report exits 2" 2
run bash scripts/dream.sh done --state-dir "$ST10" --report "$R10" --applied 1 1
assert_rc "outcome: a repeated approved number exits 2" 2
assert_contains "outcome: the repeated number is named" "proposal 1 is approved twice"
RD10="$ST10/dup-report.md"
printf '%s\n' '# Dream report 2026-11-07' '## Proposals' '1. [stale] one' '   Change: edit BACKLOG.md' \
  '1. [stale] two' '   Change: edit README.md' > "$RD10"
run bash scripts/dream.sh done --state-dir "$ST10" --report "$RD10" --applied 1
assert_rc "outcome: a report that numbers two proposals alike exits 2" 2
assert_contains "outcome: the report's repeated number is named" "numbers proposal 1 twice"
assert_file "outcome: a refused done still keeps the digest state" "$ST10/state.next.json"
printf '%s\n' '### New trap' 'seen 2026-11-07' >> "$FIX/docs/lessons/PENDING.md"
run bash scripts/dream.sh done --state-dir "$ST10" --report "$R10" --applied 1
assert_rc "outcome: done with a report exits 0" 0
assert_contains "outcome: done says where the outcome went" "dream: outcome appended to"
assert_file_has "outcome: heading" "$R10" "## Outcome 2026-11-07"
assert_file_has "outcome: applied numbers" "$R10" "Applied: 1"
assert_file_has "outcome: declined numbers" "$R10" "Declined: 2"
assert_file_has "outcome: files named in the applied Change lines" "$R10" "Files: docs/lessons/PENDING.md"
assert_file_lacks "outcome: a declined change's file is not listed" "$R10" "Files: docs/lessons/PENDING.md, BACKLOG.md"
assert_file_has "outcome: hygiene before and after" "$R10" "  pending lessons: 3 (oldest 40 days, 1 older than 30 days) -> 4 (oldest 40 days, 1 older than 30 days)"
assert_file_has "outcome: unchanged numbers are named once" "$R10" "Unchanged: AGENTS.md"

dg --projects-dir "$PROJ10" --state-dir "$ST10"
assert_rc "impact: nothing new exits 3" 3
DREAM_NOW="2026-11-09T12:00:00Z" mk "$S10" user 2026-11-09T08:00:00.000Z "a later plain message"
DREAM_NOW="2026-11-09T12:00:00Z" dg --projects-dir "$PROJ10" --state-dir "$ST10"
assert_rc "impact: second digest exits 0" 0
assert_file_has "impact: the trend keeps the earlier dream through a stop" "$D10" "  2026-11-07: C 1, H 1, U 1"
assert_file_has "impact: and counts this one" "$D10" "  this dream: U 1"
DREAM_NOW="2026-11-09T12:00:00Z" run bash scripts/dream.sh done --state-dir "$ST10"
assert_rc "impact: done without a report still works" 0

# --- scorecard ---
# Owner decisions from saved reports, counted by script. "Now" values come from
# the fixture's INDEX.md (L001 used 0, L002 used 2 last 2026-11-01) and a
# BACKLOG.md written here.
run bash scripts/dream.sh scorecard --state-dir "$FIX/nostate"
assert_rc "scorecard: no state folder exits 0" 0
assert_contains "scorecard: no state folder says so" "no saved reports"
assert_no_file "scorecard: no state folder is created" "$FIX/nostate"

printf '%s\n' '# Backlog' '| item | priority | why | status |' '|---|---|---|---|' \
  '| Alpha guard (matcher Bash\|PowerShell) with a test | P2 | recurs | done 2026-11-01 |' \
  '| `Delta` row in backticks | P3 | x | open |' > "$FIX/BACKLOG.md"
SCST11="$FIX/scstate11"
mkdir -p "$SCST11"
printf '%s\n' '# Dream report 2026-10-01' '## Proposals' \
  '1. [Mechanize] Wire the guard' '   Evidence: s1' \
  '   Change: BACKLOG.md rows "Alpha guard (matcher Bash|PowerShell) with a test | P2 | recurs | open" and "Beta missing | P3 | x | open", plus "Delta row in backticks | P3 | x | open"' \
  '2. [pending:approve] Move a lesson' '   Change: docs/lessons/INDEX.md add "[L002] Guarding commits", note L001 and L099; docs/lessons/PENDING.md add "Gamma | not a row"' \
  '3. Untagged idea' '   Change: BACKLOG.md row "Epsilon declined | P3 | x | open"; INDEX.md L077' \
  '## Considered and dropped' '- nothing' \
  '## Outcome 2026-10-01' 'Applied: 1, 2' 'Declined: 3' 'Files: BACKLOG.md' > "$SCST11/2026-10-01-report.md"
printf '%s\n' '# Dream report 2026-10-02' '## Proposals' '1. [stale] a' '2. [stale] b' > "$SCST11/2026-10-02-report.md"
printf '%s\n' '# Dream report 2026-10-03' '## Proposals' '1. [stale] only' \
  '## Outcome 2026-10-03' 'Applied: 1' 'Declined: none' \
  '## Outcome 2026-10-04' 'Applied: none' 'Declined: 1' > "$SCST11/2026-10-03-report.md"
printf '%s\n' '# r' '## Proposals' '1. [stale] one' '1. [stale] two' > "$SCST11/2026-10-04-report.md"
printf '# r\n## Proposals\n1. [stale] bad \xff\xfe bytes\n' > "$SCST11/2026-10-05-report.md"
mkdir -p "$SCST11/2026-10-06-report.md"
printf '%s\n' '# r' '## Proposals' '1. [stale] a' '## Outcome 2026-10-07' 'Applied: 1, x' 'Declined: none' > "$SCST11/2026-10-07-report.md"
printf '%s\n' '# r' '## Proposals' '1. [stale] a' '## Outcome 2026-10-08' 'Applied: 1' > "$SCST11/2026-10-08-report.md"
printf '%s\n' '# r' '## Proposals' '1. [stale] a' '## Outcome 2026-10-09' 'Applied: 5' 'Declined: 1' > "$SCST11/2026-10-09-report.md"
printf '%s\n' '# r' '## Proposals' '1. [stale] a' '2. [stale] b' '## Outcome 2026-10-10' 'Applied: 1, 2' 'Declined: 2' > "$SCST11/2026-10-10-report.md"
printf '%s\n' '# r' '## Proposals' '1. [stale] ignored' '## Outcome x' 'Applied: 1' 'Declined: none' > "$SCST11/notes-report.md"
snap() { (cd "$SCST11" && find . -type f -exec cksum {} + | sort); }
SNAP_BEFORE="$(snap)"
run bash scripts/dream.sh scorecard --state-dir "$SCST11"
assert_rc "scorecard: command exits 0 with skipped reports" 0
SC="$OUT"
assert_eq "scorecard: the command changes no file in the state folder" "$SNAP_BEFORE" "$(snap)"
assert_contains "scorecard: heading" "## Scorecard"
assert_contains "scorecard: says what it counts" "the owner's recorded decisions on past dream proposals, counted by script"
assert_contains "scorecard: names the checkout and branch read" "now values read from $NATIVE (branch "
assert_contains "scorecard: a report with an Outcome" "  2026-10-01: proposals 3, approved 2, declined 1"
assert_contains "scorecard: a report without an Outcome" "  2026-10-02: proposals 2, no Outcome recorded"
assert_contains "scorecard: the last Outcome counts" "  2026-10-03: proposals 1, approved 0, declined 1"
assert_contains "scorecard: a repeated number is skipped" "skipped 2026-10-04-report.md: numbers proposal 1 twice"
assert_contains "scorecard: invalid UTF-8 is skipped" "skipped 2026-10-05-report.md: cannot read it"
assert_contains "scorecard: an unreadable report is skipped" "skipped 2026-10-06-report.md: cannot read it"
assert_contains "scorecard: a non-numeric Outcome is skipped" "skipped 2026-10-07-report.md: Outcome Applied is not a number list"
assert_contains "scorecard: an Outcome without Declined is skipped" "skipped 2026-10-08-report.md: Outcome lacks a Declined line"
assert_contains "scorecard: an Outcome number missing from Proposals is skipped" "skipped 2026-10-09-report.md: Outcome names 5, which its Proposals lack"
assert_contains "scorecard: a number in both lists is skipped" "skipped 2026-10-10-report.md: Outcome puts 2 in both Applied and Declined"
case "$SC" in *notes-report*) t_bad "scorecard: a file not named YYYY-MM-DD-report.md is ignored" "$SC" ;; *) t_ok "scorecard: a file not named YYYY-MM-DD-report.md is ignored" ;; esac
assert_contains "scorecard: kind tag lowercased" "  mechanize: approved 1, declined 0, rate 100%"
assert_contains "scorecard: kind spacing normalised" "  pending: approve: approved 1, declined 0, rate 100%"
assert_contains "scorecard: kinds count every report with an Outcome" "  stale: approved 0, declined 1, rate 0%"
assert_contains "scorecard: a proposal without a tag is untagged" "  untagged: approved 0, declined 1, rate 0%"
assert_contains "scorecard: decided total against the thresholds" "decided: 4 (self-review pass at 30, replay check at 50)"
assert_contains "scorecard: candidates have no source without a digest" "candidates: N/A - no digest signals"
assert_contains "scorecard: a bracketed lesson id shows its INDEX values" "  L002: used 2, last 2026-11-01"
assert_contains "scorecard: a bare lesson id is read too" "  L001: used 0, last -"
assert_contains "scorecard: a lesson missing from INDEX.md" "  L099: not in INDEX.md"
case "$SC" in *L077*) t_bad "scorecard: a declined proposal's lesson is not listed" "$SC" ;; *) t_ok "scorecard: a declined proposal's lesson is not listed" ;; esac
assert_contains "scorecard: an escaped pipe still matches its row" "  Alpha guard (matcher Bash|PowerShell) with a test: done 2026-11-01"
assert_contains "scorecard: every quoted row in a Change line counts" "  Beta missing: not found"
assert_contains "scorecard: backticks do not stop a match" "  Delta row in backticks: open"
case "$SC" in *Gamma*) t_bad "scorecard: a quote outside a BACKLOG.md change is not a row" "$SC" ;; *) t_ok "scorecard: a quote outside a BACKLOG.md change is not a row" ;; esac
case "$SC" in *Epsilon*) t_bad "scorecard: a declined proposal's row is not listed" "$SC" ;; *) t_ok "scorecard: a declined proposal's row is not listed" ;; esac

NOGIT="$(mktemp -d "${TMPDIR:-/tmp}/template-selftest.nogit.XXXXXX")"
run bash scripts/dream.sh scorecard --state-dir "$SCST11" --root "$NOGIT"
assert_contains "scorecard: outside git the branch is N/A" "(branch N/A - not a git checkout)"
rm -rf "$NOGIT"
git -C "$FIX" checkout -q --detach
run bash scripts/dream.sh scorecard --state-dir "$SCST11"
assert_contains "scorecard: a detached HEAD is named" "(branch detached)"
git -C "$FIX" checkout -q -

# In a digest the section sits between Impact and Signals and counts candidates
# with the Impact section's word matcher.
SCPROJ11="$PB/scprojects11"
mkdir -p "$SCPROJ11/$SLUG"
mk "$SCPROJ11/$SLUG/kkkkkkkk11.jsonl" err 2026-11-07T09:00:00.000Z "PreToolUse hook error: BLOCKED worker commits by the guard"
dg --projects-dir "$SCPROJ11" --state-dir "$SCST11"
assert_rc "scorecard: a digest with skipped reports still completes" 0
SCD11="$SCST11/digest.md"
assert_file_has "scorecard: the digest carries the section" "$SCD11" "## Scorecard"
ORDER="$(grep -n '^## \(Impact since the last dream\|Scorecard\|Signals\)$' "$SCD11" | cut -d: -f2 | tr '\n' ',')"
assert_eq "scorecard: section order Impact, Scorecard, Signals" "## Impact since the last dream,## Scorecard,## Signals," "$ORDER"
assert_file_has "scorecard: candidates in a digest come from its signals" "$SCD11" "  L002: used 2, last 2026-11-01; candidates 1"
assert_file_has "scorecard: and the Impact section agrees" "$SCD11" "L002 shares words with s1"

# Size: 15 reports of 12 approved proposals, two lessons and two long rows each.
SCST12="$FIX/scstate12"
mkdir -p "$SCST12"
LONG="$(printf 'x%.0s' $(seq 1 90))"
for d in $(seq 1 15); do
  f="$SCST12/2026-09-$(printf '%02d' "$d")-report.md"
  { echo "# r"; echo "## Proposals"
    for p in $(seq 1 12); do
      echo "$p. [mechanize] p$p"
      echo "   Change: BACKLOG.md rows \"row-$d-$p-a $LONG | P2 | why $LONG | open $LONG\" and \"row-$d-$p-b $LONG | P2 | why | open\"; INDEX.md L$((d * 100 + p * 2)) and L$((d * 100 + p * 2 + 1))"
    done
    echo "## Outcome 2026-09-$(printf '%02d' "$d")"; echo "Applied: $(seq -s ', ' 1 12)"; echo "Declined: none"
  } > "$f"
done
run bash scripts/dream.sh scorecard --state-dir "$SCST12"
assert_rc "scorecard: the size fixture exits 0" 0
BYTES="$(printf '%s' "$OUT" | wc -c | tr -d ' ')"
if (( BYTES < 6000 )); then t_ok "scorecard: 15 heavy reports stay under 6000 bytes ($BYTES)"; else t_bad "scorecard: 15 heavy reports stay under 6000 bytes" "$BYTES bytes"; fi
assert_contains "scorecard: older reports fold into one row" "  older (5 reports): proposals 60, approved 60, declined 0, no Outcome 0"
assert_contains "scorecard: the newest report's lessons come first" "  L1502: not in INDEX.md"
assert_contains "scorecard: lessons beyond 20 are counted" "  ... 220 more not shown"
assert_contains "scorecard: rows beyond 20 are counted" "  ... 220 more not shown"
case "$OUT" in *row-15-1-a*) t_ok "scorecard: the newest report's rows come first" ;; *) t_bad "scorecard: the newest report's rows come first" "$OUT" ;; esac
case "$OUT" in *"$LONG$LONG"*) t_bad "scorecard: cells are cut to 80 characters" "$OUT" ;; *) t_ok "scorecard: cells are cut to 80 characters" ;; esac

# A skipped report's reason is cut to 160 characters, ending in "...".
SCST15="$FIX/scstate15"
mkdir -p "$SCST15"
HUGE="$(printf '9%.0s' $(seq 1 300))"
printf '%s\n' '# r' '## Proposals' '1. [stale] a' '## Outcome 2026-10-01' "Applied: $HUGE" 'Declined: none' > "$SCST15/2026-10-01-report.md"
run bash scripts/dream.sh scorecard --state-dir "$SCST15"
assert_rc "scorecard: a long skip reason exits 0" 0
SKIPLINE="$(printf '%s\n' "$OUT" | grep '^skipped 2026-10-01-report.md')"
assert_eq "scorecard: a skipped line is cut to 160 characters" "160" "${#SKIPLINE}"
case "$SKIPLINE" in *...) t_ok "scorecard: a cut skipped line ends in an ellipsis" ;; *) t_bad "scorecard: a cut skipped line ends in an ellipsis" "$SKIPLINE" ;; esac

# A Change line wrapped onto the next lines still counts whole: the row named on the
# wrapped line is found.
SCST16="$FIX/scstate16"
mkdir -p "$SCST16"
printf '%s\n' '# r' '## Proposals' '1. [stale] wrapped' '   Why: x' '   Change: edit these BACKLOG.md rows' \
  '   "Delta row in backticks | P3 | x | open" after the first one' \
  '## Outcome 2026-10-01' 'Applied: 1' 'Declined: none' > "$SCST16/2026-10-01-report.md"
run bash scripts/dream.sh scorecard --state-dir "$SCST16"
assert_rc "scorecard: a wrapped Change line exits 0" 0
assert_contains "scorecard: a row named on a wrapped Change line is found" "  Delta row in backticks: open"

# A wrapped Change continues only while indented lines follow it directly: a Why or
# Evidence line, or a blank line, ends it.
SCST17="$FIX/scstate17"
mkdir -p "$SCST17"
printf '%s\n' '# r' '## Proposals' '1. [stale] why after change' '   Change: edit BACKLOG.md' '   Why: "Zeta row | P3 | x | open"'   '2. [stale] blank after change' '   Change: edit BACKLOG.md' '' '   "Eta row | P3 | x | open"'   '## Outcome 2026-10-01' 'Applied: 1, 2' 'Declined: none' > "$SCST17/2026-10-01-report.md"
run bash scripts/dream.sh scorecard --state-dir "$SCST17"
assert_rc "scorecard: lines that end a Change exit 0" 0
assert_not_contains "scorecard: a Why line is not part of the Change" "Zeta row"
assert_not_contains "scorecard: a line after a blank is not part of the Change" "Eta row"

# Each lesson id and row prints once: repeated in one Change line, across
# reports, and a row cell differing only in case or backticks.
SCST13="$FIX/scstate13"
mkdir -p "$SCST13"
printf '%s\n' '# r' '## Proposals' '1. [counter] twice in one line' \
  '   Change: INDEX.md add [L404] and set L404 last; BACKLOG.md row "Zeta repeated row | P2 | x | open"' \
  '## Outcome 2026-08-01' 'Applied: 1' 'Declined: none' > "$SCST13/2026-08-01-report.md"
printf '%s\n' '# r' '## Proposals' '1. [counter] again in a later report' \
  '   Change: INDEX.md L404; BACKLOG.md row "`zeta REPEATED row` | P2 | y | open"' \
  '## Outcome 2026-08-02' 'Applied: 1' 'Declined: none' > "$SCST13/2026-08-02-report.md"
run bash scripts/dream.sh scorecard --state-dir "$SCST13"
assert_eq "scorecard: a lesson repeated across reports prints once" 1 "$(printf '%s\n' "$OUT" | grep -c '^  L404: ')"
assert_eq "scorecard: a row repeated across reports, by case or backticks, prints once" 1 "$(printf '%s\n' "$OUT" | grep -ci '^  `\{0,1\}zeta repeated row')"
# The repeat inside one Change line alone (an earlier report would hide it).
SCST13B="$FIX/scstate13b"
mkdir -p "$SCST13B"
cp "$SCST13/2026-08-01-report.md" "$SCST13B/"
run bash scripts/dream.sh scorecard --state-dir "$SCST13B"
assert_eq "scorecard: a lesson repeated in one Change line prints once" 1 "$(printf '%s\n' "$OUT" | grep -c '^  L404: ')"

# A long used or last value in INDEX.md is cut, so a lesson line stays short.
LR="$(mktemp -d "${TMPDIR:-/tmp}/template-selftest.longlast.XXXXXX")"
mkdir -p "$LR/docs/lessons"
printf '%s\n' "- [L404] Long values - x (used: $(printf '9%.0s' $(seq 1 60)), last: $(printf 'z%.0s' $(seq 1 200)), retire-when: y)" \
  > "$LR/docs/lessons/INDEX.md"
run bash scripts/dream.sh scorecard --state-dir "$SCST13" --root "$LR"
LINE="$(printf '%s\n' "$OUT" | grep '^  L404: ')"
assert_contains "scorecard: the long lesson is listed" "  L404: used "
if (( ${#LINE} <= 100 )); then t_ok "scorecard: long used and last values are cut (${#LINE} characters)"; else t_bad "scorecard: long used and last values are cut" "$LINE"; fi
rm -rf "$LR"

# Kind rows and skipped lines are capped too: 30 kinds and 30 bad reports.
SCST14="$FIX/scstate14"
mkdir -p "$SCST14"
for k in $(seq 1 30); do
  printf '%s\n' '# r' '## Proposals' "1. [kind-$k] one" '## Outcome 2026-07-01' 'Applied: 1' 'Declined: none' \
    > "$SCST14/2026-07-$(printf '%02d' "$k")-report.md"
  printf '%s\n' '# r' '## Proposals' '1. [x] a' '1. [x] b' > "$SCST14/2026-06-$(printf '%02d' "$k")-report.md"
done
run bash scripts/dream.sh scorecard --state-dir "$SCST14"
assert_eq "scorecard: at most 20 kind rows" 20 "$(printf '%s\n' "$OUT" | grep -c '^  kind-[0-9]*: approved')"
assert_eq "scorecard: at most 20 skipped lines" 20 "$(printf '%s\n' "$OUT" | grep -c '^skipped ')"
assert_contains "scorecard: the remaining kinds are counted" "  ... 10 more kinds not shown"
assert_contains "scorecard: the remaining skipped reports are counted" "... 10 more skipped reports not shown"

# A repository with no commits yet still names its branch.
UNBORN="$(mktemp -d "${TMPDIR:-/tmp}/template-selftest.unborn.XXXXXX")"
git -C "$UNBORN" init -q -b fresh >/dev/null 2>&1 || git -C "$UNBORN" init -q >/dev/null 2>&1
UB="$(git -C "$UNBORN" symbolic-ref --short HEAD 2>/dev/null)"
run bash scripts/dream.sh scorecard --state-dir "$SCST11" --root "$UNBORN"
assert_contains "scorecard: an unborn branch is named" "(branch $UB)"
rm -rf "$UNBORN"

# --- feedback log and repeats (A9) ---
# The log is <main checkout>/.work/feedback/log.jsonl; the digest reads it from a saved
# offset into state.next.json and done commits that offset, as for transcripts.
touch "$FIX/.start-done"
mkdir -p "$FIX/docs/preferences"
printf '%s\n' '# UI' '| ID | Rule | Source | Check |' '|---|---|---|---|' \
  '| U1 | Keep titles short and avoid decorative gradients | 2026-11 "owner words" | Review |' \
  '| U2 | Never commit rendered footage | 2026-11-02 "owner words" | Review |' \
  '```' '| ID | Rule | Source | Check |' '|---|---|---|---|' \
  '| X9 | fenced example about gradients decorative | 2026-11 | Review |' '```' > "$FIX/docs/preferences/ui.md"
cat > "$FIX/mkfb.py" <<'PYEOF'
import json, os, sys
f, kind, ts, text = sys.argv[1:5]
rest = sys.argv[5:9]
sess, branch, task, files = rest + ["sessXXXX", "main", "-", ""][len(rest):]
os.makedirs(os.path.dirname(f), exist_ok=True)
eol = "" if os.environ.get("NOEOL") else "\n"
with open(f, "a", encoding="utf-8", newline="\n") as fh:
    if kind == "raw":
        fh.write(text + eol)
    elif kind == "nl":
        fh.write("\n")
    elif kind == "pad":
        n = 0
        while n < int(text):
            s = json.dumps({"v": 1, "ts": ts, "session": "pad", "branch": "b", "task": "-", "kind": "message",
                            "text": "p" * 900, "files": [], "said": ""}) + "\n"
            fh.write(s)
            n += len(s)
    else:
        fh.write(json.dumps({"v": 1, "ts": ts, "session": sess[:8], "branch": branch, "task": task, "kind": kind,
                             "text": text, "files": [x for x in files.split(",") if x], "said": ""}) + eol)
PYEOF
fbl() { "$PY" "$FIX/mkfb.py" "$@"; }
fboff() { "$PY" -c 'import json,sys;print(json.load(open(sys.argv[1])).get("feedback",{}).get("offset"))' "$1"; }
FBLOG="$FIX/.work/feedback/log.jsonl"
PROJE="$FIX/projectse"
mkdir -p "$PROJE"
STF="$FIX/statef"
FD="$STF/digest.md"

# No log: the section says so and a digest with a transcript signal still works.
dg --projects-dir "$PROJ3" --state-dir "$FIX/statef0"
assert_rc "feedback: a missing log is not an error" 0
D0="$FIX/statef0/digest.md"
assert_file_has "feedback: no log is one line" "$D0" "no feedback log yet"
ORDER="$(grep -n '^## \(Impact since the last dream\|Scorecard\|Feedback\|Repeats\|Signals\)$' "$D0" | cut -d: -f2 | tr '\n' ',')"
assert_eq "feedback: sections follow the Scorecard before Signals" "## Impact since the last dream,## Scorecard,## Feedback,## Repeats,## Signals," "$ORDER"
dg --projects-dir "$PROJE" --state-dir "$STF"
assert_rc "feedback: no log and no signal exits 3" 3

fbl "$FBLOG" deferral   2026-11-07T09:00:00Z "not now, later: decorative gradients" sessAAAA task/x t1 ""
fbl "$FBLOG" correction 2026-11-07T09:10:00Z "no the gradients look cheap and decorative" sessAAAA task/x t1 "a.py,b.md"
fbl "$FBLOG" correction 2026-11-07T09:40:00Z "wrong: you did commit rendered footage" sessBBBB task/y t2 "c.md"
fbl "$FBLOG" preference 2026-11-07T10:00:00Z "always keep titles short, never decorative $(printf 'q%.0s' $(seq 1 500))" sessAAAA task/x t1 ""
fbl "$FBLOG" approval   2026-11-07T10:10:00Z "perfect" sessBBBB task/y t2 ""
fbl "$FBLOG" message    2026-11-07T10:20:00Z "run the tests again" sessBBBB task/y t2 ""
fbl "$FBLOG" raw        2026-11-07T10:30:00Z "{not json"
dg --projects-dir "$PROJE" --state-dir "$STF"
assert_rc "feedback: new log lines make the digest exit 0 with no transcript signal" 0
assert_file_has "feedback: heading" "$FD" "## Feedback"
assert_file_has "feedback: line counts" "$FD" "log: 7 new lines read, 1 malformed; 5 shown, 0 dropped by the 12000 byte cap"
assert_file_has "feedback: a deferral line carries the situation" "$FD" "- f1 [deferral] 2026-11-07 sessAAAA task/x task t1: not now, later: decorative gradients; files: -"
assert_file_has "feedback: newest correction first, with its files" "$FD" "- f2 [correction] 2026-11-07 sessBBBB task/y task t2: wrong: you did commit rendered footage; files: c.md"
assert_file_has "feedback: older correction, files joined" "$FD" "- f3 [correction] 2026-11-07 sessAAAA task/x task t1: no the gradients look cheap and decorative; files: a.py, b.md"
assert_file_has "feedback: preference line is clipped at 400" "$FD" "qqqqqqqq...; files: -"
assert_file_lacks "feedback: and not longer" "$FD" "$(printf 'q%.0s' $(seq 1 400))"
assert_file_has "feedback: approval line" "$FD" "- f5 [approval] 2026-11-07 sessBBBB task/y task t2: perfect; files: -"
assert_file_lacks "feedback: a plain message is not listed" "$FD" "run the tests again"
KORD="$(grep -o '^- f[0-9]* \[[a-z]*\]' "$FD" | tr '\n' ',')"
assert_eq "feedback: kind priority, then newest first" "- f1 [deferral],- f2 [correction],- f3 [correction],- f4 [preference],- f5 [approval]," "$KORD"
assert_file_has "feedback: repeats heading says candidates" "$FD" "word-overlap candidates, not proof"
assert_file_has "feedback: a correction repeats a rule" "$FD" "ui:U2 <- f2 (commit footage rendered)"
assert_file_has "feedback: another correction repeats a rule" "$FD" "ui:U1 <- f3 (decorative gradients)"
assert_file_has "feedback: a preference repeats a rule" "$FD" "ui:U1 <- f4 (decorative short titles)"
assert_file_lacks "feedback: a deferral is not matched" "$FD" "<- f1 "
assert_file_lacks "feedback: a fenced example is not a rule" "$FD" "X9 <-"
LOGSIZE="$(wc -c < "$FBLOG" | tr -d ' ')"
assert_eq "feedback: the digest proposes the log size as the offset" "$LOGSIZE" "$(fboff "$STF/state.next.json")"
run bash scripts/dream.sh done --state-dir "$STF"
assert_rc "feedback: done exits 0" 0
assert_eq "feedback: done commits the offset" "$LOGSIZE" "$(fboff "$STF/state.json")"
assert_file "feedback: a small log is not rotated" "$FBLOG"
assert_no_file "feedback: and no rotated copy exists" "$FIX/.work/feedback/log.1.jsonl"
dg --projects-dir "$PROJE" --state-dir "$STF"
assert_rc "feedback: nothing new exits 3" 3

# A line appended between digest and done is read by the next digest.
fbl "$FBLOG" correction 2026-11-08T08:00:00Z "no, the zebra border is wrong" sessCCCC task/z t3 ""
dg --projects-dir "$PROJE" --state-dir "$STF"
assert_rc "feedback: appended line digest exits 0" 0
assert_file_has "feedback: appended line read" "$FD" "the zebra border is wrong"
fbl "$FBLOG" preference 2026-11-08T08:05:00Z "from now on use zebra borders" sessCCCC task/z t3 ""
run bash scripts/dream.sh done --state-dir "$STF"
assert_rc "feedback: done after a late append exits 0" 0
dg --projects-dir "$PROJE" --state-dir "$STF"
assert_rc "feedback: the late line is read by the next digest" 0
assert_file_has "feedback: late line present" "$FD" "from now on use zebra borders"
assert_file_lacks "feedback: and the committed line is not read again" "$FD" "the zebra border is wrong"
run bash scripts/dream.sh done --state-dir "$STF"

# A partial last line waits for the next run.
NOEOL=1 fbl "$FBLOG" correction 2026-11-08T09:00:00Z "no, the partial feedback" sessCCCC task/z t3 ""
dg --projects-dir "$PROJE" --state-dir "$STF"
assert_rc "feedback: a partial line alone exits 3" 3
fbl "$FBLOG" nl 2026-11-08T09:00:00Z ""
dg --projects-dir "$PROJE" --state-dir "$STF"
assert_rc "feedback: the completed line is read" 0
assert_eq "feedback: read exactly once" "1" "$(grep -c 'the partial feedback' "$FD")"
run bash scripts/dream.sh done --state-dir "$STF"

# A malformed line is counted, not fatal.
fbl "$FBLOG" raw 2026-11-08T09:10:00Z "{broken"
fbl "$FBLOG" correction 2026-11-08T09:11:00Z "no, the margin is wrong" sessCCCC task/z t3 ""
dg --projects-dir "$PROJE" --state-dir "$STF"
assert_rc "feedback: a malformed line does not stop the digest" 0
assert_file_has "feedback: malformed counted" "$FD" "log: 2 new lines read, 1 malformed; 1 shown"
run bash scripts/dream.sh done --state-dir "$STF"

# A log shorter than the offset is read again from the start.
: > "$FBLOG"
fbl "$FBLOG" correction 2026-11-08T10:00:00Z "no, short rewrite feedback" sessDDDD task/z t3 ""
dg --projects-dir "$PROJE" --state-dir "$STF"
assert_rc "feedback: a shrunk log exits 0" 0
assert_file_has "feedback: a shrunk log is re-read from 0" "$FD" "short rewrite feedback"
assert_file_has "feedback: from the first line" "$FD" "log: 1 new lines read"
run bash scripts/dream.sh done --state-dir "$STF"

# done rotates a log over 5 MB after committing the offset; the next digest reads the new log from 0.
fbl "$FBLOG" pad 2026-11-08T11:00:00Z 5300000
fbl "$FBLOG" correction 2026-11-08T11:01:00Z "no, the big log feedback" sessEEEE task/z t3 ""
BIGSIZE="$(wc -c < "$FBLOG" | tr -d ' ')"
dg --projects-dir "$PROJE" --state-dir "$STF"
assert_rc "feedback: a big log digest exits 0" 0
assert_file_has "feedback: the big log's correction is shown" "$FD" "the big log feedback"
run bash scripts/dream.sh done --state-dir "$STF"
assert_rc "feedback: done with a big log exits 0" 0
assert_file "feedback: a log over 5 MB is rotated to log.1.jsonl" "$FIX/.work/feedback/log.1.jsonl"
assert_eq "feedback: the rotated copy is the whole old log" "$BIGSIZE" "$(wc -c < "$FIX/.work/feedback/log.1.jsonl" | tr -d ' ')"
assert_no_file "feedback: the active log starts empty" "$FBLOG"
assert_eq "feedback: the offset resets to 0" "0" "$(fboff "$STF/state.json")"
fbl "$FBLOG" correction 2026-11-08T12:00:00Z "no, the fresh log feedback" sessEEEE task/z t3 ""
dg --projects-dir "$PROJE" --state-dir "$STF"
assert_rc "feedback: the new log is read" 0
assert_file_has "feedback: the new log is read from 0" "$FD" "log: 1 new lines read, 0 malformed; 1 shown"
assert_file_has "feedback: new line shown" "$FD" "the fresh log feedback"
run bash scripts/dream.sh done --state-dir "$STF"

# Plain messages alone are not a reason to dream; a big message-only log is still rotated.
fbl "$FBLOG" pad 2026-11-08T13:00:00Z 5300000
dg --projects-dir "$PROJE" --state-dir "$STF"
assert_rc "feedback: only plain messages exits 3" 3
assert_file "feedback: a big message-only log is rotated at exit 3" "$FIX/.work/feedback/log.1.jsonl"
assert_eq "feedback: and its offset resets" "0" "$(fboff "$STF/state.json")"

# A line logged between the digest and done (the owner approving proposals)
# survives the rotation: the next digest reads it from log.1.jsonl first.
ROTROOT="$(mktemp -d "${TMPDIR:-/tmp}/template-selftest.rot.XXXXXX")"
RLOG="$ROTROOT/.work/feedback/log.jsonl"
fbl "$RLOG" pad 2026-11-08T14:00:00Z 5300000
fbl "$RLOG" correction 2026-11-08T14:01:00Z "no, before the dream" sessGGGG task/r t5 ""
dg --root "$ROTROOT" --projects-dir "$PROJE" --state-dir "$ROTROOT/st"
assert_rc "feedback: the rotation fixture digest exits 0" 0
fbl "$RLOG" correction 2026-11-08T14:05:00Z "no, typed during the dream" sessGGGG task/r t5 ""
run bash scripts/dream.sh done --root "$ROTROOT" --state-dir "$ROTROOT/st"
assert_rc "feedback: done on the rotation fixture exits 0" 0
assert_file "feedback: the fixture log was rotated" "$ROTROOT/.work/feedback/log.1.jsonl"
fbl "$RLOG" correction 2026-11-08T15:00:00Z "no, after the dream" sessGGGG task/r t5 ""
dg --root "$ROTROOT" --projects-dir "$PROJE" --state-dir "$ROTROOT/st"
assert_rc "feedback: the digest after rotation exits 0" 0
assert_file_has "feedback: a line typed during the dream survives the rotation" "$ROTROOT/st/digest.md" "typed during the dream"
assert_file_has "feedback: the new log is read too" "$ROTROOT/st/digest.md" "after the dream"
assert_file_lacks "feedback: a line read before the rotation is not read again" "$ROTROOT/st/digest.md" "before the dream"
case "$ROTROOT" in */template-selftest.rot.*) rm -rf "$ROTROOT" ;; esac

# Caps: 12000 bytes of feedback lines, 40 repeat lines, each with its dropped count.
CAPROOT="$(mktemp -d "${TMPDIR:-/tmp}/template-selftest.cap.XXXXXX")"
for n in $(seq 10 69); do
  fbl "$CAPROOT/.work/feedback/log.jsonl" correction "2026-11-08T10:$(printf '%02d' $((n - 10))):00Z" "no cap-test entry $n $(printf 'p%.0s' $(seq 1 380))" sessFFFF task/c t4 ""
done
dg --root "$CAPROOT" --projects-dir "$PROJE" --state-dir "$CAPROOT/st"
assert_rc "feedback: the cap fixture exits 0" 0
DC="$CAPROOT/st/digest.md"
CAPBYTES="$(grep '^- f[0-9]' "$DC" | wc -c | tr -d ' ')"
if (( CAPBYTES <= 12000 && CAPBYTES > 6000 )); then t_ok "feedback: lines stay within 12000 bytes ($CAPBYTES)"; else t_bad "feedback: lines stay within 12000 bytes ($CAPBYTES)"; fi
assert_file_has "feedback: the cap reports its dropped count" "$DC" "dropped by the 12000 byte cap"
assert_file_lacks "feedback: and the count is not zero" "$DC" " 0 dropped by the 12000"
assert_file_has "feedback: the newest entry is kept" "$DC" "no cap-test entry 69"
assert_file_lacks "feedback: the oldest entry is dropped" "$DC" "no cap-test entry 10 "
assert_file_has "feedback: no register means no repeats" "$DC" "no register rules"
REPROOT="$(mktemp -d "${TMPDIR:-/tmp}/template-selftest.rep.XXXXXX")"
mkdir -p "$REPROOT/docs/preferences"
{ printf '%s\n' '| ID | Rule | Source | Check |' '|---|---|---|---|'
  for n in $(seq 10 54); do echo "| R$n | Rule $n about decorative gradients | 2026-11 | Review |"; done
} > "$REPROOT/docs/preferences/big.md"
fbl "$REPROOT/.work/feedback/log.jsonl" correction 2026-11-08T10:00:00Z "no decorative gradients please" sessFFFF task/c t4 ""
dg --root "$REPROOT" --projects-dir "$PROJE" --state-dir "$REPROOT/st"
assert_rc "feedback: the repeats fixture exits 0" 0
DR="$REPROOT/st/digest.md"
assert_eq "feedback: repeats are capped at 40 lines" "40" "$(grep -c '^big:R[0-9]* <- f1 ' "$DR")"
assert_file_has "feedback: the repeats cap reports the rest" "$DR" "5 more not shown"
rm -rf "$CAPROOT" "$REPROOT"

# --- dreamer definitions (A10) ---
for f in .claude/agents/dreamer.md .codex/agents/dreamer.toml; do
  for w in "docs/preferences" "[preference]" "[escalate]" "[baseline]"; do
    assert_file_has "dreamer: $f names $w" "$T_ROOT/$f" "$w"
  done
done

# --- outcome files are checked against what changed; memory from a worktree ---
# Files lists a named file only when git (against the digest's commit) or the
# auto-memory folder shows it changed; the memory folder is the main checkout's.
# BACKLOG.md is tracked and its change is committed before done (the usual
# path: edits land on a branch); UPSTREAM.md stays untracked (a change shows
# by stat); untracked fixture files stay untouched and must not be claimed.
# The projects folder sits outside the fixture repository, as ~/.claude does,
# so memory notes are decided by the memory stat alone, never by git.
git add -u >/dev/null 2>&1
git add BACKLOG.md >/dev/null 2>&1
git commit -q -m before-dream11 >/dev/null 2>&1
PROJ11="$PB/p11"
ST11="$FIX/state11"
MEM11="$PROJ11/$SLUG/memory"
mkdir -p "$MEM11"
printf '%s\n' '---' 'name: note-a' '---' 'waiting on a merge' > "$MEM11/note-a.md"
printf '%s\n' '---' 'name: note-b' '---' 'still true' > "$MEM11/note-b.md"
mk "$PROJ11/$SLUG/kkkkkkkk11.jsonl" user 2026-11-09T08:00:00.000Z "the outcome named files nobody touched"
DREAM_NOW="2026-11-09T12:00:00Z" dg --projects-dir "$PROJ11" --state-dir "$ST11"
assert_rc "files: digest exits 0" 0
printf '%s\n' '| A new row | P3 | test | open |' >> "$FIX/BACKLOG.md"
printf '%s\n' '' '### New upstream entry' >> "$FIX/docs/lessons/UPSTREAM.md"
printf '%s\n' 'merged now' >> "$MEM11/note-a.md"
git add BACKLOG.md >/dev/null 2>&1
git commit -q -m dream-row >/dev/null 2>&1
R11="$ST11/2026-11-09-report.md"
printf '%s\n' '# Dream report 2026-11-09' '## Proposals' \
  '1. [mechanize] Two rows' \
  '   Change: BACKLOG.md row "Wire the hook into .claude/settings.json | P2 | open"; add the entry to UPSTREAM.md; separately the owner decides whether AGENTS.md records an override' \
  '2. [stale] Memory notes' '   Change: in note-a.md replace the waiting line, and note-b.md likewise' \
  '3. [mechanize] Declined' '   Change: edit README.md' > "$R11"
DREAM_NOW="2026-11-09T12:00:00Z" run bash scripts/dream.sh done --projects-dir "$PROJ11" --state-dir "$ST11" --report "$R11" --applied 1 2
assert_rc "files: done exits 0" 0
if grep -qx -- "Files: BACKLOG.md, UPSTREAM.md, note-a.md" "$R11"; then
  t_ok "files: only the named files that changed, a bare name matched by its last components"
else
  t_bad "files: expected exactly 'Files: BACKLOG.md, UPSTREAM.md, note-a.md'"; grep -- "^Files" "$R11" | sed 's/^/       | /'
fi
grep -- "^Files" "$R11" > "$ST11/files-line"
assert_file_lacks "files: a name quoted inside row text is not claimed" "$ST11/files-line" "settings.json"
assert_file_lacks "files: an owner decision is not claimed" "$ST11/files-line" "AGENTS.md"
assert_file_lacks "files: an untouched memory note is not claimed" "$ST11/files-line" "note-b.md"

ST12="$FIX/state12"
mk "$PROJ11/$SLUG/kkkkkkkk11.jsonl" user 2026-11-10T08:00:00.000Z "an older digest state"
DREAM_NOW="2026-11-10T12:00:00Z" dg --projects-dir "$PROJ11" --state-dir "$ST12"
assert_rc "files: second digest exits 0" 0
"$PY" -c 'import json,sys;p=sys.argv[1];s=json.load(open(p));s.pop("head",None);s.pop("memory",None);json.dump(s,open(p,"w"))' "$ST12/state.next.json"
R12="$ST12/2026-11-10-report.md"
printf '%s\n' '# Dream report 2026-11-10' '## Proposals' '1. [stale] One' '   Change: edit BACKLOG.md' > "$R12"
DREAM_NOW="2026-11-10T12:00:00Z" run bash scripts/dream.sh done --projects-dir "$PROJ11" --state-dir "$ST12" --report "$R12" --applied 1
assert_rc "files: done on an older digest state exits 0" 0
assert_file_has "files: an older digest state says the files were not checked" "$R12" "Files: BACKLOG.md (named in the Change lines; not checked: the digest recorded no commit)"

git add -u >/dev/null 2>&1
git commit -q -m dream11 >/dev/null 2>&1
WT3="$FIX-wt3"
git worktree add -q --detach "$WT3" >/dev/null 2>&1
run bash "$WT3/scripts/dream.sh" hygiene --projects-dir "$PROJ11"
assert_rc "worktree memory: hygiene exits 0" 0
assert_contains "worktree memory: a linked worktree reads the main checkout's memory folder" "auto-memory: 2 files"
git worktree remove --force "$WT3" >/dev/null 2>&1

# done in a checkout whose history lacks the digest's commit cannot compare.
ST13="$FIX/state13"
mk "$PROJ11/$SLUG/kkkkkkkk11.jsonl" user 2026-11-11T08:00:00.000Z "a digest on a later commit"
DREAM_NOW="2026-11-11T12:00:00Z" dg --projects-dir "$PROJ11" --state-dir "$ST13"
assert_rc "files: third digest exits 0" 0
WT4="$FIX-wt4"
git worktree add -q --detach "$WT4" HEAD~1 >/dev/null 2>&1
R13="$ST13/2026-11-11-report.md"
printf '%s\n' '# Dream report 2026-11-11' '## Proposals' '1. [stale] One' '   Change: edit BACKLOG.md' > "$R13"
DREAM_NOW="2026-11-11T12:00:00Z" run bash "$WT4/scripts/dream.sh" done --projects-dir "$PROJ11" --state-dir "$ST13" --report "$R13" --applied 1
assert_rc "files: done on another history exits 0" 0
assert_file_has "files: another history says the files were not checked" "$R13" "not checked: the digest's commit is not in this checkout's history"
git worktree remove --force "$WT4" >/dev/null 2>&1

# done when git cannot tell what changed since the digest's commit (here a commit the
# repository does not hold) says so instead of listing guesses.
ST14="$FIX/state14"
mk "$PROJ11/$SLUG/kkkkkkkk11.jsonl" user 2026-11-12T08:00:00.000Z "a digest whose commit git cannot find"
DREAM_NOW="2026-11-12T12:00:00Z" dg --projects-dir "$PROJ11" --state-dir "$ST14"
assert_rc "files: fourth digest exits 0" 0
"$PY" -c 'import json,sys;p=sys.argv[1];s=json.load(open(p));s["head"]="0123456789abcdef0123456789abcdef01234567";json.dump(s,open(p,"w"))' "$ST14/state.next.json"
R14="$ST14/2026-11-12-report.md"
printf '%s\n' '# Dream report 2026-11-12' '## Proposals' '1. [stale] One' '   Change: edit BACKLOG.md' > "$R14"
DREAM_NOW="2026-11-12T12:00:00Z" run bash scripts/dream.sh done --projects-dir "$PROJ11" --state-dir "$ST14" --report "$R14" --applied 1
assert_rc "files: done when git cannot compare exits 0" 0
assert_file_has "files: git cannot compare says the files were not checked" "$R14" "not checked: git cannot compare against 0123456789ab"

# A session started from a Windows 8.3 short path (a RUNNER~1 user folder) records that text as its
# cwd; the roots are resolved to the long form, so the short form must match too.
SHORT=""
if command -v cygpath >/dev/null 2>&1; then
  SHORT="$("$PY" -c 'import ctypes,sys;b=ctypes.create_unicode_buffer(32768);n=ctypes.windll.kernel32.GetShortPathNameW(sys.argv[1],b,32768);print(b.value if 0<n<32768 else "")' "$NATIVE" 2>/dev/null)"
fi
if [[ -n "$SHORT" ]]; then
  SSLUG="$("$PY" -c 'import re,sys;print(re.sub(r"[^A-Za-z0-9]","-",sys.argv[1]))' "$SHORT")"
  PROJSN="$PB/projsn"
  ST15="$FIX/state15"
  mkdir -p "$PROJSN/$SSLUG"
  mk "$PROJSN/$SSLUG/sssssss1.jsonl" user 2026-11-13T08:00:00.000Z "a session recorded from the short path" "$SHORT"
  DREAM_NOW="2026-11-13T12:00:00Z" run bash scripts/dream.sh due --projects-dir "$PROJSN" --state-dir "$ST15"
  assert_contains "short path: the session folder named by the short path is counted" "dream: due (1 sessions"
  DREAM_NOW="2026-11-13T12:00:00Z" dg --projects-dir "$PROJSN" --state-dir "$ST15"
  assert_rc "short path: digest exits 0" 0
  assert_file_has "short path: a cwd in short form is read" "$ST15/digest.md" "a session recorded from the short path"
else
  t_ok "short path: n/a without cygpath and 8.3 names"
fi

# The Windows runner's TEMP is C:\Users\RUNNER~1\AppData\...: a short ancestor and a long rest.
# A session started there records that mixed spelling as its cwd and names its project and
# memory folders after it, so it matches neither the long form nor the all-short form.
# The project here is a clone under two long-named folders, so its spelling with short
# ancestors and a long last part differs from both the long and the all-short form on any
# Windows machine with 8.3 names, not only where the user folder itself is long.
MIXED=""
CL="$PB/longancestorfolder/longdescendantclone"
if command -v cygpath >/dev/null 2>&1 && mkdir -p "${CL%/*}" && git clone -q "$FIX" "$CL" >/dev/null 2>&1; then
  CLN="$(cygpath -w "$CL")"
  MIXED="$("$PY" -c 'import ctypes,sys
b=ctypes.create_unicode_buffer(32768)
n=ctypes.windll.kernel32.GetShortPathNameW(sys.argv[1],b,32768)
s=b.value.split("\\") if 0<n<32768 else []
l=sys.argv[1].split("\\")
m="\\".join(s[:-1]+l[-1:]) if len(s)==len(l) else ""
print(m if m and m!=b.value and m!=sys.argv[1] else "")' "$CLN" 2>/dev/null)"
fi
if [[ -n "$MIXED" ]]; then
  MSLUG="$("$PY" -c 'import re,sys;print(re.sub(r"[^A-Za-z0-9]","-",sys.argv[1]))' "$MIXED")"
  PROJMX="$PB/projmx"
  ST16="$FIX/state16"
  mkdir -p "$PROJMX/$MSLUG/memory"
  printf '%s\n' '# A note' 'Body.' > "$PROJMX/$MSLUG/memory/note-m.md"
  mk "$PROJMX/$MSLUG/mmmmmmm1.jsonl" user 2026-11-14T08:00:00.000Z "a session recorded from a mixed path" "$MIXED"
  DREAM_NOW="2026-11-14T12:00:00Z" run bash "$CL/scripts/dream.sh" due --projects-dir "$PROJMX" --state-dir "$ST16"
  assert_contains "mixed path: the session folder named by a short-then-long path is counted" "dream: due (1 sessions"
  DREAM_NOW="2026-11-14T12:00:00Z" run bash "$CL/scripts/dream.sh" digest --projects-dir "$PROJMX" --state-dir "$ST16"
  assert_rc "mixed path: digest exits 0" 0
  assert_file_has "mixed path: a cwd in that spelling is read" "$ST16/digest.md" "a session recorded from a mixed path"
  run bash "$CL/scripts/dream.sh" hygiene --projects-dir "$PROJMX"
  assert_contains "mixed path: the memory folder named by that spelling is read" "auto-memory: 1 files"
else
  t_ok "mixed path: n/a without cygpath and 8.3 names"
fi

t_finish
