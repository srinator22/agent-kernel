# Dream - consolidate memory against what sessions actually did

A dream checks memory against sessions since the last dream. It
proposes; the human approves numbered items; nothing else changes
(kernel rule 9).

## When

`scripts/dream.sh due` decides from file stats and the git commit date of
each `.work/done` record: a dream is due when sessions have new
activity since the last dream and either a task retro landed in
`.work/done/` since then or three days passed.
Two places ask, never more than once a day for the same state:
- the Stop hook, when a turn ends with no live task (`scripts/stop-gate.sh`
  runs `scripts/dream.sh due --offer`);
- the retro, as its last step.
The human can also run `/dream`; `/dream taste` runs only the
Taste pass below.

## Steps

1. Ask "Start dreaming?". On no, stop; the offer is not repeated today.
2. Run `scripts/dream.sh digest`. It reads only transcript lines added since
   the last dream from this repository or a worktree, and
   writes `.work/dream/digest.md`: numbered signals (corrections, denials,
   hook blocks, interrupts, failed tool calls, plain messages; owner
   messages only), capped at 40 KB, plus hygiene numbers
   (`scripts/dream.sh hygiene`) and the Feedback and Repeats sections.
   Exit 3 means neither a new signal nor a new feedback line of kind
   deferral, correction, preference or approval: say so and stop; no model
   runs. State lives in the main checkout's `.work/dream/`. For a
   worktree created and removed between two digests, pass
   `--match <its path>` to the next digest.
3. Dispatch the `dreamer` agent (standard tier, read-only) with the digest
   path and this repository's Claude auto-memory folder. It returns
   at most 12 numbered proposals,
   each with evidence (digest signal ids or file:line).
4. Save the report as `.work/dream/<date>-report.md` and show the human the
   numbered list. The human answers with numbers ("apply 1, 3, 5", or none).
5. Apply only the approved numbers, each exactly as its Change line says:
   PENDING.md and INDEX.md edits (an approved number is the human's
   approval), auto-memory notes, BACKLOG rows, UPSTREAM.md entries,
   `scripts/lessons.sh use <Lnnn>` counters. Tracked files follow the
   git workflow: on the live task branch, or on `chore/dream-<date>`
   shipped per `docs/procedures/ship.md`.
6. Run `scripts/dream.sh done --report <report> --applied <numbers>` (omit
   `--applied` when nothing was approved), so the same lines are not
   read again; it appends "## Outcome <date>" to the report.
7. Run the Taste pass below.

## Scorecard

Every digest has a "## Scorecard" section;
`scripts/dream.sh scorecard` prints the same section read-only. A script
builds it from reports and files;
no model writes it, so the dreamer cannot grade itself. It shows:
- one row per report (last 10): proposals, numbers approved and
  declined, or "no Outcome recorded";
- the approval rate per proposal kind (the bracket tag);
- lesson ids and BACKLOG rows approved Change lines name (at most 20 each);
- the decided count against 30 (a self-review pass) and 50 (a replay check).

"Approved" is the owner's approval number, not proof the change landed.
A lesson id is L with three or
more digits, as INDEX.md writes them.

## Feedback and Repeats

Two more digest sections read
`.work/feedback/log.jsonl` in the main checkout (UserPromptSubmit hook,
gitignored).
- "## Feedback": lines of kind deferral, correction, preference or
  approval, newest first (ids f1, f2), with
  text clipped to 400 characters, at most 12000 bytes. The
  kind is a guess, not a verdict.
- "## Repeats": rules in `docs/preferences/*.md` sharing two or more words
  with a correction or preference, as `<rule ID> <- f<N> (words)`, at most 40
  lines; the dreamer judges each. Repeats counts change only
  through an approved proposal.

`done` commits the log offset, then renames a log over 5 MB to
`log.1.jsonl` (one kept) and resets the offset to 0, keeping a carry.
A line without its
newline waits for the next run, and a log
shorter than the saved offset is read again from 0. A missing log is not an
error.

Extra proposal kinds:
- `[preference]`: a new register row whose Source quotes the owner's words
  and the date;
- `[escalate]`: a rule with repeats moves from Review to a named check
  (a BACKLOG row or a test);
- `[baseline]`: an approved deliverable becomes a baselines row.

## Taste pass

Learns the owner's tastes from this project's sessions into
the registers (`docs/preferences/<area>.md`, see
`docs/procedures/preferences.md`); rows follow the git workflow, on the live
task branch or on `chore/dream-<date>`. Files are per computer, in the
gitignored `.work/dream/taste/`. Rules reach another
project only when the
owner asks, with `scripts/preferences.sh port --from <project>`.

T1. Run `scripts/dream.sh taste digest`. It reads this project's transcripts
    and auto-memory feedback notes, keeps only the
    owner's own words, and writes `.work/dream/taste/digest.md`:
    signals with stable ids, under a 40 KB cap, and a
    `profile:` line (registers' print against the 4000-byte cap).
    Exit 3 means fewer than 5 fresh signals or under 7 days
    since the last pass: say so and stop; no model runs.
    `--force` skips the day rule; `--projects-dir DIR` adds
    a transcript folder (a copy from another computer).
T2. Dispatch the `taste-dreamer` agent (standard tier, read-only) with the
    digest and the project's `docs/preferences/` folder as absolute paths. It
    returns at most 12 numbered proposals (add, revise or remove a row),
    each with evidence.
T3. Save its report where the digest output says
    (`.work/dream/taste/reports/<date>-report.md`) and show the owner the
    numbered list.
T4. Run `scripts/dream.sh taste apply --report <report> <numbers>` with
    exactly the approved numbers. It refuses everything when any approved
    proposal breaks the evidence rule (one stated preference, or signals from
    two or more sessions) or the cap (160 characters a rule), and in template
    mode. Otherwise it writes each add as a row (Source: date and the
    owner's quoted words or "inferred from
    sessions"; Check `Review`), applies revises and removes by register ID,
    and skips an add whose rule text a register already holds. Show the owner
    what changed; rows follow the git workflow.
T5. Run `scripts/dream.sh taste done --report <report>`, also when nothing
    was approved. Then run
    `scripts/dream.sh taste check`.

To stop loading an older release's user-level profile, delete the lines from
`<!-- taste:begin` to `<!-- taste:end -->` in `~/.claude/CLAUDE.md` and
`~/.codex/AGENTS.md`. A taste report written by an older release
is not applied: run a fresh project taste pass.

## Fleet dream (template only)

Reads what projects started from the template send back, from the list
`scripts/fleet.sh` reads (`fleet.local.list`, gitignored); it refuses
once start has run. Run it when projects have new UPSTREAM.md entries or
dream reports.

F1. Run `scripts/dream.sh fleet`. It reads, never writes, each listed
    project's Template line, open `docs/lessons/UPSTREAM.md` entries and
    newest two dream reports, and writes
    `.work/dream/fleet/digest.md` (gitignored).
    `--max-bytes` (default 40000) is shared by the projects;
    an entry is cut at 1500 bytes. A
    missing folder or a relative line is listed, not read.
F2. Transcripts only with the owner's permission: `--transcripts` adds each
    project's transcript signals. Without it no transcript is opened.
F3. Dispatch the `dreamer` agent in fleet mode with the fleet digest path
    and this repository's BACKLOG.md, `docs/lessons/` and AGENTS.md. It
    returns at most 12 numbered template-change proposals, each citing the
    project and the entry id.
F4. Save the report as `.work/dream/fleet/<date>-report.md` and show the
    owner the numbered list. Approved numbers become BACKLOG rows or
    `docs/lessons/PENDING.md` entries in the template, worded generically:
    no project name, path or quote enters a tracked file.
F5. Run `scripts/dream.sh fleet done`. It commits the transcript offsets and
    records the "last fleet dream" date. UPSTREAM entries stay in the projects
    until each sends and clears them (`docs/procedures/upstream.md`).

## Privacy and cost

- `.work/dream/` ignores itself, and
  they never leave the machine. Only the text of approved proposals
  enters tracked files, as short generic lesson wording. In a public
  repository, no private project names or quotes.
- Cost: digests are scripts with no model;
  an empty digest stops before any model call; one standard-tier agent reads
  at most 40 KB of signals plus the memory files, once (a first dream over
  all history: about 105k tokens on this template). The registers cost
  every session at most 4000 bytes, about 1k tokens. The fleet digest
  writes nothing in any project and reads
  transcripts only with `--transcripts`.
