## What and why

<!-- one paragraph; the commit bodies carry the detail -->

## Checklist

- [ ] `./scripts/check.sh` is green locally (native Windows: `scripts\check.cmd`)
- [ ] Conventional Commits; bodies state the why (fixes: exact issue, fix, files and functions touched)
- [ ] Kernel untouched, or this PR deliberately pairs the kernel edit with `scripts/kernel-hash.sh --update` and notes the human approval
- [ ] Plain hyphens only; no em or en dashes introduced
- [ ] Nothing deleted; removals are moves to `.archive/` with a one-line reason
- [ ] Template stays project-agnostic (no stack wiring, no dependencies, no example code)
