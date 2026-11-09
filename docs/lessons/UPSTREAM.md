# Upstream lessons - process lessons to send to the template

A lesson about how work is run (not what the product does) is recorded here
by `docs/procedures/retro.md`, then sent at maintenance as an issue or PR on
the template (`docs/procedures/upstream.md`). Clear sent entries and note the
link in the maintenance log. Product lessons stay in `PENDING.md`.

Entry format (all five fields required):

- what happened:
- what check should have caught it:
- what was added:
- retire-when:
- applies to: core | <profile name>

### A path printed by Python under Git Bash is in Windows form

- what happened: a test built a fixture under /tmp and asserted the path a
  Python script printed, but Python printed it as C:/Users/.../Temp/..., so
  the assertion failed while the behavior was right (2026-11-08,
  taste-profile). The assertion now matches only the path-free part.
- what check should have caught it: none, this note is the guard: in shell
  tests, assert on the path-free part of a message, or convert both sides
  with cygpath -m before comparing.
- what was added: none.
- retire-when: the test helpers compare paths through one normalizing
  function.
- applies to: core

### Scripts and long text go through files, not the shell

- what happened: python run from stdin or a here-document hung until the
  120 s timeout, inline scripts turned written backslash escapes into real
  bytes, and literal commands over about 4 KB failed with "unexpected EOF
  while looking for matching quote" in the shell tool. It recurred in at
  least five sessions from 2026-08 to 2026-11.
- what check should have caught it: the library hook refuse_shell_stdin.py
  wired into the core settings; the character gate caught escape damage,
  but only in a full run.
- what was added: scripts and text are written with the file tool and run
  by path; backslashes are built with chr(92); literal-path commands stay
  under about 4 KB and are batched.
- retire-when: the stdin hook is wired with its test and the shell tool
  runs long commands or reports its length limit.
- applies to: core

### A fixture for an outside folder sits outside the fixture repository

- what happened: a test faked the per-user projects folder inside its fixture
  git repository; git listed the fake memory notes as untracked files, so
  the check passed through git and the memory comparison it meant to cover
  could be deleted with every check green (2026-11-08, dream outcome fixes;
  found by review round 1).
- what check should have caught it: a mutation run that removes the code
  path a new test is meant to cover; this one did, once run.
- what was added: the fake folder moved next to the fixture, not inside it.
- retire-when: the test helpers create outside-repo folders through one
  function that places them outside the fixture.
- applies to: core

### The destructive-action hook reads heredoc text as a command

- what happened: a shell command that wrote a test block into a file through
  a heredoc was blocked, because the block's text named rm -rf with a
  variable target; the hook reads the whole command line, heredoc body
  included (2026-11-08, sync-defects). The block was written with the Edit
  tool instead.
- what check should have caught it: none, this note is the guard. Write file
  content that names a destructive command with the Edit or Write tool, not
  a shell heredoc.
- what was added: none.
- retire-when: the hook skips heredoc bodies that only feed a file write.
- applies to: core

### Each parallel agent gets its own scratch file names

- what happened: several agents ran at once with the same scratchpad log and
  commit message file names; one repo's check log and one commit message
  were overwritten by another agent's (2026-11-08, three project dreams).
- what check should have caught it: none, this note is the guard.
- what was added: briefs name a log and message file unique to the agent
  and repository.
- retire-when: a helper hands each agent its own scratch folder.
- applies to: core

### The pull request's CI run is the full gate when local runs crawl

- what happened: a full local ./scripts/check.sh took over an hour on a
  loaded Windows machine, while CI ran the same script on the pushed head in
  about 2 minutes and also caught a Linux-only failure (2026-11-09, feedback
  loop).
- what check should have caught it: none, this note is the guard.
- what was added: push the branch, open the PR and use the CI run on the
  exact head as the check.sh evidence for the reviewer; run only the touched
  test files locally.
- retire-when: scripts/selftest.sh runs its test files in parallel and a
  local full gate takes under 10 minutes.
- applies to: core

### Parallel speed has a ceiling

- what happened: asked for maximum parallel speed, one session reached 71
  running background tasks on one Windows computer; test runs starved each
  other for hours and the owner had to stop everything and restart the
  work one piece at a time (2026-11-09).
- what check should have caught it: a count of running background tasks
  before each wave against a cap (BACKLOG row for a session-start warning).
- what was added: docs/rules/orchestration.md caps background tasks at 8;
  a request for maximum parallel speed means waves of the cap.
- retire-when: the harness enforces a concurrency limit itself.
- applies to: core
