# Agentic template repository

A template that makes a project AI-operable from day one and keeps
improving itself. It contains no application code. It gives any coding
agent that opens it: a hash-pinned kernel (the numbered rules block of
AGENTS.md, which nothing edits without human approval), an enforcement
gauntlet (`scripts/check.sh`, the one script that runs every check and runs
unchanged in CI), memory that learns from external signal and forgets on
schedule, a task graph that survives context compaction, project-type
profiles with their own rules, gates and playbooks, and a
capability-discovery step that finds what to automate and which tools to
build before the first feature.

## Prerequisites

- git and bash (on Windows, Git Bash; `scripts\check.cmd` forwards to it).
  Required: without them nothing runs.
- gh (GitHub CLI): CI watching, repo settings, branch protection. Without it
  those steps are done by hand and `scripts/ci-watch.sh` cannot run.
- gitleaks: the secret scan. Without it start logs the gap and CI is the only
  scan.
- git-cliff: CHANGELOG generation and its freshness check. Without it the
  changelog is written by hand.
- python (python3 or python): validates `.claude/settings.json`. Without it
  that check is skipped locally and CI runs it.
- GNU grep or git grep with PCRE (`-P`): the no-dash scan. Without it the scan
  is deferred to CI.

## Start a new project

1. Use this repository as a GitHub template, or clone it into a new folder.
2. Open your coding agent in it (Claude Code, Codex, or any agent that
   reads AGENTS.md).
3. Paste this prompt:

```
Follow docs/procedures/discover.md and then docs/procedures/start.md with one batched interview. Do not touch the kernel. Ask before the first push, tag or repository setting.
```

4. What happens next: discover writes `docs/CAPABILITY_MAP.md` (what the
   agent automates, which CLI and MCP tools exist, which tools to build);
   start asks one batched interview, selects profiles, wires the stack
   into `scripts/check.sh` and `.github/workflows/ci.yml`, fills the
   Project decisions in AGENTS.md, writes ARCHITECTURE and the first ADR,
   scaffolds tests, and rewrites this README for your project.
5. The first commit and the `v0.1.0` tag are made by start once
   `./scripts/check.sh` passes for real; CI on that SHA is confirmed with
   `scripts/ci-watch.sh`. `START_REPORT.md` lists what was detected,
   wired, missing and degraded.

## Adopt into an existing project

1. Open an AI session in the existing repository.
2. Paste this prompt, replacing the two placeholders with this repository's
   URL and the latest `template-v` tag:

```
Adopt the project template from <TEMPLATE URL> at tag <TAG> into this repository. Read its AGENTS.md and docs/procedures/upstream.md. First list every file you would add or change and stop for my approval. Then copy the core file set without overwriting existing files, run docs/procedures/discover.md and docs/procedures/start.md in existing-project mode with one batched interview, wire scripts/check.sh to this project's existing commands, quarantine any test that already fails with an owner task, and record the adoption as an ADR with the template tag. Do not touch CI, branch protection or tags without asking.
```

3. An existing AGENTS.md or CLAUDE.md is merged by hand, never replaced;
   its project content moves under Project decisions. Failures that
   already exist go to BACKLOG.md; tests that already fail go to
   `tests/quarantine.list` with an owner and date. Neither is fixed during
   adoption.

## Day to day

- Begin a task: `scripts/new-task.sh <slug> [standard|quick|autopilot]`
  creates the branch and `.work/TASK.md`.
- While working run `./scripts/check.sh --quick`; before shipping run the
  full gauntlet (`./scripts/check.sh`). Shipping is a gated merge: the work
  goes through a branch and merges only after the gauntlet is green on CI.
- At milestones run `docs/procedures/bughunt.md`; at the end of every task
  run `docs/procedures/retro.md`; run `docs/procedures/maintain.md` monthly.
- Tags: the template is tagged `template-vX.Y.Z`; a project built from it is
  tagged `vX.Y.Z`. Sync to the latest `template-v` tag.

## Keep a project in sync with the template

Run `scripts/template-sync.sh` on a branch with a clean working tree, dry run
first: it fetches the template at a tag, reports the diff, and writes nothing
until you apply it (`--help` lists the flags). The core file set is listed in
`docs/procedures/upstream.md`. Adopted profiles, the AGENTS.md kernel block
and the rules index are shown as diffs and never applied; the rest of the
core set applies only when the project's copy is untouched since the last
sync. The Project decisions section is never touched. The script
re-verifies the kernel hash afterwards and logs the run to
`docs/lessons/MAINTENANCE.log`. Review the diff, run `./scripts/check.sh`,
then commit.

## Send lessons back

A retro lesson about how work is run (not about the product) goes to
`docs/lessons/UPSTREAM.md` in the project, tagged `core` or a profile
name. At maintenance the owner opens an issue or PR on the template with
those entries. The human approval gate decides; nothing lands unreviewed.
Full contract: `docs/procedures/upstream.md`.

## What the template enforces

`./scripts/check.sh` is the only gauntlet; CI runs the same script.

- Always: kernel hash verify (`.kernel.hash`); AGENTS.md at most 180
  lines; untracked-files report; the dash scan; the caps below; mirror
  parity (`.claude/skills` and `.agents/skills` identical, every
  `.claude/agents` file with a `.codex` counterpart or a recorded reason);
  the task graph; `scripts/selftest.sh` whenever `tests/template/` exists.
- Template mode (before start): template integrity, including required
  files, placeholders, skill frontmatter, settings validity, executable
  bits, ADR references and BLUEPRINT tree parity.
- Project mode (after start writes `.start-done`): the stack gauntlet wired by
  start: format, typecheck, lint with boundary rules, tests, secret scan,
  build, mutation on changed files, CHANGELOG freshness, plus each selected
  profile's gates.
- Caps: 20 approved lessons, 180 lines in AGENTS.md, 8 core skills plus the
  skills the adopted profiles declare, 40 lines per rules file. Forgetting is
  archived on evidence, never deleted.
- Self-tests: `scripts/selftest.sh` runs the fixtures in `tests/template/`
  against `kernel-hash.sh`, `new-task.sh`, `lessons.sh`, `taskgraph.sh`,
  `quickgate.sh` and `template-sync.sh`. `scripts/quickgate.sh` is the
  fast in-work subset of the gauntlet.

## Profiles

Selected at start; `software` is always on. Index: `docs/profiles/README.md`.

- software (`docs/profiles/software/`): the baseline every project gets.
- scientific (`docs/profiles/scientific/`): fixtures, golden masters, seeds, tolerances, validation status.
- embedded-firmware (`docs/profiles/embedded-firmware/`): code that drives physical outputs; safety states, host simulation.
- hardware-pcb (`docs/profiles/hardware-pcb/`): board design with decision log, requirements, issue ledger and release gate.
- data-analysis (`docs/profiles/data-analysis/`): raw instrument files and logs, import, provenance, analysis.

## Procedures

All in `docs/procedures/`, portable to any agent.

- discover: capability discovery before start; tool inventory and build list.
- start: one-shot interview and project adaptation.
- tests: test harness and layers wired from day one.
- bughunt: proactive defect hunting from profile checklists and defect memory.
- bugfix: reproduce, root cause, failing test, smallest fix.
- audit: full-repo review with P0-P3 priorities.
- ship: done-gate, version, push, monitor CI to terminal state.
- retro: end-of-task learning capture.
- maintain: pruning, caps, freshness.
- longjob: checkpointed background work.
- upstream: lessons up, template sync down, adoption.

## Harness support

- Claude Code: `CLAUDE.md` imports AGENTS.md; `.claude/` holds agents, skills and a SessionStart hook.
- Codex: reads AGENTS.md; `.codex/agents/` and `.agents/skills/` carry the same accelerators.
- Any other agent: AGENTS.md and `docs/procedures/` are sufficient; accelerators are optional.
- Model choice: `docs/rules/models.md` defines tiers (cheap, standard, strong, inherit), never model names, with adapters per harness. Task decomposition and worker rules: `docs/rules/orchestration.md`.

## Windows

On native Windows run `scripts\check.cmd`; it bypasses the execution
policy for that call and forwards through `scripts/check.ps1` to the same
check.sh via Git Bash. Git Bash is required.

## License

MIT, see LICENSE. A project built from this template may relicense itself.
