#!/usr/bin/env bash
# adr.sh: check (file names, contiguous numbering, title line, Date and Status,
# superseded-by target, leftover placeholders) and new (next number, slug,
# template that fails check until filled).
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

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

t_finish
