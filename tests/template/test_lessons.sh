#!/usr/bin/env bash
# lessons.sh: lesson cap, required fields, PENDING and QUARANTINE entries,
# skills mirror and cap, rules file size, use, expire --apply, stats.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" || { echo "$0: cannot load lib.sh; stopped before writing anything" >&2; exit 2; }

make_fixture
cp_script lessons.sh profiles.sh
export LESSONS_TODAY=2026-10-09
mkdir -p docs/lessons docs/rules .claude/skills/alpha .agents/skills/alpha
echo "# alpha" > .claude/skills/alpha/SKILL.md
echo "# alpha" > .agents/skills/alpha/SKILL.md
echo "one line" > docs/rules/small.md

INDEX_HEAD='# Lessons index

Format:

- [L001] <one-line, situation-triggered description> - <the lesson, one
  or two lines> (used: 0, last: -, approved: YYYY-MM-DD, retire-when: <condition>)
'
write_index() { printf '%s\n' "$INDEX_HEAD" > docs/lessons/INDEX.md; }
add_lesson() { # id used last retire [approved]
  echo "- [$1] When X happens - do Y (used: $2, last: $3, approved: ${5:-2026-10-01}, retire-when: $4)" >> docs/lessons/INDEX.md
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
assert_contains "names the lesson and the fields" "L001 lacks the (used: N, last: ..., approved: ..., retire-when: ...) fields"
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
echo "- [L001] When X happens - do Y (used: 0, last: 2026-13-45, approved: 2026-10-01, retire-when: never)" >> docs/lessons/INDEX.md
run ./scripts/lessons.sh check
assert_rc "invalid last date fails" 1

# approved: the date a lesson was approved (right after last:). Required and
# well formed; with used: 0 it must not be more than 45 days old (the
# mechanized form of the maintain rule "unused > 45 days").
write_index
add_lesson L001 0 - "never" 2026-08-25
run ./scripts/lessons.sh check
assert_rc "used 0, approved exactly 45 days ago passes" 0
write_index
add_lesson L001 0 - "never" 2026-08-24
run ./scripts/lessons.sh check
assert_rc "used 0, approved 46 days ago fails" 1
assert_contains "the stale unused lesson is named with its age" "L001 has used: 0 and was approved 46 days ago (> 45)"
assert_contains "the message says how to resolve it" "archive it in a maintain pass (scripts/lessons.sh expire --apply) or record a use (scripts/lessons.sh use L001)"
write_index
add_lesson L001 1 - "never" 2026-01-01
add_lesson L002 3 2026-09-01 "never" 2026-01-01
run ./scripts/lessons.sh check
assert_rc "an old lesson that was used passes" 0
write_index
echo "- [L001] When X happens - do Y (used: 2, last: 2026-10-01, retire-when: never)" >> docs/lessons/INDEX.md
run ./scripts/lessons.sh check
assert_rc "a lesson without approved: fails" 1
assert_contains "the missing approved: field is named" "L001 has no approved: YYYY-MM-DD field"
write_index
echo "- [L001] When X happens - do Y (used: 2, last: 2026-10-01, approved: , retire-when: never)" >> docs/lessons/INDEX.md
run ./scripts/lessons.sh check
assert_rc "an empty approved: fails" 1
assert_contains "the empty approved: is called malformed" "L001 has a malformed approved: date ''"
write_index
add_lesson L001 2 2026-10-01 "never" 2026-02-30x
add_lesson L002 2 2026-10-01 "never" 2026-13-01
add_lesson L003 2 2026-10-01 "never" -
run ./scripts/lessons.sh check
assert_rc "malformed approved: dates fail" 1
assert_contains "text after the date is malformed" "L001 has a malformed approved: date '2026-02-30x'"
assert_contains "month 13 is malformed" "L002 has a malformed approved: date '2026-13-01'"
assert_contains "a dash is malformed" "L003 has a malformed approved: date '-'"
assert_contains "each bad date counts" "check FAILED (3 problem(s))"
write_index
add_lesson L001 2 2026-10-01 "ships [met] 2026-10-08" 2026-10-01
add_lesson L002 2 2026-10-01 "never" 2026-10-01
run ./scripts/lessons.sh check
assert_rc "a [met] retire-when is a warning, not a failure" 0
assert_contains "the [met] warning names the lesson" "lessons: warning - L001 retire-when is marked [met]"
assert_not_contains "no warning for a lesson that is not [met]" "L002 retire-when"
write_index
add_lesson L001 0 - "never" 2026-08-24
run env LESSONS_TODAY=2026-10-08 ./scripts/lessons.sh check
assert_rc "LESSONS_TODAY moves the clock: the same lesson at 45 days passes" 0
run ./scripts/lessons.sh expire
assert_contains "expire reads a never-used lesson's age from approved:" "L001 - never used, approved 46 days ago (> 45)"
add_lesson L002 0 - "never" 2026-10-01
run ./scripts/lessons.sh expire --apply
assert_file "a stale never-used lesson is archived by expire --apply" .archive/lessons/L001.md
run ./scripts/lessons.sh check
assert_rc "check passes once the stale lesson is archived" 0
rm -f .archive/lessons/L001.md docs/lessons/MAINTENANCE.log
write_index

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

# ship_skill PROFILE NAME...: a profile ships every skill its Skills: line
# declares (shipped_set_errors requires the folders).
ship_skill() {
  local p="$1" n
  shift
  for n in "$@"; do
    mkdir -p "docs/profiles/$p/skills/$n"
    printf -- '---\nname: %s\ndescription: test skill\n---\n' "$n" > "docs/profiles/$p/skills/$n/SKILL.md"
  done
}

# Skills cap (kernel rule 10): the template core skills present, plus 2
# project skills, plus the skills the adopted profiles list. alpha is the
# fixture's first project skill.
add_skill() { local s; for s in "$@"; do mkdir -p ".claude/skills/$s" ".agents/skills/$s"; echo "# $s" > ".claude/skills/$s/SKILL.md"; echo "# $s" > ".agents/skills/$s/SKILL.md"; done; }
drop_skill() { local s; for s in "$@"; do rm -rf ".claude/skills/$s" ".agents/skills/$s"; done; }
run ./scripts/lessons.sh core-skills
assert_eq "core-skills prints the template core set" "adr dream maintain retro ship start template-update" "$(printf '%s\n' "$OUT" | tr '\n' ' ' | sed 's/ $//')"
add_skill adr maintain retro ship start template-update s2
run ./scripts/lessons.sh check
assert_rc "6 core and 2 project skills pass" 0
run ./scripts/lessons.sh skills
assert_rc "skills exits 0 within the cap" 0
assert_contains "skills prints the count and the cap" "skills: 8 (cap 8 = 6 core + 2 project + 0 skills listed by the adopted profiles)"
# The template-v0.4.0 case: a core skill the template adds takes no project slot.
add_skill dream
run ./scripts/lessons.sh check
assert_rc "a seventh core skill keeps a full project within the cap" 0
assert_contains "the cap grows with the core skill" "9 skills"
add_skill s3
run ./scripts/lessons.sh check
assert_rc "a third project skill fails" 1
assert_contains "the cap formula prints its figures" "the cap is 9 (7 core + 2 project + 0 skills listed by the adopted profiles = 9"
run ./scripts/lessons.sh skills
assert_rc "skills exits 1 over the cap" 1
assert_contains "skills names the breach" "lessons: .claude/skills has 10 skills; the cap is 9"
drop_skill dream
run ./scripts/lessons.sh check
assert_rc "a removed core skill frees no project slot" 1
add_skill dream
mkdir -p docs/profiles/p1
printf 'Profile p1\nSkills: s9-extra\n' > docs/profiles/p1/PROFILE.md
ship_skill p1 s9-extra
run ./scripts/lessons.sh check
assert_rc "a declared profile skill set raises the cap" 0
run ./scripts/lessons.sh skills
assert_contains "skills counts the profile skill" "skills: 10 (cap 10 = 7 core + 2 project + 1 skills listed by the adopted profiles)"
printf -- '- Profiles: other\n' > AGENTS.md
run ./scripts/lessons.sh check
assert_rc "a profile that is not adopted does not raise the cap" 1
printf -- '- Profiles: p1\n' > AGENTS.md
run ./scripts/lessons.sh check
assert_rc "an adopted profile raises the cap" 0
mv scripts/profiles.sh scripts/profiles.sh.off
run ./scripts/lessons.sh check
assert_rc "a missing profiles.sh fails check" 1
assert_contains "the missing parser is named" "scripts/profiles.sh is missing"
mv scripts/profiles.sh.off scripts/profiles.sh
rm -rf docs/profiles AGENTS.md
drop_skill s3
run ./scripts/lessons.sh check
assert_rc "back within the cap" 0

# Skills cap counts the skills a profile lists, not one per profile.
add_skill s3 s4 s5
mkdir -p docs/profiles/p3
printf 'Profile p3\n- Skills: ska, skb, skc\n' > docs/profiles/p3/PROFILE.md
ship_skill p3 ska skb skc
run ./scripts/lessons.sh check
assert_rc "5 project skills with a profile listing three pass" 0
add_skill s6
run ./scripts/lessons.sh check
assert_rc "6 project skills with a profile listing three fail" 1
assert_contains "the cap names the three profile skills" "the cap is 12 (7 core + 2 project + 3 skills listed by the adopted profiles = 12"
printf 'Profile p3\n- Skills: ska, skb,\n  skc (a note, with a comma), skd\n' > docs/profiles/p3/PROFILE.md
ship_skill p3 skd
run ./scripts/lessons.sh check
assert_rc "a list wrapped onto a second line counts four" 0
printf 'Profile p3\n- Skills: ska, skb, skc,\n  skd (`a note`);\n  the rest of the sentence.\n' > docs/profiles/p3/PROFILE.md
run ./scripts/lessons.sh check
assert_rc "a list ending in a parenthetical and a semicolon still counts four" 0
run ./scripts/lessons.sh stats
assert_contains "stats shows the four declared skills" "7 core + 2 project + 4 skills"
printf 'Profile p3\nSkills: none\n' > docs/profiles/p3/PROFILE.md
rm -rf docs/profiles/p3/skills
run ./scripts/lessons.sh check
assert_rc "Skills: none adds nothing" 1
rm -rf docs/profiles
drop_skill s2 s3 s4 s5 s6
run ./scripts/lessons.sh check
assert_rc "7 core and 1 project skill pass" 0

# Template mode (AGENTS.md has no usable Profiles line): only the software
# profile counts, not every profile the template ships.
mkdir -p docs/profiles/software docs/profiles/p6
printf 'Profile software\nSkills: none\n' > docs/profiles/software/PROFILE.md
printf 'Profile p6\nSkills: t1, t2, t3\n' > docs/profiles/p6/PROFILE.md
ship_skill p6 t1 t2 t3
printf -- '- Profiles: {{FILLED_BY_START}}\n' > AGENTS.md
run ./scripts/lessons.sh skills
assert_contains "a placeholder Profiles line counts only the software profile" "skills: 8 (cap 9 = 7 core + 2 project + 0 skills listed by the adopted profiles)"
printf 'Purpose only, no Profiles line\n' > AGENTS.md
run ./scripts/lessons.sh skills
assert_contains "no Profiles line counts only the software profile" "7 core + 2 project + 0 skills listed by the adopted profiles"
printf -- '- Profiles: software, p6\n' > AGENTS.md
run ./scripts/lessons.sh skills
assert_contains "a named profile still counts its skills" "7 core + 2 project + 3 skills listed by the adopted profiles"
rm -rf docs/profiles AGENTS.md

# The template core set itself is capped at 8.
cp scripts/lessons.sh "$FIX/lessons.keep"
sed -i.bak 's/^CORE_SKILLS=(\(.*\))$/CORE_SKILLS=(\1 c8 c9)/' scripts/lessons.sh && rm -f scripts/lessons.sh.bak
run ./scripts/lessons.sh check
assert_rc "a core set of 9 fails" 1
assert_contains "the core cap is named" "the template core set lists 9 skills; the cap is 8"
cp "$FIX/lessons.keep" scripts/lessons.sh && rm -f "$FIX/lessons.keep"

# The shipped-set early-stop marker: a check that returns before it prints the
# completion marker must be reported, not read as "no problems".
mkdir -p docs/profiles/p5/agents
printf 'Profile p5\nSkills: none\n' > docs/profiles/p5/PROFILE.md
printf -- '---\nname: h5\ndescription: x\nmodel: inherit\n---\n\nx\n' > docs/profiles/p5/agents/h5.md
printf 'name = "h5"\ndescription = "x"\ndeveloper_instructions = """\nx\n"""\n' > docs/profiles/p5/agents/h5.toml
run ./scripts/lessons.sh check
assert_rc "a complete shipped-set check passes" 0
cp scripts/lessons.sh "$FIX/lessons.keep"
sed -i.bak 's/^  echo "\$SHIPPED_DONE"$/  return 0/' scripts/lessons.sh && rm -f scripts/lessons.sh.bak
run ./scripts/lessons.sh check
assert_rc "a shipped-set check that stops early fails" 1
assert_contains "the early stop is named" "shipped-set check of docs/profiles/p5 stopped before completing"
cp "$FIX/lessons.keep" scripts/lessons.sh && rm -f "$FIX/lessons.keep"
rm -rf docs/profiles

# Agent mirror: every .claude agent has a Codex twin or a named exception.
mkdir -p .claude/agents .codex/agents
echo "x" > .claude/agents/reviewer.md
run ./scripts/lessons.sh check
assert_rc "an agent with no Codex twin fails" 1
assert_contains "the missing twin is named" ".claude/agents/reviewer.md has no .codex/agents/reviewer.toml"
echo "x" > .codex/agents/reviewer.toml
run ./scripts/lessons.sh check
assert_rc "an agent with a Codex twin passes" 0
# Core twin parity: .codex/agents/<name>.toml carries the .claude/agents body.
printf -- '---\nname: reviewer\ndescription: x\n---\n\nReview it.\n' > .claude/agents/reviewer.md
printf 'name = "reviewer"\ndeveloper_instructions = """\nReview it.\n"""\n' > .codex/agents/reviewer.toml
run ./scripts/lessons.sh check
assert_rc "a matching core twin passes" 0
printf 'name = "reviewer"\ndeveloper_instructions = """\nReview it, briefly.\n"""\n' > .codex/agents/reviewer.toml
run ./scripts/lessons.sh check
assert_rc "a drifted core twin fails" 1
assert_contains "the drifted core twin is named" ".codex/agents/reviewer.toml: developer_instructions differ from the body of .claude/agents/reviewer.md"
printf -- '---\nname: reviewer\ndescription: x\n---\n\nReview it.\n\n## Hand-offs\n\n- Then `no-such-agent`.\n' > .claude/agents/reviewer.md
printf 'name = "reviewer"\ndeveloper_instructions = """\nReview it.\n\n## Hand-offs\n\n- Then `no-such-agent`.\n"""\n' > .codex/agents/reviewer.toml
run ./scripts/lessons.sh check
assert_rc "a core hand-off to an unknown agent fails" 1
assert_contains "the unknown core hand-off is named" ".claude/agents/reviewer.md: Hand-offs names \`no-such-agent\`"
echo "x" > .claude/agents/reviewer.md
echo "x" > .codex/agents/reviewer.toml
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

# Shipped agent and skill sets under docs/profiles/*/ and docs/library/.
mkdir -p docs/profiles/p4
printf 'Profile p4\n- Skills: alpha-skill\n' > docs/profiles/p4/PROFILE.md
run ./scripts/lessons.sh check
assert_rc "a declared skill with no shipped folder fails" 1
assert_contains "the missing folder is named" "Skills: lists alpha-skill but docs/profiles/p4/skills/alpha-skill/SKILL.md does not exist"
ship_skill p4 alpha-skill
run ./scripts/lessons.sh check
assert_rc "a declared and shipped skill passes" 0
ship_skill p4 beta-skill
run ./scripts/lessons.sh check
assert_rc "a shipped skill the Skills: line omits fails" 1
assert_contains "the undeclared folder is named" "docs/profiles/p4/skills/beta-skill ships but docs/profiles/p4/PROFILE.md does not list it"
rm -rf docs/profiles/p4/skills/beta-skill
printf -- '---\nname: wrong\ndescription: x\n---\n' > docs/profiles/p4/skills/alpha-skill/SKILL.md
run ./scripts/lessons.sh check
assert_rc "a skill whose name: is not its folder fails" 1
assert_contains "the name mismatch is named" "alpha-skill/SKILL.md: frontmatter name: must be alpha-skill"
printf -- '---\nname: wrong\ndescription: x\n---\nname: alpha-skill\n' > docs/profiles/p4/skills/alpha-skill/SKILL.md
run ./scripts/lessons.sh check
assert_rc "a body line cannot stand in for the frontmatter name" 1
assert_contains "the frontmatter name is still required" "alpha-skill/SKILL.md: frontmatter name: must be alpha-skill"
printf -- '---\nname: alpha-skill\n---\ndescription: in the body\n' > docs/profiles/p4/skills/alpha-skill/SKILL.md
run ./scripts/lessons.sh check
assert_rc "a description outside the frontmatter fails" 1
assert_contains "the missing description is named" "alpha-skill/SKILL.md: frontmatter missing description"
ship_skill p4 alpha-skill
mkdir -p docs/profiles/p4/agents
printf -- '---\nname: helper\ndescription: x\nmodel: sonnet\n---\n\nx\n' > docs/profiles/p4/agents/helper.md
run ./scripts/lessons.sh check
assert_rc "a shipped agent with no Codex twin fails" 1
assert_contains "the missing twin is named" "no Codex twin docs/profiles/p4/agents/helper.toml"
printf 'name = "helper"\ndescription = "x"\n' > docs/profiles/p4/agents/helper.toml
run ./scripts/lessons.sh check
assert_rc "a Codex twin without developer_instructions fails" 1
assert_contains "the missing field is named" "helper.toml: missing developer_instructions field"
printf 'developer_instructions = """\nx\n"""\n' >> docs/profiles/p4/agents/helper.toml
run ./scripts/lessons.sh check
assert_rc "a complete profile agent pair passes" 0
# Twin parity covers profile agents too, not only the roster.
printf 'name = "helper"\ndescription = "x"\ndeveloper_instructions = """\ny\n"""\n' > docs/profiles/p4/agents/helper.toml
run ./scripts/lessons.sh check
assert_rc "a drifted profile twin fails" 1
assert_contains "the drifted profile twin is named" "docs/profiles/p4/agents/helper.toml: developer_instructions differ from the body of docs/profiles/p4/agents/helper.md"
printf 'name = "helper"\ndescription = "x"\ndeveloper_instructions = """\nx\n"""\n' > docs/profiles/p4/agents/helper.toml
mkdir -p docs/library/skills/gamma
echo "no frontmatter" > docs/library/skills/gamma/SKILL.md
run ./scripts/lessons.sh check
assert_rc "a library skill without frontmatter fails" 1
assert_contains "the library skill is named" "docs/library/skills/gamma/SKILL.md: frontmatter must open with ---"
printf -- '---\r\nname: gamma\r\ndescription: x\r\n---\r\n' > docs/library/skills/gamma/SKILL.md
run ./scripts/lessons.sh check
assert_rc "a CRLF library skill with frontmatter passes" 0
mkdir -p docs/roster/agents
printf -- '---\nname: lead\ndescription: x\nmodel: inherit\n---\n\nx\n' > docs/roster/agents/lead.md
run ./scripts/lessons.sh check
assert_rc "a roster agent with no Codex twin fails" 1
assert_contains "the roster twin is named" "docs/roster/agents/lead.md: no Codex twin docs/roster/agents/lead.toml"
printf 'name = "lead"\ndescription = "x"\ndeveloper_instructions = """\nx\n"""\n' > docs/roster/agents/lead.toml
run ./scripts/lessons.sh check
assert_rc "a complete roster agent pair passes" 0
# One awk judges all files of a class; an empty file yields no records and is
# still judged, and the file after it keeps its own verdict.
: > docs/roster/agents/aaa.md; : > docs/roster/agents/aaa.toml
run ./scripts/lessons.sh check
assert_contains "an empty roster agent is judged" "docs/roster/agents/aaa.md: frontmatter must open with ---"
assert_contains "an empty roster twin is judged" "docs/roster/agents/aaa.toml: missing developer_instructions field"
assert_not_contains "the agent after the empty one stays clean" "docs/roster/agents/lead"
printf '\n## Hand-offs\n- `ghost-role`\n' >> docs/roster/agents/lead.md
run ./scripts/lessons.sh check
assert_contains "a bad hand-off after an empty agent names its own file" "docs/roster/agents/lead.md: Hand-offs names \`ghost-role\`"
printf -- '---\nname: lead\ndescription: x\nmodel: inherit\n---\n\nx\n' > docs/roster/agents/lead.md
rm docs/roster/agents/aaa.md docs/roster/agents/aaa.toml
# Roster inventory: the README's advertised roles and the shipped agents agree.
printf '# Roster\n\n| Agent | Kind |\n|---|---|\n| `lead` | lead |\n| `ghost` | lead |\n' > docs/roster/README.md
run ./scripts/lessons.sh check
assert_rc "an advertised role with no files fails" 1
assert_contains "the missing role is named" "docs/roster/README.md lists ghost but docs/roster/agents/ghost.md does not exist"
assert_contains "its missing twin is named" "docs/roster/README.md lists ghost but docs/roster/agents/ghost.toml does not exist"
printf '# Roster\n\n| Agent | Kind |\n|---|---|\n| `lead` | lead |\n' > docs/roster/README.md
run ./scripts/lessons.sh check
assert_rc "a README that matches the shipped roles passes" 0
printf -- '---\nname: extra\ndescription: x\nmodel: inherit\n---\n' > docs/roster/agents/extra.md
printf 'name = "extra"\ndescription = "x"\ndeveloper_instructions = """\nx\n"""\n' > docs/roster/agents/extra.toml
run ./scripts/lessons.sh check
assert_rc "a shipped role the README does not list fails" 1
assert_contains "the unlisted role is named" "docs/roster/agents/extra ships but docs/roster/README.md does not list it"
rm -f docs/roster/agents/extra.md
run ./scripts/lessons.sh check
assert_rc "an orphan roster .toml with no README row fails" 1
assert_contains "the orphan .toml is named" "docs/roster/agents/extra ships but docs/roster/README.md does not list it"
rm -f docs/roster/agents/extra.md docs/roster/agents/extra.toml
rm -f docs/roster/agents/lead.md docs/roster/agents/lead.toml
run ./scripts/lessons.sh check
assert_rc "deleting an advertised role's files fails" 1
assert_contains "the deleted role is named" "docs/roster/README.md lists lead but docs/roster/agents/lead.md does not exist"
rm -f docs/roster/README.md
# Library inventory: the README Items table and the shipped items agree.
rm -rf docs/library
mkdir -p docs/library/agents docs/library/skills/sk docs/library/tools
printf -- '---\nname: aa\ndescription: x\nmodel: sonnet\n---\n\nx\n' > docs/library/agents/aa.md
printf 'name = "aa"\ndescription = "x"\ndeveloper_instructions = """\nx\n"""\n' > docs/library/agents/aa.toml
printf -- '---\nname: sk\ndescription: x\n---\n' > docs/library/skills/sk/SKILL.md
echo 'print(1)' > docs/library/tools/tt.py
printf '# Library\n\n## Items\n\n| Name | Kind | What |\n|---|---|---|\n| aa | agent (standard tier) | x |\n| sk | skill | x |\n| tt | tool | x |\n\n## Other\n\n| Candidate | Reason |\n|---|---|\n| zz | not ported |\n' > docs/library/README.md
run ./scripts/lessons.sh check
assert_rc "a library README matching its items passes" 0
rm -rf docs/library/skills/sk
run ./scripts/lessons.sh check
assert_rc "a deleted library skill fails" 1
assert_contains "the deleted skill is named" "docs/library/README.md lists skill sk but it does not exist under docs/library/"
mkdir -p docs/library/skills/sk && printf -- '---\nname: sk\ndescription: x\n---\n' > docs/library/skills/sk/SKILL.md
echo 'echo 1' > docs/library/tools/extra.sh
run ./scripts/lessons.sh check
assert_rc "an unlisted library tool fails" 1
assert_contains "the unlisted tool is named" "docs/library/tools/extra.sh ships but docs/library/README.md does not list it as a tool"
rm -rf docs/library

# Roster twin parity: the Codex body equals the .md body; only the read-only
# hard-rule line may use the sandbox wording.
printf -- '---\r\nname: lead\r\ndescription: x\r\nmodel: inherit\r\n---\r\n\r\nYou lead.\r\n\r\n- Read-only. Advisor records.\r\n' > docs/roster/agents/lead.md
printf 'name = "lead"\ndescription = "x"\ndeveloper_instructions = """\nYou lead.\n\n- Your sandbox is read-only. Advisor records.\n"""\n' > docs/roster/agents/lead.toml
run ./scripts/lessons.sh check
assert_rc "a CRLF twin pair differing only by the sandbox line passes" 0
printf 'name = "lead"\ndescription = "x"\ndeveloper_instructions = """\nYou lead.\n\n- Read-only. Advisor records.\n"""\n' > docs/roster/agents/lead.toml
run ./scripts/lessons.sh check
assert_rc "a twin pair keeping the md read-only wording passes" 0
printf 'name = "lead"\ndescription = "x"\ndeveloper_instructions = """\nYou lead the team.\n\n- Read-only. Advisor records.\n"""\n' > docs/roster/agents/lead.toml
run ./scripts/lessons.sh check
assert_rc "a drifted roster twin fails" 1
assert_contains "the drifted twin is named" "docs/roster/agents/lead.toml: developer_instructions differ from the body of docs/roster/agents/lead.md"

# Hand-offs resolve: backticked hyphenated names must be shipped agents.
mkdir -p docs/library/agents
printf -- '---\nname: helper-one\ndescription: x\n---\n' > docs/library/agents/helper-one.md
printf -- '---\nname: lead\ndescription: x\nmodel: inherit\n---\n\nx\n\n## Hand-offs\n\n- Review: `helper-one`; files under `render/scenes/`; run `frame_audit`.\n\n## Output\n\n`not-an-agent` outside the section is ignored.\n' > docs/roster/agents/lead.md
awk 'NR > 5' docs/roster/agents/lead.md > /dev/null
printf 'name = "lead"\ndescription = "x"\ndeveloper_instructions = """\nx\n\n## Hand-offs\n\n- Review: `helper-one`; files under `render/scenes/`; run `frame_audit`.\n\n## Output\n\n`not-an-agent` outside the section is ignored.\n"""\n' > docs/roster/agents/lead.toml
run ./scripts/lessons.sh check
assert_not_contains "a hand-off to a shipped agent, paths and tool names pass" "Hand-offs names"
printf -- '---\nname: lead\ndescription: x\nmodel: inherit\n---\n\nx\n\n## Hand-offs\n\n- Review: `ghost-role`.\n' > docs/roster/agents/lead.md
printf 'name = "lead"\ndescription = "x"\ndeveloper_instructions = """\nx\n\n## Hand-offs\n\n- Review: `ghost-role`.\n"""\n' > docs/roster/agents/lead.toml
run ./scripts/lessons.sh check
assert_rc "a hand-off to an agent that does not ship fails" 1
assert_contains "the unknown hand-off is named" "docs/roster/agents/lead.md: Hand-offs names \`ghost-role\`, which is not an agent in this template"
rm -rf docs/profiles docs/library docs/roster

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
assert_file_has "used incremented and last set" docs/lessons/INDEX.md "- [L001] When X happens - do Y (used: 1, last: 2026-10-09, approved: 2026-10-01, retire-when: never)"
run ./scripts/lessons.sh use L001
assert_file_has "second use increments again" docs/lessons/INDEX.md "(used: 2, last: 2026-10-09, approved: 2026-10-01, retire-when: never)"
assert_file_has "other lessons untouched" docs/lessons/INDEX.md "- [L002] When X happens - do Y (used: 4, last: 2026-09-01, approved: 2026-10-01, retire-when: never)"
assert_file_has "format placeholder untouched" docs/lessons/INDEX.md "(used: 0, last: -, approved: YYYY-MM-DD, retire-when: <condition>)"
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

# archive <Lnnn> <reason>: one lesson, with the reason, moved to .archive/lessons.
rm -f .archive/lessons/L001.md
write_index
add_lesson L001 5 2026-10-05 "never"
add_lesson L002 1 2026-10-05 "never"
run ./scripts/lessons.sh archive L001 "content lives in docs/x.md"
assert_rc "archive succeeds" 0
assert_file "archive writes the lesson file" .archive/lessons/L001.md
assert_file_has "the archive holds the reason" .archive/lessons/L001.md "reason: content lives in docs/x.md"
assert_file_has "the archive holds the original line" .archive/lessons/L001.md "- [L001] When X happens - do Y (used: 5"
assert_file_lacks "the lesson leaves the index" docs/lessons/INDEX.md "- [L001] When X"
assert_file_has "the other lesson stays" docs/lessons/INDEX.md "- [L002] When X"
assert_file_has "the log records the archive" docs/lessons/MAINTENANCE.log "archive: L001 archived to .archive/lessons/L001.md - content lives in docs/x.md"
run ./scripts/lessons.sh archive L001 "again"
assert_rc "archiving an id that is no longer approved fails" 1
run ./scripts/lessons.sh archive L002
assert_rc "archive without a reason is a usage error" 2
run ./scripts/lessons.sh archive bogus "x"
assert_rc "archive with a bad id is a usage error" 2
assert_file_has "a refused archive leaves the index alone" docs/lessons/INDEX.md "- [L002] When X"
rm -f .archive/lessons/L001.md docs/lessons/MAINTENANCE.log

# Triggers (ADR 0017): the optional last field, validated by check, kept by use.
add_trig() { # id trigger
  echo "- [$1] When X happens - do Y (used: 0, last: -, approved: 2026-10-01, retire-when: never, trigger: $2)" >> docs/lessons/INDEX.md
}
write_index
add_trig L001 "A:*.sh"
add_trig L002 "docs/decisions/*.md M:src/*"
add_lesson L003 0 - "never"
run ./scripts/lessons.sh check
assert_rc "lessons with and without triggers pass check" 0
write_index
add_trig L001 ""
run ./scripts/lessons.sh check
assert_rc "an empty trigger fails" 1
assert_contains "names the empty trigger" "L001 has an empty trigger"
write_index
add_trig L001 "A: X:src/* src/a:b"
run ./scripts/lessons.sh check
assert_rc "malformed trigger tokens fail" 1
assert_contains "names an empty glob after the prefix" "trigger token 'A:' is malformed"
assert_contains "names an unknown prefix" "trigger token 'X:src/*' is malformed"
assert_contains "names a colon inside the glob" "trigger token 'src/a:b' is malformed"
assert_contains "counts each bad token" "check FAILED (3 problem(s))"
echo "- [L002] When X happens - do Y (used: 0, last: -, approved: 2026-10-01, retire-when: , trigger: A:*.sh)" >> docs/lessons/INDEX.md
run ./scripts/lessons.sh check
assert_contains "a trigger does not hide an empty retire-when" "L002 has an empty retire-when"
write_index
add_trig L001 "A:*.sh"
run ./scripts/lessons.sh use L001
assert_rc "use on a lesson with a trigger succeeds" 0
assert_file_has "use keeps the trigger" docs/lessons/INDEX.md "(used: 1, last: 2026-10-09, approved: 2026-10-01, retire-when: never, trigger: A:*.sh)"
write_index
add_trig L001 "A:*.sh"
echo "- [L002] When X happens - do Y (used: 0, last: -, approved: 2026-10-01, retire-when: done [met], trigger: src/*)" >> docs/lessons/INDEX.md
run ./scripts/lessons.sh expire
assert_contains "expire reads [met] beside a trigger" "L002 - retire-when marked [met]"
assert_not_contains "a trigger alone never expires a lesson" "L001 -"

# match: changed paths from git revisions and from a diff file.
write_index
add_trig L001 "A:*.sh"
add_trig L002 "A:docs/decisions/*.md"
add_trig L003 "M:src/*"
add_trig L004 "D:old/*"
add_trig L005 ".github/workflows/*"
add_lesson L006 0 - "never"
add_trig L007 "nothing/here/*"
mkdir -p src old docs/decisions
echo "a" > src/a.txt
echo "o" > old/gone.txt
echo "r" > old/moved.sh
git add -A >/dev/null 2>&1 && git commit -qm base >/dev/null 2>&1
base="$(git rev-parse HEAD)"
run ./scripts/lessons.sh match HEAD
assert_rc "match on an unchanged tree succeeds" 0
assert_eq "no changed path, no lesson" "lessons: 0 of 6 lesson triggers match 0 changed path(s)" "$OUT"
echo "b" >> src/a.txt
git rm -q old/gone.txt
mkdir -p tools && git mv old/moved.sh tools/moved.sh
echo "# 0001 - x" > docs/decisions/0001-x.md
printf '#!/bin/sh\n' > new.sh
git add -A >/dev/null 2>&1 && git commit -qm change >/dev/null 2>&1
run ./scripts/lessons.sh match "$base..HEAD"
assert_rc "match on a range succeeds" 0
assert_contains "an added script matches A:*.sh" "L001 A new.sh (trigger A:*.sh)"
assert_contains "an added ADR matches" "L002 A docs/decisions/0001-x.md"
assert_contains "a modified file matches M:" "L003 M src/a.txt"
assert_contains "a deleted file matches D:" "L004 D old/gone.txt"
assert_not_contains "a lesson without a trigger is never printed" "L006"
assert_not_contains "a trigger matching nothing is not printed" "L007"
assert_not_contains "a workflow trigger with no workflow change is not printed" "L005"
assert_contains "the count is reported" "lessons: 4 of 6 lesson triggers match"
lines="$(printf '%s\n' "$OUT" | grep -c '^L0')"
assert_eq "one line per matching lesson, not per path" 4 "$lines"
run ./scripts/lessons.sh match "$base" HEAD
assert_contains "two revisions work like a range" "L002 A docs/decisions/0001-x.md"

# A rename adds its new path and deletes its old one; a glob crosses folders.
write_index
add_trig L001 "A:tools/*"
add_trig L002 "D:old/moved.sh"
add_trig L003 "M:*.sh"
run ./scripts/lessons.sh match "$base..HEAD"
assert_contains "a rename adds the new path" "L001 A tools/moved.sh"
assert_contains "a rename deletes the old path" "L002 D old/moved.sh"
assert_not_contains "an added script is not a modified one" "L003"

# The trigger glob is a pattern, never expanded against files in the repo.
write_index
add_trig L001 "A:*.sh"
run ./scripts/lessons.sh match "$base..HEAD"
assert_contains "*.sh is matched as a pattern although new.sh exists" "L001 A new.sh"

# --staged, refused options, bad revisions, no arguments.
echo "c" >> src/a.txt
git add src/a.txt
write_index
add_trig L001 "M:src/*"
run ./scripts/lessons.sh match --staged
assert_contains "--staged reads the index" "L001 M src/a.txt"
run ./scripts/lessons.sh match --output=x.txt HEAD
assert_rc "another option is refused" 2
assert_contains "names the refused option" "option '--output=x.txt' is not allowed"
assert_no_file "the refused option wrote nothing" x.txt
run ./scripts/lessons.sh match no-such-rev
assert_rc "an unknown revision fails" 2
assert_contains "names the git failure" "lessons: git diff failed"
run ./scripts/lessons.sh match
assert_rc "match without arguments is a usage error" 2
git reset -q >/dev/null 2>&1
git checkout -q -- src/a.txt

# A diff file: new, deleted, renamed, modified, a path with a space, CRLF.
write_index
add_trig L001 "A:*.sh"
add_trig L002 "D:old/*"
add_trig L003 "M:src/*"
add_trig L004 "A:tools/*"
add_trig L005 "M:dir?with?space/*"
mkdir -p "dir with space"
echo "s" > "dir with space/f.txt"
git add -A >/dev/null 2>&1 && git commit -qm space >/dev/null 2>&1
echo "t" >> "dir with space/f.txt"
git add -A >/dev/null 2>&1 && git commit -qm space2 >/dev/null 2>&1
git diff -M "$base..HEAD" > "$FIX.diff"
run ./scripts/lessons.sh match "$FIX.diff"
assert_rc "match on a diff file succeeds" 0
assert_contains "diff file: an added script" "L001 A new.sh"
assert_contains "diff file: a deleted file" "L002 D old/gone.txt"
assert_contains "diff file: a modified file" "L003 M src/a.txt"
assert_contains "diff file: a rename adds the new path" "L004 A tools/moved.sh"
git diff "$(git rev-parse HEAD~1)..HEAD" > "$FIX.space.diff"
run ./scripts/lessons.sh match "$FIX.space.diff"
assert_contains "diff file: a path with a space" "L005 M dir with space/f.txt"
awk '{ printf "%s\r\n", $0 }' "$FIX.diff" > "$FIX.crlf.diff"
run ./scripts/lessons.sh match "$FIX.crlf.diff"
assert_contains "a CRLF diff file reads the same" "L004 A tools/moved.sh"
assert_not_contains "no carriage return in a path" $'\r'
printf 'just some text\n' > "$FIX.notdiff"
run ./scripts/lessons.sh match "$FIX.notdiff"
assert_rc "a file with no diff header fails" 2
assert_contains "names the missing header" "holds no \"diff --git\" header"
: > "$FIX.empty"
run ./scripts/lessons.sh match "$FIX.empty"
assert_rc "an empty diff file fails" 2
rm -f "$FIX.diff" "$FIX.space.diff" "$FIX.crlf.diff" "$FIX.notdiff" "$FIX.empty"

# Skills pointer layout: .claude/skills/<name>/SKILL.md names the canonical
# file and repeats its name and description; nothing else is accepted.
rm -rf .claude/skills/alpha .agents/skills/alpha
mkdir -p .claude/skills/ptr .agents/skills/ptr
printf -- '---\nname: ptr\ndescription: the canonical one\n---\n\nbody of the real skill\nmore body\n' > .agents/skills/ptr/SKILL.md
printf -- '---\nname: ptr\ndescription: the canonical one\n---\n\nCanonical file: .agents/skills/ptr/SKILL.md\n' > .claude/skills/ptr/SKILL.md
run ./scripts/lessons.sh check
assert_rc "an accepted skills pointer passes" 0
printf -- '---\nname: ptr\ndescription: another words\n---\n\nCanonical file: .agents/skills/ptr/SKILL.md\n' > .claude/skills/ptr/SKILL.md
run ./scripts/lessons.sh check
assert_rc "a pointer with a different description fails" 1
assert_contains "the description mismatch is named" "pointer description differs"
printf -- '---\nname: other\ndescription: the canonical one\n---\n\nCanonical file: .agents/skills/ptr/SKILL.md\n' > .claude/skills/ptr/SKILL.md
run ./scripts/lessons.sh check
assert_rc "a pointer with a different name fails" 1
assert_contains "the name mismatch is named" "pointer name 'other' differs"
printf -- '---\nname: ptr\ndescription: the canonical one\n---\n\nCanonical file: .agents/skills/gone/SKILL.md\n' > .claude/skills/ptr/SKILL.md
run ./scripts/lessons.sh check
assert_rc "a pointer naming a missing file fails" 1
assert_contains "the missing file is named" ".agents/skills/gone/SKILL.md, which does not exist"
printf -- '---\nname: ptr\ndescription: the canonical one\n---\n\nsome other prose without a path\n' > .claude/skills/ptr/SKILL.md
run ./scripts/lessons.sh check
assert_rc "a differing real skill is not a pointer and fails as drift" 1
assert_contains "drift is named for a non-pointer" "differ"
rm -rf .claude/skills/ptr .agents/skills/ptr
mkdir -p .claude/skills/alpha .agents/skills/alpha
echo "# alpha" > .claude/skills/alpha/SKILL.md
echo "# alpha" > .agents/skills/alpha/SKILL.md

# UPSTREAM.md entries follow the PENDING rule plus "applies to:".
UPSTREAM_HEAD='# Upstream

Entry format (all five fields required):

- what happened:
- what check should have caught it:
- what was added:
- retire-when:
- applies to: core | <profile name>
'
printf '%s\n' "$UPSTREAM_HEAD" > docs/lessons/UPSTREAM.md
run ./scripts/lessons.sh check
assert_rc "the UPSTREAM placeholder passes" 0
printf '%s\n' "$UPSTREAM_HEAD" > docs/lessons/UPSTREAM.md
cat >> docs/lessons/UPSTREAM.md <<'EOT'
- what happened: a thing
- what check should have caught it: a check
- what was added: a script
- retire-when: the template carries it
- applies to: core
EOT
run ./scripts/lessons.sh check
assert_rc "a complete UPSTREAM entry passes" 0
sed -i.bak '/^- what was added: a script$/d' docs/lessons/UPSTREAM.md && rm -f docs/lessons/UPSTREAM.md.bak
run ./scripts/lessons.sh check
assert_rc "an UPSTREAM entry without a field fails" 1
assert_contains "the missing field is named" "UPSTREAM.md entry at line"
assert_contains "which field" "'what was added'"
sed -i.bak -e 's/^- retire-when: the template carries it$/- retire-when: the template carries it\n- what was added: a script/' -e '/^- applies to: core$/d' docs/lessons/UPSTREAM.md && rm -f docs/lessons/UPSTREAM.md.bak
run ./scripts/lessons.sh check
assert_rc "an UPSTREAM entry without applies to fails" 1
assert_contains "applies to is named" "'applies to'"
echo "- applies to: nosuchprofile" >> docs/lessons/UPSTREAM.md
run ./scripts/lessons.sh check
assert_rc "an unknown applies to fails" 1
assert_contains "the unknown value is named" "'applies to' is 'nosuchprofile'"
mkdir -p docs/profiles/known
sed -i.bak 's/^- applies to: nosuchprofile$/- applies to: known (sent: #12)/' docs/lessons/UPSTREAM.md && rm -f docs/lessons/UPSTREAM.md.bak
run ./scripts/lessons.sh check
assert_rc "a profile name with a sent note passes" 0
rm -rf docs/profiles/known docs/lessons/UPSTREAM.md

# PROFILE.md contract: 60 to 160 lines, the ten headings in order.
mkdir -p docs/profiles/pc
PROFILE_BODY() { # heading-list-file-free generator: prints a valid profile of N filler lines
  local n="$1" h
  echo "# Profile: pc"
  for h in "Purpose and risk" "Rules" "Gates" "Tools" "Playbooks" "Agents and skills" "Parameters and records" "Done means" "Lessons carried in" "Sources"; do
    echo; echo "## $h"
  done
  local have=$(( 1 + 20 ))
  while (( have < n )); do echo "filler line"; have=$((have + 1)); done
}
PROFILE_BODY 60 > docs/profiles/pc/PROFILE.md
printf 'Skills: none\n' >> docs/profiles/pc/PROFILE.md
run ./scripts/lessons.sh check
assert_rc "a PROFILE.md at 61 lines with the headings passes" 0
PROFILE_BODY 59 > docs/profiles/pc/PROFILE.md
run ./scripts/lessons.sh check
assert_rc "a 59-line PROFILE.md fails" 1
assert_contains "the short length is named" "has 59 lines; a PROFILE.md is 60 to 160 lines"
PROFILE_BODY 161 > docs/profiles/pc/PROFILE.md
run ./scripts/lessons.sh check
assert_rc "a 161-line PROFILE.md fails" 1
assert_contains "the long length is named" "has 161 lines"
PROFILE_BODY 100 | sed 's/^## Tools$/## Toolbox/' > docs/profiles/pc/PROFILE.md
run ./scripts/lessons.sh check
assert_rc "a renamed heading fails" 1
assert_contains "the headings are named" "level-2 headings are"
PROFILE_BODY 100 | sed '/^## Done means$/d' > docs/profiles/pc/PROFILE.md
run ./scripts/lessons.sh check
assert_rc "a missing heading fails" 1
PROFILE_BODY 100 > docs/profiles/pc/PROFILE.md
run ./scripts/lessons.sh check
assert_rc "a valid 100-line PROFILE.md passes" 0
rm -rf docs/profiles/pc

t_finish
