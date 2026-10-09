# Environment manifest (declarative - start checks, reports, degrades; it does not assume)

Required for start to complete: git; a working language toolchain; ability to execute scripts/check.sh end to end. Native Windows shells run it via scripts\check.cmd (execution-policy safe) or scripts/check.ps1; both locate Git Bash and forward to the same script.
Strongly recommended: gh CLI (checks, releases, branch protection, repo metadata); gitleaks; git-cliff.
Recommended methodology plugin (Claude Code): Superpowers, via the official plugin marketplace (VERIFY current install command at start time; install command never verified by this template, last review 2026-10-09). Other harnesses: docs/procedures/ is the fallback methodology.
A bash test runner is not required: scripts/selftest.sh and tests/template/ are plain bash, so the template's own checks need nothing beyond git and bash.
Policy: CLI tools over MCP servers. MCP schemas cost resident context every turn; CLIs cost nothing until invoked. Add an MCP server only when no CLI equivalent exists; record the justification as an ADR.
Search: prefer rg for repository text search. Edits: patch-based, scoped, reviewable. Non-interactive commands; deterministic scripts.

## Delegation accelerators (harness-specific; kernel rule 16 governs)

- Claude Code: for large parallel scoped work (per-file audits, mass
  migrations, extraction across many documents), prefer a dynamic workflow
  over hand-rolled worker spawning - Claude writes the orchestration script,
  intermediate state lives in script variables instead of the advisor's
  context, and caps are 16 concurrent / 1,000 total per run (VERIFY current
  availability and caps in the Claude Code workflows docs at run time; caps last verified 2026-08-01).
  Declare the TASK.md Budget before any fan-out and define the reducer first.
- Never fragment coherent-context work (architecture design, tightly coupled
  refactors, narrative documents). One context, per kernel rule 16.
- Parallel edit isolation: concurrent edit-capable workers each get their
  own git worktree; within one tree, two workers never touch the same file
  (kernel rule 16).
- Other harnesses: use the native parallel mechanism or sequential workers;
  the budget-first and reducer-first rules still apply.

## Discovery

The tool inventory for a project (which CLI tools and MCP servers exist for
each activity, which are missing, which tools must be built) is produced by
docs/procedures/discover.md before start runs, and recorded in
docs/CAPABILITY_MAP.md. This manifest stays declarative and generic; the
per-project inventory belongs in the map, not here. Each tool is verified
with its own `--version` output at discovery time (VERIFY: tool currency is
checked on the day, never assumed from this file).
