# Task: department-agent-roster
Mode: autopilot
Branch: task/department-agent-roster
Date: 2026-10-22

## Goal
Add an opt-in roster of department agents to the template (docs/roster/), as requested by the owner on 2026-10-23: R&D director, senior project manager, design lifecycle manager, systems engineer; senior mechanical engineer, senior design engineer, simulation analyst, product designer, industrial designer, DFM specialist; senior PCB designer, component selection engineer, sourcing lead, firmware lead, mechatronics integration lead; QA lead, test and validation lead, reliability engineer, safety and compliance lead, manufacturing engineer, technical writer; art director, senior video editor, storyboard specialist, footage analyst, video direction reviewer. Revamp the hardware-pcb senior-ee-reviewer as the senior electrical engineer. Duplicates in the request are merged; the library researcher serves as the research specialist (ADR 0005).

## Non-goals
<!-- explicitly out of scope; scope creep gets caught here -->
- Core agents and procedures (the approved lessons are a separate task).
- Any organisation, product, person or private-project name (public repo).
- Installing roster agents into this template's own .claude/ or .codex/.

## Budget
<!-- declare before work starts; on exhaustion: stop, keep the best verified
     artifact, and report unresolved items with reasons - never hide a partial
     result behind a fluent answer -->
- Wall-clock: 3 h
- Subagents / workflow runs: 7
- Retries per failing step: 2
- Escalate to human when: budget exhausted | criteria unreachable | scope exceeds Non-goals

## Acceptance criteria
<!-- each maps to an executable test where possible; list test paths -->
- [x] 26 roster agents, each a .md with frontmatter and a Codex .toml twin -> scripts/lessons.sh shipped_set_errors over docs/roster (tests/template/test_lessons.sh)
- [x] Leads are read-only in tools and sandbox; specialists write one named folder -> judgment: reviewer reads each file
- [x] senior-ee-reviewer revamped, every existing rule kept -> judgment: reviewer diff
- [x] start offers roster agents and installs by copy -> docs/procedures/start.md (judgment)
- [x] ./scripts/check.sh green; reviewer PASS

## Plan
<!-- task graph: one node per row; nodes that can run in the same wave must
     own disjoint files. Tiers: cheap, standard, strong, advisor, reviewer.
     Status: todo, doing, done, blocked. Validate: scripts/taskgraph.sh check -->
| node | depends on | owner files | worker tier | status |
|---|---|---|---|---|
| N1 | - | docs/roster/agents/rd-director.md, docs/roster/agents/rd-director.toml, docs/roster/agents/senior-project-manager.md, docs/roster/agents/senior-project-manager.toml, docs/roster/agents/design-lifecycle-manager.md, docs/roster/agents/design-lifecycle-manager.toml, docs/roster/agents/systems-engineer.md, docs/roster/agents/systems-engineer.toml | strong | done |
| N2 | - | docs/roster/agents/senior-mechanical-engineer.md, docs/roster/agents/senior-mechanical-engineer.toml, docs/roster/agents/senior-design-engineer.md, docs/roster/agents/senior-design-engineer.toml, docs/roster/agents/simulation-analyst.md, docs/roster/agents/simulation-analyst.toml, docs/roster/agents/product-designer.md, docs/roster/agents/product-designer.toml, docs/roster/agents/industrial-designer.md, docs/roster/agents/industrial-designer.toml, docs/roster/agents/dfm-specialist.md, docs/roster/agents/dfm-specialist.toml | strong | done |
| N3 | - | docs/roster/agents/senior-pcb-designer.md, docs/roster/agents/senior-pcb-designer.toml, docs/roster/agents/component-selection-engineer.md, docs/roster/agents/component-selection-engineer.toml, docs/roster/agents/sourcing-lead.md, docs/roster/agents/sourcing-lead.toml, docs/roster/agents/firmware-lead.md, docs/roster/agents/firmware-lead.toml, docs/roster/agents/mechatronics-integration-lead.md, docs/roster/agents/mechatronics-integration-lead.toml, docs/profiles/hardware-pcb/agents/senior-ee-reviewer.md, docs/profiles/hardware-pcb/agents/senior-ee-reviewer.toml | strong | done |
| N4 | - | docs/roster/agents/qa-lead.md, docs/roster/agents/qa-lead.toml, docs/roster/agents/test-validation-lead.md, docs/roster/agents/test-validation-lead.toml, docs/roster/agents/reliability-engineer.md, docs/roster/agents/reliability-engineer.toml, docs/roster/agents/safety-compliance-lead.md, docs/roster/agents/safety-compliance-lead.toml, docs/roster/agents/manufacturing-engineer.md, docs/roster/agents/manufacturing-engineer.toml, docs/roster/agents/technical-writer.md, docs/roster/agents/technical-writer.toml | strong | done |
| N5 | - | docs/roster/agents/art-director.md, docs/roster/agents/art-director.toml, docs/roster/agents/senior-video-editor.md, docs/roster/agents/senior-video-editor.toml, docs/roster/agents/storyboard-specialist.md, docs/roster/agents/storyboard-specialist.toml, docs/roster/agents/footage-analyst.md, docs/roster/agents/footage-analyst.toml, docs/roster/agents/video-direction-reviewer.md, docs/roster/agents/video-direction-reviewer.toml | strong | done |
| N6 | N1, N2, N3, N4, N5 | docs/roster/README.md, scripts/lessons.sh, tests/template/test_lessons.sh, scripts/check.sh, tests/template/fixtures/check.sh, docs/BLUEPRINT.md, docs/procedures/start.md, docs/decisions/0005-department-agent-roster.md, README.md | advisor | done |
| N7 | N6 | none | reviewer | done |

## Progress log
<!-- timestamped one-liners; this is what survives compaction -->
- 2026-10-23 owner request: 30 roles listed; merged to 26 roster agents plus the revamped senior-ee-reviewer; researcher reused from the library.
- 2026-10-23 N1-N5 written in parallel to disjoint files; N6 wiring: lessons.sh roster check + tests, start.md Q7, BLUEPRINT, check.sh, ADR 0005, README, generated roster README.
- 2026-10-23 review 1 FAIL (power-down sequencing dropped from senior-ee-reviewer, withdrawn ISO 2768-2 cited, three leads with unrestricted Bash) plus six minor; all fixed.
- 2026-10-23 review 2 PASS; ./scripts/check.sh exit 0 (selftest 9/9, template self-test OK, 103 required files).

## Review verdict
<!-- written ONLY by the independent reviewer -->
PASS (second round). F1 to F3 and N1 to N6 verified in both .md and .toml: senior-ee-reviewer pass 1 names rail sequencing at power-up and power-down; senior-design-engineer cites ISO 22081 (ISO 2768-2 on pre-2021 drawings); sourcing-lead, senior-pcb-designer and firmware-lead name their read-only commands; specialists propose DEFECT_MEMORY rows to the advisor; sourcing-lead returns the part-sourcing table; senior-ee-reviewer hand-offs fall back to the advisor; shutter tip limited to mains flicker; reliability-engineer and test-validation-lead strong tier with reason; footage-analyst probe under noclobber (DA-14). Twins identical in content; README 26 rows match kind, tier, model, sandbox and folder; hand-offs resolve; no dashes; same 64 files. Gate on a fresh copy of the staged state: lessons OK, taskgraph OK (7 nodes, 3 waves), selftest 9 passed 0 failed, template self-test OK (103 required files).

## Retro
<!-- filled by docs/procedures/retro.md -->
- Defects by route: (a) caught pre-merge by review round 1 (a dropped check, a withdrawn standard, unrestricted Bash in three leads, six minor) and by taskgraph.sh (glob owner paths); (d) a worker misreported the library writer agent as missing, checked and found present. No (b) or (c), so no PENDING entry.
- Lessons consulted: none approved yet in this branch.
- BACKLOG: no new items; the roster is revised by the first project that adopts a role (ADR 0005).
