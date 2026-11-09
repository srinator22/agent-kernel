# 0013 - Project taste

Date: 2026-11-09
Status: accepted

## Context

ADR 0011 kept the owner's tastes in one user-level profile (`~/.claude/taste/`,
a managed import block in `~/.claude/CLAUDE.md`, a managed copy in
`~/.codex/AGENTS.md`). The owner works on two computers. The profile and its
state exist once per computer, so each computer learned its own taste and
neither saw the other's; the second computer's first taste pass wrote a report
nobody could apply on the first. The owner asked for taste to be learned into
the project, the same on every computer, and carried to another project only
on request (2026-11-09). The project already has a home for it: the preference
registers in `docs/preferences/<area>.md` (ADR 0009's process memory), checked
by `scripts/preferences.sh` and tracked in git.

Rejected:
- the user-level profile (ADR 0011): per computer, so the computers drift, and
  it loads in every project whether or not the taste applies there;
- a shared private profile repository: the owner declined it (2026-11-09), and
  it adds a second repository to keep in step on every computer;
- a cloud folder: sync is silent and last-writer-wins, with no review and no
  history of what changed or why.

## Decision

The taste pass is per project. `scripts/dream.sh taste digest` reads only this
project's transcripts (the session's cwd is the root, a worktree or a known
root, as the project dream matches it) and this project's auto-memory notes.
`apply` writes each approved line as a row in the project's registers through
the one register writer, with the signal's date and the owner's quoted words
as Source and `Review` as Check; the evidence rule and the 160-character cap
stay. Git carries the rows between computers like any other change. Every
Claude session start prints the registers' rules under a 4000-byte cap.
`scripts/preferences.sh port --from <project>` copies rows from another
project, only when the owner asks. The digest, pool, ledger and reports stay
per computer in the main checkout's gitignored `.work/dream/taste/`.

The user-level profile is no longer written by any command. Existing files
stay as the owner left them and still load wherever their import block
remains; the owner removes the block by hand. A user-level report written by
an older release is not applied; a fresh project pass reads the project's
transcripts instead.

## Consequences

Both computers see the same rules after a pull, and every rule has a dated
source and a check. A new project starts with no taste until the owner runs a
pass or ports rows. Two computers can add rows on unsynced branches; the
register check reports a duplicate ID before merge. Codex sessions do not load
the registers until Codex has a session-start hook (BACKLOG). The 6000-byte
profile cap becomes the 4000-byte session-start print cap, so a large register
prints only part of its rules and names the files holding the rest.
