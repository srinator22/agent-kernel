# Agentic template repository

A greenfield template for fully AI-operated projects. It contains no
application code. It gives any coding agent that opens it: a governing
instruction file (AGENTS.md), an enforcement gauntlet (scripts/check.sh,
mirrored exactly in CI), a memory system that learns from external signal
and forgets on schedule, a task-state protocol that survives context
compaction, a delegation model, and a one-shot start ritual that
interviews the human and rewrites the repo for the specific project.

## Quickstart

1. Clone this repository (or use it as a GitHub template).
2. Open your coding agent in it.
3. Say "run /start" (Claude Code) or "follow docs/procedures/start.md"
   (any harness).
4. Answer one batched interview. The repo rewrites itself for your
   project: stack wired into check.sh and CI, decisions recorded, this
   README replaced.

## Philosophy

- Checks over prose: a rule that can be a script cannot be ignored.
- External signal only: tests, CI, and human reports are ground truth.
- Memory that forgets: every lesson has a retire condition and a cap.

## Where things live

- `AGENTS.md` - source of truth: kernel, standards, rules index, project
  decisions
- `docs/procedures/` - start, ship, retro, maintain, bugfix, audit,
  longjob
- `docs/rules/` - triggered reference rules, indexed in AGENTS.md
- `docs/lessons/` - gated, counted, expiring memory
- `.work/` - current task state, committed so it survives compaction
- `scripts/` - the gauntlet and its helpers
- `.claude/` - optional accelerators; the repo works without them

Note: /start rewrites this README for the project. Add a LICENSE before
publishing anything built from this template.
