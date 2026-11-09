#!/usr/bin/env bash
# scripts/dream.sh taste and taste.py: the project taste digest (owner filter,
# signal kinds, stable ids, the evidence pool, stop-early rules, once-only
# offsets, project scope by cwd, --match, --projects-dir) and the parts of
# apply that are not about register rows (the evidence rule, the 160-character
# cap, once-only application, outcome and impact, the format guards). The
# register rows themselves are in test_taste_project.sh. The home folder is a
# temporary folder; DREAM_NOW pins the clock. Transcripts and notes are
# synthetic. Without python the test is skipped.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" || { echo "$0: cannot load lib.sh; stopped before writing anything" >&2; exit 2; }

. "$T_ROOT/scripts/find-python.sh"
if [[ -z "$PY" ]]; then
  t_ok "python not found; taste tests skipped (CI runs them)"
  t_finish
fi

make_fixture
cp_script dream.sh find-python.sh dream/dream.py dream/taste.py dream/preferences.py
: > .start-done
unset DREAM_PROJECTS_DIR CODEX_HOME TASTE_HOME
finish() {
  local h
  for h in "$FIX"-*; do
    case "$h" in */template-selftest.*-*) rm -rf "$h" ;; esac
  done
  t_finish
}

H="$FIX-home"
HN="$(cygpath -w "$H" 2>/dev/null || echo "$H")"
export HOME="$H" USERPROFILE="$HN"
export DREAM_NOW="2026-11-07T12:00:00Z"
P="$H/.claude/projects"
export DREAM_PROJECTS_DIR="$P"
NATIVE="$(cygpath -w "$FIX" 2>/dev/null || echo "$FIX")"
slug_of() { "$PY" -c 'import re,sys;print(re.sub(r"[^A-Za-z0-9]","-",sys.argv[1]))' "$1"; }
SLUG="$(slug_of "$NATIVE")"
NAME="$(basename "$FIX")"
ST="$FIX/.work/dream/taste"
D="$ST/digest.md"
PREF="$FIX/docs/preferences"
mkdir -p "$P/$SLUG"
A1="$P/$SLUG/aaaaaaaa-0001.jsonl"
A2="$P/$SLUG/bbbbbbbb-0002.jsonl"
B1="$P/$SLUG/cccccccc-0003.jsonl"
CA="$NATIVE"

# Writes one transcript line (or fragment) with python so JSON escaping is
# real. A literal \n in TEXT becomes a newline. EXTRA is the toolUseResult.
cat > "$FIX/mk.py" <<'PYEOF'
import json, sys
f, kind, ts, text, sess, cwd = sys.argv[1:7]
extra = json.loads(sys.argv[7]) if len(sys.argv) > 7 and sys.argv[7] else None
text = text.replace("\\n", "\n")
base = {"timestamp": ts, "cwd": cwd, "sessionId": sess, "gitBranch": "main"}
def user(**kw):
    return dict(base, type="user", message={"role": "user", "content": text}, **kw)
if kind == "human":
    o = user(origin={"kind": "human"}, promptSource="sdk")
elif kind == "legacy":
    o = user()
elif kind == "peer":
    o = user(origin={"kind": "peer", "from": "local_x"}, promptSource="system")
elif kind == "notif":
    o = user(origin={"kind": "task-notification"}, promptSource="system")
elif kind == "brief":
    o = user(promptSource="sdk", turnOrigin="sdk")
elif kind == "sched":
    o = user(promptSource="system", turnOrigin="scheduled")
elif kind == "meta":
    o = user(isMeta=True)
elif kind == "compact":
    o = user(isCompactSummary=True)
elif kind == "queued":
    o = dict(base, type="attachment", attachment={"type": "queued_command", "prompt": text, "origin": {"kind": "human"}})
elif kind == "queuednotif":
    o = dict(base, type="attachment", attachment={"type": "queued_command", "prompt": text,
                                                  "origin": {"kind": "task-notification"}})
elif kind == "assistant":
    o = dict(base, type="assistant", message={"role": "assistant", "content": [{"type": "text", "text": text}]})
elif kind == "answer":
    o = dict(base, type="user", toolUseResult=extra, message={"role": "user", "content": [
        {"type": "tool_result", "tool_use_id": "toolu_1", "content": text}]})
elif kind == "rejected":
    o = dict(base, type="user", toolDenialKind="user-rejected", toolUseResult="User rejected tool use",
             message={"role": "user", "content": [
                 {"type": "tool_result", "tool_use_id": "toolu_2", "is_error": True, "content": text}]})
elif kind in ("partial", "nl"):
    o = user(origin={"kind": "human"})
else:
    raise SystemExit("bad kind " + kind)
with open(f, "a", encoding="utf-8", newline="\n") as fh:
    if kind == "partial":
        fh.write(json.dumps(o))
    elif kind == "nl":
        fh.write("\n")
    else:
        fh.write(json.dumps(o) + "\n")
PYEOF

# mk FILE KIND TS TEXT SESSION CWD [EXTRA_JSON]
mk() { "$PY" "$FIX/mk.py" "$@"; }
ta() { run bash "$FIX/scripts/dream.sh" taste "$@"; }
# sid TEXT: the signal id of the digest line holding TEXT (in $D unless DG is set).
sid() { grep -F -- "$1" "${DG:-$D}" | head -n 1 | sed -E 's/^- (t[0-9a-f]+) .*/\1/'; }
sha() { "$PY" -c 'import hashlib,sys;print(hashlib.sha1(open(sys.argv[1],"rb").read()).hexdigest())' "$1"; }
# newproj N: a second project root $FIX-pN with the taste scripts; sets G and GN.
newproj() {
  G="$FIX-p$1"
  mkdir -p "$G"
  (cd "$G" && git init -q . >/dev/null 2>&1)
  : > "$G/.start-done"
  GN="$(cygpath -w "$G" 2>/dev/null || echo "$G")"
}
tg() { run bash "$FIX/scripts/dream.sh" taste --root "$G" "$@"; }

ta frobnicate
assert_rc "unknown taste command exits 2" 2

# --- owner lines and their kinds ---
mk "$A1" human     2026-11-01T10:00:00.000Z "I prefer short answers that lead with the result." aaaaaaaa-0001 "$CA"
mk "$A1" human     2026-11-01T10:01:00.000Z '<pasted_content id="p1">I prefer pasted words must not appear</pasted_content>\nPlease never use em dashes in docs.' aaaaaaaa-0001 "$CA"
mk "$A1" human     2026-11-01T10:02:00.000Z "Make the layout of the settings page wider." aaaaaaaa-0001 "$CA"
mk "$A1" human     2026-11-01T10:03:00.000Z "no, that is not what I asked for" aaaaaaaa-0001 "$CA"
mk "$A1" assistant 2026-11-01T10:04:00.000Z "Here is the new chart with muted colours and no gridlines. It also adds a legend." aaaaaaaa-0001 "$CA"
mk "$A1" human     2026-11-01T10:05:00.000Z "perfect" aaaaaaaa-0001 "$CA"
mk "$A1" answer    2026-11-01T10:06:00.000Z "Your questions have been answered" aaaaaaaa-0001 "$CA" \
  '{"questions":[{"question":"Which layout should the list use?","options":[{"label":"Grid (Recommended)"},{"label":"Rows"}]},{"question":"Which accent colour?","options":[{"label":"Teal"},{"label":"Orange"}]}],"answers":{"Which layout should the list use?":"Rows","Which accent colour?":"Something calmer than both"},"annotations":{"Which layout should the list use?":{"notes":"keep the rows compact"}}}'
mk "$A1" answer    2026-11-01T10:07:00.000Z "Your questions have been answered" aaaaaaaa-0001 "$CA" \
  '{"questions":[{"question":"Ship the fix now?","options":[{"label":"Yes (Recommended)"},{"label":"Later"}]},{"question":"Which parts?","multiSelect":true,"options":[{"label":"Docs"},{"label":"Tests"}]}],"answers":{"Ship the fix now?":"Yes (Recommended)","Which parts?":["Docs","Tests"]}}'
mk "$A1" rejected  2026-11-01T10:08:00.000Z "The user doesn't want to proceed with this tool use. The tool use was rejected." aaaaaaaa-0001 "$CA"
mk "$A1" human     2026-11-01T10:09:00.000Z "use the existing helper module for this" aaaaaaaa-0001 "$CA"
mk "$A1" queued    2026-11-01T10:10:00.000Z "I love the new colour palette." aaaaaaaa-0001 "$CA"
mk "$A1" answer    2026-11-01T10:11:00.000Z "Your questions have been answered" aaaaaaaa-0001 "$CA" \
  '{"questions":[{"question":"Which port?","options":[{"label":"A"},{"label":"B"}]}],"answers":{"Which port?":"[User did not answer this question - a placeholder must not appear]"}}'
mk "$A1" human     2026-11-01T10:12:00.000Z "I prefer the subfolder words." aaaaaaaa-0001 "$CA\\docs"
mkdir -p "$P/$SLUG--claude-worktrees-bold"
mk "$P/$SLUG--claude-worktrees-bold/abcdabcd-0009.jsonl" human 2026-11-01T11:00:00.000Z "I prefer the worktree words." abcdabcd-0009 "$CA\\.claude\\worktrees\\bold-x"
mk "$B1" legacy    2026-11-02T09:00:00.000Z "I prefer short answers that lead with the result." cccccccc-0003 "$CA"
mk "$B1" legacy    2026-11-02T09:01:00.000Z "Check the spacing on the cards page." cccccccc-0003 "$CA"
# --- lines that are not the owner's words ---
mk "$B1" peer        2026-11-02T09:02:00.000Z "I prefer peer words must not appear" cccccccc-0003 "$CA"
mk "$B1" notif       2026-11-02T09:03:00.000Z "I prefer notification words must not appear" cccccccc-0003 "$CA"
mk "$B1" brief       2026-11-02T09:04:00.000Z "Task (from the session that started this one): I prefer brief words must not appear" cccccccc-0003 "$CA"
mk "$B1" legacy      2026-11-02T09:05:00.000Z "Background (from the session that started this one): I prefer legacy brief words must not appear" cccccccc-0003 "$CA"
mk "$B1" sched       2026-11-02T09:06:00.000Z "I prefer scheduled words must not appear" cccccccc-0003 "$CA"
mk "$B1" legacy      2026-11-02T09:07:00.000Z "Base directory for this skill: I prefer skill words must not appear" cccccccc-0003 "$CA"
mk "$B1" meta        2026-11-02T09:08:00.000Z "I prefer meta words must not appear" cccccccc-0003 "$CA"
mk "$B1" compact     2026-11-02T09:09:00.000Z "I prefer compact words must not appear" cccccccc-0003 "$CA"
mk "$B1" queuednotif 2026-11-02T09:10:00.000Z "I prefer queued notification words must not appear" cccccccc-0003 "$CA"
mk "$B1" assistant   2026-11-02T09:11:00.000Z "I prefer assistant words must not appear" cccccccc-0003 "$CA"
# --- auto-memory notes of this project ---
mkdir -p "$P/$SLUG/memory"
printf '%s\n' '---' 'name: tone' 'description: "Owner wants plain words"' 'metadata:' '  type: feedback' \
  '  originSessionId: dddddddd-0004' '  modified: 2026-10-30T08:00:00.000Z' '---' '' 'No jargon in replies.' \
  > "$P/$SLUG/memory/feedback_tone.md"
printf '%s\n' '---' 'name: proj' 'description: "I prefer project-note words must not appear"' 'metadata:' \
  '  type: project' '---' 'body' > "$P/$SLUG/memory/proj.md"
printf '%s\n' '- [Tone](feedback_tone.md) - I prefer index words must not appear' > "$P/$SLUG/memory/MEMORY.md"

ta digest --min-signals 99
assert_rc "too few fresh signals exits 3" 3
assert_contains "too few says why" "not enough new signal"
assert_no_file "too few writes no digest" "$D"
assert_no_file "too few leaves no pending state" "$ST/state.next.json"
assert_file "too few keeps the signals in the pool" "$ST/state.json"
assert_file_has "the pool holds the new signals" "$ST/state.json" "I prefer short answers that lead with the result."

ta digest
assert_rc "digest exits 0" 0
assert_contains "digest names the report path" "2026-11-07-report.md"
assert_file "digest written" "$D"
assert_file "digest leaves pending state" "$ST/state.next.json"
assert_file_has "state folder ignores itself" "$ST/.gitignore" "*"
assert_file_has "P merged across sessions" "$D" "[P] 2026-11-02 $NAME cccccccc: I prefer short answers that lead with the result. (x2, 2 sessions)"
assert_file_has "P from the owner's words after pasted content" "$D" "[P] 2026-11-01 $NAME aaaaaaaa: Please never use em dashes in docs."
assert_file_lacks "pasted content excluded" "$D" "pasted words"
assert_file_has "T topic sentence" "$D" "[T] 2026-11-01 $NAME aaaaaaaa: Make the layout of the settings page wider."
assert_file_has "T from a second session" "$D" "[T] 2026-11-02 $NAME cccccccc: Check the spacing on the cards page."
assert_file_has "C correction" "$D" "[C] 2026-11-01 $NAME aaaaaaaa: no, that is not what I asked for"
assert_file_has "R reaction with the reply it answers" "$D" "[R] 2026-11-01 $NAME aaaaaaaa: perfect re: Here is the new chart with muted colours"
assert_file_has "A picked option" "$D" "[A] 2026-11-01 $NAME aaaaaaaa: Q: Which layout should the list use? -> Rows"
assert_file_has "A recommended option marked" "$D" "Q: Ship the fix now? -> Yes (recommended)"
assert_file_has "A multi-select options" "$D" "Q: Which parts? -> Docs, Tests"
assert_file_has "O own words in an answer" "$D" "[O] 2026-11-01 $NAME aaaaaaaa: Q: Which accent colour? -> own words: Something calmer than both"
assert_file_has "O note on an answer" "$D" "Q: Which layout should the list use? -> note: keep the rows compact"
assert_file_lacks "a placeholder answer is not the owner's words" "$D" "a placeholder must not appear"
assert_file_has "a session keeps the project it started in" "$D" "[P] 2026-11-01 $NAME aaaaaaaa: I prefer the subfolder words."
assert_file_has "a worktree session counts for its repository" "$D" "[P] 2026-11-01 $NAME abcdabcd: I prefer the worktree words."
assert_file_has "D rejection and the owner's next message" "$D" "[D] 2026-11-01 $NAME aaaaaaaa: use the existing helper module for this"
assert_file_has "queued owner message" "$D" "[P] 2026-11-01 $NAME aaaaaaaa: I love the new colour palette."
assert_file_has "F feedback note" "$D" "[F] 2026-10-30 $SLUG dddddddd: Owner wants plain words - No jargon in replies."
assert_file_lacks "not owner: any excluded line" "$D" "must not appear"
assert_file_has "digest states the register print against its cap" "$D" "profile: 0 of 4000 bytes"
BAD="$(grep '^- ' "$D" | grep -cvE '^- t[0-9a-f]{6} \[[POCDARTF]\] ')"
assert_eq "every signal line has an id and a kind" "0" "$BAD"

SID_P="$(sid 'I prefer short answers that lead with the result.')"
SID_T1="$(sid 'Make the layout of the settings page wider.')"
SID_T2="$(sid 'Check the spacing on the cards page.')"
SID_C="$(sid 'no, that is not what I asked for')"
SID_A="$(sid 'Q: Which layout should the list use? -> Rows')"
SID_O="$(sid 'own words: Something calmer than both')"

# Stable ids: the same transcripts digested with fresh state give the same id.
mv "$ST" "$FIX/st-keep"
ta digest
SID_P9="$(grep -F 'I prefer short answers that lead with the result.' "$D" | sed -E 's/^- (t[0-9a-f]+) .*/\1/')"
assert_eq "ids are stable across runs" "$SID_P" "$SID_P9"
rm -rf "$ST"
mv "$FIX/st-keep" "$ST"

ta done
assert_rc "done exits 0" 0
assert_no_file "done consumes the pending state" "$ST/state.next.json"
assert_file_has "done records the pass" "$ST/state.json" "2026-11-07T12:00:00Z"

# --- once only, partial lines, the day rule ---
ta digest --force --min-signals 1
assert_rc "nothing new after done exits 3" 3
assert_contains "nothing new says so" "not enough new signal (0 fresh"
mk "$A2" partial 2026-11-07T13:00:00.000Z "I prefer partial lines read once." bbbbbbbb-0002 "$CA"
ta digest --force --min-signals 1
assert_rc "a partial last line is not read" 3
mk "$A2" nl 2026-11-07T13:00:00.000Z "" bbbbbbbb-0002 "$CA"
ta digest --force --min-signals 1
assert_rc "the completed line is read" 0
assert_eq "a completed partial line is read once" "1" "$(grep -c 'I prefer partial lines read once.' "$D")"
assert_file_lacks "lines from before done are not fresh again" "$D" "[C] 2026-11-01 $NAME aaaaaaaa: no, that is not what I asked for (x"
ta done

export DREAM_NOW="2026-11-09T12:00:00Z"
mk "$A2" human 2026-11-09T10:00:00.000Z "I prefer the day rule words." bbbbbbbb-0002 "$CA"
rm -f "$D"
ta digest --min-signals 1
assert_rc "under seven days since the last pass exits 3" 3
assert_contains "the day rule says why" "under 7 days"
assert_no_file "the day rule writes no digest" "$D"
assert_no_file "the day rule leaves no pending state" "$ST/state.next.json"
ta digest --min-signals 1 --force
assert_rc "--force skips the day rule" 0
assert_file_has "a signal kept by an earlier exit 3 is shown" "$D" "I prefer the day rule words."

# --- apply: the evidence rule, the cap, once only (rows: test_taste_project.sh) ---
R1="$ST/reports/2026-11-09-report.md"
mkdir -p "$ST/reports"
LONG="$(printf 'w%.0s' $(seq 1 161))"
cat > "$R1" <<EOF
# Taste report 2026-11-09
Read: 20 signals
## Proposals
1. add communication: Lead with the result in one short sentence.
   Evidence: $SID_P (P)
   Why: stated in two sessions
2. add design: Prefer roomy layouts.
   Evidence: $SID_T1, $SID_T2
   Why: two sessions
5. change everything somehow
   Evidence: $SID_P
6. add writing: Use plain hyphens.
   Evidence: t000000
7. add design: Keep corrections brief.
   Evidence: $SID_C
8. add art: $LONG
   Evidence: $SID_P
9. add design: Use the Rows layout.
   Evidence: $SID_A
10. add working: Ask before large refactors.
   Evidence: $SID_O
11. revise T001 communication: the old profile form is malformed here.
   Evidence: $SID_P
## Considered and dropped
- nothing
EOF

ta apply --report "$R1" 5
assert_rc "malformed proposal exits 1" 1
assert_contains "malformed proposal named" "proposal 5 is malformed"
ta apply --report "$R1" 11
assert_rc "the old revise form is malformed" 1
assert_contains "the expected forms name the area and the ID" "revise <area> <ID>"
ta apply --report "$R1" 1 6
assert_rc "unknown evidence exits 1" 1
assert_contains "unknown evidence named" "t000000"
ta apply --report "$R1" 1 7
assert_rc "an inferred line from one session exits 1" 1
assert_contains "the session rule says why" "two or more sessions"
ta apply --report "$R1" 9
assert_rc "a picked option alone is not explicit" 1
ta apply --report "$R1" 8
assert_rc "a line over 160 characters exits 1" 1
assert_contains "the line cap says why" "160 characters"
ta apply --report "$R1" 12
assert_rc "an unknown number exits 1" 1
assert_contains "the unknown number named" "no proposal 12"
assert_no_file "a refused apply writes no register" "$PREF/communication.md"
ta apply --report "$R1" 10 10
assert_rc "a repeated approved number exits 1" 1
assert_contains "the repeated number is named" "proposal 10 is approved twice"
assert_no_file "a repeated number writes nothing" "$PREF/working.md"
RDUP="$ST/reports/2026-11-09-dup.md"
printf '%s\n' '# Taste report 2026-11-09' '## Proposals' \
  '1. add working: Ask before large refactors.' "   Evidence: $SID_O" \
  '1. add design: Prefer roomy layouts.' "   Evidence: $SID_P" > "$RDUP"
ta apply --report "$RDUP" 1
assert_rc "a report that numbers two proposals alike exits 2" 2
assert_contains "the report's repeated number is named" "numbers proposal 1 twice"
assert_no_file "a repeated report number writes nothing" "$PREF/working.md"

ta apply --report "$R1" 1 2 10
assert_rc "apply exits 0" 0
assert_file_has "add writes the area file" "$PREF/communication.md" "Lead with the result in one short sentence."
assert_file_has "a third area" "$PREF/working.md" "| WORKING-001 | Ask before large refactors. |"
assert_file_has "apply records the used signals" "$ST/ledger.json" "$SID_T1"

S_COM="$(sha "$PREF/communication.md")"
ta apply --report "$R1" 1
assert_rc "applying the same number again exits 0" 0
assert_contains "the same number is reported as already applied" "already applied"
assert_eq "a repeated apply changes nothing" "$S_COM" "$(sha "$PREF/communication.md")"

ta digest --force --min-signals 1
assert_file_lacks "a used signal is not offered again" "$D" "Make the layout of the settings page wider."

R2="$ST/reports/2026-11-10-report.md"
cat > "$R2" <<EOF
# Taste report 2026-11-10
## Proposals
1. revise communication COMMUNICATION-001: Lead with the result, then at most three bullets.
   Evidence: $SID_P
2. remove design DESIGN-001: contradicted
   Evidence:
3. add design: Prefer roomy layouts with clear spacing.
   Evidence: $SID_T1, $SID_T2
EOF
ta apply --report "$R2" 1 2 3
assert_rc "revise, remove and add exit 0" 0
assert_file_has "revise replaces the text" "$PREF/communication.md" "Lead with the result, then at most three bullets."
assert_file_lacks "revise drops the old text" "$PREF/communication.md" "in one short sentence"
assert_file_lacks "remove deletes the row" "$PREF/design.md" "DESIGN-001"
assert_file_has "numbers are never reused" "$PREF/design.md" "| DESIGN-002 | Prefer roomy layouts with clear spacing. |"
ta check
assert_rc "check passes on clean registers" 0
assert_contains "check reports OK" "taste: OK"

# --- outcome and impact ---
ta done --report "$R1"
assert_rc "done with a report exits 0" 0
assert_file_has "outcome heading" "$R1" "## Outcome 2026-11-09"
assert_file_has "outcome lists applied numbers" "$R1" "Applied: 1, 2, 10"
assert_file_has "outcome lists declined numbers" "$R1" "Declined: 5, 6, 7, 8, 9, 11"
assert_file_has "outcome lists the changes" "$R1" "WORKING-001 added (working)"
assert_file_has "outcome lists the files touched" "$R1" "docs/preferences/working.md"
assert_file_has "outcome gives profile numbers before and after" "$R1" "Profile: "
export DREAM_NOW="2026-11-20T12:00:00Z"
B2="$P/$SLUG/cdcdcdcd-0010.jsonl"
mk "$B2" legacy 2026-11-19T09:00:00.000Z "Check the spacing on the cards page." cdcdcdcd-0010 "$CA"
mk "$B2" legacy 2026-11-19T09:01:00.000Z "The roomy spacing on the new screen works." cdcdcdcd-0010 "$CA"
ta digest --min-signals 1
assert_rc "a digest after an applied pass exits 0" 0
assert_file_has "impact section" "$D" "## Impact since the last pass"
assert_file_has "impact lists a revision" "$D" "COMMUNICATION-001 revised (communication)"
assert_file_has "impact lists a removal" "$D" "DESIGN-001 removed (design)"
assert_file_has "impact lists an addition" "$D" "DESIGN-002 added (design)"
assert_file_has "impact lists a line seen again" "$D" "design:DESIGN-002 seen again since applied: $SID_T2 +1"
assert_file_has "impact lists a word-overlap candidate" "$D" "design:DESIGN-002 shares words with"
assert_file_has "impact gives a trend" "$D" "trend, fresh signals by kind per pass:"
assert_file_has "the trend holds an earlier pass" "$D" "  2026-11-09: "
ta done
export DREAM_NOW="2026-11-09T12:00:00Z"

# --- the evidence pool: cut signals return, two sessions across passes, pruning ---
newproj 2
G2="$G"
mkdir -p "$P/$(slug_of "$GN")"
GP="$P/$(slug_of "$GN")"
G1F="$GP/eeeeeeee-0005.jsonl"
mk "$G1F" human 2026-11-01T08:00:00.000Z "I prefer the cap-kept words." eeeeeeee-0005 "$GN"
for n in $(seq 10 49); do
  mk "$G1F" human "2026-11-01T09:$n:00.000Z" "Change the layout of panel $n to the plan $(printf 'q%.0s' $(seq 1 120))." eeeeeeee-0005 "$GN"
done
G2ST="$G/.work/dream/taste"
D2="$G2ST/digest.md"
export DREAM_NOW="2026-11-10T12:00:00Z"
tg digest --max-bytes 2000
assert_rc "capped digest exits 0" 0
assert_file_has "the cap keeps the stated preference first" "$D2" "I prefer the cap-kept words."
assert_file_has "the cap reports dropped signals" "$D2" "dropped by the 2000 byte cap"
assert_file_has "the newest topic sentence is kept" "$D2" "panel 49 "
LOW="$(grep -oE 'panel [0-9]+ ' "$D2" | grep -oE '[0-9]+' | sort -n | head -n 1)"
NEXT=$((LOW - 1))
assert_file_lacks "an older topic sentence is cut" "$D2" "panel $NEXT "
tg done
export DREAM_NOW="2026-11-20T12:00:00Z"
tg digest --max-bytes 2000 --min-signals 1
assert_rc "the next digest exits 0" 0
assert_file_has "a signal the cap cut is shown next time" "$D2" "panel $NEXT "
SID_OLD="$(grep -F "panel $NEXT " "$D2" | sed -E 's/^- (t[0-9a-f]+) .*/\1/')"
tg done
mk "$G1F" human 2026-11-21T08:00:00.000Z "Move the legend of panel 7 so the layout breathes." ffffffff-0006 "$GN"
export DREAM_NOW="2026-11-28T12:00:00Z"
tg digest --max-bytes 2000 --min-signals 1
assert_rc "a later pass exits 0" 0
SID_NEW="$(grep -F 'Move the legend of panel 7' "$D2" | sed -E 's/^- (t[0-9a-f]+) .*/\1/')"
mkdir -p "$G2ST/reports"
R3="$G2ST/reports/2026-11-28-report.md"
printf '%s\n' '## Proposals' '1. add design: Keep panel legends out of the plot area.' "   Evidence: $SID_OLD, $SID_NEW" > "$R3"
tg apply --report "$R3" 1
assert_rc "an older signal plus a new session meets the two-session rule" 0
assert_file_has "the row lands in the root the pass ran for" "$G/docs/preferences/design.md" "Keep panel legends out of the plot area."
tg done
export DREAM_NOW="2027-06-30T12:00:00Z"
tg digest --force --min-signals 1
tg done
assert_file_lacks "a shown, unused signal unseen for 180 days is pruned" "$G2ST/state.json" "I prefer the cap-kept words."
assert_file_has "a used signal is kept" "$G2ST/state.json" "panel $NEXT "
export DREAM_NOW="2026-11-09T12:00:00Z"

# --- scope: --match and --projects-dir ---
newproj 3
M="$FIX-m3"
MN="$(cygpath -w "$M" 2>/dev/null || echo "$M")"
mkdir -p "$P/elsewhere"
mk "$P/elsewhere/mmmmmmmm-0011.jsonl" human 2026-11-08T08:00:00.000Z "I prefer words from a matched path." mmmmmmmm-0011 "$MN"
tg digest --min-signals 1
assert_rc "no signal from an unmatched path exits 3" 3
tg digest --min-signals 1 --match "$M"
assert_rc "--match adds a root" 0
assert_file_has "the matched session counts" "$G/.work/dream/taste/digest.md" "I prefer words from a matched path."
X="$FIX-x3/copy-from-another-computer"
mkdir -p "$X/$(slug_of "$GN")" "$X/other"
mk "$X/$(slug_of "$GN")/abababab-0007.jsonl" human 2026-11-08T08:00:00.000Z "I prefer words from another computer." abababab-0007 "$GN"
mk "$X/other/acacacac-0008.jsonl" human 2026-11-08T08:00:00.000Z "I prefer words of another computer's other project." acacacac-0008 'C:\work\delta'
tg digest --min-signals 1 --force --projects-dir "$X"
assert_rc "an extra --projects-dir is read" 0
assert_file_has "signals from the extra folder that match the project" "$G/.work/dream/taste/digest.md" "I prefer words from another computer."
assert_file_lacks "the extra folder's other project is not read" "$G/.work/dream/taste/digest.md" "other project"

# --- guards ---
newproj 4
mkdir -p "$G/.work/dream/taste"
echo '{"format": 99}' > "$G/.work/dream/taste/state.json"
tg digest
assert_rc "a newer state format exits 2" 2
assert_contains "a newer state format says to update" "update the template"
rm -f "$G/.work/dream/taste/state.json"
echo '{"format": 99}' > "$G/.work/dream/taste/ledger.json"
tg apply --report "$R1" 1
assert_rc "a newer ledger format exits 2" 2
assert_contains "a newer ledger format says to update" "update the template"
ta digest --max-bytes 10
assert_rc "a too small --max-bytes exits 2" 2

finish
