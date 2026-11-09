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

## How rows are written

`scripts/dream/preferences.py` holds the one writer, `write_rows`, that the
taste pass and port both use. A new row goes after the last row of the file's
first rules table; a file with only baselines gets a rules table above them; a
new file gets a title, a purpose line and the rules header. The ID prefix is the
one most rows in the file use, else the area name in capitals without
punctuation. Numbers have three digits, run above the file's highest number and
are never reused. A pipe in a cell is escaped and a newline is refused. A rule
whose text (case and spacing aside) already exists in any register is not added
again. Revising a rule appends the date and the owner's words to its Source and
keeps its Check. Removing or revising a row guarded by a named check prints a
warning naming that check. Line endings stay as the file has them, and nothing
is written in template mode or when the result fails `scripts/preferences.sh check`.

## Porting rules from another project

Only when the owner asks. `scripts/preferences.sh port --from <path>` lists
the rules rows of the other project's registers that would be copied and those
skipped as duplicates, and writes nothing. Add `--apply` to copy them, and
`--area <a>` and `--id <ID>` (which needs `--area`) to narrow the list. Each
copied row has the Source `YYYY-MM-DD: ported from <folder> (<original source>)`,
the Check `Review (was <original check> in <folder>)` (plain `Review` when it
was Review) and no Repeats. Baselines are never copied. Port refuses in template
mode, when the path has no registers and when it is this project's own root.

## What a session starts with

Session start prints a one-line summary of the registers and then each area's
rules (ID and Rule), up to 4000 bytes. Past that cap one line names the files
that hold the rest; read them there.

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
