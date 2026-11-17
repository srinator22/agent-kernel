#!/usr/bin/env bash
# scripts/dream.sh fleet (scripts/dream/fleet.py): the read-only fleet dream digest over
# synthetic fixture projects: open UPSTREAM.md entries (headed, unheaded, the empty format
# block), the newest dream reports, a project with no UPSTREAM.md, a missing path, a
# relative line, a duplicate line, CRLF and comments in the list, the byte caps and their
# cut notices, transcripts off by default and on with --transcripts (offsets committed by
# done), the template-mode and usage refusals, and that no project file changes, .git
# included. Without python the test is skipped (CI has python3).
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" || { echo "$0: cannot load lib.sh; stopped before writing anything" >&2; exit 2; }

. "$T_ROOT/scripts/find-python.sh"
if [[ -z "$PY" ]]; then
  t_ok "python not found; fleet dream tests skipped (CI runs them)"
  t_finish
fi

make_fixture
cp_script dream.sh find-python.sh dream/dream.py dream/fleet.py
export DREAM_NOW="2026-11-17T12:00:00Z"
# Python reads the list file's lines as written, so they carry the native spelling.
native() { cygpath -m "$1" 2>/dev/null || printf '%s\n' "$1"; }

# Projects and the fake transcript folder sit beside the fixture, not inside it, so
# git in the fixture never sees them.
OUTSIDE="$(mktemp -d "${TMPDIR:-/tmp}/template-selftest.fleet.XXXXXX")"
[[ -n "$OUTSIDE" && -d "$OUTSIDE" ]] || { t_bad "no temp folder for the fixture projects"; t_finish; }
cleanup_extra() { case "$OUTSIDE" in */template-selftest.fleet.*) rm -rf "$OUTSIDE" ;; esac; }
trap 'cleanup_extra; t_exit' EXIT
PRJ="$OUTSIDE/projects"
export DREAM_PROJECTS_DIR="$OUTSIDE/claude-projects"
mkdir -p "$DREAM_PROJECTS_DIR/some-folder"

mkproj() { # dir templateline
  mkdir -p "$1/docs/lessons"
  git init -q "$1" >/dev/null 2>&1
  git -C "$1" config user.email t@example.invalid
  git -C "$1" config user.name t
  git -C "$1" config core.autocrlf false
  printf '# P\n\n## Project decisions\n\n%s\n' "$2" > "$1/AGENTS.md"
  printf 'template-sync: template-v0.1.0 2026-10-01\ntemplate-sync: template-v0.2.0 2026-11-01\n' > "$1/docs/lessons/MAINTENANCE.log"
  git -C "$1" add -A >/dev/null 2>&1
  git -C "$1" commit -q -m init >/dev/null 2>&1
}

mkproj "$PRJ/alpha" "- Template: https://x.invalid/t.git template-v0.2.0"
cat > "$PRJ/alpha/docs/lessons/UPSTREAM.md" <<'EOF'
# Upstream lessons - process lessons to send to the template

Entry format (all five fields required):

- what happened:
- what check should have caught it:
- what was added:
- retire-when:
- applies to: core | <profile name>

### Synthetic headed entry
- what happened: the widget check ran twice per task
- what check should have caught it: a counter in the gate
- what was added: none
- retire-when: the gate counts runs
- applies to: core

- what happened: an unheaded entry about slow fixtures
- what check should have caught it: none
- what was added: none
- retire-when: fixtures are cached
- applies to: core
EOF
mkdir -p "$PRJ/alpha/.work/dream"
for d in 2026-11-01 2026-11-08 2026-11-10; do
  printf '# Dream report %s\nRead: 3 signals\n## Proposals\n1. [mechanize] synthetic proposal from %s\n' "$d" "$d" > "$PRJ/alpha/.work/dream/$d-report.md"
done
printf 'not a report\n' > "$PRJ/alpha/.work/dream/digest.md"

mkproj "$PRJ/beta" "- Template: https://x.invalid/t.git template-v0.1.0 with prose"

mkproj "$PRJ/gamma" "- Template: https://x.invalid/t.git template-v0.2.0"
{
  printf '### Long entry\n- what happened: '
  for i in $(seq 1 120); do printf 'word%03d ' "$i"; done
  printf '\n- applies to: core\n'
  for i in $(seq 1 12); do
    printf '\n### Entry %02d\n- what happened: ' "$i"
    for j in $(seq 1 60); do printf 'filler%02d ' "$j"; done
    printf '\n- applies to: core\n'
  done
} > "$PRJ/gamma/docs/lessons/UPSTREAM.md"

LIST="$FIX/fleet.local.list"
{
  printf '# synthetic fleet\r\n\r\n'
  printf '%s\r\n' "$(native "$PRJ/alpha")" "$(native "$PRJ/beta")" "$(native "$PRJ/gone")" "relative/path" "$(native "$PRJ/alpha")"
} > "$LIST"

snapshot() { (cd "$PRJ" && find . -type f -print0 | sort -z | xargs -0 cksum); }
BEFORE="$(snapshot)"
DIGEST="$FIX/.work/dream/fleet/digest.md"

# Default run: the root's list, the default state folder, transcripts off.
run scripts/dream.sh fleet
assert_rc "fleet digest runs" 0
assert_contains "prints where the digest went" "fleet: digest "
assert_contains "summary counts" "4 projects (2 read, 2 missing or bad), 2 open entries, 2 reports, 0 signals shown"
assert_file "digest written under .work/dream/fleet" "$DIGEST"
assert_file_has "the state folder ignores itself" "$FIX/.work/dream/.gitignore" "*"
assert_eq "the digest folder never shows in git status" "" "$(git status --porcelain --untracked-files=all | grep -F '.work' || true)"
assert_eq "no project file changed, .git included" "$BEFORE" "$(snapshot)"
OUT="$(cat "$DIGEST")"
assert_contains "header counts" "projects: 4 listed, 2 read, 2 missing or bad, 1 duplicate lines skipped"
assert_contains "transcripts off by default" "transcripts: off (pass --transcripts"
assert_not_contains "no transcript section by default" "### Transcript signals"
assert_contains "first project id" "## p1 alpha"
assert_contains "template ref" "template: template-v0.2.0  synced: template-v0.2.0"
assert_contains "two open entries" "### UPSTREAM.md: 2 open entries"
assert_contains "headed entry keeps its title" "- p1.u1 Synthetic headed entry"
assert_contains "headed entry quoted" "  | - what happened: the widget check ran twice per task"
assert_contains "unheaded entry" "- p1.u2 (no heading)"
assert_contains "unheaded entry quoted" "  | - what happened: an unheaded entry about slow fixtures"
assert_not_contains "the empty format block is no entry" "p1.u3"
assert_contains "reports found and shown" "### Dream reports: 3 found, newest 2 shown"
assert_contains "newest report first" "- p1.r1 2026-11-10-report.md"
assert_contains "second newest report" "- p1.r2 2026-11-08-report.md"
assert_not_contains "oldest report left out" "2026-11-01-report.md"
assert_not_contains "digest.md is no report" "not a report"
assert_contains "report text quoted" "  | 1. [mechanize] synthetic proposal from 2026-11-10"
if grep -q '^# Dream report' "$DIGEST"; then t_bad "a report heading passes for a digest heading"; else t_ok "report headings stay quoted"; fi
assert_contains "malformed Template line named" "## p2 beta"
assert_contains "beta template line" "template: malformed Template line"
assert_contains "no UPSTREAM.md said" "### UPSTREAM.md: none"
assert_contains "no reports said" "### Dream reports: none"
assert_contains "missing project" "status: MISSING (no folder or no AGENTS.md); nothing read"
assert_contains "relative line" "status: BAD-LINE (not an absolute path); nothing read"
assert_not_contains "duplicate line not repeated" "## p5"

# Caps: one large project under a small cap; every cut says what it left out.
printf '%s\n' "$(native "$PRJ/gamma")" > "$FIX/gamma.list"
run scripts/dream.sh fleet --list "$FIX/gamma.list" --max-bytes 3000
assert_rc "capped run" 0
OUT="$(cat "$DIGEST")"
assert_contains "13 open entries counted" "### UPSTREAM.md: 13 open entries"
assert_contains "a long entry says how much it shows" "bytes shown]"
assert_contains "entries past the cap are counted" "entries not shown, section cap 3000 bytes]"
size="$(wc -c < "$DIGEST" | tr -d ' ')"
if (( size <= 3000 + 1200 )); then t_ok "digest stays near the cap ($size bytes)"; else t_bad "digest $size bytes for a 3000-byte cap"; fi
run scripts/dream.sh fleet --list "$FIX/gamma.list" --max-bytes 1999
assert_rc "--max-bytes below 2000 refused" 2
assert_contains "--max-bytes refusal names the floor" "at least 2000"

# Transcripts: only with --transcripts; each line once, after done.
CWD="$(native "$PRJ/alpha")"
printf '{"timestamp":"2026-11-15T10:00:00Z","cwd":"%s","gitBranch":"main","sessionId":"aaaa1111","type":"user","message":{"role":"user","content":"synthetic owner message for the fleet"}}\n' "$CWD" > "$DREAM_PROJECTS_DIR/some-folder/aaaa1111.jsonl"
printf '{"timestamp":"2026-11-15T11:00:00Z","cwd":"%s","gitBranch":"main","sessionId":"bbbb2222","type":"user","message":{"role":"user","content":"message from an unlisted project"}}\n' "$(native "$OUTSIDE/elsewhere")" > "$DREAM_PROJECTS_DIR/some-folder/bbbb2222.jsonl"
BEFORE="$(snapshot)"
run scripts/dream.sh fleet --transcripts
assert_rc "transcripts run" 0
assert_contains "one signal shown" ", 1 signals shown"
OUT="$(cat "$DIGEST")"
assert_contains "transcripts on in the header" "transcripts: on"
assert_contains "the project's signal" "- p1.s1 [U] 2026-11-15 10:00 aaaa1111 main: synthetic owner message for the fleet"
assert_not_contains "an unlisted project's signal is not read" "message from an unlisted project"
assert_contains "beta has no signals" "### Transcript signals: 0 from 0 sessions"
assert_eq "transcripts leave every project file unchanged" "$BEFORE" "$(snapshot)"
run scripts/dream.sh fleet --transcripts
OUT="$(cat "$DIGEST")"
assert_contains "without done the same signal is offered again" "synthetic owner message for the fleet"
run scripts/dream.sh fleet done
assert_rc "done" 0
assert_contains "done commits the offsets" "transcript offsets committed for 2 projects"
run scripts/dream.sh fleet --transcripts
OUT="$(cat "$DIGEST")"
assert_not_contains "after done the line is not read again" "synthetic owner message for the fleet"
assert_contains "the last fleet dream is recorded" "last fleet dream: 2026-11-17T12:00:00Z"

# Refusals: no list file, unknown action, start has run here.
run scripts/dream.sh fleet --list "$FIX/no-such.list"
assert_rc "missing list refused" 2
assert_contains "missing list named" "no list file"
run scripts/dream.sh fleet sideways
assert_rc "unknown action refused" 2
touch .start-done
run scripts/dream.sh fleet
assert_rc "refused once start has run" 2
assert_contains "refusal says template only" "run this in the template repository"
rm -f .start-done

t_finish
