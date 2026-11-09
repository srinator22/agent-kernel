# Preferences - learn what the owner wants and keep it learned

The owner's lasting preferences live in registers, one file per area:
`docs/preferences/<area>.md`. This procedure covers capturing feedback,
recording rows, escalating rules that repeat, starting variants from
baselines, and checking a first draft before the owner sees it.

## What is captured

In Claude Code, the UserPromptSubmit hook `scripts/feedback-log.sh` appends
every owner message to `.work/feedback/log.jsonl` in the main checkout, shared
by every worktree. Each line holds the time, branch, task, a script guess of
the kind (deferral, correction, preference, approval or message), the text,
the files being edited and the agent's last words. The log is local and
gitignored; it holds the owner's words and never enters git. The dream reads
it. `FEEDBACK_LOG=0` turns the hook off.

Codex has no capture hook. In a Codex session, follow the steps below by hand
and note owner feedback in the plan or BACKLOG.md.

The hook may print a line after a message. Treat the kind as a guess and
check it against what the owner said.

## Recording a row in the same turn

Record a register row in the turn only when the owner states a preference
outright. Quote the owner's words with the date in the Source cell, and show
the new row in the reply so the owner can veto it. Anything you inferred, or
a correction that might be a one-off, is left for the dream, which proposes
it for numbered approval.

In template mode (before start has run) no row is recorded: the template
ships the format and the tools, and projects own their rows.

## Register format

The format, the check grammar and the baselines table are in
`docs/preferences/README.md`. `scripts/preferences.sh check` validates every
register, and `./scripts/check.sh` runs it. A new rule starts as `Review`.

## The ladder

1. `Review`: a reviewer looks for the rule.
2. A named check, a test or script step that fails when the rule is broken.

When feedback repeats a rule, the dream raises its `Repeats` count and
proposes moving it up the ladder, through a BACKLOG row or a test. The count
changes only through an approved proposal.

## Baselines

An approved deliverable is recorded in the register's baselines table as the
baseline for its kind. Before building a new variant of that kind, start from
the baseline and reuse what it owns; do not ask the owner again about those
parts. `scripts/new-task.sh` lists the baselines and areas that match the
task name.

## Draft review

Before the owner sees a first draft of an owner-facing deliverable (a render,
a UI, a document or a design), a reviewer checks it against every rule in the
relevant registers. The reviewer reports each rule as met or broken, with
evidence: frames, screenshots or quotes. Fix what is broken, then show the
draft.

## Deferrals

When the owner says "later" or "not now", write a note in BACKLOG.md or the
plan and do not start the work.
