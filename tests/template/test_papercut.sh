#!/usr/bin/env bash
# scripts/papercut.sh (scripts/dream/papercut.py): add files one friction report as a
# JSON line in the main checkout's .work/papercuts/log.jsonl; list groups them. Covers
# each missing, empty, repeated or invalid field, the 300-character limit, JSON escaping,
# the 200-entry cap, grouping, the correct-refusal section, a malformed log line, the
# git-ignored path, a linked worktree and a missing Python.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" || { echo "$0: cannot load lib.sh; stopped before writing anything" >&2; exit 2; }

. "$T_ROOT/scripts/find-python.sh"
if [[ -z "$PY" ]]; then
  t_ok "python not found; papercut tests skipped (CI runs them)"
  t_finish
fi

make_fixture
cp_script papercut.sh find-python.sh dream/dream.py dream/papercut.py
cp "$T_ROOT/.gitignore" .gitignore
git add . && git commit -q -m "chore: scripts"
FIX0="$FIX"
trap 'case "$FIX0-wt" in */template-selftest.*) rm -rf "$FIX0-wt" ;; esac; t_cleanup' EXIT
LOG="$FIX/.work/papercuts/log.jsonl"
export PAPERCUT_NOW="2026-11-20T10:00:00Z"
pc() { run bash "$FIX/scripts/papercut.sh" "$@"; }
# add5 TOOL TRIED EXPECTED GOT FIX REFUSAL
add5() { pc add --tool "$1" --tried "$2" --expected "$3" --got "$4" --fix "$5" --refusal "$6"; }
lines() { if [[ -f "$LOG" ]]; then wc -l < "$LOG" | tr -d ' '; else echo 0; fi; }
# field KEY: the value of KEY in the last log line, parsed as JSON, as UTF-8 bytes.
field() {
  "$PY" -c 'import json,sys
v = json.loads(open(sys.argv[1], encoding="utf-8").read().splitlines()[-1])[sys.argv[2]]
sys.stdout.buffer.write(str(v).encode("utf-8"))' "$LOG" "$1"
}

# --- the path is git-ignored by the repository's .gitignore, before the folder exists ---
if git check-ignore -q .work/papercuts/log.jsonl; then t_ok "the log path is git-ignored"; else t_bad "the log path is git-ignored"; fi

# --- empty log ---
pc list
assert_rc "list with no log exits 0" 0
assert_contains "list with no log says none" "papercuts: none"
assert_no_file "list writes nothing" "$FIX/.work/papercuts"

# --- usage ---
pc
assert_rc "no subcommand exits 2" 2
assert_contains "no subcommand prints the usage" "usage: scripts/papercut.sh add"
pc frobnicate
assert_rc "an unknown subcommand exits 2" 2
pc help
assert_rc "help exits 0" 0
assert_contains "the usage states the privacy rule" "no prompt text, no file contents, no secrets, no private names"

# --- missing, empty, repeated and invalid fields: exit 2, nothing written ---
ALL=(--tool t.sh --tried "ran it" --expected "exit 1" --got "exit 0" --fix "check the status" --refusal none)
for (( i = 0; i < ${#ALL[@]}; i += 2 )); do
  flag="${ALL[$i]}"
  ARGS=("${ALL[@]:0:$i}" "${ALL[@]:$((i + 2))}")
  pc add "${ARGS[@]}"
  assert_rc "missing $flag exits 2" 2
  assert_contains "missing $flag is named" "papercut: $flag is required"
  ARGS=("${ALL[@]:0:$i}" "$flag" "  " "${ALL[@]:$((i + 2))}")
  pc add "${ARGS[@]}"
  assert_rc "blank $flag exits 2" 2
  assert_contains "blank $flag is named" "papercut: $flag is empty"
done
pc add "${ALL[@]:0:11}" maybe
assert_rc "an invalid --refusal exits 2" 2
assert_contains "an invalid --refusal names the choices" 'papercut: --refusal must be correct, wrong or none (got "maybe")'
pc add "${ALL[@]}" --tool again
assert_rc "a repeated flag exits 2" 2
assert_contains "a repeated flag is named" "papercut: --tool given twice"
pc add "${ALL[@]}" --color red
assert_rc "an unknown flag exits 2" 2
assert_contains "an unknown flag is named" 'papercut: unknown argument "--color"'
pc add "${ALL[@]:0:10}" --refusal
assert_rc "a flag without a value exits 2" 2
assert_contains "a flag without a value is named" "papercut: --refusal needs a value"
X300="$(head -c 300 /dev/zero | tr '\0' 'x')"
add5 t.sh "ran it" "exit 1" "${X300}x" "check" none
assert_rc "a 301-character field exits 2" 2
assert_contains "a 301-character field is refused, not cut" "papercut: --got is 301 characters; the limit is 300"
run env PAPERCUT_NOW=yesterday bash "$FIX/scripts/papercut.sh" add "${ALL[@]}"
assert_rc "a PAPERCUT_NOW that is not a time exits 2" 2
assert_eq "no refused add wrote a line" 0 "$(lines)"

# --- add: schema, extremes, escaping ---
add5 t.sh "ran it" "exit 1" "$X300" "check" wrong
assert_rc "a 300-character field is accepted" 0
assert_contains "add reports the count" "papercut: filed (1 entries"
assert_eq "one line written" 1 "$(lines)"
assert_eq "the 300 characters are stored whole" "$X300" "$(field got)"
assert_eq "ts is the injected UTC time" "2026-11-20T10:00:00Z" "$(field ts)"
assert_eq "refusal is stored" "wrong" "$(field refusal)"
assert_eq "only the given fields are stored" "expected,fix,got,refusal,tool,tried,ts,v" \
  "$("$PY" -c 'import json,sys;print(",".join(sorted(json.loads(open(sys.argv[1]).readline()))))' "$LOG")"
assert_eq "the folder ignores itself" "*" "$(cat "$FIX/.work/papercuts/.gitignore" 2>/dev/null)"
assert_eq "git status stays clean" "" "$(git status --short)"
# quotes, a backslash, a newline, a tab, and non-ASCII: e-acute (2 bytes) 300 times is 300 characters
ODD="say \"hi\" it's C:\\dir\\n"$'\n\t'"caf$(printf '\303\251') $(printf '\346\227\245')"
EA300="$(head -c 300 /dev/zero | tr '\0' 'e' | sed "s/e/$(printf '\303\251')/g")"
add5 "--tool" "$ODD" "--expected" "$EA300" "$ODD" none
assert_rc "odd characters and flag-like values are accepted" 0
assert_eq "quotes, backslashes, newline and non-ASCII round-trip" "$ODD" "$(field tried)"
assert_eq "300 two-byte characters are within the limit" "$EA300" "$(field got)"
assert_eq "a value that looks like a flag is a value" "--tool" "$(field tool)"
assert_eq "a newline in a field stays inside one JSON line" 2 "$(lines)"

# --- list: groups, counts, newest first, the correct-refusal section, a malformed line ---
rm -f "$LOG"
PAPERCUT_NOW=2026-11-20T10:00:00Z add5 dream.sh "digest --since x" "a usage error" "exit 0  and no output" "reject unknown flags" none
PAPERCUT_NOW=2026-11-20T11:00:00Z add5 check.sh "ran it under POSIX" "a pass" "dash scan fails" "set the locale" none
PAPERCUT_NOW=2026-11-20T12:00:00Z add5 dream.sh "digest --until y" "a usage error" "exit 0 and no output" "newest fix" wrong
PAPERCUT_NOW=2026-11-20T13:00:00Z add5 guard.sh "rm -rf build" "allowed" "refused" "nothing" correct
PAPERCUT_NOW=2026-11-20T14:00:00Z add5 guard.sh "rm -rf dist" "allowed" "refused" "nothing" correct
printf '%s\n' '{not json' '{"tool":"x"}' >> "$LOG"
pc list
assert_rc "list exits 0" 0
assert_contains "list totals" "papercuts: 3 entries in 2 groups; correct refusals: 2 entries in 1 groups; malformed lines skipped: 2"
assert_contains "same tool and same got after whitespace normalization are one group, newest details" \
  "- 2x dream.sh: exit 0 and no output (last 2026-11-20T12:00:00Z; refusal: wrong 1, none 1)"
assert_contains "the group shows its newest fix" "fix: newest fix"
assert_contains "a single entry is a group of one" "- 1x check.sh: dash scan fails (last 2026-11-20T11:00:00Z; refusal: none 1)"
assert_contains "correct refusals have their own section" "## Correct refusals (not defects)"
assert_contains "and are grouped there" "- 2x guard.sh: refused (last 2026-11-20T14:00:00Z)"
ORDER="$(printf '%s\n' "$OUT" | grep -o '^## [A-Z][a-z]*\|^- [0-9]x [a-z]*' | tr '\n' ',')"
assert_eq "groups newest first, correct refusals after the defects" "## Defect,- 2x dream,- 1x check,## Correct,- 2x guard," "$ORDER"

# --- cap: 200 entries, the oldest dropped, one stderr line ---
rm -f "$LOG"
for n in $(seq 1 204); do
  printf '{"v":1,"ts":"2026-11-19T00:00:00Z","tool":"seed","tried":"t","expected":"e","got":"g%d","fix":"f","refusal":"none"}\n' "$n"
done > "$LOG"
ERR="$(bash "$FIX/scripts/papercut.sh" add "${ALL[@]}" 2>&1 >/dev/null)"
assert_eq "past the cap one stderr line says how many were dropped" "papercut: log is capped at 200 entries; dropped the 5 oldest" "$ERR"
assert_eq "the log holds 200 entries" 200 "$(lines)"
assert_eq "the new entry is last" "t.sh" "$(field tool)"
assert_eq "the oldest kept is the sixth" '"got":"g6"' "$(sed -n 1p "$LOG" | grep -o '"got":"g[0-9]*"')"
ERR="$(bash "$FIX/scripts/papercut.sh" add "${ALL[@]}" 2>&1 >/dev/null)"
assert_eq "at the cap one more add drops one" "papercut: log is capped at 200 entries; dropped the 1 oldest" "$ERR"
# A log whose last line has no newline: the new entry starts its own line.
printf '{"partial' > "$LOG"
pc add "${ALL[@]}"
assert_eq "a partial last line does not swallow the new entry" "t.sh" "$(field tool)"

# --- a linked worktree files into the main checkout's log ---
rm -f "$LOG"
git worktree add -q "$FIX-wt" -b wt >/dev/null 2>&1
run bash "$FIX-wt/scripts/papercut.sh" add "${ALL[@]}"
assert_rc "add from a linked worktree exits 0" 0
assert_eq "it lands in the main checkout's log" 1 "$(lines)"
assert_no_file "and not in the worktree" "$FIX-wt/.work/papercuts"

# --- no python: a clear failure, never silent ---
run env PATH=/nonexistent "$BASH" "$FIX/scripts/papercut.sh" add "${ALL[@]}"
assert_rc "no python: exits 2" 2
assert_contains "no python: says so" "papercut: python not found"
assert_eq "no python: nothing written" 1 "$(lines)"

t_finish
