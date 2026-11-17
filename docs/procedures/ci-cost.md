# CI cost - when checks take too long

Run when checks hold up delivery or burn compute: a PR waits on CI, agents
queue behind each other, or the bill grows. The order matters: measure, delete
waste, then stage, reuse, select, localise, cache, balance. Every step keeps
the required answer: kernel rule 5 still needs every required check green for
the exact pushed SHA, and a release gate stays attached to the version
shipped. Moving or narrowing a check never makes a required answer optional.

Source: Vincent Koc, "Making OpenClaw CI faster and 95% cheaper" (2026-11-17,
https://vincent.build/openclaw-ci-cost-reduction/). Its numbers are one
organisation's, on a changing workload, and not causally split per change;
this template has measured only what its own timing lines print.

1. Baseline first. Applies always, before any change. Record in the task
   record: per-job durations of the last N runs (`gh run list`, then
   `gh run view <id> --json jobs`); locally the `check.sh: timing:` line and
   the `selftest: slowest:` line; agent cycle time, PR opened to merged
   (`gh pr list --state merged --json createdAt,mergedAt`). Verify: the numbers
   carry units, N and dates. Trap: a median of successful runs hides queue
   time, retries and cancelled runs; state what the sample leaves out.
2. Delete waste before optimizing. Applies when the suite grew faster than the
   product. Name the contract each test protects, keep one strong owner per
   contract, drop implementation-mirroring duplicates, keep growth visible
   (`docs/procedures/tests.md` "Test audit" and `tests/BUDGET`). Verify: break
   the code on purpose and see the retained test fail. Trap: deleting by
   slowness; a fast test may protect nothing and a slow one may be the only
   guard. Never delete the only regression test (kernel rule 2).
3. Stop jobs before setup, cancel what is superseded. Applies to optional or
   conditional jobs. A job-level `if:` fed by a `paths` job allocates no
   runner; a step-level skip has already paid for checkout and setup. Use
   `concurrency` with `cancel-in-progress` for pull-request runs only. Verify:
   a skipped job shows "skipped", not a green job with empty steps. Trap:
   cancel-in-progress on main, tags or deploys cancels a run that must finish
   (`docs/rules/ci-baseline.md`).
4. Stage checks by when the answer is needed. Applies when one workflow runs
   everything on every push. Three stages: the PR answer required to merge;
   small push-to-main guards that catch immediate breakage; scheduled broad
   validation of a named main revision, with an owner for its failures.
   Verify: the required check list in branch protection is unchanged and still
   runs for the exact SHA. Trap: treating an old green scheduled run as proof
   for a newer commit; a release gate must match the version shipped.
5. Reuse results whose inputs are unchanged. Applies to the template
   self-tests: `scripts/selftest-reuse.sh` skips a test whose inputs listed in
   `tests/template/selftest-inputs.list` are unchanged since a green run;
   `CHECK_SELFTEST=full` forces a run; CI's `verify-inputs` job proves the list
   complete. Same principle for a project suite: key a result on a hash of
   every input. Verify: change one listed input and see the test run. Trap: an
   incomplete inputs list silently skips a test that should run; widen when in
   doubt.
6. Select tests from the change, deterministically. Applies once the suite is
   audited and large. Map changed files to owner tests, then reverse imports
   (callers); a changed test runs; shared, unknown, dynamic or deleted paths
   widen the run; an incomplete plan is rejected, never read as "nothing to
   run". Record why each test was chosen. Verify: backtest against past
   regressions (restore the revision before a fix, replay the diff, confirm the
   test that exposes the bug is selected), including deleted files and shared
   helpers, and keep a switch that forces the full run. Trap: a learned model
   as the skipper. Run any prediction in shadow mode first (record its picks,
   run everything, count misses). Files read from disk are invisible to an
   import graph; declare them.
7. Catch cheap failures locally. Applies to format, lint and focused tests that
   an author can run in seconds (`./scripts/check.sh --fast`). Verify: the same
   check still runs in CI. Trap: a skipped hook is not proof; CI keeps the
   required checks.
8. Make cache hits real, and fetch less. Applies when setup dominates a small
   job. Key the cache on lockfile hash, toolchain version and platform; read the
   restore result and the install time still spent. Only trusted jobs write the
   cache; untrusted jobs restore only. Use a blobless checkout (`filter:
   blob:none`) when the job needs history for a diff. Verify: a second run
   shows a hit and less setup time. Trap: a shallow checkout can drop the merge
   base and give a wrong diff; a cache shared with an untrusted job can be
   poisoned.
9. Pack and balance shards by measured time, then size runners. Applies when
   jobs repeat setup or one job finishes long after the rest.
   `scripts/selftest.sh --shard K/N` splits by `tests/template/selftest-weights.txt`.
   Sharding divides the suite; parallelism is how many shards run at once, and
   each extra shard repeats setup. Balance so jobs end together. Runner size is
   a cost x time tradeoff: the article's one paired job (240 test files) was
   41.7% cheaper and 16.5% slower on the smaller runner. Verify: compare the
   slowest job and total billed minutes before and after. Trap: more shards
   shorten the wait and can raise the cost; stale weights unbalance the split.
   Locally the same limit applies to an agent session: at most 8 concurrent
   heavy background tasks (full checks, suites, renders), with the count
   recorded in the task record. Trap: dozens of parallel suites on one
   machine starve each other and finish later than a few at a time.
10. Record before and after. Applies to every step above. Write both numbers
    with units, the sample, and what was not measured (wall time versus billed
    time, queue time, PR-to-merge) in the task record (kernel rule 14). Trap:
    adding up gains measured on different clocks, or crediting one change with
    a drop that several changes and a changing workload produced.
