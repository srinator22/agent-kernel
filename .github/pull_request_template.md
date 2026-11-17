## What and why

<!-- one paragraph; the commit bodies carry the detail -->

## Checklist

- [ ] `./scripts/check.sh` is green locally (native Windows: `scripts\check.cmd`), or in the template repository the `check` job log for the head ends with `check.sh: verified tree <id>`
- [ ] Conventional Commits; bodies state the why (fixes: exact issue, fix, files and functions touched)
- [ ] A PR that changes a gate file carries the owner-added `gate-change` label (ADR 0018)
- [ ] Kernel untouched, or this PR deliberately pairs the kernel edit with `scripts/kernel-hash.sh --update` and notes the human approval
- [ ] Plain hyphens only; no em or en dashes introduced
- [ ] Nothing deleted; removals are moves to `.archive/` with a one-line reason
- [ ] No hook command, agent instruction, or MCP server changes slipped in unreviewed (agent config is an attack surface)
- [ ] Template stays project-agnostic (no stack wiring, no dependencies, no example code)
