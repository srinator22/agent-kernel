# CI cost - when checks take too long

Run when checks hold up delivery or burn compute. Order: measure, delete
waste, stage, reuse, select, localise, cache, balance. Every step keeps
the required answer: kernel rule 5 needs every
required check green for the exact pushed SHA; a release gate stays
attached to the version shipped. Moving or narrowing a check never makes a
required answer optional.

1. Baseline first. Applies always, before any change. Record in the task
   record: per-job durations of the last N runs (`gh run list`, then
   `gh run view <id> --json jobs`); locally the `check.sh: timing:` line
   and the `selftest: slowest:` line; agent cycle time, PR opened to merged
   (`gh pr list --state merged --json createdAt,mergedAt`). Verify: numbers
   carry units, N and dates. Trap: a median of successful runs hides queue
   time, retries and cancelled runs; state what the sample leaves out.
2. Delete waste before optimizing. Applies when the suite grew faster than the
   product. Name the contract each test protects, keep one strong owner per
   contract, drop duplicates (`docs/procedures/tests.md` "Test audit").
   Verify: break
   the code on purpose and see the retained test fail. Trap: deleting by
   slowness; a fast test may protect nothing, a slow one may be the only
   guard. Never delete the only regression test (kernel rule 2).
3. Stop jobs before setup, cancel what is superseded. Applies to optional or
   conditional jobs. A job-level `if:` fed by a `paths` job allocates no
   runner; a step-level skip has paid for setup. Use
   `concurrency` with `cancel-in-progress` for pull-request runs only. Verify:
   a skipped job shows "skipped", not a green job with empty steps. Trap:
   cancel-in-progress on main, tags or deploys cancels a run that must finish;
   GitHub also cancels a pending run in a shared group, so
   key non-PR runs on ref and SHA (`docs/rules/ci-baseline.md`).
4. Stage checks by when the answer is needed. Applies when one workflow runs
   everything on every push. Three stages:
   the PR answer required to merge;
   small push-to-main guards; scheduled broad
   validation of a named main revision, with an owner for failures.
   Verify: the required check list in branch protection is unchanged and still
   runs for the exact SHA. Trap: an old green scheduled run is no proof
   for a newer commit; a release gate must match the version shipped.
5. Reuse results whose inputs are unchanged. Applies to template
   self-tests: `scripts/selftest-reuse.sh` skips a test whose inputs listed in
   `tests/template/selftest-inputs.list` are unchanged since a green run;
   `CHECK_SELFTEST=full` forces a run; CI's `verify-inputs` job proves the list
   complete. For a project suite,
   key a result on a hash of
   every input. Verify: change one listed input and see the test run. Trap: an
   incomplete inputs list silently skips a test.
6. Select tests from the change, deterministically. Applies once the suite is
   audited and large. Map changed files to owner tests, then reverse imports
   (callers); a changed test runs; shared, unknown, dynamic or deleted paths
   widen the run; an incomplete plan is rejected, never read as "nothing to
   run". Verify:
   backtest against past
   regressions (replay a past fix's diff, confirm the exposing test is
   selected) and
   keep a switch that forces the full run. Trap: a learned model
   as the skipper.
   Run any prediction in shadow mode first (record picks,
   run everything, count misses).
   Files read from disk are invisible to an
   import graph; declare them.
7. Catch cheap failures locally. Applies to format, lint and focused tests
   (`./scripts/check.sh --fast`). Verify: the same
   check still runs in CI. Trap:
   a skipped hook is not proof; CI keeps the
   required checks.
8. Make cache hits real, and fetch less. Applies when setup dominates a small
   job.
   Key the cache on lockfile hash, toolchain version and platform.
   Only trusted jobs write the
   cache; untrusted jobs restore only. Use a blobless checkout (`filter:
   blob:none`) when the job needs history for a diff. Verify: a second run
   shows a hit and less setup time. Trap: a shallow checkout can drop the merge
   base and give a wrong diff.
9. Pack and balance shards by measured time, then size runners. Applies when
   jobs repeat setup or one job finishes long after the rest.
   `scripts/selftest.sh --shard K/N` splits by
   `tests/template/selftest-weights.txt`.
   Each extra shard repeats setup. Runner size trades cost for time
   (one paired job: 41.7% cheaper and 16.5% slower
   on the smaller runner). Verify: compare slowest job and billed
   minutes before and after. Trap: more shards
   can raise cost; stale weights unbalance the split.
   Locally an agent session runs
   at most 8 concurrent
   heavy background tasks, with the count
   recorded in the task record.
10. Record before and after. Applies to every step above. Write both numbers
    with units, the sample, and
    what was not measured (wall time versus billed
    time, queue time, PR-to-merge) in the task record (kernel rule 14). Trap:
    adding gains measured on different clocks, or crediting one change
    with a drop several changes produced.
