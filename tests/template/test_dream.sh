#!/usr/bin/env bash
# scripts/dream.sh and scripts/dream/dream.py: the signal digest, the once-only offsets, the
# due decision and the memory hygiene report. Transcripts are synthetic JSONL
# under a fake projects folder; DREAM_PROJECTS_DIR and DREAM_NOW pin the inputs.
# Without python the test is skipped (CI has python3).
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

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
PROJ="$FIX/projects"
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
PROJ3="$FIX/projects3"
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
PROJ0="$FIX/projects0"
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
PROJ4="$FIX/projects4"
mkdir -p "$PROJ4/${SLUG}-bar"
mk "$PROJ4/${SLUG}-bar/eeeeeeee55.jsonl" user 2026-11-07T07:00:00.000Z "sibling activity" "${NATIVE}-bar"
run env DREAM_PROJECTS_DIR="$PROJ4" bash scripts/dream.sh due --state-dir "$FIX/state4"
assert_rc "due: a sibling folder named root-bar is not this repository" 1
mkdir -p "$PROJ4/$SLUG"
mk "$PROJ4/$SLUG/ffffffff66.jsonl" user 2026-11-07T07:00:00.000Z "own activity"
run env DREAM_PROJECTS_DIR="$PROJ4" bash scripts/dream.sh due --state-dir "$FIX/state4"
assert_rc "due: the same activity in the root folder is due" 0
PROJ5="$FIX/projects5"
mkdir -p "$PROJ5/${SLUG}--claude-worktrees-foo"
mk "$PROJ5/${SLUG}--claude-worktrees-foo/gggggggg77.jsonl" user 2026-11-07T07:00:00.000Z "app worktree activity" "$NATIVE/.claude/worktrees/foo"
run env DREAM_PROJECTS_DIR="$PROJ5" bash scripts/dream.sh due --state-dir "$FIX/state5"
assert_rc "due: an app worktree folder counts" 0

# --- a partial line survives done and is read exactly once ---
PROJ6="$FIX/projects6"
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
PROJ9="$FIX/projects9"
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
PROJ7="$FIX/projects7"
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
PROJ8="$FIX/projects8"
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
PROJ10="$FIX/projects10"
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
PROJ11="$FIX-p11"
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
case "$PROJ11" in */template-selftest.*-p11) rm -rf "$PROJ11" ;; esac

t_finish
