# 0016 - The software profile ships a verify skill that runs the real app

Date: 2026-11-17
Status: accepted

## Context

Kernel rule 5 counts "rendered output inspected when presentation matters"
as part of verification done, but nothing in the template made it happen:
it was prose, with no command behind it. Tests can pass while the feature
is broken in the running app (a mocked boundary, a route never registered,
a missing asset), and `./scripts/check.sh` runs only tests and static
gates. Each derived project had to invent how to boot and drive its app,
or skipped it.

Alternatives considered:
- A core skill in `.claude/skills/`. Lost: booting and driving an app is
  stack-specific, so a core skill would be generic text every project
  rewrites, and template-sync would then report the rewrite as a conflict
  on every release.
- Leave it to each project as one of its 2 project skill slots. Lost: a
  requirement that costs an optional slot is skipped by the projects that
  most need their slots, and nothing marks the gap.
- A script in `scripts/` that runs the app. Lost: no script can know a
  project's boot and drive steps before start, and inspection of a screen
  needs the agent's judgment.

## Decision

The software profile ships `docs/profiles/software/skills/verify/SKILL.md`
as a template and declares it on its `Skills:` line, so it is counted as a
profile skill (kernel rule 10) and takes no project slot. Start
(`docs/procedures/start.md` step 4) fills its wiring lines (kind, build,
boot, ready signal, drive, inspect, stop) for the project's stack from the
table in the skill, deletes that table, and installs the filled copy into
`.claude/skills/verify/` and `.agents/skills/verify/` (the Codex location,
`docs/rules/models.md`), byte-identical. Start runs it once and records the
run in `START_REPORT.md`. Rule SW-15 requires the skill and a recorded
`verify:` line in `.work/TASK.md` before ship for any change the app shows.
The gate rows: check.sh project mode fails when the installed skill is
missing or still holds an unfilled wiring placeholder; the recorded run is a review gate.

## Consequences

- Every new project has a named, stack-specific way to see its app work,
  written while the stack is fresh in mind.
- The template's skills cap rises by one in template mode (software counts
  there), and in every project.
- The recorded-run requirement is checked by the reviewer, not by a script;
  a mechanical check of the `verify:` line in tasklint is open.
- Projects started before this decision get the skill template through
  template-sync as an adopted-profile DIFF and must fill and install it by
  hand.
- The check.sh project-mode line is owned by check.sh and lands with it.
