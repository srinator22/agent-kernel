# Tests - from day one

Tests exist before the first feature. Start wires the harness, the gate
step and one passing test per applicable layer (kernel rules 2 and 4).

1. Wire per stack, as applicable, and name each in `scripts/stack-check.sh`:
   unit, property-based, golden-master, integration, end-to-end. Log a
   layer as "N/A - reason" in START_REPORT.md rather than omitting it.
   Also, a replacement or port gets differential
   tests: run old and new on the same inputs, normalize harmless
   differences, and keep an approved-differences list.
2. Test contract. Deterministic: no wall-clock races, no order
   dependence, seeds fixed and stored. Await real completion (promise,
   event or process exit), never a sleep. Assert behaviour at
   the contract, not internals. Cover empty, malformed, extreme,
   duplicate, partial and missing inputs.
3. Oracle first. The acceptance document (`.work/TASK.md`, a spec or a
   reference) is written before the tests. Each assertion names, in a
   comment or id, the document line it enforces. Numbers are read from
   the source of truth, never retyped into the test.
4. Golden masters. Pin ported or numerical logic to validated real
   numbers with units, source and tolerance written beside each value
   (docs/rules/scientific-integrity.md). Never change an expected value
   to match new output; a wrong reference is its own reviewed commit.
   An expected value that can be mathematically zero carries an absolute
   tolerance scaled to the problem, never a relative one only.
5. Quarantine protocol. A flaky test is a defect (kernel rule 2). Add it
   to `tests/quarantine.list`, read by the test runner: one test path per
   line, `# owner: <task> date: YYYY-MM-DD`. The runner skips only listed
   paths and prints them each run: `scripts/selftest.sh` for
   `tests/template/` paths (a listed path that does not exist fails it), the
   project's own runner (wired in `scripts/stack-check.sh`) for the rest. A
   case that does not apply here prints an `n/a` line naming
   the gate that covers it (`t_na` in `tests/template/lib.sh`). The maintain
   pass fails on any entry older
   than 30 days (`scripts/lessons.sh check` reads the file); also record it
   in `docs/lessons/QUARANTINE.md`. Deleting or weakening a
   test is never quarantine.
   Adoption baseline: when the template is adopted into an existing project,
   every test that already fails goes to the list with an owner task and the
   adoption date.
6. Fakes. A fake dependency reproduces the real one's failure
   behaviour (timeouts, partial writes, retries, error codes), not only
   success; a test pins each fake against recorded real behaviour.
7. A missing toolchain fails the gate; it never skips. A test that
   cannot run because its tool is absent is a red check, not a pass.
8. Timeouts are sized for the CI runner, with headroom, not for the
   laptop. A timeout expiry reports the awaited condition, not a bare
   failure.
9. The template's own scripts are tested by `scripts/selftest.sh`
   (fixtures under `tests/template/`), called from `check.sh`. A script
   change that skips its selftest case is incomplete.
10. Regression tests: a defect that escapes gets its failing test before
    the fix and a row in `docs/DEFECT_MEMORY.md` (kernel rule 3;
    `docs/procedures/bugfix.md`). Behaviour changes extend or add a
    scenario in the same change.
11. Scripted edits and mutation runs. A script that edits a file asserts its
    anchor matches exactly once before replacing. In a mutation run,
    each test's workflow run lives in a function-scoped fixture, so one
    mutant's state never leaks into the next test.

## Test audit

Deleting and consolidating tests is a first-class deliverable of a test
change.

1. Audit one subsystem at a time. Read the production code and its tests;
   for each test: name the behaviour it protects; show a believable bug
   (a one-line change to the code) that would make it fail; keep one strong
   owner per contract. A test with no believable bug is repaired or removed;
   a second test whose only bug the owner already catches is merged or
   removed.
2. Kernel rule 2 holds: never delete or weaken a test to get green, and
   never delete the only regression guard for a defect (a row in
   `docs/DEFECT_MEMORY.md` names its test). Consolidation keeps every
   distinct contract assertion.
3. Ledger. An audit records, in `.work/done/<date>-<slug>-ledger.md`: the
   areas completed, the duplication removed (file and lines, before and
   after), the contract coverage that remains, and unresolved
   risks. A later pass starts from the ledger instead of re-reading the suite.
4. Budget. `tests/BUDGET` names the counted test files (`paths:`), the
   current `ceiling:` in non-blank lines and a per-change `allowance:` (the
   template ships 400). `scripts/test-budget.sh check` (check.sh step 4)
   fails when the count exceeds ceiling plus allowance: consolidate or delete
   duplicates, or raise the ceiling in the same
   change with a dated `raise: <old>-><new> <YYYY-MM-DD> <reason>` line.
   After a pass that removes lines, lower `ceiling:` to the new count.
   `scripts/test-budget.sh report` lists files by
   size. A project edits `paths:` for its own suites; a project whose sync
   predates the file skips the check with a printed line.
