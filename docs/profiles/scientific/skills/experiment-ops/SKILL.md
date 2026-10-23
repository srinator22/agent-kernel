---
name: experiment-ops
description: Route experiment and model operations to the smallest correct tool or specialist skill. Use for raw capture preparation, unit splitting, single-unit inspection, experiment intake, outcome validation, dataset audit, model training, prediction explanation, readiness review, publication, or questions about which experiment to run next.
---

# Route experiment operations

Classify the request once. Run a deterministic command when one fits; load a
specialist skill only when the stage needs judgment beyond a command. Unused
workflow text stays out of context.

| Request | Route |
|---|---|
| Raw capture splitting, set-up pulse exclusion | the project's prepare command |
| One-unit diagnostics | the project's inspect command |
| Compare two detector or boundary results | the project's compare command |
| Outcome arithmetic, target conversion | the project's outcome-validation command |
| Integrity or freshness check | the dataset audit and freshness commands (SC-13, SC-15) |
| Explain one candidate prediction | the project's explain command |
| New labelled run, unit-to-replicate mapping | `register-experiment` |
| Rebuild or evaluate the model | `train-model` |
| Dataset readiness, next-experiment advice | `experiment-review` |
| Commit, push, release, deploy, CI watching | `publish-model` |
| Port or change numerical logic | `verify-core` |

The commands live in the project's experiment CLI (profile Tools row: prepare,
validate, audit, train, inspect, explain, compare). Read its docs only when
arguments or file contracts are needed. Every command writes to a new output
directory and exits 0 pass, 1 fail, 2 needs review (SC-14).

For a mixed request, run the stages in dependency order (prepare, register,
audit, train, review, publish) and load each specialist when its stage begins.
If no command exists for a stage you keep needing, that is a `build` Tools item
for BACKLOG.md, not a one-off script (kernel rule 1).
