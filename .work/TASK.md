# Task: self-improving-template
Mode: standard
Branch: task/self-improving-template
Date: 2026-10-09

## Goal
Fold the process lessons of four real projects (an embedded controller firmware line with safety states, a controller
PCB design, an instrument data analysis pipeline, and a CAD add-in) and the smaller projects beside them into this
template, so a project started from it (or an existing project that adopts it) begins with: tests ready from day one,
proactive bug-hunting playbooks, a learnings loop that is mechanized and also flows back to the template, project-type
profiles (software, scientific, embedded firmware, hardware PCB, data analysis) with their own rules, gates, tools and
playbooks, a pre-project capability-discovery step (what AI automates, which CLI and MCP tools exist, which tools must
be built), an orchestrator-worker model with a task graph, and model-and-harness-agnostic operation. The README gains
real instructions for starting a project, adopting the template into an existing project and keeping a project synced
with the template. Owner request 2026-10-09 (chat), granted broad latitude: "make additional changes as appropriate
even if I haven't already said so". The source projects are private; nothing project-specific (names, paths, figures,
internal IDs) is carried into this public repository (kernel rule 12).

## Non-goals
- No application code, no stack-specific dependencies in the template itself (CONTRIBUTING rule).
- No change to the 20 kernel rules except two explicit amendments listed under Plan item 9, each with the hash update.
- No rewrite of the source projects; they are read-only inputs.

## Budget
- Wall-clock: 6 hours of orchestrator time
- Subagents / workflow runs: 12 workers maximum, 4 concurrent, disjoint file sets per worker
- Retries per failing step: 2
- Escalate to human when: a kernel amendment beyond the two listed is needed, or check.sh cannot be made green

## Acceptance criteria
- [ ] ./scripts/check.sh green in template mode with the new steps (lessons caps, skills cap, rules-file cap, mirror parity,
      ADR references, BLUEPRINT tree parity) -> scripts/check.sh step 4 output
- [ ] scripts/selftest.sh exercises kernel-hash.sh, new-task.sh, lessons.sh, taskgraph.sh, quickgate (fixtures under
      tests/template/) and is called from check.sh -> tests/template/*.sh
- [ ] docs/profiles/ exists with README, software, scientific, embedded-firmware, hardware-pcb, data-analysis, each with
      rules, gates to wire, tools to build, playbook pointers, agent set -> judgment: cold read by a context-free agent
- [ ] docs/procedures/discover.md (capability discovery before start) and start.md step 0 calls it -> judgment
- [ ] docs/procedures/bughunt.md (proactive) plus docs/DEFECT_MEMORY.md template and per-profile pattern checklists
      -> judgment
- [ ] docs/procedures/upstream.md (template lessons flow back; project sync from template) plus scripts/template-sync.sh
      -> tests/template/test_template_sync.sh
- [ ] .work/TASK.md Plan becomes a task graph (node, depends on, owner files, worker tier, status) validated by
      scripts/taskgraph.sh -> tests/template/test_taskgraph.sh
- [ ] docs/rules/orchestration.md and docs/rules/models.md (tiers cheap/standard/strong/inherit, not model names; harness
      adapters; parity rule) -> AGENTS.md rules index lines
- [ ] README.md rewritten: start a new project, adopt into an existing project (paste-ready prompts), keep in sync, what
      the template enforces -> judgment: a reader can start without asking
- [ ] docs/BLUEPRINT.md tree and sections match the repo (BACKLOG P3 closed) -> check.sh BLUEPRINT parity step
- [ ] Pushed to github.com/srinator22/New-Project with CI green on the exact SHA -> scripts/ci-watch.sh

## Plan
<!-- task graph: one node per line; owner files are disjoint between nodes that run in the same wave -->
| node | depends on | owner files | worker tier | status |
|---|---|---|---|---|
| G1 profiles | - | docs/profiles/** | standard | done |
| G2 procedures and rules | - | docs/procedures/discover.md, bughunt.md, upstream.md, tests.md; docs/rules/orchestration.md, models.md; docs/DEFECT_MEMORY.md | standard | done |
| G3 scripts and self-tests | - | scripts/lessons.sh, scripts/taskgraph.sh, scripts/template-sync.sh, scripts/selftest.sh, scripts/quickgate.sh, scripts/new-task.sh; tests/template/** | standard | done |
| G4 README, blueprint, manifest, ADR | - | README.md, docs/BLUEPRINT.md, manifest.md, BUILD_NOTES.md, docs/decisions/0003-*.md, BACKLOG.md | standard | done |
| G5 check.sh integration | G1, G3, G2, G4 | scripts/check.sh, .github/workflows/ci.yml | advisor | done |
| G6 AGENTS.md and kernel amendments | G1, G2, G3, G4 | AGENTS.md, .kernel.hash, CLAUDE.md, .claude/**, .agents/**, .codex/** | advisor | done |
| G8 hygiene and procedures | G1, G2, G3, G4 | .gitignore, CONTRIBUTING.md, docs/procedures/maintain.md, docs/procedures/retro.md, docs/procedures/start.md, docs/lessons/UPSTREAM.md | advisor | done |
| G7 review and ship | G5, G6, G8 | .work/TASK.md | reviewer then advisor | done |

Kernel amendments (item 9), as applied: rule 10 skills cap becomes "8 core skills plus the skills the adopted
profiles declare" (counted by scripts/lessons.sh from each profile's Skills: line; the first draft said "one profile
skill set", which was ambiguous between one directory and one set of N, so the mechanizable wording was applied), and
rule 16 gains "The plan is a task graph: nodes with dependencies, a worker tier and owner files, and nodes in one wave
own disjoint files." Both applied with scripts/kernel-hash.sh --update under the owner's 2026-10-09 blanket grant
quoted in the Goal; the exact applied text is put to the owner in the final report for confirmation, and the revert is
one kernel edit plus the hash update.

## Progress log
- 2026-10-09 owner authorisation (chat): "make additional changes as appropriate even if I haven't already said so"; the two kernel amendments are applied under it with the hash updated, revertable on request
- 2026-10-09 task scaffolded on task/self-improving-template; sources: an explore report on this repo, a learnings report over the sibling projects, and the PCB project's issue ledger (about a hundred rows), all read-only
- 2026-10-09 G1 to G6 done by four parallel workers plus the advisor; check.sh green in template mode
- 2026-10-09 review round 1 FAIL (12 findings: exposure in the profiles, kernel records, cap mechanism, parity depth, sync claims, mirror claims, a profile contradicting the kernel, stale procedures, tier vocabulary, profile contract, a message mismatch, bookkeeping); all addressed in fix waves A to C
- 2026-10-09 review round 2 FAIL (9 findings: exposure moved into this file, the self-tests failing in any started project, kernel approval record, cap records, template-sync conflicts never recordable, UPSTREAM.md parity, three doc mismatches); all addressed: this file genericised, tests/template/fixtures/check.sh with a started-project scenario, template-sync --resolved with a test, UPSTREAM.md in the tree, records aligned, Skills: line in every profile
- 2026-10-09 review round 3 FAIL (2 findings: the skills parser dropped a name before a trailing semicolon, one stale cap line in BLUEPRINT); both fixed with a parser test; lessons.sh stats reports 14 declared profile skills
- 2026-10-09 review round 4 PASS (no findings); shipping
- 2026-10-09 G8 hygiene files (.gitignore, CONTRIBUTING.md, maintain.md, retro.md, start.md, UPSTREAM.md) edited by the advisor in the fix waves; node added so every changed file has an owner

## Review verdict
Verdict: PASS (reviewer, 2026-10-09, round 4; rounds 1 to 3 superseded)

Checked and sound:
- Round-3 finding 1 fixed: profile_skill_count drops trailing sentence punctuation after removing parentheticals and backticks. The five profiles count 0, 1, 5, 7 and 1. lessons.sh stats prints "cap 22 = 8 core + 14 skills listed by the adopted profiles", matching the declared total and the BACKLOG row.
- test_lessons.sh has a case for a list ending in a parenthetical and a semicolon, followed by a continuation line. It passes only if all four skills are counted (12 skill dirs against a cap of 12), and it asserts "8 core + 4 skills" in the stats output. test_lessons.sh: 82 passed, 0 failed.
- Round-3 finding 2 fixed: the maintain.md spec in BLUEPRINT section 3 states the cap as kernel rule 10 does and names scripts/lessons.sh check. No other "<= 8 skills" wording remains outside test labels and the recorded round-3 verdict.
- ./scripts/check.sh exit 0 in template mode: selftest 8 passed, 0 failed; template self-test OK (98 required files, check.sh fixture, blueprint parity).
- No en or em dash in tracked or untracked files. No new exposure hit; the only path-pattern hit is a generic tool install path in an unchanged file.
- Round-2 and round-3 items verified in round 3 are unchanged: this file is generic; tests/template/fixtures/check.sh is load-bearing and kept identical in template mode; a started copy passes check.sh with the nested selftest; --resolved cannot skip a kernel change; UPSTREAM.md and the fixture are in the tree and the required list; G8 owns the hygiene files.
- Kernel amendments: rules 14 and 15 are met as a recorded disposition. Owner confirmation of the exact text of rules 10 and 16 is still outstanding and must be in the final report.

Findings:
None.

## Retro
<!-- filled by docs/procedures/retro.md -->
