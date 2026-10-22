---
name: train-model
description: Audit, rebuild, evaluate and explain the repository-backed model. Use when new labelled experiments are added, generated model files may be stale, training is requested, or readiness and grouped-validation results must be reported. Use only when explicitly asked.
---

# Train the model

Rules: SC-5 to SC-12, SC-14, SC-15. Scoring and status vocabulary:
`docs/rules/scientific-integrity.md`.

1. Read the project's data intake and toolkit docs and the current model status
   record. Run `git status` and preserve unrelated work.
2. Run the integrity gates: dataset audit, then outcome validation.
3. Stop on missing files, checksum mismatches, duplicate experiment, run or unit
   identities, unresolved target semantics, or pending metadata on a record
   marked ready.
4. Rebuild through the validated repository generator. Never hand-edit a
   generated model, status or table file (kernel rule 18). Seeds derive from
   content and are stored with the parameters they seeded (SC-5).
5. Run the project's verify command (`./scripts/check.sh`) and read its output;
   the freshness gate must show the regenerated files byte-identical (SC-15).
6. Read the generated model and status. Report, per group (for example per line
   and sex):
   - independent experiment count and labelled unit count;
   - noise-floor ratio (replicate noise against signal);
   - selected features;
   - grouped cross-validation error, the baseline error on the same held-out
     points, and skill = 1 - (rmse / baselineRmse)^2 (SC-7);
   - the significance result and minimum independent units of the SC-9 rule;
   - readiness state and the technical reason.
7. Keep experiment groups intact. Never split units or conditions of one
   experiment across training and validation (SC-6); run the leakage gate.
8. Never weaken a minimum-experiment, noise, feature-selection or
   cross-validation gate to produce a prediction (SC-11). Code cannot create
   independent experiments; more units of one run do not replace more runs.
9. State the result as built, trained, evaluated, validated or blocked, exactly
   as the evidence supports (SC-8, kernel rule 14). A rebuilt model that is
   blocked on noise or too few independent units is not a validated predictor,
   and a model on a few experiments is labelled a prototype (SC-12).
10. Constants of the validation rule are a decision, not a gate edit (SC-9);
    if a threshold seems wrong, record evidence and a new rule version first.
