# 0003 - Self-improving template

Date: 2026-10-09
Status: Accepted

## Context

The template was exercised by four real projects of the owner: an embedded
controller firmware project, a controller PCB project, a vibration data
analysis project and a CAD add-in project. Their learnings, plus an inventory
of this repository, found these gaps:

- Caps were stated but not enforced: the 20-lesson cap, the skills cap and
  the 40-line rules-file cap lived in prose and were checked by nobody.
- No self-tests: check.sh template mode checked structure, but the
  template's own scripts (kernel-hash, new-task, and later ones) had no
  tests, so a green badge attested less than it implied.
- No profiles: embedded, hardware, scientific and data-analysis projects
  each rediscovered their own rules, gates and defect patterns.
- No discovery step: tools were found or built weeks into a project (the
  controller PCB project needed a routability checker and a
  board-from-netlist builder after the fact), when they should have been
  planned before the first feature.
- A flat plan: .work/TASK.md held a numbered list, so parallel workers had
  no dependency order and no disjoint file ownership.
- No mirror parity: the .claude, .agents and .codex accelerators could
  drift from each other and from the procedures they point at.
- No upstream channel: a lesson learned in a project never reached the
  template, and a template fix never reached the projects.

## Decision

- Profiles: project-type bundles under `docs/profiles/` (software always
  on; scientific, embedded-firmware, hardware-pcb, data-analysis), each with
  rules, gates, tools to build, playbooks, defect-pattern checklist and an
  agent set. Start selects them and wires their gates.
- Discovery: `docs/procedures/discover.md` runs before start, classifies
  every activity (automate, semi-automate, human only), inventories CLI and
  MCP tools, and ranks tools to build.
- Proactive bug hunting: `docs/procedures/bughunt.md`, driven by profile
  checklists and defect memory, distinct from reactive bugfix.
- Defect memory: `docs/DEFECT_MEMORY.md` records each confirmed defect and
  the check that now prevents it; a fix without a row is not done.
- Tests from day one: `docs/procedures/tests.md`; start wires the harness
  and one passing test per applicable layer.
- Lessons mechanized: `scripts/lessons.sh` enforces caps, usage counters
  and expiry; check.sh also enforces the skills cap and the rules-file cap.
- Upstream and sync: `docs/lessons/UPSTREAM.md`, `docs/procedures/upstream.md`
  and `scripts/template-sync.sh` carry process lessons up and template
  updates down, and describe adoption into an existing project.
- Task graph: the .work/TASK.md Plan is a table of nodes with dependencies,
  owner files, worker tier and status, validated by `scripts/taskgraph.sh`.
- Model tiers: `docs/rules/models.md` names tiers (cheap, standard, strong,
  inherit), never model names, with an adapter per harness and a parity rule.
- Harness adapters: `.claude`, `.agents` and `.codex` mirror each other, with
  mirror parity checked in check.sh.
- Self-tests: `scripts/selftest.sh` and `tests/template/` run in template
  mode, so a green badge attests the scripts as well as the tree.
- Kernel amendments, applied with the hash updated under the owner's blanket
  authorisation of 2026-10-09 (recorded in `.work/TASK.md`): rule 10 skills
  cap becomes "8 core skills plus the skills the adopted profiles declare";
  rule 16 gains "the plan is a task graph; nodes in one wave own disjoint
  files". The count is mechanized in `scripts/lessons.sh` (the `Skills:`
  line of each adopted profile); the task graph rule is detailed in
  `docs/rules/orchestration.md`. Reverting is a kernel
  edit plus `scripts/kernel-hash.sh --update`, on the owner's request.

## Consequences

- A project starts with tests, gates, tools and defect checklists chosen for
  its type instead of rediscovering them; the cost is more files in the
  template to maintain.
- The template's green badge now attests its own scripts, at the price of
  slower template-mode checks and a larger selftest surface.
- Lessons and sync create a two-way channel; the human approval gate stays,
  so improvement is reviewed, not automatic.
- The task graph makes parallel work checkable; plans take more effort to
  write than a numbered list.
- The kernel now states both amendments, so the skills cap and the
  task-graph rule bind from AGENTS.md itself; the kernel hash was updated in
  the same change.

## Rejected alternatives

- One repository per project type: multiplies maintenance, splits shared
  process fixes across copies, and recreates the drift this ADR removes.
- Copying rules between projects by hand: no record, no versioning, no
  conflict handling; that is how the gaps above arose.
- A plugin marketplace: ties the process to one harness, adds resident
  context and an install step, and conflicts with the CLI-over-MCP policy
  in manifest.md.

See `docs/BLUEPRINT.md` Amendment 2 for the specification summary.
