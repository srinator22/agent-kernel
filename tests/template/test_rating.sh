#!/usr/bin/env bash
# rating.sh: the labelled numbers behind a template rating, on a fixture template
# with a backlog, lessons, skills, tags, a maintain log and a two-project fleet.
# gh is a fake on PATH (L011), each faked command backed by one recorded real
# response (public CI metadata of the template repository, 2026-11-17):
#   gh run list --branch main --limit 1 --json conclusion,headSha
#     [{"conclusion":"success","headSha":"6e3e70b1efb0ef968c188c50166cffc195d7d726"}]
#   gh pr list --state merged --limit 3 --json createdAt,mergedAt
#     [{"createdAt":"2026-11-10T10:13:17Z","mergedAt":"2026-11-10T11:04:18Z"},{"createdAt":"2026-11-10T08:38:55Z","mergedAt":"2026-11-10T09:48:29Z"},{"createdAt":"2026-11-10T05:25:44Z","mergedAt":"2026-11-10T07:46:44Z"}]
#   (the real output carries no trailing newline; the fake keeps that)
# Durations of the recorded PRs: 51m01s, 1h09m34s, 2h21m00s; median 1h09m34s.
# Recorded: gh run list --branch main --limit 1 --json conclusion,headSha -> [{"conclusion":"success","headSha":"6e3e70b1efb0ef968c188c50166cffc195d7d726"}] (real, re-run 2026-11-18, same output)
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" || { echo "$0: cannot load lib.sh; stopped before writing anything" >&2; exit 2; }

make_fixture
cp_script rating.sh fleet-status.sh lessons.sh
printf '# Agents\n' > AGENTS.md
mkdir -p docs/lessons docs/rules .claude/skills
for s in adr dream maintain retro ship start template-update; do mkdir -p ".claude/skills/$s"; printf '# s\n' > ".claude/skills/$s/SKILL.md"; done
cat > BACKLOG.md <<'BL'
# Backlog

| Item | Priority | Reason | Status |
| ---- | -------- | ------ | ------ |
| open one | P1 | r | open |
| open two | P2 (soon) | r | open |
| open three | P2 | r | open |
| has a | pipe in the item | P3 | r | open |
| odd | later | r | open |
| finished | P1 | r | done 2026-11-17 (x) |
| waiting | P0 | r | blocked |
BL
cat > docs/lessons/INDEX.md <<'IX'
# Lessons index

- [L001] one thing - do it (used: 0, last: -, retire-when: never)
- [L002] other thing - do that (used: 3, last: 2026-11-01, retire-when: never)
IX
printf 'template-sync: x 2026-02-02\n2026-10-20 expire: L009 archived\n2026-11-05 maintain pass: nothing to do\ntemplate-sync: y 2026-11-30\n' > docs/lessons/MAINTENANCE.log
git remote add origin https://github.com/example/tmpl.git
git add -A >/dev/null 2>&1 && git commit -q -m one && git tag template-v0.1.0
printf 'x\n' > x.txt; git add -A >/dev/null 2>&1 && git commit -q -m two && git tag template-v0.2.0

PRJ="$FIX/projects"
mkproj() {
  mkdir -p "$1"; git init -q "$1" >/dev/null 2>&1
  printf '# P\n%s\n' "$2" > "$1/AGENTS.md"
}
mkproj "$PRJ/alpha" "- Template: https://github.com/example/tmpl.git template-v0.1.0"
mkproj "$PRJ/beta" "- Template: https://github.com/example/tmpl.git template-v0.2.0"
printf '%s\n%s\n%s\n' "$PRJ/alpha" "$PRJ/beta" "$PRJ/gone" > fleet.local.list

BIN="$FIX/bin"; mkdir -p "$BIN"
cat > "$BIN/gh" <<'GH'
#!/usr/bin/env bash
echo "$*" >> "$GH_LOG"
RUN='[{"conclusion":"success","headSha":"6e3e70b1efb0ef968c188c50166cffc195d7d726"}]'
PRS='[{"createdAt":"2026-11-10T10:13:17Z","mergedAt":"2026-11-10T11:04:18Z"},{"createdAt":"2026-11-10T08:38:55Z","mergedAt":"2026-11-10T09:48:29Z"},{"createdAt":"2026-11-10T05:25:44Z","mergedAt":"2026-11-10T07:46:44Z"}]'
if [[ -n "${GH_RUN+x}" ]]; then RUN="$GH_RUN"; fi
if [[ -n "${GH_PRS+x}" ]]; then PRS="$GH_PRS"; fi
case "$*" in
  "run list --branch main --limit 1 --json conclusion,headSha") printf '%s' "$RUN" ;;
  "pr list --state merged --limit 30 --json createdAt,mergedAt") printf '%s' "$PRS" ;;
  *) echo "fake gh: unexpected $*" >&2; exit 2 ;;
esac
GH
chmod +x "$BIN/gh"
export GH_LOG="$FIX/gh.log"; : > "$GH_LOG"
export PATH="$BIN:$PATH"

run scripts/rating.sh
assert_rc "rating runs" 0
assert_contains "P0 open count" "backlog open P0: 0"
assert_contains "P1 open count (done row excluded)" "backlog open P1: 1"
assert_contains "P2 open count (token 'P2' with a note)" "backlog open P2: 2"
assert_contains "P3 open count (pipe inside the item)" "backlog open P3: 1"
assert_contains "open row without priority" "backlog open without a P0-P3 priority: 1"
assert_contains "lesson slots and unused" "approved lessons: 2/20 (never used: 1)"
assert_contains "skills against cap" "skills: 7 (cap"
assert_contains "last maintain pass ignores template-sync lines" "last maintain pass: 2026-11-05"
assert_contains "latest tag by version" "latest template tag: template-v0.2.0"
assert_contains "CI status" "CI status of main: success (6e3e70b)"
assert_contains "cycle time median of three" "1h 9m (n=3)"
assert_contains "fleet alpha behind 1" "fleet: alpha ref=template-v0.1.0 synced=- behind=1 state=ok"
assert_contains "fleet beta behind 0" "fleet: beta ref=template-v0.2.0 synced=- behind=0 state=ok"
assert_contains "fleet missing" "fleet: gone ref=- synced=- behind=- state=missing"
assert_contains "fleet count" "fleet projects: 3"
assert_not_contains "no fabricated N/A when data exists" "N/A"

: > "$GH_LOG"
run scripts/rating.sh --offline
assert_rc "--offline runs" 0
assert_contains "offline CI" "CI status of main: N/A - gh unavailable/offline"
assert_contains "offline cycle time" "last 30 merged): N/A - gh unavailable/offline"
assert_eq "--offline never calls gh" "" "$(cat "$GH_LOG")"

GH_RUN='[]' GH_PRS='[]' run scripts/rating.sh
assert_contains "no run on main" "CI status of main: N/A - no workflow run on main"
assert_contains "no merged PRs" "N/A - no merged PRs"
GH_RUN='[{"conclusion":"","headSha":"abcdef1234"}]' run scripts/rating.sh
assert_contains "unfinished run" "CI status of main: N/A - latest run not finished (abcdef1)"
GH_PRS='[{"createdAt":"2026-11-10T00:00:00Z","mergedAt":"2026-11-10T01:00:00Z"},{"createdAt":"2026-12-31T23:00:00Z","mergedAt":"2027-01-01T01:00:00Z"}]' run scripts/rating.sh
assert_contains "median of two is their mean, across a year end" "1h 30m (n=2)"

# gh failing (not logged in, no network): N/A, not a failure.
printf '#!/usr/bin/env bash\nexit 1\n' > "$BIN/gh"; chmod +x "$BIN/gh"
run scripts/rating.sh
assert_rc "failing gh still exits 0" 0
assert_contains "failing gh CI" "CI status of main: N/A - gh unavailable/offline"

# Missing inputs print N/A with a reason.
rm -f fleet.local.list BACKLOG.md docs/lessons/MAINTENANCE.log
run scripts/rating.sh --offline
assert_rc "missing inputs exit 0" 0
assert_contains "no backlog" "backlog open: N/A - BACKLOG.md missing"
assert_contains "no maintain log" "last maintain pass: N/A - no maintain pass recorded"
assert_contains "no fleet list" "fleet: N/A - scripts/fleet-status.sh failed"

run scripts/rating.sh --bogus
assert_rc "unknown option exits 2" 2
run scripts/rating.sh --help
assert_rc "--help exits 0" 0

t_check_exec rating
t_finish
