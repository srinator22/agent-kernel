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
The human can also start one with `/dream`; `/dream taste` runs only the
Taste pass below. Prefer the gap between tasks.

## Steps

1. Ask "Start dreaming?". On no, stop; the offer is not repeated today.
2. Run `scripts/dream.sh digest`. It reads only the transcript lines added
   since the last dream (each line is read once ever), keeps the lines whose
   working directory is this repository or one of its worktrees (a session
   started elsewhere still counts when it worked here), and writes
   `.work/dream/digest.md`: numbered signals (corrections, denials, hook
   blocks, interrupts, failed tool calls, then plain messages; only the
   owner's own messages count, never another session's message or a
   background notification, and compaction summaries, which the model
   wrote, are skipped), capped at 40 KB, plus
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
6. Run `scripts/dream.sh done --report <report> --applied <numbers>` (leave
   out `--applied` when nothing was approved), so the same lines are not
   read again. It records the offsets, the dream date and the signal counts
   in the gitignored state only, so a dream with nothing approved leaves no
   tracked change, and appends "## Outcome <date>" to the report: the
   applied and declined numbers, the files named in the applied Change
   lines, and the hygiene numbers at the digest against now. The next
   digest's "Impact since the last dream" section starts from this record.
7. Run the Taste pass below.

## Scorecard

Every digest has a "## Scorecard" section between Impact and Signals.
`scripts/dream.sh scorecard` prints the same section read-only, which is
how to see it when a digest exits 3. A script builds it from the saved
reports (`.work/dream/YYYY-MM-DD-report.md`) and the checkout's current
files; no model writes it, so the dreamer cannot grade itself. It shows:
- one row per report, oldest first (the last 10; older ones fold into one
  row), with the proposals, the numbers the owner approved and declined in
  the report's last Outcome, or "no Outcome recorded";
- the approval rate per proposal kind (the bracket tag);
- each lesson id and each quoted BACKLOG row that an approved Change line
  names, newest report first, at most 20 of each: its INDEX.md used and
  last values, or the row's last cell, as they are now in the checkout and
  branch the first line names;
- the decided count against 30 (a self-review pass) and 50 (a replay check).

"Approved" is the owner's approval number, not proof the change landed:
"not in INDEX.md" or "not found" on a branch the change has not reached yet
is expected. Candidates are signals that share two or more words with a
lesson, the same matcher as Impact, not proof of recurrence. A report that
cannot be read or has a malformed Outcome is listed as skipped. Kind rows
and skipped lines are capped at 20 as well. A lesson id is L with three or
more digits, as INDEX.md writes them, read as written: a range such as
"L011-L013" counts L011 and L013 only.

## Taste pass

The taste pass learns the owner's tastes across every local project into a
personal profile outside every repository: `~/.claude/taste/<area>.md`,
imported by a managed block in `~/.claude/CLAUDE.md` so every Claude session
in every project loads it, and copied into a managed block in
`~/.codex/AGENTS.md` for Codex. Any project with `scripts/dream/taste.py` can run
it; all of them share one user-level state in `~/.claude/taste/.dream/`.

T1. Run `scripts/dream.sh taste digest`. It reads every project's
    transcripts and the feedback and user notes in every project's
    auto-memory, keeps only the owner's own words (stated preferences,
    answers to questions, corrections, rejected actions, short reactions,
    taste topics), and writes `~/.claude/taste/.dream/digest.md`: signals
    with stable ids, fresh ones first, under a 40 KB cap. Exit 3 means
    fewer than 5 fresh signals or under 7 days since the last pass: say so
    and stop; no model runs, and what was read waits in the pool. `--force`
    skips the day rule; `--projects-dir DIR` adds a transcript folder, such
    as a copy from another computer.
T2. Dispatch the `taste-dreamer` agent (standard tier, read-only) with the
    digest and the profile folder as absolute paths. It returns at most 12
    numbered proposals (add, revise or remove a profile line), each with
    evidence.
T3. Save its report where the digest output says
    (`~/.claude/taste/.dream/reports/<date>-report.md`) and show the owner
    the numbered list. The owner answers with numbers.
T4. Run `scripts/dream.sh taste apply --report <report> <numbers>` with
    exactly the approved numbers. It refuses everything when any approved
    proposal breaks the evidence rule (one stated preference, or signals
    from two or more sessions) or a cap (160 characters a line, 6000 bytes
    in all); otherwise it writes the area files and both managed blocks,
    never touching text outside the blocks. Show the owner what changed.
T5. Run `scripts/dream.sh taste done --report <report>`, also when nothing
    was approved: it appends an Outcome section (applied and declined
    numbers, changes, files, profile lines and bytes before and after) to
    the report. Then run `scripts/dream.sh taste check`. The next digest
    opens with "Impact since the last pass": profile changes, lines whose
    evidence was seen again, lines that share words with new signals, and
    a trend of signal kinds per pass.

The profile belongs to the owner: hand edits to the area files are fine,
`scripts/dream.sh taste sync` rewrites both blocks after them, and `check`
reports caps, duplicate ids and stale blocks. Apply and sync refuse a taste
folder inside a git work tree.

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
- The taste digest, pool and reports live in `~/.claude/taste/.dream/` and
  never enter a repository; only approved lines reach the profile. A full
  taste digest over 1.46 GB of transcripts took about 4 s (2026-11-08); the
  agent reads at most 40 KB of signals plus the profile; the profile costs
  every session at most 6000 bytes, about 1.5k tokens.
