# 0012 - Template core skills are counted apart from project skills

Date: 2026-11-08
Status: accepted

## Context

Kernel rule 10 capped skills at 8 core skills plus the skills the adopted
profiles declare. The template's own core skills and the skills a project
added itself (library skills, its own) shared those 8 slots. The template
shipped 6 core skills, so a project had 2 free slots; template-v0.4.0 added
the dream skill, the seventh, and one project that had filled its slots went
from 16 to 17 skills against a cap of 16. Its sync held the skill back in a
separate commit. Every later core skill would do the same to every full
project.

Alternatives considered:
- Raise the 8 each time the template adds a core skill. Lost: every such
  release becomes a kernel change in every project, and the number stops
  bounding anything.
- Keep the cap and have template-sync report the breach as an action item.
  Lost as the counting rule: each new core skill would force projects to
  delete a skill they chose. The report itself is kept (below).

## Decision

The cap is the template's core skills present in the project (at most 8)
plus 2 project skills plus the skills the adopted profiles declare.
`scripts/lessons.sh` holds the core list (`CORE_SKILLS`); the file syncs to
every project, so the list travels with each release. In template mode,
`scripts/check.sh` step 5m requires `.claude/skills` to hold exactly that
list, and `lessons.sh check` fails a list longer than 8. A core skill a
project removed frees no project slot. After a sync, `scripts/template-sync.sh`
runs `lessons.sh skills` and prints an `ACTION: skills cap` line and exits 1
when the project is over its cap. Chosen by the owner on 2026-11-08.

## Consequences

- A new core skill never pushes a project over its cap; the template's core
  set is bounded by the 8 instead.
- Adding a core skill means adding its name to `CORE_SKILLS` in the same
  change; step 5m fails otherwise.
- A project that fills its 2 project slots and wants a third skill must
  retire one, as before.
- The ceiling a project can reach is 10 plus its profile skills once the core
  set reaches 8, against 8 plus profile skills before.
