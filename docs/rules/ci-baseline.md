# CI permissions, pinning, caching, deploy gating

- Installs use a frozen lockfile; fail on any metadata/lockfile
  disagreement, never auto-resolve inside CI.
- Workflow permissions are least-privilege: `contents: read` as the
  baseline; write scopes granted per job only where needed.
- Third-party actions are pinned - a major version tag at minimum, a
  commit SHA where the action is not from a trusted publisher.
- Runner images are pinned to an explicit label (for example
  `ubuntu-24.04`), not `-latest`, so an image migration is a reviewed
  change. Only the job branch protection requires gates a merge; a
  secondary-platform job (such as the Windows self-tests) is not required,
  and carries its own `timeout-minutes`. A slow secondary job runs on
  pull requests only when the change touches its files, decided by a
  `paths` job inside the same workflow, and skips private repositories
  where its minutes are billed.
- A pull request that changes a gate file (check.sh, the self-test
  runner, the reviewer brief, the workflows) needs the `gate-change`
  label, added by a human who reviewed the gate change (ADR 0018).
- Cache keys include the lockfile hash and the toolchain version so a
  stale cache cannot mask breakage.
- On failure, upload diagnostic artifacts (logs, reports) with no secrets
  in them.
- Deployment depends on validation of the exact same SHA; an unvalidated
  commit is never deployed.
- Racing deploys are serialized with a concurrency group; never cancel a
  production deploy in flight unless the rollback design makes
  cancellation safe.
- Record every deployment: commit, artifact, environment, time, result.
- A documented rollback path exists before the first deploy, not after
  the first incident.
- `cancel-in-progress` is for pull-request runs only, keyed on the PR; never
  on main, tags or deploys.
- Optional jobs are gated at the job level (`if:` fed by a `paths` job) so a
  skipped job allocates no runner; a step-level skip has already paid setup.
- Only trusted jobs write caches; untrusted jobs (fork or pull-request code)
  restore only.
- Moving a check to another stage (push, schedule) never makes a required
  answer optional: required checks stay green for the exact pushed SHA and a
  release gate stays attached to the version shipped
  (docs/procedures/ci-cost.md).
- `actions/upload-artifact` and `actions/download-artifact` are pinned by
  commit SHA like other third-party actions.
