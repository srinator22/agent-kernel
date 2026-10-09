# Tests - from day one

Tests exist before the first feature. Start wires the harness, the gate
step and one passing test per applicable layer, so the first real change
already has somewhere to put its test (kernel rules 2 and 4).

1. Wire per stack, as applicable, and name each in `scripts/check.sh`:
   unit, property-based, golden-master, integration, end-to-end. Log a
   layer as "N/A - reason" in START_REPORT.md rather than omitting it.
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
   paths and prints them each run. The maintain pass fails on any entry older
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
