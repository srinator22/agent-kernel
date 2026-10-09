# Profile: software (always on)

## Purpose and risk

Baseline for every project. Risk: a green badge that does not mean the code
works, local and CI results that diverge, and process damage (lost work,
leaked secrets, unreviewed merges). Every other profile stacks on this one.

## Rules

- SW-1 There is one canonical verify command, `./scripts/check.sh`, and CI
  runs that exact script; no step exists in CI that is absent locally.
- SW-2 The gauntlet roles are format, lint with boundaries, typecheck, tests,
  mutation, secrets scan, and changelog freshness; an unfillable role is
  logged in `START_REPORT.md` with a reason, never silently dropped.
- SW-3 No tracked text file contains an en dash (U+2013) or em dash (U+2014);
  vendored and captured third-party files are listed as exempt in one place.
- SW-4 Tests are deterministic: no wall-clock races, no unseeded randomness,
  no network, no test-order dependence; a flaky test is quarantined in
  `docs/lessons/QUARANTINE.md` and fixed as its own task.
- SW-5 A bug found after merge gets a failing regression test before the fix.
- SW-6 The reviewer is a fresh-context agent given the diff and the acceptance
  criteria, not the author's conclusions; the verdict is recorded in
  `.work/TASK.md` by the reviewer only.
- SW-7 A push is not done until CI for the exact pushed SHA reaches terminal
  success, observed by `scripts/ci-watch.sh`; queued or running is not done.
- SW-8 Nothing is deleted; removal moves the artifact to `.archive/` with a
  one-line reason during a maintenance pass.
- SW-9 Generated artifacts (CHANGELOG.md, lockfiles, build output) are never
  hand-edited; CI regenerates and diffs them.
- SW-10 Every CI action pin is verified against the upstream repository, and
  every directly included library is pinned in the clean-runner bootstrap.
- SW-11 Secret scanning uses a pinned open-source CLI release whose published
  checksum is verified, not a licensed hosted action.
- SW-12 Markdown and file discovery in checks excludes generated and cache
  roots (build output, `.build/`, caches) so a build cannot break a docs check.
- SW-13 The advisor commits with the pathspec form (`git commit -- <paths>`)
  limited to the task's files so another worker's staged file never rides
  along; workers never commit.
- SW-14 A clean-clone build runs in the release path; local-only success is
  not evidence.

## Gates

| Gate | Command (wire in check.sh and CI) | Pass | Rule |
|---|---|---|---|
| Kernel hash | `./scripts/kernel-hash.sh --verify` | exit 0 | kernel |
| Line budget | `wc -l < AGENTS.md` at most 180 | exit 0 | kernel 10 |
| Format | stack formatter in check mode | exit 0 | SW-2 |
| Lint and boundaries | stack linter plus import rules | exit 0 | SW-2 |
| Typecheck | strict typecheck | exit 0 | SW-2 |
| Tests | stack test runner, deterministic seed | exit 0 | SW-4 |
| Mutation | stack mutation tool on changed modules | score at least the recorded floor | SW-2 |
| Secrets | pinned gitleaks CLI, checksum verified | no findings | SW-11 |
| No-dash | `grep -rnP "[\x{2013}\x{2014}]"` over tracked text minus the exempt list | no match | SW-3 |
| Changelog freshness | regenerate with git-cliff, diff | no diff | SW-9 |
| Untracked report | `git status --porcelain` | listed, reviewed | kernel 6 |
| Clean clone | fresh clone, run check.sh | exit 0 | SW-14 |

## Tools

- git-cliff, gitleaks, gh: `exists`; install check is `<tool> --version`.
- `scripts/ci-watch.sh`, `scripts/bg.sh`, `scripts/kernel-hash.sh`: `exists` in
  this template.
- no-dash check: `build`, a 10 line script in `check.sh`; exit 1 on a match,
  prints file and line.
- Stack tools come from the table in `docs/BLUEPRINT.md` section 4.

## Playbooks

- `docs/procedures/bugfix.md` (reproduce, regression test, root cause, guard).
- `docs/procedures/ship.md`, `docs/procedures/audit.md`,
  `docs/procedures/longjob.md`, `docs/procedures/maintain.md`.
- `docs/procedures/bughunt.md` for proactive review; `docs/DEFECT_MEMORY.md`
  records each confirmed defect with its permanent defence.
- Defect patterns (recurring-defect checklist for bughunt.md, each maps to a
  trace test or a hunt): stale async result applied after a newer one; off-by-one
  at boundaries (first, last, empty, one element); time zone and locale
  assumptions; unhandled empty input; swallowed errors; flaky timing in tests.
  Beyond these, use the generic hunts in `docs/procedures/bughunt.md` (steps 2
  and 3).

## Agents and skills

- Agents: `worker` (bounded edits, never commits), `reviewer` (read-only,
  fresh context), `explore` (read-only search), `monitor` (tracks a push to
  terminal state).
- Skills: none (the core set of `start`, `ship`, `retro`, `maintain` and the
  other core skills covers this profile; the cap is 8 core skills plus the
  skills the adopted profiles declare on their `Skills:` lines).

## Parameters and records

- Tunable settings live in one headers or config file; checks read it, no
  number is duplicated in two places.
- Decisions are ADRs under `docs/decisions/`; lessons follow the PENDING to
  INDEX gate; defects go to `docs/DEFECT_MEMORY.md`.
- Versions have one source of truth recorded in Project decisions.

## Done means

- Implementation: behavior at the correct layer, tests cover it, nothing
  unrelated included.
- Verification: acceptance tests green, `./scripts/check.sh` green, reviewer
  verdict recorded.
- Delivery: CI green on the exact SHA, observed to terminal success.
- Every confirmed defect has a regression test and a DEFECT_MEMORY row.

## Lessons carried in

- One gauntlet script for local and CI keeps the two from diverging.
- A pinned action SHA that did not resolve upstream; a licensed secret-scan
  action that failed for an organisation; an exact-SHA watcher that mixed push
  and PR run IDs; clean CI lacking a library the local machine had; build
  output that broke a docs link check.
- A local build passed while a fresh clone failed.
- A shared git index let one worker's staged file ride into another's commit.
- Dashes broke repository CI.

## Sources

Sources: distilled from four prior projects of the template owner (embedded
firmware, controller PCB, vibration data analysis, CAD add-in); project records
stay in those repositories.
