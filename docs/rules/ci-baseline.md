# CI permissions, pinning, caching, deploy gating

- Installs use a frozen lockfile; fail on any metadata/lockfile
  disagreement, never auto-resolve inside CI.
- Workflow permissions are least-privilege: `contents: read` as the
  baseline; write scopes granted per job only where needed.
- Third-party actions are pinned - a major version tag at minimum, a
  commit SHA where the action is not from a trusted publisher.
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
