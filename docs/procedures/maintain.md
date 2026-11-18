# Maintain - pruning, caps, freshness

Run monthly or on request; never mid-task. Forgetting is mandatory (kernel
rule 10): archival happens on evidence, never on vibes.

1. Verify caps: `./scripts/check.sh` (the `AGENTS.md` line budget) and
   `scripts/lessons.sh check` (<= 20 approved lessons; core
   skills (at most 8) plus 2 project skills plus adopted-profile skills;
   rules files <= 40 lines). Over any cap: merge or
   archive until under. The check also fails a lesson with `used: 0` more
   than 45 days after its `approved:` date, and warns on a `[met]` marker.
2. Run `scripts/lessons.sh expire` to list lessons unused > 45 days or with
   their retire-when condition met; `scripts/lessons.sh expire --apply`
   archives them. A lesson whose content now lives in a repo file (kernel
   rule 9) or a check goes with `scripts/lessons.sh archive <Lnnn> <reason>`,
   naming the file or check. Merge near-duplicates into one
   entry. Archival is a move to `.archive/` with a one-line
   reason (kernel rule 11). Read every retire-when against the repo before
   keeping a lesson, and record the evidence per lesson in the step 7 entry.
3. Run `./scripts/check.sh --full-mutation`; quarantine anything flaky in
   `tests/quarantine.list` (owner and date) and record it in
   `docs/lessons/QUARANTINE.md` (`docs/procedures/tests.md` step 5), each
   as its own task.
4. Audit surviving external/live data calls against the local-first rule
   (each must carry its written reason); convert stragglers. Remove unused
   dependencies; review lockfile drift.
5. Verify the kernel hash; regenerate CHANGELOG.md if a release is pending;
   confirm README.md is still present-tense truthful.
5a. Run the doc evaluation (`docs/procedures/doc-eval.md`) and put its counts
   in the step 7 summary.
6. Open an issue or PR on the template repository carrying the
   `docs/lessons/UPSTREAM.md` entries (`docs/procedures/upstream.md`), then
   clear them from the file, noting the link in the summary below.
7. Append a dated summary to `docs/lessons/MAINTENANCE.log` (create on
   first run). Its first line is `YYYY-MM-DD maintain: <summary>` - the line
   `scripts/session-context.sh` looks for: with none dated within the last 35
   days it prints a reminder at session start. Indent per-lesson
   evidence lines beneath it. `expire --apply` and `archive` add their own
   `YYYY-MM-DD expire:` and `archive:` lines, which do not count as a pass.
