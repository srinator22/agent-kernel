# b18 budgetline (worker D8)

## Goal
BACKLOG row A: selftest.sh prints the test-budget line after a full run. Row B: narrow
tests/template/selftest-inputs.list from all of docs/, and key the python and ruff versions.

## Acceptance criteria and evidence
- A full selftest run prints the `test-budget:` line, exit status unchanged: test_selftest.sh "the test-budget line" cases.
- Named file, shard, absent script, absent tests/BUDGET print nothing: same cases.
- docs/ narrowed to files and folders the tests read: audit below; proof is the CI selftest-inputs job (verify-inputs runs the whole suite; not runnable locally).
- python and ruff versions in the key; a changed python identity misses: test_selftest_reuse.sh cases.

## Decisions
- Audit: grep of docs/ paths in tests/template, scripts, tests/docs, .claude, .codex, .agents, .github. Read top-level: BLUEPRINT.md, ARCHITECTURE.md, operations.md (check.sh 5b required list), DEFECT_MEMORY.md. Subfolders kept whole: procedures, rules, profiles, decisions, lessons, library, roster, preferences. Dropped: docs/assets, docs/research (no reader).
- Ruff identity: TEMPLATE_RUFF if set, else ruff on PATH (how check.sh 5k picks it), else "none"; uvx and pipx routes are not seen (documented).
- Python identity: the interpreter scripts/find-python.sh picks; "none" when absent or the script is missing.
- Budget line is the first stdout line starting "test-budget: "; stderr dropped.

## Progress log
- list, reuse script and test, selftest.sh and test edited; the two touched test files run.

## Open risks
- CI selftest-inputs job not run locally; an undeclared docs path read by a test would fail there.
