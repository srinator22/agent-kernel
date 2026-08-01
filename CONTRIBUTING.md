# Contributing

This template is designed to be operated by coding agents, with humans
approving direction. Contributions follow the same rules the agents do.

- Read AGENTS.md first. The kernel block is hash-pinned: editing it
  requires human approval plus `scripts/kernel-hash.sh --update` in the
  same commit, or CI fails.
- `./scripts/check.sh` must be green (native Windows:
  `scripts\check.cmd`). CI runs the exact same script.
- Conventional Commits; the body carries the why. No attribution
  trailers. Plain hyphens only - no em or en dashes anywhere.
- Keep the budgets: AGENTS.md <= 180 lines, rules files <= 40 lines,
  <= 8 skills.
- Removing anything means moving it to `.archive/` with a one-line
  reason, never deleting.
- The template stays project-agnostic: no stacks, dependencies, or
  example code. Per-project wiring happens via docs/procedures/start.md
  in the cloned project, not here.
