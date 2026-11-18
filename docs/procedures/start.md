# Start - one-shot project initialization

If `.start-done` exists, STOP: this procedure already ran and must not run
again. Never touch the kernel block in AGENTS.md or `.kernel.hash`.

Before step 0, run `bash scripts/doctor.sh`. A required failure (git, bash
3.2+, Python 3, and in template mode ruff 0.16.10, uvx or pipx) stops start:
show doctor's install lines, do nothing else.
A recommended gap (gh, gitleaks, git-cliff,
`git grep -P`) does not stop start: record it under "missing" or "degraded"
in `START_REPORT.md`.

0. If `docs/CAPABILITY_MAP.md` is absent, run `docs/procedures/discover.md`
   first; start reads the map for profiles, tools to build (first BACKLOG
   items) and risk register. Discover and start share ONE batched
   interview (see discover.md header).
   Existing-project mode: when the repository already holds code, read the
   code, build files and any existing AGENTS.md or CLAUDE.md to fill every
   answer, ask only the rest, merge an existing agent file
   by hand into Project decisions,
   wire `scripts/stack-check.sh` to the commands that
   already exist and make `./scripts/check.sh` pass on the unmodified code.
   Failures already present go to
   BACKLOG.md, never fixed during adoption. Tests that already fail go to
   `tests/quarantine.list` with an owner task and date (protocol in
   `docs/procedures/tests.md`), never deleted or weakened;
   each entry expires in 30 days.
1. Read `docs/BLUEPRINT.md`, `AGENTS.md` and `docs/CAPABILITY_MAP.md` in full.
   Inspect the environment against `manifest.md`.
2. Ask the human ONE batched set of questions - only what cannot be inferred:
   1. What is the project? Purpose, users, non-goals, system boundary.
   2. Stack preference, or propose one from `docs/BLUEPRINT.md` section 4?
   3. Repo host and visibility (private/public), solo or team?
   4. Git workflow: branch + gated merge (default), or direct-to-main as an
      explicit standing choice? Record the value starting with the choice:
      "branch + gated merge, <details>" or "direct-to-main, <details>".
      scripts/new-task.sh reads direct-to-main only when that word is
      followed by the end of the value or by ; . : , ( or " - ".
   5. Deploy target, or none for now? If deploying: private or public
      exposure, auth approach?
   6. Does it ship data or assets? (If yes: local-first data, self-hosted
      assets, and version-stamped caches become project defaults, recorded
      as an ADR.)
   7. Risk profile: ordinary, scientific/numerical, safety-sensitive, or
      embedded? And the LIST of profiles to adopt from
      `docs/profiles/README.md` (software always; others as
      `docs/CAPABILITY_MAP.md` suggests). Also: which
      optional items from `docs/library/README.md` to adopt, and which
      department agents from `docs/roster/README.md` (default none)?
   8. Default task mode: `standard | quick | autopilot`?
   9. Any hard invariants I should never violate (UX, performance,
      compliance, compatibility)?
   10. Is there confidential context that must not appear in the committed
       repo? (If yes: create a gitignored local instruction file, add the
       ignore line first, and never reference its existence in committed
       files.)
   11. Consent for the first push, the v0.1.0 tag, repo description and
       topics, and branch protection: now, or ask per action?
3. Wire the stack: write the stack steps from the gauntlet
   comment of `scripts/check.sh` into a new `scripts/stack-check.sh`
   (project-owned; check.sh runs it with bash;
   it takes `--full-mutation` and `--quick` and honours both;
   template-sync never touches it), leave
   `scripts/check.sh` itself unchanged so later syncs apply
   cleanly, and fill every `{{...}}` in `.github/workflows/ci.yml` from the
   reference table. Add lint, format, test, mutation and gitleaks
   configs; pin runtime and
   package-manager versions; commit the lockfile; wire mechanical boundary
   rules per `docs/rules/architecture.md`. Fill every gauntlet
   role or log the gap. The ci.yml deploy job fires
   on `v*` tags: keep it only when a deploy target exists (Q5). Keep
   `tests/template/` and `scripts/selftest.sh` only if the
   project keeps the template scripts (default: keep).
4. Fill the Project decisions section of `AGENTS.md` including the Profiles
   and Capability map lines; record exactly `- Template: <url> <tag>`
   (two tokens, no notes) and `- Profiles:` there and append
   `template-sync: <tag> <date>` to
   `docs/lessons/MAINTENANCE.log` (create it) so a later sync has its base.
   Promote each adopted profile's rules into the rules index; append
   stack-specific lines to Standards if needed (respect the 180-line
   budget). Wire each adopted profile's gates into `scripts/stack-check.sh`
   (`docs/profiles/<name>/PROFILE.md`, Gates) and scaffold the test layout of
   `docs/procedures/tests.md` with one passing example per layer.
   Install each adopted profile's shipped set, copying, never moving:
   `agents/<n>.md` to
   `.claude/agents/`, `agents/<n>.toml` to `.codex/agents/`,
   `skills/<n>/` to both `.claude/skills/` and `.agents/skills/`, and
   `tools/` (with `tools/tests/`) to the project's tool folder, recorded in
   Project decisions; wire each tool's tests into `scripts/stack-check.sh`.
   A name that
   already exists is merged by hand, never overwritten. Library items and
   roster agents chosen in Q7 install the same way; a library procedure goes
   to `docs/procedures/`, and a library skill takes one of the 2 project skill
   slots (kernel rule 10). `scripts/lessons.sh check` must pass
   after the copy.
   The software profile's `verify` skill is a template (SW-15,
   template ADR 0016): fill every `{{VERIFY_...}}`
   wiring line with the project's real build, boot, ready signal, drive,
   inspect and stop commands (see its "Adapting at start" table), then
   delete that section; install the filled copy to both
   skill folders, byte-identical. No `{{` may remain in the installed copy.
5. Write `docs/ARCHITECTURE.md` (modules, boundaries, dependency direction)
   and, if deploying, `docs/operations.md` (deploy, rollback, monitoring).
   Write the next-numbered ADR under docs/decisions/ (stack choice, with
   rejected alternatives) with `scripts/adr.sh new` per
   `docs/procedures/adr.md`.
6. Rewrite `README.md` for the project, present tense. Set repo description,
   homepage, and topics (gh) (per Q11). Replace
   `BACKLOG.md` with the project's backlog (milestones plus the discover
   tool rows); move the template rows to
   `.archive/` with the reason "template maintenance items". With the
   lessons files committed as copied, run
   `bash scripts/start-reset-lessons.sh`, then the same with `--check`
   (exit 0): it resets the `docs/lessons/` index, pending, quarantine and
   upstream files to their format headers. It refuses
   after `.start-done` or with uncommitted changes in those files;
   `--check` names a file that still
   holds entries. `docs/DEFECT_MEMORY.md` is left as shipped.
7. Configure the harness: attribution/trailers off in settings (verify
   current key names at run time); seed the permissions allowlist with
   the stack's safe verification commands; branch protection
   if gated workflow (per Q11).
8. Write `.start-done` (date + summary) so `check.sh` leaves template mode and
   runs the stack gauntlet.
9. Verify a clean state: run `./scripts/check.sh` for real. Fix until it is
   green. Completion rule: start may not declare itself complete if
   format/lint/typecheck/tests cannot actually execute. Then run the
   installed `verify` skill once against the scaffolded app; it must pass.
10. Write `START_REPORT.md` (detected, wired, missing, degraded, manual
    steps, first verify run: command, what was driven, observed
    result, or "N/A - reason"), commit with conventional commits,
    tag `v0.1.0`, and if the
    workflow is gated, confirm CI on that SHA via `scripts/ci-watch.sh`.
    Push and tag only as Q11 allowed.
11. Never touch the kernel or `.kernel.hash`.
