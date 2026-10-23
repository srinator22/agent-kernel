# Bugfix - reproduce, root cause, failing test, smallest fix

1. Reproduce with the smallest reliable case, against real data where it
   exists. Get a numeric, exact root cause before writing a fix -
   instrument the actual code path; do not theorize. State the root cause
   as file, function and condition (for example "`src/parse.ts`,
   `readHeader`, a header shorter than 4 bytes is read past its end").
2. Identify the owning layer. For every fix, not only bugs that escaped
   past merge: write the regression test first, pinned to the real
   numbers from step 1, not a synthetic happy path (kernel rule 3).
3. Run the new test before patching and confirm it fails for the stated
   root cause: the failure message points at that file, function and
   condition, not at a typo, a missing import or an unrelated assertion. A
   test that passes before the patch tests nothing; rewrite it. Record the
   repro command and its failing output (verbatim, trimmed to the
   relevant lines) in the Progress log of `.work/TASK.md`.
4. Patch the smallest safe surface; no unrelated cleanup in the same change
   (kernel rule 4).
5. Run the targeted tests (the new test now passes; record that output
   too), then `./scripts/check.sh`. Re-verify against the motivating real
   data independently of the unit tests.
6. Independent adversarial review (the reviewer agent) trying to find what
   is still wrong, not rubber-stamping.
7. Ship per `docs/procedures/ship.md`. When speed is requested, parallelize
   steps across workers; that is never permission to skip re-verification
   or review.
