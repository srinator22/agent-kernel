---
name: verify-core
description: Port or verify a numerical function against a golden master so it matches the validated reference number within a derived tolerance. Use when moving or changing any analysis math, signal processing or model code. Do not use for UI or plumbing changes with no numeric output.
---

# verify-core

Args: the function name. Rules: SC-1 to SC-4 in
`docs/profiles/scientific/PROFILE.md`; background in
`docs/rules/scientific-integrity.md`.

## Steps

1. Find the reference implementation (the original tool, a hand calculation, an
   accepted published value) and the validated number it produces on a fixture.
   If no fixture exists, build a small synthetic one whose answer can be worked
   out by hand, and record how.
2. Write the fixture entry first with all four fields: expected value, units,
   source, precision, plus the tolerance and its derivation (SC-2). Use 1
   percent only where that is the accepted contract.
3. Write the failing test against the fixture. Run it and confirm it fails for
   the right reason (missing function, wrong value), not a typo.
4. Port the function with a module header: purpose, inputs, outputs, formula,
   assumptions, and the validation source (AGENTS.md Standards).
5. Run the test until it passes within tolerance. Never move the expected value
   toward the new output (SC-3). If the reference itself is wrong, stop: the
   fixture change is its own reviewed commit with the evidence and decision
   first, and its commit message carries a `Reference-change:` line.
6. Recompute the golden value independently, with a second implementation in
   another language or library, written from the spec and not from your port
   (SC-4). Record the agreement next to the fixture.
7. Test the method on inputs where the right answer is known to be zero or
   trivial (white noise, a constant, an empty series). A method that scores
   noise above zero is wrong however well it matches the golden value.
8. If the function sits in a larger pipeline, add or extend an end-to-end golden
   master on a fixture file, and check determinism by running it twice (SC-5).
9. Run the project's verify command (`./scripts/check.sh`), read the output, and
   only then claim a pass. Commit with a `feat:` or `test:` Conventional Commit.

## Report

Function, fixture, expected value with units and source, tolerance with its
derivation, independent-recomputation result, verify output, and any limit of
the reference (range, sample rate, conditions it was validated under).
