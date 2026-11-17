#!/usr/bin/env bash
# adr.sh: check (file names, contiguous numbering, title line, Date and Status,
# superseded-by target, leftover placeholders) and new (next number, slug,
# template that fails check until filled).
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" || { echo "$0: cannot load lib.sh; stopped before writing anything" >&2; exit 2; }

# A nested run under check.sh --quick exports QUICK=1; this file sets each lane itself.
export QUICK=0
make_fixture
cp_script adr.sh
D=docs/decisions
adr() { # file title-number date status
  mkdir -p "$D"
  printf '# %s - A decision\n\nDate: %s\nStatus: %s\n\n## Context\n\nText.\n\n## Decision\n\nText.\n\n## Consequences\n\nText.\n' "$2" "$3" "$4" > "$D/$1"
}

run ./scripts/adr.sh check
assert_rc "no decisions folder passes" 0
mkdir -p "$D"
run ./scripts/adr.sh check
assert_rc "an empty decisions folder passes" 0

adr 0001-first.md 0001 2026-01-02 accepted
adr 0002-second-choice.md 0002 2026-01-03 Accepted
echo "# Decisions index" > "$D/README.md"
run ./scripts/adr.sh check
assert_rc "two well-formed ADRs and a README pass" 0
assert_contains "the count is reported" "adr: OK (2 decision records, numbered 0001 to 0002)"

adr 0004-gap.md 0004 2026-01-04 accepted
run ./scripts/adr.sh check
assert_rc "a gap in the numbering fails" 1
assert_contains "the gap is named" "0004-gap.md: number 0004 breaks the sequence; expected 0003"
rm "$D/0004-gap.md"

adr 0002-dup.md 0002 2026-01-04 accepted
run ./scripts/adr.sh check
assert_rc "a duplicate number fails" 1
assert_contains "the duplicate is named" "duplicate number 0002"
rm "$D/0002-dup.md"

adr 0003-Bad_Name.md 0003 2026-01-04 accepted
run ./scripts/adr.sh check
assert_rc "a file name that is not NNNN-slug.md fails" 1
assert_contains "the name rule is stated" "file name must be NNNN-slug.md"
rm "$D/0003-Bad_Name.md"

adr 0003-third.md 0007 2026-01-04 accepted
run ./scripts/adr.sh check
assert_rc "a title number that differs from the file number fails" 1
assert_contains "the mismatch is named" "title number 0007 does not match the file number 0003"
printf 'No title here\n\nDate: 2026-01-04\nStatus: accepted\n' > "$D/0003-third.md"
run ./scripts/adr.sh check
assert_rc "a missing '# NNNN - Title' line fails" 1
assert_contains "the title rule is stated" "first line must be '# 0003 - Title'"

adr 0003-third.md 0003 2026-13-40 accepted
run ./scripts/adr.sh check
assert_rc "an invalid date fails" 1
assert_contains "the date rule is stated" "needs a 'Date: YYYY-MM-DD' line"
printf '# 0003 - A decision\n\nStatus: accepted\n\n## Context\n\nDate: 2026-01-04\n' > "$D/0003-third.md"
run ./scripts/adr.sh check
assert_rc "a Date line only inside a section fails" 1
adr 0003-third.md 0003 2026-01-04 ""
run ./scripts/adr.sh check
assert_rc "an empty Status fails" 1
assert_contains "the status rule is stated" "needs a non-empty 'Status:' line"

printf '# 0003 - A decision\n\nDate: 2026-01-04\nStatus: accepted\n\n## Context\n\nOnly a context.\n' > "$D/0003-third.md"
run ./scripts/adr.sh check
assert_rc "an ADR without Decision and Consequences fails" 1
assert_contains "the missing sections are named" "0003-third.md: needs the sections '## Context', '## Decision' and '## Consequences'"
printf '# 0003 - A decision\n\nDate: 2026-01-04\nStatus: accepted\n\n## Decision\n\nX.\n\n## Context\n\nX.\n\n## Consequences\n\nX.\n' > "$D/0003-third.md"
run ./scripts/adr.sh check
assert_rc "sections out of order fail" 1
assert_contains "the order rule is stated" "the sections must run '## Context', '## Decision', '## Consequences' in that order"
printf '# 0003 - A decision\n\nDate: 2026-01-04\nStatus: accepted\n\n## Context\n\nX.\n\n## Decision\n\nX.\n\n## Consequences\n\nX.\n\n## Rejected alternatives\n\nX.\n' > "$D/0003-third.md"
run ./scripts/adr.sh check
assert_rc "an extra section after the three passes" 0
printf '# 0003 - A decision\n\nDate: 2026-01-04\nStatus: accepted\n\nNo sections, only an example:\n\n```markdown\n## Context\n## Decision\n## Consequences\n```\n' > "$D/0003-third.md"
run ./scripts/adr.sh check
assert_rc "headings inside a fenced block are not sections" 1
assert_contains "the fenced-only ADR is named" "0003-third.md: needs the sections"
printf '# 0003 - A decision\n\nDate: 2026-01-04\nStatus: accepted\n\n~~~\n## Context\n## Decision\n## Consequences\n~~~\n' > "$D/0003-third.md"
run ./scripts/adr.sh check
assert_rc "a tilde fence hides its headings too" 1
printf '# 0003 - A decision\n\nDate: 2026-01-04\nStatus: accepted\n\n## Context\n\n```\n## Consequences\n```\n\n## Decision\n\nX.\n\n## Consequences\n\nX.\n' > "$D/0003-third.md"
run ./scripts/adr.sh check
assert_rc "a fenced heading does not count toward the order" 0
adr 0001-first.md 0001 2026-01-02 "superseded by 0009 (2026-02-01)"
adr 0003-third.md 0003 2026-01-04 accepted
run ./scripts/adr.sh check
assert_rc "superseded by a missing ADR fails" 1
assert_contains "the missing target is named" "status names ADR 0009, which does not exist"
adr 0001-first.md 0001 2026-01-02 "superseded by 0003 (2026-02-01)"
run ./scripts/adr.sh check
assert_rc "superseded by an existing ADR passes" 0

# new: next number, slug, template; the unfilled template fails check.
export ADR_TODAY=2026-10-23
run ./scripts/adr.sh new "Use SQLite for the cache!"
assert_rc "new exits 0" 0
assert_eq "new prints the path" "docs/decisions/0004-use-sqlite-for-the-cache.md" "$OUT"
assert_file "new creates the file" "$D/0004-use-sqlite-for-the-cache.md"
assert_file_has "the title line is in the format" "$D/0004-use-sqlite-for-the-cache.md" "# 0004 - Use SQLite for the cache!"
assert_file_has "the date is today" "$D/0004-use-sqlite-for-the-cache.md" "Date: 2026-10-23"
assert_file_has "the status is accepted" "$D/0004-use-sqlite-for-the-cache.md" "Status: accepted"
run ./scripts/adr.sh check
assert_rc "an unfilled new ADR fails check" 1
assert_contains "the placeholder is named" "0004-use-sqlite-for-the-cache.md: still holds a {{ template placeholder"
sed -i.bak 's/{{//; s/}}//' "$D/0004-use-sqlite-for-the-cache.md" && rm -f "$D"/*.bak
run ./scripts/adr.sh check
assert_rc "the filled ADR passes check" 0
run ./scripts/adr.sh new "Second one"
assert_eq "new takes the following number" "docs/decisions/0005-second-one.md" "$OUT"
run ./scripts/adr.sh new "!!!"
assert_rc "a title with no letters or digits is refused" 2
run ./scripts/adr.sh new
assert_rc "new without a title is a usage error" 2
run ./scripts/adr.sh bogus
assert_rc "an unknown command is a usage error" 2
unset ADR_TODAY

# Cited ADRs exist, in template mode and after start alike (adr.sh never reads
# the template status). Refused: a docs/decisions/NNNN citation in a procedure,
# rule or profile file that names no record. Allowed: a citation that resolves,
# the "template ADR NNNN" prose form, and the NNNN placeholder.
make_fixture
cp_script adr.sh
printf '# Project\n\n## Project decisions\n\nStatus: started 2026-11-17.\n\n- Purpose, users, non-goals, boundary: a tool.\n' > AGENTS.md
adr 0001-first.md 0001 2026-01-02 accepted
mkdir -p docs/procedures docs/rules docs/profiles/sci
printf 'See docs/decisions/0001, template ADR 0014 and docs/decisions/NNNN.\n' > docs/procedures/one.md
printf 'Rule from docs/decisions/0001.\n' > docs/rules/r.md
run ./scripts/adr.sh check
assert_rc "citations that resolve pass in a started project" 0
printf 'Rule from docs/decisions/0002.\n' > docs/rules/r.md
printf 'Profile rule from docs/decisions/0003.\n' > docs/profiles/sci/rules.md
run ./scripts/adr.sh check
assert_rc "a cited ADR that does not exist fails after start" 1
assert_contains "the rule citation is named" "docs/rules/r.md cites docs/decisions/0002, which does not exist"
assert_contains "the profile citation is named" "docs/profiles/sci/rules.md cites docs/decisions/0003, which does not exist"
adr 0002-second.md 0002 2026-01-03 accepted
adr 0003-third.md 0003 2026-01-04 accepted
run ./scripts/adr.sh check
assert_rc "creating the cited ADRs clears the failure" 0
# The template itself (Status: TEMPLATE, no .start-done): synced files must
# cite template ADRs in prose, since a path names each project's own records.
printf '# Template\n\n## Project decisions\n\nStatus: TEMPLATE - not initialized.\n' > AGENTS.md
run ./scripts/adr.sh check
assert_rc "a path citation fails in the template even when the record exists" 1
assert_contains "the prose form is named" "docs/rules/r.md cites docs/decisions/0002 by path; this file syncs into projects whose docs/decisions/ holds their own records, so write 'template ADR 0002'"
printf 'Rule from template ADR 0002.\n' > docs/rules/r.md
printf 'Profile rule from template ADR 0003.\n' > docs/profiles/sci/rules.md
printf 'See template ADR 0001 and docs/decisions/NNNN.\n' > docs/procedures/one.md
run ./scripts/adr.sh check
assert_rc "prose citations pass in the template" 0
touch .start-done
printf 'Rule from docs/decisions/0002.\n' > docs/rules/r.md
run ./scripts/adr.sh check
assert_rc "after start a resolving path citation passes again" 0

# The records folder: the AGENTS.md Project decisions line
# "- Decision records: <folder>", else docs/decisions. Records in another
# known ADR folder fail instead of passing with nothing checked.
make_fixture
cp_script adr.sh
pd() { printf '# Project\n\n## Rules index\n\n- Decision records: docs/elsewhere\n\n## Project decisions\n\n%s\n' "$1" > AGENTS.md; }
mkdir -p docs/adr
printf '# 0001 - A decision\n\nDate: 2026-01-02\nStatus: accepted\n\n## Context\n\nX.\n\n## Decision\n\nX.\n\n## Consequences\n\nX.\n' > docs/adr/0001-kept-elsewhere.md
pd '- Decision records: {{docs/decisions (default) or the folder the project keeps them in}}'
run ./scripts/adr.sh check
assert_rc "records in docs/adr/ while the folder is the default fail" 1
assert_contains "the other folder and the fix are named" "docs/adr/ holds 1 decision record(s) (docs/adr/0001-kept-elsewhere.md) but adr.sh checks docs/decisions/; name the folder on the AGENTS.md Project decisions line '- Decision records: docs/adr' or move the records into docs/decisions/"
rm AGENTS.md
run ./scripts/adr.sh check
assert_rc "with no AGENTS.md the default applies and docs/adr/ still fails" 1
pd '- Decision records: docs/adr'
run ./scripts/adr.sh check
assert_rc "the folder named in Project decisions is checked" 0
assert_contains "its record is counted" "adr: OK (1 decision records, numbered 0001 to 0001)"
pd '- Decision records: `docs/adr/` (kept from before the template)'
run ./scripts/adr.sh check
assert_rc "backticks, a trailing slash and a note after the path are accepted" 0
printf '# 0002 - Bad\n' > docs/adr/0002-bad.md
run ./scripts/adr.sh check
assert_rc "the named folder gets the full format check" 1
assert_contains "the bad record there is named" "docs/adr/0002-bad.md: needs a 'Date: YYYY-MM-DD' line"
rm docs/adr/0002-bad.md
mkdir -p docs/procedures
printf 'See docs/adr/0004.\n' > docs/procedures/p.md
run ./scripts/adr.sh check
assert_rc "citations are checked against the named folder" 1
assert_contains "the citation names the named folder" "docs/procedures/p.md cites docs/adr/0004, which does not exist"
rm docs/procedures/p.md
mkdir -p docs/decisions
adr 0001-stale.md 0001 2026-01-02 accepted
run ./scripts/adr.sh check
assert_rc "records left in docs/decisions/ beside the named folder fail" 1
assert_contains "the default folder is named as the stray one" "docs/decisions/ holds 1 decision record(s)"
rm "$D/0001-stale.md"
export ADR_TODAY=2026-11-17
run ./scripts/adr.sh new "Into the named folder"
assert_eq "new writes into the named folder" "docs/adr/0002-into-the-named-folder.md" "$OUT"
unset ADR_TODAY
pd '- Decision records: ../outside'
run ./scripts/adr.sh check
assert_rc "a folder outside the repository is refused" 2
assert_contains "the bad value is named" "adr: the AGENTS.md line '- Decision records:' names '../outside'"
pd '- Decision records: /abs/path'
run ./scripts/adr.sh check
assert_rc "an absolute folder is refused" 2
run ./scripts/adr.sh new "Refused too"
assert_rc "new refuses the bad folder as well" 2

# New numbers against the remote default branch. The "origin" is a local bare
# repository inside the fixture's .git, so no network is touched.
make_fixture
cp_script adr.sh
git symbolic-ref HEAD refs/heads/main
mkdir -p "$D"
adr 0001-first.md 0001 2026-01-02 accepted
run ./scripts/adr.sh check
assert_rc "no origin remote passes" 0
assert_contains "the skipped comparison is said" "adr: origin check skipped: no 'origin' remote; new numbers were not compared with the default branch"
git remote add origin "$FIX/.git/missing.git"
run ./scripts/adr.sh check
assert_rc "an unreachable origin passes" 0
assert_contains "the failed fetch is said" "adr: origin check skipped: could not fetch origin/main (offline, or no such branch); new numbers were not compared"
git remote remove origin
git init -q --bare "$FIX/.git/origin.git"
git -C "$FIX/.git/origin.git" symbolic-ref HEAD refs/heads/main
git remote add origin "$FIX/.git/origin.git"
adr 0002-second.md 0002 2026-01-03 accepted
git add -A && git commit -qm base && git push -q origin main 2>/dev/null
git checkout -q -b theirs
adr 0003-theirs.md 0003 2026-01-04 accepted
git add -A && git commit -qm theirs && git push -q origin theirs:main 2>/dev/null
git checkout -q main
git checkout -q -b mine
adr 0003-mine.md 0003 2026-01-05 accepted
# Without a fetch the comparison has no origin/main to read.
git update-ref -d refs/remotes/origin/main
# The quick lanes skip the fetch and say so; the full gate compares.
QUICK=1 run ./scripts/adr.sh check
assert_rc "QUICK=1 skips the origin comparison" 0
assert_contains "the quick skip is said" "adr: origin check skipped: quick lane (QUICK=1); the full check.sh compares new numbers with the default branch"
run ./scripts/adr.sh check
assert_rc "a new number already taken on origin/main fails" 1
assert_contains "the collision and the fix are named" "docs/decisions/0003-mine.md: number 0003 is already taken on origin/main by docs/decisions/0003-theirs.md; number the ADRs this branch adds from 0004 (after origin/main's last, 0003): git mv the file and fix its title line"
mv "$D/0003-mine.md" "$D/0004-mine.md"
sed -i.bak 's/^# 0003/# 0004/' "$D/0004-mine.md" && rm -f "$D"/*.bak
git merge -q origin/main 2>/dev/null
run ./scripts/adr.sh check
assert_rc "the renumbered ADR after main passes" 0
assert_contains "the comparison is reported" "adr: origin check: 1 ADR(s) added on this branch, none reuses a number on origin/main"
git add -A && git commit -qm mine
git checkout -q main && git merge -q mine 2>/dev/null && git push -q origin main 2>/dev/null
run ./scripts/adr.sh check
assert_contains "a branch even with origin/main adds nothing" "adr: origin check: 0 ADR(s) added on this branch, none reuses a number on origin/main"
# A default branch other than main is read from refs/remotes/origin/HEAD.
git push -q origin main:trunk 2>/dev/null
git -C "$FIX/.git/origin.git" symbolic-ref HEAD refs/heads/trunk
git remote set-head origin trunk >/dev/null 2>&1
git checkout -q -b trunk-side
adr 0005-trunk.md 0005 2026-01-06 accepted
git add -A && git commit -qm trunk && git push -q origin trunk-side:trunk 2>/dev/null
git checkout -q -b t2 main
adr 0005-mine.md 0005 2026-01-06 accepted
run ./scripts/adr.sh check
assert_rc "a collision with origin's default branch named by origin/HEAD fails" 1
assert_contains "the default branch is named" "is already taken on origin/trunk by docs/decisions/0005-trunk.md"

t_finish
