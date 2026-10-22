# Pending lessons - awaiting human approval

Proposed lessons land here. Unapproved entries are never acted on;
approval means a human moves the entry into `INDEX.md` (kernel rule 9).
Confirmed-good calls belong here too, not only corrections. Never record
what is derivable from the repo itself.

Entry format (all four fields required):

- what happened:
- what check should have caught it:
- what was added:
- retire-when:

### Reviewer: missing evidence means FAIL

- what happened: in a prior project's copy of the core agents, the reviewer
  could approve on the implementer's claim that checks passed, because it
  received only the diff and the task file.
- what check should have caught it: the reviewer is handed the verify output
  and returns FAIL when it is missing, truncated, or does not show every stage
  exiting cleanly.
- what was added: nothing yet; proposal: that input contract and FAIL rule in
  `.claude/agents/reviewer.md` and its Codex twin, with an "Evidence checked"
  list ending the verdict block.
- retire-when: recording a verdict in `.work/TASK.md` is impossible without an
  attached check log.

### Reviewer: check the promoted rules, not only the brief

- what happened: a change can obey its brief and still break a rule promoted
  from an adopted profile, and the core reviewer lists only generic checks.
- what check should have caught it: the reviewer reads the AGENTS.md rules
  index and the adopted profiles' rules and checks the diff against each one
  that applies.
- what was added: nothing yet; proposal: one bullet in the reviewer agent and
  its Codex twin.
- retire-when: every promoted rule has a mechanical gate in `scripts/check.sh`.

### Worker: report checks verbatim

- what happened: a worker could summarise a failing check as a pass, or say
  tests pass without showing output.
- what check should have caught it: a reply format that requires each check's
  command and its verbatim final result, with "could not run" said as such.
- what was added: nothing yet; proposal: the reply format (files touched,
  checks run with verbatim result, conflicts or open questions) in the worker
  agent, plus "no version bump unless the brief says so".
- retire-when: the advisor re-runs every worker check itself as a standing step.

### Worker commit block must cover every shell the harness offers

- what happened: the worker's commit-blocking hook matches only Bash, so on
  Windows a `git commit` run through PowerShell passes it.
- what check should have caught it: a test that feeds `git commit` and
  `git push` through each shell's hook path.
- what was added: nothing yet; proposal: matcher `Bash|PowerShell` with the
  logic in one hook script file instead of an inline string.
- retire-when: the harness enforces a per-agent deny list natively.

### Monitor must stay in the foreground

- what happened: a backgrounded CI watch ends the monitor's turn and hands back
  before CI is terminal.
- what check should have caught it: the monitor's instructions forbid
  background runs, use the foreground call at the maximum tool timeout, and
  re-run the same command when it times out with runs still in progress.
- what was added: nothing yet; proposal: those lines in the monitor agent, plus
  both SHAs on a mismatch and the failing log tail verbatim on failure.
- retire-when: the harness resumes an agent when a background task exits.

### CI watcher must not wait on workflows that cannot run

- what happened: a path-filtered workflow never runs for a commit that touches
  none of its paths, so a watcher expecting it waits until timeout.
- what check should have caught it: the watcher derives the expected workflows
  from the commit's changed files and the path filters, prints them, and falls
  back to "expect all" when it cannot decide.
- what was added: nothing yet; proposal: an expected-workflows step and an
  `--expect` override in `scripts/ci-watch.sh`, with a test.
- retire-when: the project has no path-filtered required workflows.

### Explore returns conclusions, not dumps

- what happened: lookups returned large file excerpts that flooded the
  caller's context.
- what check should have caught it: an output contract on the explore agent.
- what was added: nothing yet; proposal: "return conclusions, quote at most a
  few lines when the exact text matters; skip vendored, build-output and
  dependency folders unless asked".
- retire-when: the harness truncates subagent output by size.

### Retro records time-costing traps and routes decisions to an ADR

- what happened: a CI-only gate or a command trap cost a session time with no
  escaped defect, and the retro captured nothing because it records only
  escaped defects and rule gaps.
- what check should have caught it: a retro category for traps that cost time.
- what was added: nothing yet; proposal: a retro step for such traps, whose
  "check that now catches it" may read "none, this note is the guard", and a
  step that sends a durable decision to `docs/decisions/` instead.
- retire-when: each such trap has a mechanical check or the environment changes.

### Bugfix: every regression test is shown failing first

- what happened: `docs/procedures/bugfix.md` requires the failing test first
  only for bugs found after merge; a prior project required it for every fix.
- what check should have caught it: a fix whose new test passes before the
  patch tests nothing.
- what was added: nothing yet; proposal: "run the new test, confirm it fails
  for the stated root cause, then patch", with the root cause named as file,
  function and condition, and the repro command and output recorded.
- retire-when: tooling enforces fail-first (for example mutation checks).

### Decision records need a procedure

- what happened: ADRs live in `docs/decisions/` with no procedure, so format
  and numbering drift between projects.
- what check should have caught it: a numbering and format check, or a
  procedure.
- what was added: an optional `adr` skill in `docs/library/skills/adr/`;
  proposal: promote it to a core procedure once a second project uses it.
- retire-when: `scripts/` generates and lints ADRs.
