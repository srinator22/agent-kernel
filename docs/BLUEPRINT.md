# BUILD PROMPT v2 - Self-Improving Agentic Template Repository

**Your first action, before anything else:** initialize a new git repository and save this entire file, verbatim, to `docs/BLUEPRINT.md`. Build from the saved copy, not from conversation memory - context gets compacted; the file does not. After any compaction or new session during this build, re-read `docs/BLUEPRINT.md` before continuing.

Style rule that applies to every file you create, including this one once saved: plain hyphens only. No em dashes, no en dashes, anywhere - code, docs, commits, comments.

---

## 0. What you are building

A greenfield **template repository**. It is cloned to start new coding projects. It contains no application code. It gives any coding agent that opens it: a governing instruction file, an enforcement gauntlet, a memory system that learns from external signal and forgets on schedule, a task-state protocol that survives context compaction, a delegation model, and a one-shot `/start` ritual that interviews the human and adapts the template to the specific project.

Owner constraints:

- **Fully AI-operated.** No human writes code. Humans give tasks, answer the start interview, approve specs (waivable), approve prose lessons, and authorize irreversible or outward-facing actions.
- **Subscription billing.** Optimize context-window occupancy and compaction survival, not per-token cost.
- **Cross-harness.** Must work under Claude Code, Codex CLI, Cursor, Gemini CLI, and others. `AGENTS.md` is the single source of truth. Anything harness-specific is an optional accelerator that degrades gracefully.
- **Language-agnostic at rest.** The start procedure wires a concrete stack per project.
- **Greenfield projects only** (for now).

If a capability referenced here does not exist in your harness, implement the portable form and record the gap in `BUILD_NOTES.md`.

---

## 1. Design principles (do not violate these while building)

1. **Mechanize first.** A rule that can be a lint rule, type, test, hook, or script must be one. Prose is the last resort: resident text costs context every turn and gets ignored under pressure; checks cost nothing and cannot be ignored.
2. **External signal only.** In a full-AI loop, the agent grading its own work is the least reliable data in the system. Ground truth is tests, CI, and human reports. Memory records only what external signal confirms.
3. **Progressive disclosure.** Resident text is minimal and stable. Everything else loads on trigger (one-line index, open on match) or on query (grep git log, ADRs, CHANGELOG). Detailed reference rules live in `docs/rules/` and are indexed, not resident.
4. **Detection over prevention for kernel drift.** No harness can hard-block an agent from editing a file. The kernel section is hash-checked; drift fails the build loudly. Legitimate edits are a deliberate two-step (edit plus hash update) visible in the diff.
5. **Portable core, accelerator shell.** Procedures are plain markdown in `docs/procedures/` that any agent can follow. `.claude/` contents are thin wrappers. Enforcement lives at git and CI level; harness hooks are optional speed-ups.
6. **Forgetting is a feature.** Every memory artifact has a retire condition and a usage counter. Hard caps force pruning.
7. **Server-side enforcement is the only real enforcement.** Local hooks are bypassable by the agent they constrain. CI on the exact pushed SHA, plus branch protection where the chosen workflow uses it, is the outer wall.
8. **Generated artifacts are never hand-edited.** Change the source or the generator and rebuild. This applies to CHANGELOG.md, lockfiles, and any build product.

---

## 2. Repository tree - build exactly this

```
AGENTS.md                     # source of truth: kernel + standards + rules index + project decisions
CLAUDE.md                     # exactly one line: @AGENTS.md
README.md                     # for humans: what this template is, how to start
BACKLOG.md                    # remaining work, priority, reason (template: empty scaffold)
BUILD_NOTES.md                # gaps/uncertainties hit while building (create only if needed)
manifest.md                   # declarative environment expectations
cliff.toml                    # git-cliff config: Conventional Commits -> CHANGELOG.md
.kernel.hash                  # sha256 of the kernel block in AGENTS.md
.gitignore
.editorconfig                 # deterministic whitespace/line endings
.gitattributes                # deterministic line endings across platforms
.github/
  workflows/
    ci.yml                    # runs scripts/check.sh; optional deploy job gated on same SHA
docs/
  BLUEPRINT.md                # this file, saved verbatim
  ARCHITECTURE.md             # {{FILLED_BY_START}}: modules, boundaries, data flow
  operations.md               # {{FILLED_BY_START if deploy target}}: deploy, rollback, monitoring
  decisions/
    0001-template-architecture.md
  procedures/
    start.md                  # the /start interview + adaptation ritual (one-shot)
    ship.md                   # done-gate: verify, version, changelog, push, monitor to terminal
    retro.md                  # end-of-task learning capture
    maintain.md               # pruning, caps, freshness
    bugfix.md                 # reproduce -> root cause -> failing test -> smallest fix
    audit.md                  # full-repo review with P0-P3 priorities
    longjob.md                # background work: checkpointed, resumable, polite
  rules/                      # triggered reference rules; indexed one line each in AGENTS.md
    architecture.md
    security.md
    data-provenance.md
    scientific-integrity.md
    destructive-actions.md
    ci-baseline.md
  lessons/
    INDEX.md                  # one line per approved lesson + usage counters
    PENDING.md                # proposed lessons awaiting human approval
    QUARANTINE.md             # flaky tests parked here, each as an open task
scripts/
  check.sh                    # the single gauntlet: local == CI
  kernel-hash.sh              # --verify | --update (the only sanctioned way to touch .kernel.hash)
  ci-watch.sh                 # poll checks for the exact HEAD SHA until terminal; nonzero on failure
  new-task.sh                 # branch + .work/TASK.md scaffold from template
  bg.sh                       # start/status/tail/stop a background job with log, pidfile, exit marker
.work/
  TASK.md                     # current-task state (template with placeholders); committed
  done/                       # archived task files; committed
    .gitkeep
  jobs/                       # background-job STATE files and logs; GITIGNORED
    .gitkeep
.claude/
  settings.json
  agents/
    reviewer.md               # fresh-context adversarial review; model inherit
    explore.md                # read-only codebase search; model haiku
    worker.md                 # mechanical execution; model sonnet; git commit/push DENIED in tools
    monitor.md                # post-push CI watcher; model haiku; runs scripts/ci-watch.sh
  skills/
    start/SKILL.md            # thin wrapper -> docs/procedures/start.md
    ship/SKILL.md             # thin wrapper -> docs/procedures/ship.md
    retro/SKILL.md            # thin wrapper -> docs/procedures/retro.md
    maintain/SKILL.md         # thin wrapper -> docs/procedures/maintain.md
.archive/
  README.md                   # graveyard: moved-not-deleted, one-line reason each
```

Placeholder convention: anything the start procedure must fill is written `{{LIKE_THIS}}`. Nothing may look finished when it is not.

---

## 3. File specifications

### 3.1 AGENTS.md

Four sections. Total file <= 180 lines - hard budget, verified by check.sh. Copy the kernel byte-exact between the markers; do not paraphrase, reorder, or improve it:

```markdown
<!-- KERNEL:BEGIN -->
## Kernel - how this repo works and learns (edits require human approval + scripts/kernel-hash.sh --update in the same commit)

These rules govern process. Project truth lives in the Project decisions section and may be rewritten there.

1. Mechanize first. A lesson becomes prose only if no lint rule, type, test, or script can express it. Prefer checks over words.
2. Tests are ground truth. Never delete, skip, weaken, or loosen a failing test or gate to get green. A flaky test is a defect: quarantine it in docs/lessons/QUARANTINE.md and fix it as its own task.
3. Root cause, guard, repair. Reproduce first, on real data where it exists. A bug found after merge gets its failing regression test before the fix. Fix the cause at the owning layer, add the check that makes recurrence impossible, and repair existing damage. A workaround is acceptable only when the cause cannot safely be fixed now, and is recorded with its follow-up.
4. Spec before code, tests before implementation. Non-trivial tasks get .work/TASK.md filled in (goal, acceptance criteria, plan, progress). Criteria become executable tests where possible and are approved by the human unless the task is marked autopilot. Patch the smallest safe surface; no unrelated cleanup in the same change.
5. Done is layered. Implementation done: behavior at the correct layer, contracts explicit, tests cover it, nothing unrelated included. Verification done: acceptance tests green, ./scripts/check.sh green, rendered output inspected when presentation matters, reviewer verdict recorded in .work/TASK.md. Delivery done: CI and any deploy for the exact pushed SHA reached terminal success. A push is not done while any required check is queued or running; never report an in-progress state as success.
6. Git discipline. Follow the recorded workflow in Project decisions (default: branch + gated merge). Conventional Commits; a fix commit body states the exact issue, the fix, and the files and functions touched. Inspect git status before editing and before committing; untracked or unrelated changes are preserved, never staged, reverted, or overwritten. No --no-verify, no force-push, no destructive git commands unless explicitly requested with a verified target.
7. Session protocol. At session start and after any compaction: re-read AGENTS.md, .work/TASK.md, and BACKLOG.md before acting. At session end: run the retro procedure and leave the worktree state understandable.
8. Memory tiers. Resident: this file (<= 180 lines). Triggered: scan docs/lessons/INDEX.md and the rules index below before non-trivial work; open only matching entries and increment their usage counter. Queryable: docs/decisions/, CHANGELOG.md, git log - grep on demand. Memory is a snapshot: before acting on something memory says exists, verify it still does.
9. Learning is gated. Proposed lessons go to docs/lessons/PENDING.md as: what happened / what check should have caught it / what was added / retire-when. Confirmed-good calls count as lessons too, not only corrections. Never record what is derivable from the repo itself. Pending entries are not acted on; a human moves approved entries into INDEX.md.
10. Forgetting is mandatory. Hard caps: 20 approved lessons, 180 lines for this file, 8 skills. The maintain procedure archives on evidence (unused > 45 days, or retire-when met), never on vibes.
11. Archive, never delete. Removing a repo artifact means moving it to .archive/ with a one-line reason, only during a maintenance pass, never mid-task. Anything else destructive follows docs/rules/destructive-actions.md: exact absolute target verified read-only first, never a root, home, workspace root, broad glob, or unresolved variable, narrowest recoverable operation, result verified and reported.
12. Security defaults. Proprietary code and data are private by default. Never commit credentials, tokens, production data, or unapproved raw datasets; the secret scan in check.sh is not optional. Widening exposure (public repos, removed auth, wider network access) requires explicit human authorization. See docs/rules/security.md.
13. Dependencies are justified. Check existing capability first; the commit body states why. Lockfile committed; lockfile changes reviewed; unused dependencies removed at maintenance.
14. Evidence before claims. Run it and read the output in this turn before saying it passes. Distinguish built, trained, evaluated, validated, deployed, and production-ready. Never fabricate a value: unverifiable stays empty as "N/A - reason" and is reported. A plausible wrong answer is worse than a visible gap. Full numerical precision internally; round only for display.
15. Scope and autonomy. Read-only inspection authorizes no edits. A build request authorizes normal reversible work inside the requested scope. Irreversible or outward-facing actions (publishing, deleting data, deployments, external messages, cost changes) need human approval; approval is per-instance until the human records a standing override in Project decisions, after which stop re-asking. Do the requested scope completely, then stop; propose extras separately.
16. Delegation. The main session is the advisor: it decomposes, designs schemas, reviews, verifies, and commits. Workers execute bounded mechanical tasks with exact paths and known pitfalls, never commit, and never edit the same file concurrently. A monitor agent tracks every push to terminal state. No agents for conversational turns, judgment calls, or trivial edits. Speed comes from parallel rigor, not less rigor.
17. Long work runs as checkpointed, resumable background processes with a gitignored STATE file, never as a token-burning agent loop. See docs/procedures/longjob.md.
18. Generated artifacts (CHANGELOG.md, lockfiles, build products) are never hand-edited. Change the source or generator and rebuild; CI freshness-checks them.
19. Escape hatch. A task prefixed "quick:" skips spec and plan ceremony. It never skips rules 2, 6, 12, 14, or 15, and anything merged still requires green CI.
20. Style. Plain hyphens only - no em dashes or en dashes anywhere in repo output. No attribution trailers of any kind. Concise, lead with the result, observational reporting: quote the numbers and let evidence carry the conclusion.
<!-- KERNEL:END -->
```

**Section 2 - Standards** (editable; the start procedure may extend it per stack):

```markdown
## Standards

- Non-obvious modules open with a header: purpose, inputs, outputs, dependencies, assumptions, and the validation source when logic is ported from elsewhere.
- Comments explain why, constraints, or provenance - never what, and never the current task or ticket.
- Errors are explicit and actionable; malformed input is never silently converted into plausible output.
- Tests are deterministic: await the actual promises and events, never race real work against a wall-clock timeout. Test contracts and behavior, not incidental internals. Cover empty, malformed, extreme, duplicate, partial, and missing inputs.
- Ported or numerical logic gets golden-master tests pinned to validated real numbers with units, source, and documented tolerance. Never change expected values just to match a new implementation.
- Architectural boundaries are enforced mechanically (lint/import rules wired at start), with dependencies pointing inward and external systems behind adapters.
- No speculative abstraction: three similar lines beat a premature abstraction. Match the surrounding code's idioms. Typed arrays and minimal allocation in numeric hot loops; measure before optimizing and record before/after evidence.
- Local folders mirroring canonical records are named by the canonical ID, no parallel schemes.
- README stays present-tense: what the thing IS, not a history.
```

**Section 3 - Rules index** (one line each; open on match, never load wholesale):

```markdown
## Rules index (triggered)

- Architecture and boundaries -> docs/rules/architecture.md
- Security, secrets, exposure -> docs/rules/security.md
- Data classes, provenance, hashing, what enters git -> docs/rules/data-provenance.md
- Experiments, models, leakage, validation status -> docs/rules/scientific-integrity.md
- Deleting or overwriting anything material -> docs/rules/destructive-actions.md
- CI permissions, pinning, caching, deploy gating -> docs/rules/ci-baseline.md
```

**Section 4 - Project decisions** (template state; start fills every line):

```markdown
## Project decisions

Status: TEMPLATE - not initialized. Run docs/procedures/start.md before any project work.

- Purpose, users, non-goals, boundary: {{FILLED_BY_START}}
- Ownership and visibility: {{private/public, solo/team}}
- Git workflow: {{branch+gated merge (default) OR direct-to-main, recorded as an explicit choice}}
- Release model and versioning source of truth: {{FILLED_BY_START}}
- Deploy target and exposure: {{FILLED_BY_START or none}}
- Canonical verification: ./scripts/check.sh
- Data policy: {{what may enter git; where large/private data lives}}
- Risk profile: {{ordinary / scientific / safety-sensitive / embedded}}
- Standing overrides recorded by the human: {{none yet}}
- Stack and commands: {{FILLED_BY_START - must exactly match scripts/check.sh}}
```

### 3.2 CLAUDE.md

Exactly one line:

```
@AGENTS.md
```

(Claude Code expands the import at load time; other harnesses read AGENTS.md directly. One file of truth. Do not mention any local instruction file here.)

### 3.3 scripts/check.sh

The single entry point; CI runs this exact script so local and CI cannot diverge. Requirements:

- `#!/usr/bin/env bash`, `set -euo pipefail`, executable bit set.
- Step 1, always: kernel hash verify via `scripts/kernel-hash.sh --verify`. On mismatch, print a loud multi-line error explaining kernel drift and the sanctioned edit path (human approval + `--update` in the same commit); exit 1.
- Step 2, always: AGENTS.md line budget, `wc -l` <= 180, else fail.
- Step 3, always: untracked-files report. `git status --porcelain` untracked entries are printed as a warning block (non-fatal) so nothing new is silently left unstaged. New modules that pass locally while never being staged is a known CI-breaker.
- Step 4: template-mode gate. If `.start-done` does not exist: print `TEMPLATE MODE - start has not run; stack checks inactive.` and exit 0.
- Steps 5+ ({{FILLED_BY_START}}), each a clearly commented block: format check -> typecheck -> lint (including mechanical boundary rules) -> tests -> secret scan (gitleaks) -> production build if the stack has one -> mutation testing on changed files (full run behind a `--full-mutation` flag) -> generated-artifact freshness check (regenerate CHANGELOG.md with git-cliff to a temp path and diff; fail on unexplained drift).

### 3.4 scripts/kernel-hash.sh

`--verify`: extract the block from `<!-- KERNEL:BEGIN -->` through `<!-- KERNEL:END -->` inclusive, sha256, compare to `.kernel.hash`, exit accordingly. `--update`: recompute and overwrite `.kernel.hash`, printing a reminder that this belongs in a human-approved commit. Write the extraction logic once, here; check.sh calls this script rather than duplicating it.

### 3.5 scripts/ci-watch.sh

Mechanizes "a push is not done until CI is terminal." Capture the exact HEAD SHA; verify the remote branch points at it (`git ls-remote`); then poll every required check for that SHA via `gh` until each reaches a terminal state, printing transitions. Exit 0 only if all succeed; on failure, print workflow, job, and log URL, exit nonzero. Sensible timeout with clear message. Degrade: if `gh` is absent, say exactly what could not be verified and exit nonzero (unverified is not success - kernel rule 14).

### 3.6 scripts/new-task.sh

Args: slug and optional mode. Creates a branch per the recorded workflow, instantiates `.work/TASK.md` from the template with title, mode, branch, and date filled, prints next steps. Refuses to overwrite an in-progress TASK.md.

### 3.7 scripts/bg.sh

Minimal background-job wrapper: `start <name> -- <command>` (nohup, log to `.work/jobs/<name>.log`, pidfile, exit-marker file with code and finish time), `status`, `tail`, `stop`. Jobs must checkpoint their own progress; the wrapper's README-comment says so and points to docs/procedures/longjob.md.

### 3.8 .github/workflows/ci.yml

- Top comment: the start procedure fills setup, enables branch protection requiring this check when the recorded workflow uses gated merges (via `gh api` if available, else logged as a manual step), and sets repo description/topics.
- `permissions:` block set least-privilege (contents: read as baseline).
- Job `check`: checkout (pinned action version), `{{SETUP_STEPS_FILLED_BY_START}}` (pin runtime version, frozen lockfile install), run `./scripts/check.sh`.
- Job `deploy` ({{delete if no deploy target}}): needs `check`, runs only on version tags, `concurrency:` group to serialize, `{{DEPLOY_STEPS_FILLED_BY_START}}`, records deployed SHA and result in the run summary. Deployment depends on validation of the same SHA, per docs/rules/ci-baseline.md.

### 3.9 docs/procedures/ - portable, numbered, any agent can follow

**start.md** (one-shot; refuses to re-run if `.start-done` exists). This is the /start ritual:

1. Read `docs/BLUEPRINT.md` and `AGENTS.md` in full. Inspect the environment against `manifest.md`.
2. Ask the human ONE batched set of questions - only what cannot be inferred:
   1. What is the project? Purpose, users, non-goals, system boundary (a paragraph is fine).
   2. Stack preference, or should I propose one from the reference table?
   3. Repo host and visibility (private/public), solo or team?
   4. Git workflow: branch + gated merge (default), or direct-to-main as an explicit standing choice?
   5. Deploy target, or none for now? If deploying: private or public exposure, auth approach?
   6. Does it ship data or assets? (If yes: local-first data, self-hosted assets, and version-stamped caches become project defaults, recorded as an ADR - external sources are justified fallbacks with a written reason.)
   7. Risk profile: ordinary, scientific/numerical, safety-sensitive, or embedded? (Scientific wires golden-master fixtures, deterministic seeds, and promotes docs/rules/scientific-integrity.md in the index.)
   8. Default task mode: spec-approval or autopilot?
   9. Any hard invariants I should never violate (UX, performance, compliance, compatibility)?
   10. Is there confidential context that must not appear in the committed repo? (If yes: create a gitignored local instruction file, add the ignore line first, and never reference its existence in committed files.)
3. Wire the stack: fill every `{{...}}` in `scripts/check.sh` and `ci.yml` from the reference table; add linter/formatter/test/mutation/gitleaks configs; pin runtime and package-manager versions; commit the lockfile; wire mechanical boundary rules per the architecture in docs/rules/architecture.md. All gauntlet roles filled or the gap logged with a reason.
4. Fill the Project decisions section of AGENTS.md; append stack-specific lines to Standards if needed (respect the 180-line budget).
5. Write `docs/ARCHITECTURE.md` (modules, boundaries, dependency direction) and, if deploying, `docs/operations.md` (deploy, rollback, monitoring). Write the next-numbered ADR under docs/decisions/ (stack choice, with rejected alternatives).
6. Rewrite `README.md` for the project, present tense. Set repo description, homepage, and topics (gh) so the sidebar reads properly. Scaffold BACKLOG.md with the first milestones from the interview.
7. Configure the harness: attribution/trailers off in settings (verify current key names at run time), branch protection if gated workflow.
8. Verify a clean state: `./scripts/check.sh` passes for real (not template mode). Fix until it does. Completion rule: start may not declare itself complete if format/lint/typecheck/tests cannot actually execute.
9. Write `.start-done` (date + summary), write `START_REPORT.md` (detected, wired, missing, degraded, manual steps), commit with conventional commits, tag `v0.1.0`, and if the workflow is gated, confirm CI on that SHA via `scripts/ci-watch.sh`.
10. Never touch the kernel or `.kernel.hash`.

**ship.md** (the done-gate; run when a logical change is ready to land):

1. Confirm scope: `git status`; unrelated or untracked work is preserved and excluded; resolve every untracked file deliberately (stage it or ignore it, never leave it ambiguous).
2. Run `./scripts/check.sh`. Anything red: stop and fix first.
3. Reviewer gate: independent review verdict present in `.work/TASK.md` (kernel rule 5). Quick-mode tasks may skip the reviewer only if the diff touches no logic (docs/config-comments), and say so.
4. Version: bump the single source-of-truth version file per semver (patch fix, minor feature, major breaking; pre-1.0 per Project decisions).
5. Regenerate CHANGELOG.md via git-cliff (never hand-edit; the detail lives in commit bodies).
6. Conventional commit; the body carries why, and for fixes the exact issue, fix, and files/functions touched.
7. Push per the recorded workflow. Then `scripts/ci-watch.sh` - delegate to the monitor agent when available. A push is complete only when every required check for the exact SHA is terminal-success; on failure: inspect logs, fix root cause, verify locally, push the replacement, monitor the replacement SHA.
8. Release, when a coherent wave ships: move the version, annotated tag `vX.Y.Z`, push the tag, AND create the platform Release object (`gh release create`) with user-facing plain-language notes curated from the changelog - a tag alone does not appear in the Releases panel.
9. Final handoff format: Outcome / Evidence (commands and terminal results) / Artifacts (commit, release, deployment) / Limitations / Next action only if required.

**retro.md** (end of every non-quick task):

1. Classify each defect by discovery route: (a) caught pre-merge by checks, (b) escaped past merge, (c) reported by the human, (d) self-noticed and self-corrected.
2. Routes (a) and (d): record nothing; the system worked.
3. Routes (b) and (c): verify the failing-then-fixed regression test exists (kernel rule 3). If the cause cannot be expressed as any check, append one entry to PENDING.md in the four-field format.
4. Confirmed-good calls: if the human explicitly validated an approach worth repeating, that is a lesson too - same gate, same format, retire-when included.
5. Never record what the repo can already tell you (layout, conventions, history).
6. Increment `used:` and `last:` in INDEX.md for each lesson consulted.
7. Fill the Retro section of `.work/TASK.md`; update BACKLOG.md (done items off, discovered items on, with reasons); move TASK.md to `.work/done/YYYY-MM-DD-<slug>.md`; reset from template.

**maintain.md** (monthly or on request; never mid-task):

1. Verify caps: AGENTS.md <= 180 lines; <= 20 lessons; <= 8 skills. Over cap: merge or archive until under.
2. Archive lessons unused > 45 days or with retire-when met; merge near-duplicates into one generalized entry. Archival is a move to `.archive/` with a one-line reason.
3. Run `./scripts/check.sh --full-mutation`; quarantine anything flaky as its own task.
4. Audit surviving external/live data calls against the local-first rule (each must carry its written reason); convert stragglers. Remove unused dependencies; review lockfile drift.
5. Verify kernel hash; regenerate CHANGELOG if a release is pending; confirm README is still present-tense truthful.
6. Append a dated summary to docs/lessons/MAINTENANCE.log (create on first run).

**bugfix.md**:

1. Reproduce with the smallest reliable case, against real data where it exists. Get a numeric, exact root cause before writing a fix - instrument the actual code path; do not theorize.
2. Identify the owning layer. Escaped or human-reported: failing regression test first, pinned to the real numbers from step 1, not a synthetic happy path.
3. Patch the smallest safe surface; no unrelated cleanup.
4. Targeted tests, then `./scripts/check.sh`. Re-verify against the motivating real data independently of the unit tests.
5. Independent adversarial review (the reviewer agent) trying to find what is still wrong, not rubber-stamping.
6. Ship per ship.md. When speed is requested, parallelize steps across workers; that is never permission to skip re-verification or review.

**audit.md** (full-repo review):

1. Triggers: after a major architecture change or migration; before first real data, customer, or production use; when failures across modules suggest systemic problems; before removing a legacy reference implementation; when security/CI/deploy assumptions have accumulated unreviewed.
2. Scope: architecture boundaries, data flow, validation, error handling, state, concurrency, numerical logic, security, CI, deployment, documentation. Parallelize across workers by disjoint area; the advisor integrates.
3. Priorities: P0 data loss, security exposure, unsafe behavior - stop and fix immediately. P1 wrong core result or broken critical journey - fix before release. P2 material reliability/maintainability defect - plan and fix with regression coverage. P3 minor - record in BACKLOG and batch.
4. Separate confirmed defects (evidence, impact, reproduction, owning layer, verification method) from risks and ideas. Confirmed defects enter BACKLOG with priority; P0/P1 become tasks now.

**longjob.md**:

1. Anything slow (crawls, bulk downloads, migrations, transfers) runs via `scripts/bg.sh`, not as an agent loop.
2. The job checkpoints to a file after every small unit so a kill resumes exactly where it stopped; never write a long job that starts over.
3. A STATE file in `.work/jobs/` carries: mandate, plan checklist, running processes with log and checkpoint paths, decisions made and why, resume instructions. Update as you go so a cold session can pick up.
4. Respect external hosts: honor robots.txt delays, descriptive User-Agent, polite pacing, one process per host.
5. If usage limits may interrupt, schedule a wakeup to resume plus a cheap periodic pulse that restarts a stalled job and deletes itself when done (harness-dependent; degrade to documenting the manual resume).

### 3.10 docs/rules/ - triggered reference rules (each <= 40 lines, dense, no filler)

- **architecture.md**: domain/analysis logic independent from UI, storage, hosting, SDKs; dependencies point inward through explicit contracts; external systems behind adapters; validate and normalize at boundaries, pass typed values into the core; document units, sign conventions, frames, sampling assumptions, missing-value behavior; expensive work off the UI thread; async UI guarded against stale results with cancellation; unavailable controls disabled with a reason or omitted; the dependency-direction diagram (UI -> workflows -> pure core; external -> adapters -> contracts).
- **security.md**: private by default; never commit passwords, tokens, keys, certificates, connection strings, production data; secrets in the approved store; least privilege per identity; no widening exposure without human authorization; no sensitive values in logs, artifacts, or screenshots; validate file type/size/recursion/decompression limits; normalize paths, reject traversal and writes outside the intended root; never execute imported content or interpolate untrusted data into shell commands; review lockfile changes; rotate exposed secrets immediately.
- **data-provenance.md**: keep raw source, normalized data, features, labels, models, and reports distinct; no large raw datasets in git unless designed for them; commit only minimal approved fixtures with source linkage; SHA-256 digests identify external sources; never credentials or private URLs in manifests; preserve original counts, derive percentages reproducibly; never overwrite raw observations with adjusted values; record absolute-vs-control semantics and units in schemas; versioned schemas, strict validation, explicit duplicate policy.
- **scientific-integrity.md**: start from an accepted reference or hand-calculated fixture; record input, expected output, units, source, precision, tolerance (derive the tolerance, do not default to 1 percent unless it is the accepted contract); deterministic seeds stored with parameters; never change expected values to match a new implementation - if the reference is wrong, document evidence and the decision first; independent runs stay independent groups; split train/validation by run group to prevent leakage; report independent-run count, uncertainty, limitations; few-run models are prototypes; software verification is not field or regulatory validation - state validation status honestly.
- **destructive-actions.md**: the seven-step protocol from kernel rule 11, expanded with examples of forbidden targets and the recoverable-first preference.
- **ci-baseline.md**: frozen lockfile installs, fail on metadata/lockfile disagreement; least-privilege workflow permissions; pin third-party actions; cache keys include lockfile/toolchain hashes; upload failure artifacts without secrets; deployment depends on validation of the same SHA; serialize racing deploys; never cancel a production deploy unless rollback design makes it safe; record deployed commit, artifact, environment, time, result; documented rollback path.

### 3.11 .work/TASK.md - template content

```markdown
# Task: {{title}}
Mode: standard | quick | autopilot
Branch: {{branch}}
Date: {{date}}

## Goal
{{one paragraph}}

## Budget
<!-- declare before work starts; on exhaustion: stop, keep the best verified
     artifact, and report unresolved items with reasons - never hide a partial
     result behind a fluent answer -->
- Wall-clock: {{max}}
- Subagents / workflow runs: {{max}}
- Retries per failing step: {{max, default 2}}
- Escalate to human when: {{budget exhausted | criteria unreachable | scope exceeds Non-goals}}

## Acceptance criteria
<!-- each maps to an executable test where possible; list test paths -->
- [ ] {{criterion}} -> {{test path or "judgment: reason"}}

## Plan
1. {{step}}

## Progress log
<!-- timestamped one-liners; this is what survives compaction -->

## Review verdict
<!-- written ONLY by the independent reviewer -->

## Retro
<!-- filled by docs/procedures/retro.md -->
```

### 3.12 docs/lessons/

- **INDEX.md**: header explaining format, then zero entries. Format: `- [L001] <one-line, situation-triggered description> - <the lesson, one or two lines> (used: 0, last: -, retire-when: <condition>)`. Separate file per lesson only if genuinely long.
- **PENDING.md**: header: proposed lessons await human approval; unapproved entries are never acted on; approval = human moves the entry to INDEX.md. Confirmations and corrections both belong here.
- **QUARANTINE.md**: header: flaky tests are defects; each entry carries test path, observed flake behavior, date, and an owner task. A quarantined test may not be deleted.

### 3.13 .claude/ - accelerators only; the repo must function without this directory

- **settings.json**: minimal safe defaults; disable commit/PR attribution trailers (verify the current setting keys against Claude Code docs at build time; if unverifiable, ship `{}` plus a comment in START_REPORT territory - do not invent keys) (VERIFY).
- **agents/reviewer.md**: `model: inherit`, read-only tools (VERIFY current tools syntax). Body: fresh-context adversarial reviewer; receives only the diff, `.work/TASK.md`, and files it chooses to read; must not receive implementer reasoning; checks criteria met, tests assert requirements not current behavior, no gate weakened, no secrets, no unjustified dependencies, edge cases handled; writes PASS/FAIL with specifics into the Review verdict section; gains nothing by being agreeable.
- **agents/explore.md**: `model: haiku`, read-only; fast search and summarization; returns findings, never modifies.
- **agents/worker.md**: `model: sonnet`; edit-capable but git commit and push DENIED via tool permissions (VERIFY syntax; this mechanizes "workers never commit"). Body: executes exactly the scoped instruction it is given - precise paths, schemas, pitfalls; reports files touched; if its instruction conflicts with observed evidence, follows the evidence and says so.
- **agents/monitor.md**: `model: haiku`; tools limited to Bash for `scripts/ci-watch.sh` and gh reads (VERIFY). Body: given a SHA, watch every required check to terminal state and report per the failure format in ship.md.
- **skills/**: four thin wrappers (start, ship, retro, maintain). Each SKILL.md: a description written to trigger on the situation ("Initialize this template for a new project...", "A logical change is complete and ready to land...", "A task just finished; capture what external signal showed...", "Periodic pruning and cap enforcement..."), body = "Follow docs/procedures/<name>.md exactly." Procedures are the truth; skills are pointers.

### 3.14 manifest.md

```markdown
# Environment manifest (declarative - start checks, reports, degrades; it does not assume)

Required for start to complete: git; a working language toolchain; ability to execute scripts/check.sh end to end.
Strongly recommended: gh CLI (checks, releases, branch protection, repo metadata); gitleaks; git-cliff.
Recommended methodology plugin (Claude Code): Superpowers, via the official plugin marketplace (VERIFY current install command at start time). Other harnesses: docs/procedures/ is the fallback methodology.
Policy: CLI tools over MCP servers. MCP schemas cost resident context every turn; CLIs cost nothing until invoked. Add an MCP server only when no CLI equivalent exists; record the justification as an ADR.
Search: prefer rg for repository text search. Edits: patch-based, scoped, reviewable. Non-interactive commands; deterministic scripts.

## Delegation accelerators (harness-specific; kernel rule 16 governs)

- Claude Code: for large parallel scoped work (per-file audits, mass
  migrations, extraction across many documents), prefer a dynamic workflow
  over hand-rolled worker spawning - Claude writes the orchestration script,
  intermediate state lives in script variables instead of the advisor's
  context, and caps are 16 concurrent / 1,000 total per run (VERIFY current
  availability and caps in the Claude Code workflows docs at run time).
  Declare the TASK.md Budget before any fan-out and define the reducer first.
- Never fragment coherent-context work (architecture design, tightly coupled
  refactors, narrative documents). One context, per kernel rule 16.
- Other harnesses: use the native parallel mechanism or sequential workers;
  the budget-first and reducer-first rules still apply.
```

### 3.15 Remaining files

- **cliff.toml**: standard git-cliff config parsing Conventional Commits (feat, fix, docs, test, refactor, perf, build, ci, chore) into Added/Fixed/Changed sections.
- **README.md** (template state): what this template is (one paragraph); quickstart: clone -> open your coding agent -> say "run /start" (Claude Code) or "follow docs/procedures/start.md" (any harness) -> answer one batched interview -> the repo rewrites itself for your project; the philosophy in three lines (checks over prose; external signal only; memory that forgets); a short map of where things live; note that /start rewrites this README; "add a LICENSE before publishing."
- **BACKLOG.md**: scaffold with column headers (item, priority, reason, status) and no rows.
- **docs/ARCHITECTURE.md** and **docs/operations.md**: placeholder headers + `{{FILLED_BY_START}}`.
- **docs/decisions/0001-template-architecture.md**: ADR (Context/Decision/Consequences) recording: AGENTS.md-as-truth with CLAUDE.md import; kernel hash detection; check.sh single gauntlet; four-tier memory with gated learning and mandatory forgetting; generated-changelog-with-detailed-commit-bodies (and why hand-edited changelogs were rejected: generated artifacts are never hand-edited, and commit bodies make the record atomic by construction); CLI-over-MCP; delegation with commit-denied workers. Point to BLUEPRINT.md.
- **.editorconfig**: root=true; utf-8; lf; final newline; trim trailing whitespace (markdown excepted for double-space breaks if desired).
- **.gitattributes**: `* text=auto eol=lf` plus common binary exclusions.
- **.gitignore**: `.env`, `.env.*` (allow `!.env.example`), `.work/jobs/` contents (keep `.gitkeep`), the local instruction file name used by the harness (single line, no comment advertising it), OS/editor junk, caches, coverage, build products. Comment: `.work/TASK.md` and `.work/done/` are deliberately committed - they are memory.
- **.archive/README.md**: two lines: nothing here is deleted, only moved; every entry gets a one-line reason in the moving commit.
- **.kernel.hash**: generated last via `scripts/kernel-hash.sh --update` once AGENTS.md is final.

---

## 4. Stack reference table (start fills check.sh from this; verify tool currency at start time)

| Role | Python | TypeScript/Node | Go | Rust |
|---|---|---|---|---|
| Format | ruff format | prettier or biome | gofmt | rustfmt |
| Lint + boundaries | ruff + import-linter | eslint or biome + import rules / tsconfig refs | golangci-lint | clippy |
| Typecheck | pyright or mypy (strict) | tsc --noEmit (strict) | built-in | built-in |
| Tests | pytest | vitest (+ playwright for e2e) | go test | cargo test |
| Mutation | mutmut | Stryker | go-mutesting (weak - note it) | cargo-mutants |
| Secrets | gitleaks | gitleaks | gitleaks | gitleaks |
| Pinning | pyproject + lockfile (uv/poetry) | pnpm + lockfile, frozen in CI | go.mod/go.sum | Cargo.lock |

Profiles: scientific work adds reference fixtures, golden-master tests, deterministic seeds, documented tolerances. Embedded adds pinned toolchain, firmware build, protocol fixtures, host-side tests, and a documented hardware-in-loop gate. Other stacks: research current equivalents for every role; unfillable roles are logged in START_REPORT.md with a reason.

---

## 5. Build order

1. `git init`; save this file to `docs/BLUEPRINT.md`; first commit.
2. AGENTS.md (kernel byte-exact) + CLAUDE.md; then `scripts/kernel-hash.sh` and run `--update`.
3. `scripts/check.sh` and the other four scripts; verify check.sh runs green in template mode, and verify it FAILS when you temporarily alter one kernel character (restore after).
4. `ci.yml`, `.gitignore`, `.editorconfig`, `.gitattributes`, `manifest.md`, `cliff.toml`.
5. `docs/` procedures, rules, lessons files, ARCHITECTURE/operations placeholders, ADR-0001.
6. `.work/` templates, `.archive/README.md`, `BACKLOG.md`.
7. `.claude/` agents, skills, settings.
8. `README.md`.
9. Conventional commits per logical unit throughout; final tag `template-v0.2.0`.

## 6. Acceptance checklist - self-verify before declaring done

- [ ] Tree matches section 2 exactly; every unfilled value is wrapped `{{ }}`.
- [ ] Kernel block byte-exact per 3.1; `scripts/kernel-hash.sh --verify` passes; mutating one kernel character makes check.sh fail (restored after).
- [ ] `wc -l AGENTS.md` <= 180. CLAUDE.md is exactly `@AGENTS.md`.
- [ ] `bash -n` clean on all five scripts; executable bits set; ci.yml is valid YAML.
- [ ] `grep -rP '[\x{2013}\x{2014}]' .` finds no em or en dashes anywhere in the repo, including docs/BLUEPRINT.md.
- [ ] No plugin installed, no start run, no stack wired, no dependencies added; the template stays project-agnostic.
- [ ] Git history is conventional commits; tagged `template-v0.2.0`.
- [ ] Every (VERIFY) item was checked against current docs, or left as a marked TODO with the uncertainty stated in BUILD_NOTES.md.

## 7. Do-nots

- Do not paraphrase or improve the kernel text.
- Do not run the start procedure; that happens per-project.
- Do not add languages, frameworks, example code, or extra tooling to pad value.
- Do not exceed the line and count budgets anywhere; the budgets are the design.
- Do not use em dashes or en dashes in any file you write.
- Do not silently guess on (VERIFY) items; verify or mark TODO.

---

## Amendment 1 (2026-08-01)

Per-task complexity budgets and dynamic-workflow delegation, from the Karpathy autoresearch / Anthropic workflow synthesis (ADR-0002). TASK.md template (3.11) and new-task.sh gain a Budget block; manifest.md (3.14) gains the Delegation accelerators section; start.md now says "the next-numbered ADR" instead of hardcoding 0002. Kernel untouched: budgets are task-state, workflow pointers are harness-specific.
