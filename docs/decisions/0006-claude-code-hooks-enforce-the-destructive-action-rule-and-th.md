# 0006 - Claude Code hooks enforce the destructive-action rule and the done gate

Date: 2026-10-29
Status: accepted

## Context

Kernel rules 5, 6 and 11 and `docs/rules/destructive-actions.md` were prose
only in the main session; only the worker's commit block was mechanical. The
owner approved adapting hook ideas from a public agentic-coding knowledge base
(BLUEPRINT Amendment 4). Two forces shaped the design.

- The quick lane is slow where template self-tests exist: `scripts/quickgate.sh`
  took 565 s on Windows Git Bash, and `tests/template/test_check_always.sh`
  alone took 340 s. Running it at every turn end would stall every turn of an
  open task for minutes.
- A PreToolUse hook sees command text, not what the shell will do. Five
  review rounds kept finding new spellings that reach the same deletion.
  Examples: keywords and grouping, an earlier cd, escaped spaces, and
  wrappers that rebuild a quoted path.

Alternatives considered:
- Quick gate at every turn end: lost on the measured cost. The owner chose
  the narrowed form on 2026-10-29.
- A shell parser: lost because it needs a dependency in a hook that runs
  before every command, and the template allows none.
- Prose only: lost on kernel rule 1 (mechanize first).

## Decision

- `scripts/destructive-guard.sh` runs as a PreToolUse hook (matcher
  `Bash|PowerShell`) in every session and subagent.
- It is a text guard that fails toward refusing:
  - Every reading of an ambiguous form is checked, and any one of them can
    refuse. Examples: a backslash before a space, and a cd inside a
    subshell, which is checked both as persisting and as not.
  - Over-blocking inside quoted strings is accepted.
  - There is no bypass. The human runs any command it refuses.
- Its stated coverage is the list in `docs/rules/destructive-actions.md`.
  Forms outside that list are documented limits, not defects.
- `scripts/stop-gate.sh` runs as a Stop hook.
  - It runs the fast task-state checks (taskgraph, tasklint) at every turn
    end.
  - It runs the quick lane only once every acceptance criterion is ticked,
    and caches a green run by the state of the working tree.
  - `stop_hook_active` limits it to one block in a row.

## Consequences

- An agent can no longer remove the workspace, home or a root by mistake, or
  skip hooks and force-push, without the human running the command.
- An agent also cannot end a turn with broken task state, or claim a task
  finished while the quick lane is red.
- Agents that write tests or commit messages naming a refused form must put
  the text in a file and pass it by path. The guard reads the command line,
  including heredocs.
- The guard needs bash 4.4 or newer (manifest.md); a port to bash 3.2 is in
  BACKLOG.
- The quick lane is too slow to run at every turn end until the self-tests
  are faster (BACKLOG P2). Revisit the Stop gate trigger then.
- Codex and other harnesses have no equivalent hooks. They keep the prose
  rules and the ship procedure (docs/rules/models.md).
