---
name: experiment-review
description: Review experimental coverage, data integrity, model readiness, feature drift, replication gaps and the most informative next experiment. Use when asked what the accumulated dataset supports, why prediction is blocked, whether more runs are needed, or which condition to test next. Use only when explicitly asked.
---

# Review experimental readiness

Rules: SC-6 to SC-12, SC-16; `docs/rules/scientific-integrity.md`.

1. Read the model status record, the current model record, the experiment
   manifests and the latest training note.
2. Run the dataset audit and the generated-file freshness check; read the
   output (kernel rule 14).
3. Count separately: independent experiments, labelled units, mechanisms or
   conditions, set-ups, groups (line, sex, arm), controls and replicate
   coverage. Never add them into one number (SC-12).
4. Confirm every percentage target is either raw or control-relative and that
   the distinction is preserved end to end.
5. Check for:
   - duplicated identities or source hashes;
   - missing controls or provenance;
   - imbalance across mechanisms and conditions;
   - experiment-group leakage (SC-6);
   - feature or model staleness (SC-15);
   - outlier units and feature drift;
   - factors confounded with the experiment (SC-16);
   - too little replication of the thing that varies.
6. Read the per-group diagnostics. Keep these distinct outcomes apart: a low
   noise-floor ratio (replicate noise swamps the signal), no surviving
   repeatable feature, grouped validation unavailable (too few independent
   units), and validated with zero skill. Each calls for a different next step.
7. Recommend the next experiment that resolves the dominant blocker. When
   replicate noise is the blocker, prefer replication within the
   under-replicated condition. When separation between conditions is too small,
   prefer a deliberately contrasting condition.
8. Report confirmed evidence, limitations, and the exact gate the next
   experiment is meant to improve (SC-10, SC-11). Do not promise that one more
   run will make the model valid, and never propose loosening a gate instead.

Status words follow SC-8; use "validated" only when the SC-9 rule is met.
