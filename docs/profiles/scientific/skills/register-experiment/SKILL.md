---
name: register-experiment
description: Register a new experiment from a raw capture, the selected labelled units, outcome counts, controls and provenance. Use when adding a run, mapping captured units to outcome replicates, converting absolute outcomes to control-relative targets, or preparing repository training data without committing the raw capture. Use only when explicitly asked to add data.
---

# Register an experiment

Rules: SC-5, SC-6, SC-12, SC-13, SC-14, SC-16 and DA-1 to DA-4 when the
data-analysis profile is adopted. Read the project's data intake and experiment
toolkit docs first (named in the profile's Parameters and records section).

1. Inspect the source capture and evidence. Do not infer dates, labels, counts,
   mounting, set-up or target meaning from file names when the user supplied a
   different authoritative source. Unknown stays `N/A - reason`, never guessed.
2. Prepare the raw capture outside git with the project's prepare command. The
   output directory must be new, so a stale unit file cannot survive a changed
   detection result (SC-14). Exit 2 means needs review, never a pass.
3. Review the boundary plot and the detection report. Stop if the expected unit
   count fails, long-gap flags make numbering ambiguous, or a set-up or tuning
   pulse was not separated from the real units.
4. Scaffold the record with the project's scaffold command. Keep its status
   `pending_metadata` until every required field and stored-file hash is
   confirmed.
5. Copy only outcome-linked unit files into the repository. Never copy the full
   raw capture into git (SC-13); record its name, byte size, SHA-256, capture
   provenance and `rawFileStoredInRepository: false`.
6. Map unit to replicate explicitly. A unit's capture index and its physical
   number can differ (a restart, an excluded failed cycle); record both.
   Preserve treatment and control counts per group (for example per sex or
   per arm) separately.
7. State the target semantics. Supplied percentages are absolute unless the
   user explicitly says they are already relative to control; store the target
   type (raw, or control-relative) and keep the original counts at full
   precision. Rounded tables are audit output only.
8. Add evidence files with hashes. Do not invent missing metadata.
9. Validate the outcome arithmetic and audit the whole dataset, then rebuild
   generated model files via the `train-model` skill.
10. Mark the experiment `ready` only after every audit error is resolved.
    Report independent experiments separately from labelled units (SC-12); a
    new unit is not a new independent experiment.

Write the limitations seen (drift within a run, few replicates, a factor
confounded with this experiment) next to the record (SC-16).
