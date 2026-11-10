# Models and harnesses - tiers, adapters, parity

Procedures and rules name tiers, never model names; a model name appears only in harness configuration.

Tiers:
- cheap: search, summaries from supplied facts, monitors, formatting.
- standard: bounded implementation, operators of tools, research with
  cited sources.
- strong: review, safety analysis, verification, design, root-cause work.
- inherit: the advisor's own model, for roles that are the advisor's
  judgment (the reviewer is inherit or strong).

Tier to model mapping lives only in harness config: `model:` in
`.claude/agents/*.md` and `.codex/agents/*.toml`; update it there when
models change.

Harness adapters:
- Claude Code: hooks (commit block, session context, feedback capture),
  agents, skills, background tasks, workflows. VERIFY 2026-11-08.
- Codex: agents in `.codex/agents/*.toml`, skills in `.agents/skills`, the
  same four hooks in `.codex/hooks.json` (Windows through
  `scripts/codex-hook.cmd`), run once the owner trusts the project and its
  hooks; no per-agent hooks, so the worker no-commit rule is prose plus the
  advisor gate (ADR 0014). VERIFY 2026-11-10.
- Gemini CLI and Cursor: AGENTS.md only; record what loads at adoption in
  the capability map. VERIFY 2026-10-09.

Parity rule:
- `.claude/skills` and `.agents/skills` stay byte-identical; check.sh
  compares them.
- Every Claude agent has a Codex counterpart, or the reason it has none
  is recorded. explore: no Codex counterpart, Codex's built-in explorer is
  used (recorded reason).
- A one-harness capability is an accelerator; procedures work without it.

Every claim about harness limits (caps, hook support, tool names, settings
keys) carries `VERIFY <date>`; an unmarked claim is a defect. Maintenance
re-checks each marker. Tier per role is recorded in `docs/CAPABILITY_MAP.md`.
Escalate a node one tier after two failures: cheap to standard to strong;
strong escalates to the advisor.
