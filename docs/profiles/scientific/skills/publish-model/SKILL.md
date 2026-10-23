---
name: publish-model
description: Publish an approved experiment or model update through local verification, intentional git scope, exact commit confirmation, CI monitoring and deployment verification. Use when asked to commit, push, release, deploy or publish training-data and model changes. Use only when explicitly asked; publishing is outward-facing (kernel rule 15).
---

# Publish a model update

Follow `docs/procedures/ship.md` for the done-gate; this skill adds the
model-specific steps. Rules: SC-8, SC-13, SC-15; kernel rules 5, 6, 12, 15.

1. Confirm the git workflow recorded in Project decisions (branch with gated
   merge by default; direct-to-main only when explicitly recorded or asked).
2. Run `git status`. Exclude unrelated changes and every full raw capture;
   only labelled subsets, manifests, counts and evidence may enter git
   (SC-13, kernel rule 12).
3. Run the dataset audit, rebuild the model through the validated generator,
   then `./scripts/check.sh`. Read the output; the freshness gate must show the
   generated files current (SC-15).
4. Check the status word on the model record is one SC-8 allows and that
   "validated" is claimed only under the SC-9 rule. A publish never upgrades
   the status.
5. Run the ship procedure steps: reviewer verdict recorded in `.work/TASK.md`,
   version bump, generated CHANGELOG (never hand-edited), Conventional Commit.
6. Review the staged diff and create one coherent commit. The body names why,
   and for fixes the exact issue, fix, files and functions.
7. Push per the recorded workflow and capture the exact commit SHA. Verify the
   remote branch points at it.
8. Delegate watching to the `monitor` agent (`scripts/ci-watch.sh <SHA>`). The
   publishing agent stays responsible for the final result.
9. On any failing workflow: read the failing job and step, fix the root cause,
   rerun local verification, push the replacement and watch the replacement SHA.
10. Never report success while a required check is queued, running, skipped
    unexpectedly or failed (kernel rule 5).
11. Finish with the final SHA, workflow conclusions, deployment result, the
    model's status word, independent experiment count, and any validation
    limit that still applies (field or external validation is a separate claim).

Use the handoff format of ship.md: Outcome / Evidence / Artifacts /
Limitations / Next action only if required.
