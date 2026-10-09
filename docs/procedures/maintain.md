# Maintain - pruning, caps, freshness

Run monthly or on request; never mid-task. Forgetting is mandatory (kernel
rule 10): archival happens on evidence, never on vibes.

1. Verify caps with `scripts/lessons.sh check`: `AGENTS.md` <= 180 lines;
   <= 20 approved lessons; 8 core skills plus the skills the adopted
   profiles declare (the script enforces it). Over any cap: merge or archive until
   under.
2. Run `scripts/lessons.sh expire` to list lessons unused > 45 days or with
   their retire-when condition met; `scripts/lessons.sh expire --apply`
   archives them. Merge near-duplicates into one generalized entry.
   Archival is a move to `.archive/` with a one-line reason (kernel rule 11).
3. Run `./scripts/check.sh --full-mutation`; quarantine anything flaky in
   `docs/lessons/QUARANTINE.md` as its own task.
4. Audit surviving external/live data calls against the local-first rule
   (each must carry its written reason); convert stragglers. Remove unused
   dependencies; review lockfile drift.
5. Verify the kernel hash; regenerate CHANGELOG.md if a release is pending;
   confirm README.md is still present-tense truthful.
6. Open an issue or PR on the template repository carrying the
   `docs/lessons/UPSTREAM.md` entries (`docs/procedures/upstream.md`), then
   clear them from the file, noting the link in the summary below.
7. Append a dated summary to `docs/lessons/MAINTENANCE.log` (create on
   first run).
