# Task: port-agent-library
Mode: autopilot
Branch: task/port-agent-library
Date: 2026-10-22

## Goal
Copy the custom agents, skills, hooks and generic tools built in the owner's other projects into this template as genericised, profile-scoped sets (docs/profiles/<p>/agents, skills, tools) plus an opt-in docs/library/ for single-project items, installed by start when a profile is adopted. Sources are read-only and stay unchanged. Owner chose on 2026-10-23: genericise (public repo, kernel rule 12) and port generic tools only.

## Non-goals
<!-- explicitly out of scope; scope creep gets caught here -->
- Changing any source project.
- Proprietary names, IDs, part numbers, figures or paths (repo is public).
- Unlicensed third-party skills (changelog-generator, domain-name-brainstormer): their registry forbids redistribution.
- Domain-specific tools (RPM analysers, firmware host simulator, KiCad routing and placement scripts).
- Editing core agents or skills; generic improvements found go to docs/lessons/PENDING.md.

## Budget
<!-- declare before work starts; on exhaustion: stop, keep the best verified
     artifact, and report unresolved items with reasons - never hide a partial
     result behind a fluent answer -->
- Wall-clock: 4 h
- Subagents / workflow runs: 8
- Retries per failing step: 2
- Escalate to human when: budget exhausted | criteria unreachable | scope exceeds Non-goals

## Acceptance criteria
<!-- each maps to an executable test where possible; list test paths -->
- [x] Every ported agent has a Claude .md and a Codex .toml counterpart -> scripts/lessons.sh shipped_set_errors (check.sh 4b), tests/template/test_lessons.sh
- [x] Every name on a profile Skills: line has docs/profiles/<p>/skills/<name>/SKILL.md and every such folder is listed -> scripts/lessons.sh shipped_set_errors (check.sh 4b), tests/template/test_lessons.sh
- [x] start installs the adopted profiles' agents, skills and tools -> docs/procedures/start.md (judgment: procedure text)
- [x] Ported tools pass their own unit tests -> docs/profiles/*/tools/tests, docs/library/tools/tests
- [x] No proprietary identifier in the diff -> local denylist scan (judgment: denylist kept outside the public repo)
- [x] ./scripts/check.sh green; reviewer PASS

## Plan
<!-- task graph: one node per row; nodes that can run in the same wave must
     own disjoint files. Tiers: cheap, standard, strong, advisor, reviewer.
     Status: todo, doing, done, blocked. Validate: scripts/taskgraph.sh check -->
| node | depends on | owner files | worker tier | status |
|---|---|---|---|---|
| N1 | - | docs/profiles/hardware-pcb/agents, docs/profiles/hardware-pcb/skills | strong | done |
| N2 | - | docs/profiles/hardware-pcb/tools | standard | done |
| N3 | - | docs/profiles/embedded-firmware/skills, docs/profiles/embedded-firmware/tools, docs/profiles/data-analysis/skills/test-data-analyst | standard | done |
| N4 | - | docs/profiles/scientific/skills, docs/profiles/data-analysis/skills/add-channel | standard | done |
| N5 | - | docs/library/agents, docs/library/skills, docs/library/procedures, docs/library/README.md | standard | done |
| N6 | - | docs/library/tools, docs/library/hooks | standard | done |
| N7 | N1, N2, N3, N4, N5, N6 | docs/profiles/*/PROFILE.md, docs/profiles/README.md, docs/procedures/start.md, docs/BLUEPRINT.md, scripts/check.sh, tests/template/fixtures/check.sh, docs/decisions/0004-profile-agent-sets.md, docs/lessons/PENDING.md, README.md | advisor | done |
| N8 | N7 | none | reviewer | done |

## Progress log
<!-- timestamped one-liners; this is what survives compaction -->
- 2026-10-23 inventory: 7 source projects; owner chose genericise (public repo) and generic tools only.
- 2026-10-23 N1-N6 ported in parallel, disjoint folders; sources read-only, unchanged.
- 2026-10-23 N7: lessons.sh shipped_set_errors + tests, test_profile_tools.sh, start.md install step, profile text, ADR 0004, BLUEPRINT, 10 PENDING lessons.
- 2026-10-23 review 1 FAIL (real MPN and refdes, incident figures in a fixture, null regeneration silent, calculator called optional); all fixed.
- 2026-10-23 review 2 PASS; ./scripts/check.sh exit 0 (selftest 9/9, template self-test OK).

## Review verdict
<!-- written ONLY by the independent reviewer -->
PASS (second round). All four first-round findings fixed in the staged change; a fresh sweep found nothing else exposing the private sources. Part-number tokens in the added lines checked against 134 source files: 0 shared. Power-branch fixtures share no value with the source fixture or example; test count 36 to 39, assertions 65 to 73, none loosened. Null regeneration_j reports UNKNOWN; --strict exits 1. Calculator mandatory in component-selection, box-design-review, component-reviewer and senior-ee-reviewer (.md and .toml). Gates re-run: lessons.sh check OK, test_lessons 101/101, test_profile_tools 6/6, test_blueprint_parity 11/11, hook --self-test PASS, no dashes, profiles 124/160/127/131/124 lines, fixture identical, third-party skills absent. Non-blocking: the early-stop marker in lessons.sh has no test; the library adr row cites two projects against the one-project rule, flagged in PENDING as a core-procedure candidate.

## Retro
<!-- filled by docs/procedures/retro.md -->
