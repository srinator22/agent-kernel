# 0005 - An opt-in roster of department agents

Date: 2026-10-23
Status: Accepted

## Context

Engineering projects built from this template need more roles than the
core set (advisor, worker, reviewer, explore, monitor) and the profile
agents (board design, firmware, data). The owner asked on 2026-10-23 for
department leads and specialists across R&D leadership, programme
management, mechanical and product design, electronics and firmware,
quality and safety, production, documentation, and video production for
demos and build logs.

None of these roles has project evidence yet, so none qualifies for a
profile (two projects) or the library (one project). Several requested
roles overlap: two video editor entries, a project manager and a senior
project manager, and three sourcing or selection roles. Two already exist:
the library `researcher` and the hardware-pcb `senior-ee-reviewer`.

## Decision

- Add `docs/roster/agents/` with one Claude agent and its Codex twin per
  role, and `docs/roster/README.md` with the department chart, each role's
  kind, tier and folder, and how to adopt it. start asks which to adopt
  (Q7) and installs them by copy.
- Two kinds of role. A lead is read-only (strong tier): it plans, reviews
  and decides, and ends with a verdict the advisor records. A specialist
  writes one kind of artifact in one named folder, at standard tier, or
  strong where its work is verification or safety analysis
  (`docs/rules/models.md`: test-validation-lead, reliability-engineer). No role
  commits, pushes, orders, purchases, publishes, or contacts suppliers or
  customers (kernel rules 15 and 16).
- Overlaps are merged: one senior video editor, one senior project
  manager, and supply split from technical fit as `sourcing-lead` and
  `component-selection-engineer`. Existing agents are reused rather than
  copied: the library `researcher` serves as the research specialist, and
  `senior-ee-reviewer` is revamped as the senior electrical engineer.
- Added because engineering projects need them: systems engineer, test and
  validation lead, reliability engineer, safety and compliance lead,
  manufacturing engineer, simulation analyst, technical writer.
- `scripts/lessons.sh check` applies the shipped-set checks of ADR 0004 to
  `docs/roster/`.
- A role graduates to a profile or the library as projects prove it, by
  the library's rules.

## Consequences

- A project picks the roles it needs at start instead of writing agents
  from scratch, and the roles hand work to each other by exact name.
- The roster is unproven: each role's checklist is expert judgment, not
  learned practice, and is revised on the first project that uses it.
- Roles use the template's evidence rules (kernel rule 14), so a
  simulation, prediction or plan is never reported as a measured result.
