# Environment manifest (declarative - start checks, reports, degrades; it does not assume)

Required for start to complete: git; a working language toolchain; ability to execute scripts/check.sh end to end. Native Windows shells run it via scripts\check.cmd (execution-policy safe) or scripts/check.ps1; both locate Git Bash and forward to the same script.
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
