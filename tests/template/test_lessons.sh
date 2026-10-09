#!/usr/bin/env bash
# lessons.sh: lesson cap, required fields, PENDING and QUARANTINE entries,
# skills mirror and cap, rules file size, use, expire --apply, stats.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

make_fixture
cp_script lessons.sh
export LESSONS_TODAY=2026-10-09
mkdir -p docs/lessons docs/rules .claude/skills/alpha .agents/skills/alpha
echo "# alpha" > .claude/skills/alpha/SKILL.md
echo "# alpha" > .agents/skills/alpha/SKILL.md
echo "one line" > docs/rules/small.md

INDEX_HEAD='# Lessons index

Format:

- [L001] <one-line, situation-triggered description> - <the lesson, one
  or two lines> (used: 0, last: -, retire-when: <condition>)
'
write_index() { printf '%s\n' "$INDEX_HEAD" > docs/lessons/INDEX.md; }
add_lesson() { # id used last retire
  echo "- [$1] When X happens - do Y (used: $2, last: $3, retire-when: $4)" >> docs/lessons/INDEX.md
}
PENDING_HEAD='# Pending

Entry format (all four fields required):

- what happened:
- what check should have caught it:
- what was added:
- retire-when:

No pending lessons.'
QUAR_HEAD='# Quarantine

Entry format:

- test path:
- observed flake behavior:
- date quarantined:
- owner task (BACKLOG.md item or task slug):

No quarantined tests.'
write_index
printf '%s\n' "$PENDING_HEAD" > docs/lessons/PENDING.md
printf '%s\n' "$QUAR_HEAD" > docs/lessons/QUARANTINE.md

run ./scripts/lessons.sh check
assert_rc "pristine files pass (placeholders ignored)" 0
assert_contains "reports zero approved lessons" "0/20 approved"

# Cap of 20.
write_index
for i in $(seq -f "L%03g" 1 20); do add_lesson "$i" 0 2026-10-01 "never"; done
run ./scripts/lessons.sh check
assert_rc "20 approved lessons pass" 0
add_lesson L021 0 2026-10-01 "never"
run ./scripts/lessons.sh check
assert_rc "21 approved lessons fail" 1
assert_contains "cap is named" "hard cap is 20"

# Missing fields.
write_index
echo "- [L001] When X happens - do Y (used: 0, last: -)" >> docs/lessons/INDEX.md
run ./scripts/lessons.sh check
assert_rc "lesson without retire-when fails" 1
assert_contains "names the lesson and the fields" "L001 lacks the (used: N, last: ..., retire-when: ...) fields"
write_index
echo "- [L001] When X happens - do Y" >> docs/lessons/INDEX.md
run ./scripts/lessons.sh check
assert_rc "lesson with no fields fails" 1
write_index
add_lesson L001 0 - "never"
add_lesson L001 0 - "never"
run ./scripts/lessons.sh check
assert_rc "duplicate lesson id fails" 1
write_index
echo "- [L001] When X happens - do Y (used: 0, last: 2026-13-45, retire-when: never)" >> docs/lessons/INDEX.md
run ./scripts/lessons.sh check
assert_rc "invalid last date fails" 1

# PENDING entries.
write_index
printf '%s\n' "$PENDING_HEAD" > docs/lessons/PENDING.md
cat >> docs/lessons/PENDING.md <<'PE'

- what happened: a thing
- what check should have caught it: a test
- what was added: nothing yet
PE
run ./scripts/lessons.sh check
assert_rc "pending entry missing retire-when fails" 1
assert_contains "names the missing field" "retire-when"
echo "- retire-when: the test exists" >> docs/lessons/PENDING.md
run ./scripts/lessons.sh check
assert_rc "complete pending entry passes" 0
printf '%s\n' "$PENDING_HEAD" > docs/lessons/PENDING.md

# QUARANTINE entries.
printf '%s\n' "$QUAR_HEAD" > docs/lessons/QUARANTINE.md
cat >> docs/lessons/QUARANTINE.md <<'QU'

- test path: tests/flaky.test
- observed flake behavior: fails 1 in 5
- date quarantined: 2026-08-01
- owner task (BACKLOG.md item or task slug):
QU
run ./scripts/lessons.sh check
assert_rc "old quarantine entry without owner fails" 1
assert_contains "age is reported" "days old (> 30) with no owner task"
sed -i.bak '$ s/^- owner task.*/- owner task (BACKLOG.md item or task slug): fix-flaky/' docs/lessons/QUARANTINE.md && rm -f docs/lessons/QUARANTINE.md.bak
run ./scripts/lessons.sh check
assert_rc "old quarantine entry with an owner passes" 0
sed -i.bak -e 's/2026-08-01/2026-10-01/' -e 's/^- owner task.*/- owner task (BACKLOG.md item or task slug):/' docs/lessons/QUARANTINE.md && rm -f docs/lessons/QUARANTINE.md.bak
run ./scripts/lessons.sh check
assert_rc "recent quarantine entry without owner passes" 0
printf '%s\n' "$QUAR_HEAD" > docs/lessons/QUARANTINE.md

# Skills mirror.
echo "# drifted" > .agents/skills/alpha/SKILL.md
run ./scripts/lessons.sh check
assert_rc "skills mirror drift fails" 1
assert_contains "drift is named" "differ"
echo "# alpha" > .agents/skills/alpha/SKILL.md
run ./scripts/lessons.sh check
assert_rc "mirrored skills pass" 0

# Skills cap: 8 core plus declared profile skill sets.
for i in 2 3 4 5 6 7 8 9; do
  mkdir -p ".claude/skills/s$i" ".agents/skills/s$i"
  echo "# s$i" > ".claude/skills/s$i/SKILL.md"; echo "# s$i" > ".agents/skills/s$i/SKILL.md"
done
run ./scripts/lessons.sh check
assert_rc "9 skills with no profile skill set fail" 1
assert_contains "cap of 8 is named" "the cap is 8"
mkdir -p docs/profiles/p1
printf 'Profile p1\nSkills: s9-extra\n' > docs/profiles/p1/PROFILE.md
run ./scripts/lessons.sh check
assert_rc "9 skills with one declared profile skill set pass" 0
printf -- '- Profiles: other\n' > AGENTS.md
run ./scripts/lessons.sh check
assert_rc "a profile that is not adopted does not raise the cap" 1
printf -- '- Profiles: p1\n' > AGENTS.md
run ./scripts/lessons.sh check
assert_rc "an adopted profile raises the cap" 0
rm -rf docs/profiles AGENTS.md .claude/skills/s9 .agents/skills/s9
run ./scripts/lessons.sh check
assert_rc "8 skills pass" 0

# Skills cap counts the skills a profile lists, not one per profile.
for i in 9 10 11; do
  mkdir -p ".claude/skills/s$i" ".agents/skills/s$i"
  echo "# s$i" > ".claude/skills/s$i/SKILL.md"; echo "# s$i" > ".agents/skills/s$i/SKILL.md"
done
mkdir -p docs/profiles/p3
printf 'Profile p3\n- Skills: ska, skb, skc\n' > docs/profiles/p3/PROFILE.md
run ./scripts/lessons.sh check
assert_rc "11 skills with a profile listing three pass" 0
mkdir -p .claude/skills/s12 .agents/skills/s12
echo "# s12" > .claude/skills/s12/SKILL.md; echo "# s12" > .agents/skills/s12/SKILL.md
run ./scripts/lessons.sh check
assert_rc "12 skills with a profile listing three fail" 1
assert_contains "the cap formula prints its figures" "the cap is 11 (8 core + 3 skills listed by the adopted profiles = 11"
printf 'Profile p3\n- Skills: ska, skb,\n  skc (a note, with a comma), skd\n' > docs/profiles/p3/PROFILE.md
run ./scripts/lessons.sh check
assert_rc "a list wrapped onto a second line counts four" 0
printf 'Profile p3\n- Skills: ska, skb, skc,\n  skd (`a note`);\n  the rest of the sentence.\n' > docs/profiles/p3/PROFILE.md
run ./scripts/lessons.sh check
assert_rc "a list ending in a parenthetical and a semicolon still counts four" 0
run ./scripts/lessons.sh stats
assert_contains "stats shows the four declared skills" "8 core + 4 skills"
printf 'Profile p3\nSkills: none\n' > docs/profiles/p3/PROFILE.md
run ./scripts/lessons.sh check
assert_rc "Skills: none adds nothing" 1
rm -rf docs/profiles .claude/skills/s9 .claude/skills/s10 .claude/skills/s11 .claude/skills/s12
rm -rf .agents/skills/s9 .agents/skills/s10 .agents/skills/s11 .agents/skills/s12
run ./scripts/lessons.sh check
assert_rc "back to 8 skills passes" 0

# Agent mirror: every .claude agent has a Codex twin or a named exception.
mkdir -p .claude/agents .codex/agents
echo "x" > .claude/agents/reviewer.md
run ./scripts/lessons.sh check
assert_rc "an agent with no Codex twin fails" 1
assert_contains "the missing twin is named" ".claude/agents/reviewer.md has no .codex/agents/reviewer.toml"
echo "x" > .codex/agents/reviewer.toml
run ./scripts/lessons.sh check
assert_rc "an agent with a Codex twin passes" 0
echo "x" > .claude/agents/explore.md
run ./scripts/lessons.sh check
assert_rc "a second agent with no twin fails" 1
printf 'explore: no Codex counterpart, Codex has a built-in explorer\n' > docs/rules/models.md
run ./scripts/lessons.sh check
assert_rc "a named exception in models.md passes" 0
printf 'the explore agent is mentioned here only\n' > docs/rules/models.md
run ./scripts/lessons.sh check
assert_rc "a mention without the exception wording fails" 1
rm -rf .claude/agents .codex docs/rules/models.md

# tests/quarantine.list: owner and date required, at most 30 days old.
mkdir -p tests
printf '%s\n' '# comment line' '' > tests/quarantine.list
run ./scripts/lessons.sh check
assert_rc "an empty quarantine list passes" 0
printf '%s\n' 'tests/flaky_a.test # owner: fix-flaky date: 2026-10-01' >> tests/quarantine.list
run ./scripts/lessons.sh check
assert_rc "a recent entry with owner and date passes" 0
printf '%s\n' 'tests/flaky_b.test # owner: fix-old date: 2026-08-01' > tests/quarantine.list
run ./scripts/lessons.sh check
assert_rc "an entry older than 30 days fails" 1
assert_contains "the old entry is named with its age" "tests/flaky_b.test' is 69 days old (> 30)"
printf '%s\n' 'tests/flaky_c.test # date: 2026-10-01' > tests/quarantine.list
run ./scripts/lessons.sh check
assert_rc "an entry without an owner fails" 1
assert_contains "the missing owner is named" "tests/flaky_c.test' has no owner"
printf '%s\n' 'tests/flaky_d.test # owner: fix-d date:' > tests/quarantine.list
run ./scripts/lessons.sh check
assert_rc "an entry without a date fails" 1
assert_contains "the missing date is named" "tests/flaky_d.test' has no valid date"
printf '%s\n' 'tests/flaky_e.test # owner: fix-e date: 2026-13-45' > tests/quarantine.list
run ./scripts/lessons.sh check
assert_rc "an entry with an invalid date fails" 1
printf '%s\n' 'tests/flaky_f.test' > tests/quarantine.list
run ./scripts/lessons.sh check
assert_rc "a bare path fails" 1
rm -f tests/quarantine.list
run ./scripts/lessons.sh check
assert_rc "no list passes" 0

# Rules file size.
seq 1 41 > docs/rules/big.md
run ./scripts/lessons.sh check
assert_rc "rules file of 41 lines fails" 1
assert_contains "names the file" "docs/rules/big.md has 41 lines"
seq 1 40 > docs/rules/big.md
run ./scripts/lessons.sh check
assert_rc "rules file of 40 lines passes" 0
rm -f docs/rules/big.md

# use.
write_index
add_lesson L001 0 - "never"
add_lesson L002 4 2026-09-01 "never"
run ./scripts/lessons.sh use L001
assert_rc "use succeeds" 0
assert_file_has "used incremented and last set" docs/lessons/INDEX.md "- [L001] When X happens - do Y (used: 1, last: 2026-10-09, retire-when: never)"
run ./scripts/lessons.sh use L001
assert_file_has "second use increments again" docs/lessons/INDEX.md "(used: 2, last: 2026-10-09, retire-when: never)"
assert_file_has "other lessons untouched" docs/lessons/INDEX.md "- [L002] When X happens - do Y (used: 4, last: 2026-09-01, retire-when: never)"
assert_file_has "format placeholder untouched" docs/lessons/INDEX.md "(used: 0, last: -, retire-when: <condition>)"
run ./scripts/lessons.sh use L999
assert_rc "use of an unknown lesson fails" 1
run ./scripts/lessons.sh use bogus
assert_rc "use with a bad id is a usage error" 2

# expire.
write_index
add_lesson L001 3 2026-01-01 "never"
add_lesson L002 3 2026-10-01 "never"
add_lesson L003 1 2026-10-05 "the fix ships [met]"
add_lesson L004 0 - "never"
run ./scripts/lessons.sh expire
assert_rc "expire dry run succeeds" 0
assert_contains "old lesson listed" "L001 - last used"
assert_contains "met lesson listed" "L003 - retire-when marked [met]"
assert_not_contains "fresh lesson not listed" "L002 -"
assert_contains "never-used lesson is only noted" "never used"
assert_file_has "dry run changed nothing" docs/lessons/INDEX.md "[L001]"
assert_no_file "dry run archived nothing" .archive/lessons/L001.md
run ./scripts/lessons.sh expire --apply
assert_rc "expire --apply succeeds" 0
assert_file "L001 archived" .archive/lessons/L001.md
assert_file "L003 archived" .archive/lessons/L003.md
assert_file_lacks "L001 removed from the index" docs/lessons/INDEX.md "- [L001] When X"
assert_file_lacks "L003 removed from the index" docs/lessons/INDEX.md "- [L003] When X"
assert_file_has "L002 kept" docs/lessons/INDEX.md "- [L002]"
assert_file_has "L004 kept" docs/lessons/INDEX.md "- [L004]"
assert_file_has "archive holds the original line" .archive/lessons/L001.md "- [L001] When X happens"
assert_file_has "maintenance log records L001" docs/lessons/MAINTENANCE.log "expire: L001 archived"
assert_file_has "maintenance log records the reason" docs/lessons/MAINTENANCE.log "retire-when marked [met]"
run ./scripts/lessons.sh expire
assert_contains "nothing left to expire" "nothing to expire"

# stats.
run ./scripts/lessons.sh stats
assert_rc "stats succeeds" 0
assert_contains "stats counts approved lessons" "approved lessons: 2/20"

run ./scripts/lessons.sh bogus
assert_rc "unknown subcommand is a usage error" 2

t_finish
