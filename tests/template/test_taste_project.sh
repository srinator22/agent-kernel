#!/usr/bin/env bash
# scripts/dream.sh taste as a per-project pass: the digest reads only this
# project's transcripts and auto-memory notes (A4); nothing is written under
# the home folder (A5); apply writes register rows through the one writer
# (A6), skips what the registers already hold (A7) and refuses in template
# mode (A8). Transcripts, notes and rule text are synthetic. Without python
# the test is skipped.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" || { echo "$0: cannot load lib.sh; stopped before writing anything" >&2; exit 2; }

. "$T_ROOT/scripts/find-python.sh"
if [[ -z "$PY" ]]; then
  t_ok "python not found; project taste tests skipped (CI runs them)"
  t_finish
fi

make_fixture
cp_script dream.sh find-python.sh preferences.sh dream/dream.py dream/taste.py dream/preferences.py
: > .start-done
mkdir -p docs
printf 'baseline file\n' > docs/trailer.md
git add -A >/dev/null 2>&1
git commit -q -m fixture >/dev/null 2>&1
NATIVE="$(cygpath -w "$FIX" 2>/dev/null || echo "$FIX")"
SLUG="$("$PY" -c 'import re,sys;print(re.sub(r"[^A-Za-z0-9]","-",sys.argv[1]))' "$NATIVE")"
finish() {
  case "$FIX" in */template-selftest.*) rm -rf "$FIX-home" ;; esac
  t_finish
}

# A home that already holds the owner's user-level profile and both blocks.
H="$FIX-home"
HN="$(cygpath -w "$H" 2>/dev/null || echo "$H")"
export HOME="$H" USERPROFILE="$HN"
unset TASTE_HOME CODEX_HOME
export DREAM_NOW="2026-11-09T12:00:00Z"
PR="$H/.claude/projects"
export DREAM_PROJECTS_DIR="$PR"
mkdir -p "$H/.claude/taste" "$H/.codex" "$PR/$SLUG/memory" "$PR/other/memory" "$PR/$SLUG"
printf '%s\n' '# Communication' 'x' '' '- [T001] Existing user-level line.' > "$H/.claude/taste/communication.md"
printf '%s\n' '# Mine' '<!-- taste:begin - managed -->' '@taste/communication.md' '<!-- taste:end -->' > "$H/.claude/CLAUDE.md"
printf '%s\n' '# Codex' '<!-- taste:begin - managed -->' '- [T001] Existing user-level line.' '<!-- taste:end -->' > "$H/.codex/AGENTS.md"
home_sum() { (cd "$H" && find .claude .codex -type f ! -path '.claude/projects/*' | LC_ALL=C sort | while IFS= read -r f; do printf '%s %s\n' "$f" "$(cksum < "$f")"; done); }
HOME_BEFORE="$(home_sum)"

cat > "$FIX/mk.py" <<'PYEOF'
import json, sys
f, kind, ts, text, sess, cwd = sys.argv[1:7]
extra = json.loads(sys.argv[7]) if len(sys.argv) > 7 and sys.argv[7] else None
base = {"timestamp": ts, "cwd": cwd, "sessionId": sess, "gitBranch": "main"}
if kind == "human":
    o = dict(base, type="user", message={"role": "user", "content": text}, origin={"kind": "human"}, promptSource="sdk")
elif kind == "answer":
    o = dict(base, type="user", toolUseResult=extra, message={"role": "user", "content": [
        {"type": "tool_result", "tool_use_id": "toolu_1", "content": text}]})
else:
    raise SystemExit("bad kind " + kind)
with open(f, "a", encoding="utf-8", newline="\n") as fh:
    fh.write(json.dumps(o) + "\n")
PYEOF
mk() { "$PY" "$FIX/mk.py" "$@"; }
ta() { run bash "$FIX/scripts/dream.sh" taste "$@"; }
sid() { grep -F -- "$1" "$D" | head -n 1 | sed -E 's/^- (t[0-9a-f]+) .*/\1/'; }
sha() { "$PY" -c 'import hashlib,sys;print(hashlib.sha1(open(sys.argv[1],"rb").read()).hexdigest())' "$1"; }
ST="$FIX/.work/dream/taste"
D="$ST/digest.md"
PREF="$FIX/docs/preferences"

# --- A4: only this project's sessions and notes ---
A1="$PR/$SLUG/aaaaaaaa-0001.jsonl"
A2="$PR/other/bbbbbbbb-0002.jsonl"
X1="$PR/other/cccccccc-0003.jsonl"
mk "$A1" human 2026-11-01T10:00:00.000Z "I prefer short answers that lead with the result." aaaaaaaa-0001 "$NATIVE"
mk "$A1" human 2026-11-01T10:01:00.000Z "Please never use em dashes in docs." aaaaaaaa-0001 "$NATIVE"
mk "$A1" human 2026-11-01T10:02:00.000Z "Make the layout of the settings page wider." aaaaaaaa-0001 "$NATIVE"
mk "$A1" answer 2026-11-01T10:03:00.000Z "Your questions have been answered" aaaaaaaa-0001 "$NATIVE" \
  '{"questions":[{"question":"Which accent colour?","options":[{"label":"Teal"},{"label":"Orange"}]}],"answers":{"Which accent colour?":"Something calmer than both"}}'
mk "$A1" human 2026-11-01T10:05:00.000Z "Check the colour scheme on the docs page." aaaaaaaa-0001 "$NATIVE"
mk "$A1" human 2026-11-01T10:04:00.000Z "I prefer the subfolder words." aaaaaaaa-0001 "$NATIVE/docs"
mk "$A2" human 2026-11-02T09:00:00.000Z "Make the layout of the settings page wider." bbbbbbbb-0002 "$NATIVE"
mk "$A2" human 2026-11-02T09:01:00.000Z "I prefer the words of a session that worked here." bbbbbbbb-0002 "$NATIVE"
mk "$X1" human 2026-11-02T09:02:00.000Z "I prefer foreign project words must not appear." cccccccc-0003 'C:\work\other'
printf '%s\n' '---' 'name: tone' 'description: "Owner wants plain words"' 'metadata:' '  type: feedback' \
  '  originSessionId: dddddddd-0004' '---' '' 'No jargon in replies.' > "$PR/$SLUG/memory/feedback_tone.md"
printf '%s\n' '---' 'name: foreign' 'description: "foreign note words must not appear"' 'metadata:' '  type: feedback' \
  '  originSessionId: bbbbbbbb-0002' '---' '' 'Other project note.' > "$PR/other/memory/feedback_other.md"

ta digest --min-signals 1
assert_rc "digest exits 0" 0
assert_file "state lives in the main checkout's .work/dream/taste" "$ST/state.next.json"
assert_file_has "the state folder ignores itself" "$ST/.gitignore" "*"
assert_file_has "this project's transcript counts" "$D" "I prefer short answers that lead with the result."
assert_file_has "a subfolder of the project counts" "$D" "I prefer the subfolder words."
assert_file_has "a session of another folder that worked here counts" "$D" "I prefer the words of a session that worked here."
assert_file_has "this project's memory note counts" "$D" "No jargon in replies."
assert_file_lacks "another project's transcript contributes nothing" "$D" "foreign project words"
assert_file_lacks "another project's memory note contributes nothing" "$D" "Other project note"
assert_file_lacks "the foreign transcript is not kept in the pool" "$ST/state.next.json" "foreign project words"
assert_file_has "the digest reports the register print against the 4000-byte cap" "$D" "profile: 0 of 4000 bytes"

# --- A5: nothing under the home folder ---
assert_eq "digest leaves the home profile and blocks alone" "$HOME_BEFORE" "$(home_sum)"
assert_no_file "no taste state under the home folder" "$H/.claude/taste/.dream"

SID_P="$(sid 'I prefer short answers that lead with the result.')"
SID_P2="$(sid 'Please never use em dashes in docs.')"
SID_T="$(sid 'Make the layout of the settings page wider.')"
SID_O="$(sid 'own words: Something calmer than both')"
SID_T1="$(sid 'Check the colour scheme on the docs page.')"
SID_P3="$(sid 'I prefer the words of a session that worked here.')"

# --- A6: rows in docs/preferences ---
mkdir -p "$PREF"
cat > "$PREF/film.md" <<'EOF'
# Film

| ID | Rule | Source | Check |
|---|---|---|---|
| FILM-001 | Keep cuts short. | 2026-10-01: "short cuts" | Review |

## Baselines

| Kind | Reference | Owns | Check |
|---|---|---|---|
| trailer | `docs/trailer.md` 2026-10-01 | cut | Review |
EOF
git add -A >/dev/null 2>&1
R1="$ST/reports/2026-11-09-report.md"
mkdir -p "$ST/reports"
LONG="$(printf 'w%.0s' $(seq 1 161))"
cat > "$R1" <<EOF
# Taste report 2026-11-09
## Proposals
1. add communication: Lead with the result in one short sentence.
   Evidence: $SID_P (P)
2. add film: Cut a | b only when both hold.
   Evidence: $SID_P2
3. add visual-tone: Prefer calm accent colours.
   Evidence: $SID_O
4. add design: Prefer roomy layouts.
   Evidence: $SID_T
5. add writing: Use plain hyphens.
   Evidence: $SID_P2
6. add writing: use  PLAIN hyphens.
   Evidence: $SID_P2
7. add communication: lead with the result in one SHORT sentence.
   Evidence: $SID_P
8. add design: Keep corrections brief.
   Evidence: $SID_P3
9. add art: $LONG
   Evidence: $SID_P
10. add design: Needs a stated preference.
   Evidence: $SID_T1
11. revise communication COMMUNICATION-001: Lead with the result, then at most three bullets.
   Evidence: $SID_P
12. remove film FILM-001: contradicted
   Evidence:
13. add working: Ask before large refactors.
   Evidence: $SID_O
14. revise communication COMMUNICATION-099: Nothing there.
   Evidence: $SID_P
15. add design: x
   Evidence: t000000
EOF
ta apply --report "$R1" 9
assert_rc "a rule over 160 characters is refused" 1
assert_contains "the cap says why" "160 characters"
ta apply --report "$R1" 15
assert_rc "evidence outside the pool is refused" 1
ta apply --report "$R1" 10
assert_rc "an inferred rule from one session is refused" 1
assert_contains "the session rule says why" "two or more sessions"
ta apply --report "$R1" 1 14
assert_rc "a revise of an unknown ID is refused" 1
assert_no_file "a refused apply writes no register" "$PREF/communication.md"
assert_no_file "a refused apply leaves no new area file" "$PREF/visual-tone.md"

ta apply --report "$R1" 1 2 3 4
assert_rc "apply exits 0" 0
assert_file_has "a new file gets its title" "$PREF/communication.md" "# Communication"
assert_file_has "a new file gets the rules header" "$PREF/communication.md" "| ID | Rule | Source | Check | Repeats |"
assert_file_has "the row has ID, rule, owner's quoted words and Review" "$PREF/communication.md" \
  '| COMMUNICATION-001 | Lead with the result in one short sentence. | 2026-11-01: "I prefer short answers that lead with the result." | Review |'
assert_file_has "a pipe in a rule is escaped" "$PREF/film.md" "Cut a \\| b only when both hold."
assert_file_has "the film ID continues the file's prefix" "$PREF/film.md" "| FILM-002 |"
FILM_ROW="$(grep -n 'FILM-002' "$PREF/film.md" | cut -d: -f1)"
BASE_ROW="$(grep -n '## Baselines' "$PREF/film.md" | cut -d: -f1)"
assert_eq "the new row sits before the baselines table" "yes" "$([[ "$FILM_ROW" -lt "$BASE_ROW" ]] && echo yes || echo no)"
assert_file_has "the baselines table is kept" "$PREF/film.md" "| trailer | \`docs/trailer.md\` 2026-10-01 | cut | Review |"
assert_file_has "a hyphenated area gets an ID without the hyphen" "$PREF/visual-tone.md" "| VISUALTONE-001 | Prefer calm accent colours. |"
assert_file_has "an O signal quotes only the owner's words" "$PREF/visual-tone.md" '2026-11-01: "Something calmer than both"'
assert_file_lacks "an O signal drops the question" "$PREF/visual-tone.md" "Q: Which"
assert_file_has "an inferred rule says so" "$PREF/design.md" "inferred from sessions aaaaaaaa, bbbbbbbb"
run bash "$FIX/scripts/preferences.sh" check
assert_rc "the register check passes" 0
assert_file_has "the ledger records the used signals" "$ST/ledger.json" "$SID_T"
assert_file_has "the ledger records the highest number written" "$ST/ledger.json" '"communication": 1'

# --- A7: nothing twice ---
S_COM="$(sha "$PREF/communication.md")"
ta apply --report "$R1" 7
assert_rc "an existing rule is applied without a row" 0
assert_contains "the skip names the existing rule" "already a rule"
assert_eq "no row was added for an existing rule" "$S_COM" "$(sha "$PREF/communication.md")"
ta apply --report "$R1" 7
assert_contains "the skipped proposal counts as applied" "already applied"
ta apply --report "$R1" 5 6
assert_rc "two equal proposals in one apply exit 0" 0
assert_eq "two equal proposals add one row" "1" "$(grep -c 'plain hyphens' "$PREF/writing.md")"
S_ALL="$(sha "$PREF/film.md")$(sha "$PREF/writing.md")$(sha "$PREF/design.md")$(sha "$ST/ledger.json")"
ta apply --report "$R1" 1 2 3 4 5 6 7
assert_rc "the same report again exits 0" 0
assert_eq "the same report twice adds nothing" "$S_ALL" "$(sha "$PREF/film.md")$(sha "$PREF/writing.md")$(sha "$PREF/design.md")$(sha "$ST/ledger.json")"

# revise, remove, and a removed number is never reused
ta apply --report "$R1" 11 12
assert_rc "revise and remove exit 0" 0
assert_file_has "revise replaces the rule" "$PREF/communication.md" "Lead with the result, then at most three bullets."
assert_file_has "revise appends the owner's words to Source" "$PREF/communication.md" '; 2026-11-01: "I prefer short answers that lead with the result."'
assert_file_lacks "remove deletes the row" "$PREF/film.md" "FILM-001"
ta apply --report "$R1" 13
R2="$ST/reports/2026-11-10-report.md"
printf '%s\n' '## Proposals' '1. remove communication COMMUNICATION-001: tired' '2. add communication: Name the file in every reply.' "   Evidence: $SID_P" > "$R2"
ta apply --report "$R2" 1 2
assert_rc "remove then add exits 0" 0
assert_file_has "a removed number is not reused" "$PREF/communication.md" "| COMMUNICATION-002 | Name the file in every reply. |"
run bash "$FIX/scripts/preferences.sh" check
assert_rc "the register check still passes" 0
ta check
assert_rc "taste check exits 0" 0
assert_contains "taste check reports OK" "taste: OK"

# a proposal that wraps onto a second indented line applies its full text
R4="$ST/reports/2026-11-11-report.md"
printf '%s\n' '## Proposals' '1. add working: Say what changed first,' '   then name the risk in one clause.' "   Evidence: $SID_P" '   Why: stated once' > "$R4"
ta apply --report "$R4" 1
assert_rc "a wrapped proposal applies" 0
assert_file_has "the full wrapped text is the rule" "$PREF/working.md" "Say what changed first, then name the risk in one clause."
assert_file_lacks "the Why line is not part of the rule" "$PREF/working.md" "stated once"

# a wrapped Why tail never joins the rule; a wrapped Evidence tail adds its ids
R5="$ST/reports/2026-11-12-report.md"
printf '%s\n' '## Proposals' '1. add working: Keep commit subjects short.' '   Why: said in a review' '   and again later' "   Evidence: $SID_P" \
  '2. add working: Name the test file in each fix.' "   Evidence: $SID_P2" "   $SID_T1" > "$R5"
ta apply --report "$R5" 1 2
assert_rc "wrapped Why and Evidence proposals apply" 0
assert_file_has "a wrapped Why tail is not part of the rule" "$PREF/working.md" "| Keep commit subjects short. |"
assert_file_lacks "the Why tail is nowhere in the register" "$PREF/working.md" "and again later"
assert_file_has "a wrapped Evidence tail is not part of the rule" "$PREF/working.md" "| Name the test file in each fix. |"
assert_file_has "a wrapped Evidence tail counts as evidence" "$ST/ledger.json" "$SID_T1"

# removing a hand-written top row keeps its number taken, even within one apply
cat > "$PREF/voice.md" <<'EOF'
# Voice

| ID | Rule | Source | Check |
|---|---|---|---|
| VOICE-001 | Speak plainly. | 2026-10-01: "plain" | Review |
| VOICE-007 | Keep it short. | 2026-10-02: "short" | Review |
EOF
git add "$PREF/voice.md" >/dev/null 2>&1
R6="$ST/reports/2026-11-13-report.md"
printf '%s\n' '## Proposals' '1. remove voice VOICE-007: replaced' '2. add voice: Keep each answer under ten lines.' "   Evidence: $SID_P" > "$R6"
ta apply --report "$R6" 1 2
assert_rc "remove of a hand-written top row then add exits 0" 0
assert_file_has "the add takes the number after the removed one" "$PREF/voice.md" "| VOICE-008 | Keep each answer under ten lines. |"
assert_file_lacks "the removed number is not given out again" "$PREF/voice.md" "VOICE-007"
assert_file_has "the ledger keeps the removed number as the floor" "$ST/ledger.json" '"voice": 8'

# --- A5 again, after every command ---
ta done --report "$R1"
assert_rc "done exits 0" 0
assert_eq "digest, apply and done leave the home profile and blocks byte-identical" "$HOME_BEFORE" "$(home_sum)"
assert_file_has "the user-level profile line is untouched" "$H/.claude/taste/communication.md" "[T001] Existing user-level line."

# --- A8: template mode ---
mv .start-done "$FIX/start-done.saved"
rm -f "$PREF/working.md"
S_L="$(sha "$ST/ledger.json")"
ta apply --report "$R1" 13
assert_rc "template mode refuses apply" 1
assert_contains "the refusal names template mode" "template mode"
assert_no_file "template mode writes no register" "$PREF/working.md"
assert_eq "template mode leaves the ledger alone" "$S_L" "$(sha "$ST/ledger.json")"
mv "$FIX/start-done.saved" .start-done

finish
