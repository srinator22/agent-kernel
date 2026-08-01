# Start - one-shot project initialization

If `.start-done` exists, STOP: this procedure already ran and must not run
again. Never touch the kernel block in AGENTS.md or `.kernel.hash` at any
point in this procedure.

1. Read `docs/BLUEPRINT.md` and `AGENTS.md` in full. Inspect the environment
   against `manifest.md`; note what is present, missing, or degraded.
2. Ask the human ONE batched set of questions - only what cannot be inferred:
   1. What is the project? Purpose, users, non-goals, system boundary
      (a paragraph is fine).
   2. Stack preference, or should I propose one from the reference table in
      `docs/BLUEPRINT.md` section 4?
   3. Repo host and visibility (private/public), solo or team?
   4. Git workflow: branch + gated merge (default), or direct-to-main as an
      explicit standing choice?
   5. Deploy target, or none for now? If deploying: private or public
      exposure, auth approach?
   6. Does it ship data or assets? (If yes: local-first data, self-hosted
      assets, and version-stamped caches become project defaults, recorded
      as an ADR - external sources are justified fallbacks with a written
      reason.)
   7. Risk profile: ordinary, scientific/numerical, safety-sensitive, or
      embedded? (Scientific wires golden-master fixtures, deterministic
      seeds, and promotes docs/rules/scientific-integrity.md in the index.)
   8. Default task mode: spec-approval or autopilot?
   9. Any hard invariants I should never violate (UX, performance,
      compliance, compatibility)?
   10. Is there confidential context that must not appear in the committed
       repo? (If yes: create a gitignored local instruction file, add the
       ignore line first, and never reference its existence in committed
       files.)
3. Wire the stack: fill every `{{...}}` in `scripts/check.sh` and
   `.github/workflows/ci.yml` from the reference table; add
   linter/formatter/test/mutation/gitleaks configs; pin runtime and
   package-manager versions; commit the lockfile; wire mechanical boundary
   rules per the architecture in `docs/rules/architecture.md`. All gauntlet
   roles filled or the gap logged with a reason.
4. Fill the Project decisions section of `AGENTS.md`; append stack-specific
   lines to Standards if needed (respect the 180-line budget).
5. Write `docs/ARCHITECTURE.md` (modules, boundaries, dependency direction)
   and, if deploying, `docs/operations.md` (deploy, rollback, monitoring).
   Write the next-numbered ADR under docs/decisions/ (stack choice, with
   rejected alternatives).
6. Rewrite `README.md` for the project, present tense. Set repo description,
   homepage, and topics (gh) so the sidebar reads properly. Scaffold
   `BACKLOG.md` with the first milestones from the interview.
7. Configure the harness: attribution/trailers off in settings (verify
   current key names at run time); seed the permissions allowlist with
   the stack's safe verification commands (the same format, lint,
   typecheck, and test commands wired into check.sh); branch protection
   if gated workflow.
8. Verify a clean state: `./scripts/check.sh` passes for real (not template
   mode). Fix until it does. Completion rule: start may not declare itself
   complete if format/lint/typecheck/tests cannot actually execute.
9. Write `.start-done` (date + summary), write `START_REPORT.md` (detected,
   wired, missing, degraded, manual steps), commit with conventional
   commits, tag `v0.1.0`, and if the workflow is gated, confirm CI on that
   SHA via `scripts/ci-watch.sh`.
10. Never touch the kernel or `.kernel.hash`.
