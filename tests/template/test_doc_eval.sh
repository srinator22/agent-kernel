#!/usr/bin/env bash
# doc-eval.sh: question-table validation (format, ids, kinds, existing sources,
# minimum counts) and the brief, which must never carry the key or sources.
# Also checks the shipped tests/docs/questions.md is valid.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

HDR='| id | kind | question | answer key | sources |
|---|---|---|---|---|'
# table ROWS...: write tests/docs/questions.md with the header and the rows.
table() { mkdir -p tests/docs; { echo "# Q"; echo; echo "$HDR"; printf '%s\n' "$@"; } > tests/docs/questions.md; }
A() { echo "| $1 | answerable | Question $1? | Key $1 SECRETKEY | docs/a.md |"; }
T() { echo "| $1 | trap | Trap $1? | Decline $1 SECRETKEY | - |"; }

make_fixture
cp_script doc-eval.sh
mkdir -p docs && echo "doc" > docs/a.md

run ./scripts/doc-eval.sh
assert_rc "no subcommand is a usage error" 2
run ./scripts/doc-eval.sh check extra
assert_rc "an extra argument is a usage error" 2

run ./scripts/doc-eval.sh check
assert_rc "a missing question file passes check with a note" 0
assert_contains "the note names the file" "no question file"
run ./scripts/doc-eval.sh brief
assert_rc "brief without a question file fails" 1

table "$(A q01)" "$(T q02)" "$(A q03)" "$(A q04)" "$(T q05)" "$(A q06)" "$(T q07)" "$(A q08)"
run ./scripts/doc-eval.sh check
assert_rc "a valid table passes" 0
assert_contains "counts are reported" "5 answerable, 3 trap questions"

printf 'id\r\n' > /dev/null
sed 's/$/\r/' tests/docs/questions.md > q.tmp && mv q.tmp tests/docs/questions.md
run ./scripts/doc-eval.sh check
assert_rc "a CRLF table passes" 0

run ./scripts/doc-eval.sh brief
assert_rc "brief exits 0" 0
assert_contains "brief lists a question with its id" "q01: Question q01?"
assert_contains "brief lists a trap like any other question" "q02: Trap q02?"
assert_not_contains "brief never prints the answer key" "SECRETKEY"
assert_not_contains "brief never prints a source path" "docs/a.md"
assert_not_contains "brief never prints the kind" "answerable"
assert_contains "brief tells the agent to decline" "DECLINE: not covered"
assert_contains "brief keeps the agent out of the key" "anything under tests/docs/"

table "$(A q01)" "$(T q02)" "| q03 | answerable | Question? | Key | docs/missing.md, docs/a.md |" "$(A q04)" "$(T q05)" "$(A q06)" "$(T q07)" "$(A q08)"
run ./scripts/doc-eval.sh check
assert_rc "a missing source fails" 1
assert_contains "the missing source is named" "q03: source does not exist: docs/missing.md"

table "$(A q01)" "$(T q02)" "| q03 | answerable | Question? | Key | \`docs/a.md\` |" "$(A q04)" "$(T q05)" "$(A q06)" "$(T q07)" "$(A q08)"
run ./scripts/doc-eval.sh check
assert_rc "a backticked source path passes" 0

table "$(A q01)" "$(T q02)" "| q03 | answerable | Question? | Key | - |" "| q09 | trap | Trap? | Decline | docs/a.md |" "$(A q04)" "$(T q05)" "$(A q06)" "$(T q07)" "$(A q08)"
run ./scripts/doc-eval.sh check
assert_rc "wrong sources cells fail" 1
assert_contains "an answerable row needs sources" "q03: an answerable question needs its source paths"
assert_contains "a trap row needs -" "q09: a trap question's sources cell must be -"

table "$(A q01)" "$(A q01)" "| Q2 | answerable | Question? | Key | docs/a.md |" "| q03 | guess | Question? | Key | docs/a.md |" "| q04 | answerable | Not a question | | docs/a.md |" "| q05 | answerable | {{question}}? | Key | docs/a.md |" "| q06 | trap | Too | few | cells |  extra |" "$(T q07)"
run ./scripts/doc-eval.sh check
assert_rc "malformed rows fail" 1
assert_contains "duplicate id" "duplicate id q01"
assert_contains "bad id" "id 'Q2' must be a letter and two or more digits"
assert_contains "bad kind" "q03: kind 'guess' must be answerable or trap"
assert_contains "question must end with ?" "q04: the question must be non-empty and end with ?"
assert_contains "empty key" "q04: empty answer key"
assert_contains "placeholder" "q05: unfilled placeholder"
assert_contains "wrong cell count" "row has 6 cells, expected 5"
assert_contains "minimum traps" "only 1 trap questions; keep at least 3"
assert_contains "problem count" "check FAILED"

table "$(A q01)" "$(T q02)" "$(T q03)" "$(T q04)"
run ./scripts/doc-eval.sh check
assert_rc "too few answerable questions fail" 1
assert_contains "minimum answerable" "only 1 answerable questions; keep at least 5"

mkdir -p tests/docs && echo "no table here" > tests/docs/questions.md
run ./scripts/doc-eval.sh check
assert_rc "a file without the table fails" 1
assert_contains "the missing table is named" "has no '| id | kind | question | answer key | sources |' table"

run env DOCEVAL_FILE=elsewhere.md ./scripts/doc-eval.sh check
assert_rc "DOCEVAL_FILE selects another file" 0
assert_contains "the other file is the one checked" "no question file at elsewhere.md"
t_cleanup

# The shipped question set is valid against the real repository.
OUT="$(cd "$T_ROOT" && ./scripts/doc-eval.sh check 2>&1)"; RC=$?
assert_rc "the shipped tests/docs/questions.md passes check" 0

t_finish
