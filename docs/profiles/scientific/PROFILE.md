# Profile: scientific

## Purpose and risk

For projects that produce numbers, models, or validation claims. Risk: a
plausible wrong number that passes every software test, a model that "works"
because of leakage or a weak baseline, and a claim stronger than the evidence.
Promote `docs/rules/scientific-integrity.md` and `docs/rules/data-provenance.md`
into the AGENTS.md rules index.

## Rules

- SC-1 A golden-master test pins ported or numerical logic to a validated
  number with its units, source, precision and tolerance; a fixture missing any
  of the four fields fails the gate.
- SC-2 A tolerance is derived from the reference and the use case and carries
  its derivation; 1 percent is used only where it is the accepted contract.
- SC-3 Expected values never change to match a new implementation; a changed
  reference is its own reviewed commit with the evidence and decision first.
- SC-4 Golden values are checked against an independent recomputation (a second
  implementation in another language or library), not only a previous output.
- SC-5 Seeds are deterministic, stored with the parameters they seeded, and
  derived from content (for example a hash of file name, label and sample
  count) so reordering inputs does not change a result.
- SC-6 Cross-validation holds out whole experiments; sub-units (conditions,
  samples, doses) of a held-out experiment never appear in a training fold.
- SC-7 Error is scored against a baseline (training mean) on the same held-out
  points at the same level; skill = 1 - (rmse / baselineRmse)^2.
- SC-8 Status words are exact and ordered: built, trained, evaluated,
  validated, deployed, production-ready; a model record carries one, and
  "validated" requires the written rule of SC-9.
- SC-9 "Validated" is a fixed, versioned rule with named constants (minimum
  skill, significance test, minimum independent units); changing a constant is
  a new decision and a new rule version, never a gate edit.
- SC-10 A threshold records the evidence that set it (the data splits tried,
  the share passing at each candidate, the chosen value and why).
- SC-11 A failing scientific gate is kept and replication is added; the gate is
  never loosened, skipped or re-labelled to pass.
- SC-12 Independent experiments stay independent groups; they are never pooled
  as repeated measurements, and the independent count is reported with every
  result. A model on a few experiments is labelled a prototype.
- SC-13 Raw captures never enter git; manifests carry the raw file hash,
  labelled units, the labelled subset and source evidence.
- SC-14 Every analysis command writes to an output directory that must be new,
  and exits non-zero (2 = needs review) on a count mismatch or integrity flag.
- SC-15 Method changes bump a methods version that is part of every build ID;
  stored results from an older version are marked stale, not reused.
- SC-16 Limitations seen in the evidence (drift within a run, few repetitions,
  a factor confounded with the experiment) are written next to the result they limit.

## Gates

| Gate | Command (project supplies) | Pass | Rule |
|---|---|---|---|
| Golden masters | `<test runner> golden` | all pinned values within tolerance | SC-1, SC-4 |
| Fixture completeness | script parses fixtures | every fixture has units, source, tolerance | SC-1 |
| Fixture-change guard (build) | diff check in CI | a golden file and its implementation do not change together without a `Reference-change:` commit line | SC-3 |
| Determinism | run the pipeline twice | byte-identical outputs | SC-5 |
| Leakage | fold audit | no experiment id in both train and held-out | SC-6 |
| Status vocabulary | schema check on model records | status in the set; validated only with rule fields | SC-8, SC-9 |
| Freshness | regenerate all generated model files, compare | byte-identical | SC-15 |
| Dataset audit | audit command | unique identities, counts, files exist, SHA-256 match, no raw storage declared | SC-13 |

## Tools

- Numeric reference implementation (NumPy or MATLAB), a test runner with
  seeded RNG: `exists`; install check is `--version`.
- Experiment CLI (prepare, validate, audit, train, inspect, explain, compare):
  `exists in a prior vibration analysis project, port on adoption`.
- Paired sign-flip permutation test and baseline-scored cross-validation:
  `exists in a prior vibration analysis project, port on adoption`.
- Fixture-change guard and fixture completeness script: `build`; exit 1 on
  violation, 2 when git history is unavailable.

## Playbooks

- `docs/procedures/bugfix.md` with a golden fixture as the regression test.
- `docs/procedures/bughunt.md` with the checklist: leakage, pooling,
  baseline level mismatch, unit mix-ups, stale generated outputs.
- Replication plan: when a gate fails, add independent experiments, record the
  count needed, and re-run; the failing result stays published as it is.

## Agents and skills

- Skills: verify-core (run goldens, read output, then claim).
- `reviewer` checks every number in a report against its source file.
- Independent recomputation is done by a worker given only the spec, not the
  implementation.

## Parameters and records

- Constants of the validation rule live in one named module and are quoted in
  its ADR. Example constants, illustrative and not defaults: skill at least 0.10; one-sided paired sign-flip permutation
  p below 0.05 with 10000 seeded resamples; at least 5 predicted conditions
  (with 5, one tie gives p = 2/32, so every difference must be positive).
- Selection records per experiment and release condition; model records carry
  cvRmse, baseline, skill, p, n, validated.
- Manifest per experiment: run id, hashes, units, labelled counts, set-up.

## Done means

- Every reported number has its source, units, independent count and status
  word, and the status word is justified by the rule.
- Goldens, determinism and leakage gates are green on the exact SHA.
- A failing scientific gate is recorded as such with its replication plan.

## Lessons carried in

- Pooled repeated measurements hid drift and inflated the noise floor; keep
  independent groups independent.
- Error scored at the experiment level against a condition-level spread looked
  small, and a model that only matched the mean read as "Validated" with a high
  accuracy; score against a baseline on the same held-out points.
- "Validated" with a trivial skill needed a minimum-skill rule.
- A fixed best-match alignment scored white noise well above zero; an
  order-tracking alignment scored it at zero. Test the method on noise.
- A threshold chosen after trying many splits recorded the share passing at
  each candidate, so the choice is auditable.
- A subgroup that failed the gate stayed blocked by its confounding factor
  rather than the gate being loosened; an unwired feature promotion is stopped
  by a build guard until its wiring lands, and the model is compared before and
  after any promotion.

## Sources

Sources: distilled from four prior projects of the template owner (embedded
firmware, controller PCB, vibration data analysis, CAD add-in); project records
stay in those repositories.
