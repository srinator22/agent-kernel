# Maintain - pruning, caps, freshness

Run monthly or on request; never mid-task. Forgetting is mandatory (kernel
rule 10): archival happens on evidence, never on vibes.

1. Verify caps: `AGENTS.md` <= 180 lines; <= 20 approved lessons; <= 8
   skills. Over any cap: merge or archive until under.
2. Archive lessons unused > 45 days or with their retire-when condition met;
   merge near-duplicates into one generalized entry. Archival is a move to
   `.archive/` with a one-line reason (kernel rule 11).
3. Run `./scripts/check.sh --full-mutation`; quarantine anything flaky in
   `docs/lessons/QUARANTINE.md` as its own task.
4. Audit surviving external/live data calls against the local-first rule
   (each must carry its written reason); convert stragglers. Remove unused
   dependencies; review lockfile drift.
5. Verify the kernel hash; regenerate CHANGELOG.md if a release is pending;
   confirm README.md is still present-tense truthful.
6. Append a dated summary to `docs/lessons/MAINTENANCE.log` (create on
   first run).
