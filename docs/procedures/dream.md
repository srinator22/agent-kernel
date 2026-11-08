# Dream - consolidate memory against what sessions actually did

A retro records what the agent noticed during one task. A dream reads what
happened across every session since the last dream and checks the memory
against it: pending lessons approved, merged or rejected with evidence, new
lessons that recur, stale notes corrected, lessons turned into checks. It
proposes; the human approves numbered items; nothing else changes (kernel
rule 9). Session transcripts are the ground truth; the dream never edits or
moves them.

## When

`scripts/dream.sh due` decides from file stats alone: a dream is due when
sessions have new activity since the last dream and either a task retro
landed in `.work/done/` since then or three days passed. Two places ask the
human, never more than once a day for the same state:
- the Stop hook, when a turn ends with no live task (`scripts/stop-gate.sh`
  runs `scripts/dream.sh due --offer`);
- the retro, as its last step.
The human can also start one with `/dream`. Prefer the gap between tasks.

## Steps

1. Ask "Start dreaming?". On no, stop; the offer is not repeated today.
2. Run `scripts/dream.sh digest`. It reads only the transcript lines added
   since the last dream (each line is read once ever), keeps the lines whose
   working directory is this repository or one of its worktrees (a session
   started elsewhere still counts when it worked here), and writes
   `.work/dream/digest.md`: numbered signals (corrections, denials, hook
   blocks, interrupts, failed tool calls, then plain messages; compaction
   summaries, which the model wrote, are skipped), capped at 40 KB, plus
   hygiene numbers (`scripts/dream.sh hygiene`). Exit 3 means nothing new to
   dream about: say so and stop; no model runs. The state lives in the main
   checkout's `.work/dream/`, shared by every worktree, and the folder
   carries its own `.gitignore`. A worktree root seen by any digest is
   remembered; for a worktree created and removed between two digests, pass
   `--match <its path>` to the next digest, since lines read without it are
   not read again.
3. Dispatch the `dreamer` agent (standard tier, read-only) with the digest
   path, the memory file list in its definition, and this repository's
   Claude auto-memory folder (`~/.claude/projects/<folder named after the
   repository path>/memory`). It returns at most 12 numbered proposals,
   each with evidence (digest signal ids or file:line).
4. Save the report as `.work/dream/<date>-report.md` and show the human the
   numbered list. The human answers with numbers ("apply 1, 3, 5", or none).
5. Apply only the approved numbers, each exactly as its Change line says:
   PENDING.md and INDEX.md edits (an approved number is the human's
   approval), auto-memory notes, BACKLOG rows, UPSTREAM.md entries, and
   `scripts/lessons.sh use <Lnnn>` for counters. Tracked files follow the
   git workflow: on the live task branch, or on `chore/dream-<date>`
   shipped per `docs/procedures/ship.md`.
6. Run `scripts/dream.sh done`, also when nothing was approved, so the same
   lines are not read again. It records the offsets and the dream date in
   the gitignored state only, so a dream with nothing approved leaves no
   tracked change.

## Privacy and cost

- The digest, its state and the reports live in `.work/dream/`, which
  ignores itself through its own `.gitignore` (projects that sync the
  template do not get the template's .gitignore); they never leave the
  machine. Only the text of approved proposals
  enters tracked files, as short generic lesson wording. In a public
  repository, no private project names or quotes.
- Cost: the digest is a script with no model and reads each transcript line
  once ever; an empty digest stops before any model call; one standard-tier
  agent reads at most 40 KB of signals plus the memory files, once. A first
  dream over all history measured about 105k tokens on this template; later
  dreams read only the signals added since.
