# Start - one-shot project initialization

If `.start-done` exists, STOP: this procedure already ran and must not run
again. Never touch the kernel block in AGENTS.md or `.kernel.hash` at any
point in this procedure.

0. If `docs/CAPABILITY_MAP.md` is absent, run `docs/procedures/discover.md`
   first and come back; start reads the capability map for the profiles,
   the tools to build (they become the first BACKLOG items) and the risk
   register. Run back to back, discover and start share ONE batched
   interview (see discover.md header). Existing-project mode: when the
   repository already holds code, read the code, the build files and any
   existing AGENTS.md or CLAUDE.md to fill every interview answer the code
   can give, ask only the rest, merge an existing agent file by hand into
   Project decisions, wire check.sh to the commands that already exist and
   make it pass on the unmodified code. Failures already present go to
   BACKLOG.md, never fixed during adoption. Tests that already fail go to
   `tests/quarantine.list` with an owner task and date (protocol in
   `docs/procedures/tests.md`), never deleted or weakened; the gate is green
   only because the quarantine is explicit, and each entry expires in 30 days.
1. Read `docs/BLUEPRINT.md`, `AGENTS.md` and `docs/CAPABILITY_MAP.md` in full.
   Inspect the environment against `manifest.md`; note what is present,
   missing, or degraded. Re-check the stack-specific tools discover could
   only list as "any".
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
      embedded? And the LIST of profiles to adopt from
      `docs/profiles/README.md` (software always; scientific,
      embedded-firmware, hardware-pcb, data-analysis as the suggestion in
      `docs/CAPABILITY_MAP.md` says; the human confirms or edits it).
      (Scientific wires golden-master fixtures, deterministic seeds, and
      promotes docs/rules/scientific-integrity.md in the index.)
   8. Default task mode: `standard | quick | autopilot` (the names
      `scripts/new-task.sh` takes)?
   9. Any hard invariants I should never violate (UX, performance,
      compliance, compatibility)?
   10. Is there confidential context that must not appear in the committed
       repo? (If yes: create a gitignored local instruction file, add the
       ignore line first, and never reference its existence in committed
       files.)
   11. Consent for the first push, the v0.1.0 tag, repo description and
       topics, and branch protection: given now for this run, or ask per
       action?
3. Wire the stack: fill every `{{...}}` in `scripts/check.sh` and
   `.github/workflows/ci.yml` from the reference table, and DELETE the final
   `fail ".start-done exists ..."` line of `check.sh`; add
   linter/formatter/test/mutation/gitleaks configs; pin runtime and
   package-manager versions; commit the lockfile; wire mechanical boundary
   rules per the architecture in `docs/rules/architecture.md`. All gauntlet
   roles filled or the gap logged with a reason. The ci.yml deploy job fires
   on `v*` tags: keep it only when a deploy target exists (Q5), otherwise
   delete the job here. Keep the always-on block of check.sh (memory caps,
   task graph, dash scan) untouched. Keep `tests/template/` and
   `scripts/selftest.sh` only if the project keeps the template scripts
   (default: keep; they run in the always-on block).
4. Fill the Project decisions section of `AGENTS.md` including the Profiles
   and Capability map lines; record `- Template: <url> <tag>` and
   `- Profiles:` there and append `template-sync: <tag> <date>` to
   `docs/lessons/MAINTENANCE.log` (create it) so a later sync has its base.
   Promote each adopted profile's rules into the rules index; append
   stack-specific lines to Standards if needed (respect the 180-line
   budget). Wire each adopted profile's gates into check.sh
   (`docs/profiles/<name>/PROFILE.md`, Gates) and scaffold the test layout of
   `docs/procedures/tests.md` with one passing example per layer.
5. Write `docs/ARCHITECTURE.md` (modules, boundaries, dependency direction)
   and, if deploying, `docs/operations.md` (deploy, rollback, monitoring).
   Write the next-numbered ADR under docs/decisions/ (stack choice, with
   rejected alternatives). The template's ADRs 0001 to 0003 stay as history;
   project ADRs start after them.
6. Rewrite `README.md` for the project, present tense. Set repo description,
   homepage, and topics (gh) so the sidebar reads properly (per Q11). Replace
   `BACKLOG.md` with the project's backlog (first milestones from the
   interview, plus the discover tool rows); move the template rows to
   `.archive/` with the reason "template maintenance items".
7. Configure the harness: attribution/trailers off in settings (verify
   current key names at run time); seed the permissions allowlist with
   the stack's safe verification commands (the same format, lint,
   typecheck, and test commands wired into check.sh); branch protection
   if gated workflow (per Q11).
8. Write `.start-done` (date + summary) so `check.sh` leaves template mode and
   runs the stack gauntlet.
9. Verify a clean state: run `./scripts/check.sh` for real. Fix until it is
   green. Completion rule: start may not declare itself complete if
   format/lint/typecheck/tests cannot actually execute.
10. Write `START_REPORT.md` (detected, wired, missing, degraded, manual
    steps), commit with conventional commits, tag `v0.1.0`, and if the
    workflow is gated, confirm CI on that SHA via `scripts/ci-watch.sh`.
    Push and tag only as Q11 allowed.
11. Never touch the kernel or `.kernel.hash`.
