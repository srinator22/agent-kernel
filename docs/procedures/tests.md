# Tests - from day one

Tests exist before the first feature. Start wires the harness, the gate
step and one passing test per applicable layer, so the first real change
already has somewhere to put its test (kernel rules 2 and 4).

1. Wire per stack, as applicable, and name each in `scripts/stack-check.sh`:
   unit, property-based, golden-master, integration, end-to-end. Log a
   layer as "N/A - reason" in START_REPORT.md rather than omitting it.
   Next to property-based tests, a replacement or port gets differential
   tests: run the old and new system on the same inputs, normalize
   differences that cannot matter, and keep an approved-differences list.
2. Test contract. Deterministic: no wall-clock races, no order
   dependence, seeds fixed and stored. Await real completion (the
   promise, event or process exit), never a sleep. Assert behaviour at
   the contract, not internals. Cover empty, malformed, extreme,
   duplicate, partial and missing inputs.
3. Oracle first. The acceptance document (`.work/TASK.md`, a spec or a
   reference) is written before the tests. Each assertion names, in a
   comment or id, the document line it enforces. Numbers come from the
   source of truth by reading it (a generated fixture, a parsed spec),
   never retyped into the test.
4. Golden masters. Pin ported or numerical logic to validated real
   numbers with units, source and tolerance written beside each value
   (docs/rules/scientific-integrity.md). Never change an expected value
   to match new output; a wrong reference is its own reviewed commit.
5. Quarantine protocol. A flaky test is a defect (kernel rule 2). Add it
   to `tests/quarantine.list`, read by the test runner: one test path per
   line, `# owner: <task> date: YYYY-MM-DD`. The runner skips only listed
   paths and prints them each run: `scripts/selftest.sh` for
   `tests/template/` paths (a listed path that does not exist fails it), the
   project's own runner (wired in `scripts/stack-check.sh`) for the rest. A
   case that does not apply in this repository prints an `n/a` line naming
   the gate that covers it (`t_na` in `tests/template/lib.sh`), and selftest
   shows those lines on every run. The maintain pass fails on any entry older
   than 30 days (`scripts/lessons.sh check` reads the file); the entry is
   also recorded in `docs/lessons/QUARANTINE.md`. Deleting or weakening a
   test is never quarantine.
   Adoption baseline: when the template is adopted into an existing project,
   every test that already fails goes to the list with an owner task and the
   adoption date; the gate is green only because the quarantine is explicit
   and each entry expires in 30 days.
6. Fakes. A fake dependency reproduces the real one's failure behaviour
   (timeouts, partial writes, retries, error codes), not only success. A
   test pins each fake against recorded real behaviour, so the fake
   cannot drift from what it stands for.
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
    `docs/procedures/bugfix.md`). Behaviour changes extend an existing
    scenario or add one in the same change.

## Test audit

Agents add tests easily and delete them rarely, so a suite grows without
protecting more. More test code is not more protection: a test that restates
the implementation, breaks on a harmless refactor or stays green when its
behaviour breaks is noise ("make every test earn its place", the OpenClaw
write-up, Nov 2026). Deleting and consolidating tests is a first-class
deliverable of a test change, not cleanup to skip.

1. Audit one subsystem at a time. Read the production code and its tests,
   then for each test: name the behaviour it protects; show a believable bug
   (a one-line change to the code) that would make it fail; keep one strong
   owner per contract. A test with no believable bug is repaired or removed;
   a second test whose only bug is already caught by the owner is merged into
   it or removed.
2. Kernel rule 2 still holds. Never delete or weaken a test to get green, and
   never delete the only regression guard for a defect (a row in
   `docs/DEFECT_MEMORY.md` names its test). Consolidation keeps every
   distinct contract assertion.
3. Ledger. An audit records, in `.work/done/<date>-<slug>-ledger.md`: the
   areas completed, the duplication removed (file and lines, before and
   after), the contract coverage that remains per file, and unresolved
   risks. A later pass starts from the ledger instead of re-reading the suite.
4. Budget. `tests/BUDGET` names the counted test files (`paths:`), the
   current `ceiling:` in non-blank lines and a per-change `allowance:` (the
   template ships 400). `scripts/test-budget.sh check` (check.sh step 4)
   fails when the count exceeds ceiling plus allowance; the remedy is to
   consolidate or delete duplicates, or to raise the ceiling in the same
   change with a dated `raise: <old>-><new> <YYYY-MM-DD> <reason>` line.
   After a pass that removes lines, lower `ceiling:` to the new count so the
   saving is not spent again. `scripts/test-budget.sh report` lists files by
   size. A project edits `paths:` for its own suites; a project whose sync
   predates the file skips the check with a printed line.
