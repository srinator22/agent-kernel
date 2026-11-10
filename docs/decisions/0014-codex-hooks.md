# 0014 - Codex hooks and Codex sessions in the dream

Date: 2026-11-10
Status: accepted

## Context

ADR 0006 wired four Claude Code hooks (session context, feedback capture, the
destructive guard, the stop gate) and recorded that Codex had no equivalent.
Codex now has lifecycle hooks, on by default, with the same JSON shape as
Claude Code's (SessionStart, UserPromptSubmit, PreToolUse, Stop and others).
A live probe on 2026-11-10 (codex-cli 0.167.0-alpha.3.2, Windows) recorded
the payloads: every event carries session_id, transcript_path, cwd and
hook_event_name; PreToolUse sends `tool_name: "Bash"` and
`tool_input.command` as a string, also for the desktop app's code-mode
shell; UserPromptSubmit sends `prompt`; Stop sends `stop_hook_active`. The
four scripts already read exactly these fields.

Codex runs a hook on Windows as `%COMSPEC% /C "<command>"` with the command
passed raw, and on Unix as `$SHELL -lc <command>`. Project hooks load only
after the owner trusts the project, and each new or changed hook needs its
own trust. The dream and taste passes read only Claude Code transcripts, so
work done in Codex never reached them.

## Decision

`.codex/hooks.json` wires the four scripts for Codex. On Unix each command is
`bash "$(git rev-parse --show-toplevel)/scripts/<name>.sh"`; the guard's ends
with `|| exit 2`. On Windows `commandWindows` first checks that git runs
(the guard blocks with exit 2 when it does not, the others warn and allow),
then finds the root with `git rev-parse` and calls `scripts/codex-hook.cmd
<name>`, which finds Git Bash from `git --exec-path` and runs the script with
stdin passed through. The guard fails closed when Git Bash is missing.

The feedback wiring check (`scripts/preferences.sh wired`) accepts either
harness's hook file.

dream.py has one reader for Codex rollouts
(`$CODEX_HOME/sessions/**/rollout-*.jsonl` and `.jsonl.zst`). It keeps only
interactive threads whose session cwd is this project, skips subagent
threads, `codex exec` sessions and injected text, and keys its state by
thread id so a rollout that is compressed later is not read twice. The
digest, `due` and the taste pass all use it. This replaces the last bullet of
ADR 0006's Consequences ("Codex and other harnesses have no equivalent
hooks"); the rest of ADR 0006 stands.

## Consequences

- After a template sync, the owner opens the project in Codex once, trusts
  it, and approves the four hooks (`/hooks` lists them). Until then Codex
  runs none of them.
- Codex has no per-agent hooks, so the worker's no-commit rule stays prose
  plus the advisor gate under Codex.
- Limits:
  - Codex caps hook output at about 2,500 tokens; session-context prints the
    task file whole and can be cut short.
  - `~/.codex/archived_sessions` is not read.
  - On Unix a login profile that prints to stdout pollutes the SessionStart
    context.
  - The hook input carries no `workdir`, so the guard resolves a relative
    target against the session folder.
  - A repository git refuses for dubious ownership makes `git rev-parse`
    fail: the guard blocks and the other hooks are skipped.
  - That Codex compresses a rollout to `.zst` after the session is an
    inference from the files on disk, not observed; the reader handles a
    later rename and a `.zst` that is still being written.
  - Reading `.zst` rollouts needs Python 3.14's `compression.zstd` or a
    `zstd` binary; without either they are counted and skipped.

Owner checklist for the first Codex session in a project:

1. `/hooks` lists the four project hooks; trust them.
2. Ask Codex to quote the `[session-context]` lines it received; it names
   the branch and the preference rules.
3. Ask it to run a command the guard blocks, such as `git push --force`;
   Codex reports `BLOCKED by scripts/destructive-guard.sh`.
4. Say "from now on always lead with the result"; a line appears in
   `.work/feedback/log.jsonl`.
5. With a task in progress and a failing check, end a turn: the stop gate
   continues it once. Look at how the rollout records that continuation;
   `scripts/dream.sh digest` must show no signal for it.
6. `scripts/dream.sh digest` lists signals from the Codex session.
