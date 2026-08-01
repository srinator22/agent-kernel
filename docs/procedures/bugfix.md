# Bugfix - reproduce, root cause, failing test, smallest fix

1. Reproduce with the smallest reliable case, against real data where it
   exists. Get a numeric, exact root cause before writing a fix -
   instrument the actual code path; do not theorize.
2. Identify the owning layer. If the bug escaped past merge or was reported
   by the human: write the failing regression test first, pinned to the
   real numbers from step 1, not a synthetic happy path (kernel rule 3).
3. Patch the smallest safe surface; no unrelated cleanup in the same change
   (kernel rule 4).
4. Run the targeted tests, then `./scripts/check.sh`. Re-verify against the
   motivating real data independently of the unit tests.
5. Independent adversarial review (the reviewer agent) trying to find what
   is still wrong, not rubber-stamping.
6. Ship per `docs/procedures/ship.md`. When speed is requested, parallelize
   steps across workers; that is never permission to skip re-verification
   or review.
