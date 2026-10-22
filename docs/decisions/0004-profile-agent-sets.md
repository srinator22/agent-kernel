# 0004 - Profiles ship their agents, skills and tools; a library holds the rest

Date: 2026-10-23
Status: Accepted

## Context

ADR 0003 gave each profile an "Agents and skills" section, but the sets it
named lived only in the owner's prior projects and were marked "port on
adoption". Every new project therefore re-ported them by hand, and each copy
drifted from the others. Other prior projects (a hardware R&D journal, a CAD
add-in, a personal software project) built useful agents and skills that no
profile claims, because a profile needs evidence from two projects.

This repository is public. The source projects are private, and some belong
to an organisation. A verbatim copy would publish their names, part numbers,
record IDs and figures (kernel rule 12).

## Decision

- Each profile ships its set inside its own folder:
  `docs/profiles/<p>/agents/<n>.md` with a Codex twin `<n>.toml`,
  `skills/<n>/SKILL.md`, and `tools/` with `tools/tests/`. start copies the
  adopted profiles' sets into `.claude/`, `.codex/`, `.agents/` and the
  project's tool folder (start.md step 4). Copy, never move: the profile
  folder stays the synced source.
- Items with evidence from one project go in `docs/library/` with the same
  layout and are opt-in (start.md Q7). They graduate to a profile when a
  second project uses them (`docs/library/README.md`).
- Every ported item is a generic rewrite: the process, checks and lessons
  are kept; names, part numbers, record IDs, incident dates and figures,
  paths and the application domain are removed. The owner chose this over
  a verbatim private copy on 2026-10-23.
- `scripts/lessons.sh check` enforces the shape: each profile's `Skills:`
  names equal its `skills/` folders, every shipped skill and agent has
  frontmatter whose `name:` is its file or folder name, and every shipped
  Claude agent has a Codex twin carrying name, description and
  developer_instructions. So the cap of kernel rule 10 counts exactly what
  start installs.
- Library skills take free core slots (8 minus the core skills shipped), so
  kernel rule 10 is unchanged.
- Not ported: third-party skills without a licence that permits
  redistribution; tools that are mostly one product's data (firmware
  simulators, run-log analysers for one log schema, board routing and
  placement scripts). Generic improvements to the core agents found while
  porting go to `docs/lessons/PENDING.md` for human approval, not into the
  core files.

## Consequences

- A project gets working profile agents, skills and tested tools on day one,
  not a list of things to port.
- The template now carries tools whose tests must stay green.
  `tests/template/test_profile_tools.sh` runs every shipped tools/ and
  hooks/ test folder in the template's own self-test, and the adopting
  project wires the copies into its check.sh at start.
- A leak check of genericised content is a judgment step at port time. The
  denylist names the private sources, so it stays outside this repository.
- Profile "Tools" rows that say `port on adoption` remain only for tools
  that could not be made generic.
