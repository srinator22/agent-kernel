# 0015 - Shell-stdin hook in core and project hook folders

Date: 2026-11-17
Status: accepted

## Context

The shell-stdin hook refuses `python -` and here-documents, which hung or broke
shell calls in at least five sessions. It sat in `docs/library/hooks/`, and PR 7
wired it into `.claude/settings.json` from there. That failed in a started
project: settings.json is core and syncs to every project, while docs/library
syncs only where a project carries the folder, so a synced project got a
missing-file hook error on every shell call.

Long literal commands also failed with quote errors. A warning on stderr with
exit 0 never reaches the model (PR 9 withdrew one). The Claude Code hooks
reference (https://code.claude.com/docs/en/hooks, read 2026-11-17) documents a
PreToolUse output the model reads without a decision: `hookSpecificOutput`
with `additionalContext`, added as a system reminder next to the tool result
("JSON output > Add context for Claude"; "PreToolUse decision control").

A survey on 2026-11-07 found that every derived project had customized
`.claude/settings.json`, so each template change to that file conflicted at
sync.

## Decision

- The hook moves into core as `scripts/hooks/refuse_shell_stdin.py` (its own
  `ruff.toml` and unittest folder beside it), run through
  `scripts/refuse-shell-stdin.sh`, which picks Python with
  `scripts/find-python.sh`. The library item row goes; the KiCad rule stays
  behind its flag.
- `.claude/settings.json` runs it under matcher `Bash|PowerShell` with
  `--warn-long`, next to the destructive guard. `.codex/hooks.json` runs it as
  a second PreToolUse hook without that flag (Codex's handling of the JSON is
  unchecked); `scripts/codex-hook.cmd` knows the name.
- It fails open: with no Python, git or Git Bash it exits 0 or 1, never 2. It
  refuses a habit; the destructive guard is the one that fails closed.
- `--warn-long` prints one `additionalContext` line when the command exceeds
  4096 bytes and sets no `permissionDecision`, so the permission flow is
  unchanged.
- `scripts/hooks-dispatch.sh EVENT` runs every executable file in the
  project-owned `scripts/hooks.d/<EVENT>/` in name order with the same stdin,
  for SessionStart, UserPromptSubmit, PreToolUse (matcher
  `Bash|PowerShell|Edit|Write|NotebookEdit`) and Stop. Exit 2 from any hook
  passes through. Any other failure, or a file that is not executable, makes
  PreToolUse exit 2 (fail closed) and the other events exit 1. The template's
  own hooks stay wired directly; the dispatcher is a separate matcher group,
  and the harness runs both in parallel and combines their decisions.
  template-sync never lists `scripts/hooks.d/` files, since it walks only the
  template's paths.

## Consequences

- A project adds a hook by dropping a file into `scripts/hooks.d/<EVENT>/`,
  with no edit to settings.json. A project that already customized
  settings.json still merges this change by hand once.
- Every shell and edit call starts one more bash. With no folder the
  dispatcher returns before any fork; on this Windows machine a bare bash start
  measured 180 to 540 ms under load, run in parallel with the other hooks.
- Limits: dispatched hooks share stdout, so in an event whose stdout is read as
  JSON only one of them may print JSON; the harness timeout covers the whole
  folder; the dispatcher is wired for Claude Code only, so a Codex project still
  edits `.codex/hooks.json` for its own hooks.
- The long-command context arrives with the tool result, after the command
  ran; it explains a quote failure, it does not prevent one. The 4096-byte
  figure is the backlog row's, not measured.
- ADR 0014's Codex wiring gains the second PreToolUse hook; the rest of ADR
  0014 and ADR 0006 stands.
