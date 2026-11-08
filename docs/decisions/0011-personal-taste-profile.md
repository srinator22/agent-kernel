# 0011 - Personal taste profile

Date: 2026-11-08
Status: accepted

## Context

Dreaming (ADR 0009) checks one repository's process memory against its
sessions. The owner's tastes - how to be talked to, writing, design, art,
code, how to work together - recur across every project, yet each session
learns them again: corrections repeat, and the auto-memory notes that capture
them belong to one project folder. Claude Code loads the user-level
`~/.claude/CLAUDE.md` in every session and lets it import files with `@path`
(user-scope imports load without the approval dialog); Codex reads
`~/.codex/AGENTS.md` as global instructions. A survey of the local
transcripts (2026-11-08) found the owner's messages tagged by `origin.kind`
(another session's message is `peer`, a background result
`task-notification`), answers to questions stored as structured data, and a
full scan of 1.46 GB taking about 4 s with a byte prefilter.

## Decision

A taste pass in the dream, built like the project pass. `scripts/dream.sh
taste digest` (stdlib Python, no model) reads every project's transcripts and
the feedback and user notes in every project's auto-memory, keeps only the
owner's own words, and turns them into signals with stable ids kept in a
user-level evidence pool. It shows fresh signals first under a 40 KB cap, and
it stops before any model when fewer than 5 are fresh or the last pass was
under 7 days ago. A read-only `taste-dreamer` agent at the standard tier
proposes at most 12 numbered profile lines with evidence. `apply` writes only
the approved numbers, after checking the owner's evidence rule (one stated
preference, or signals from two or more sessions) and the caps (160
characters a line, 6000 bytes in all). It writes `~/.claude/taste/<area>.md`,
a managed import block in `~/.claude/CLAUDE.md` and a managed copy in
`~/.codex/AGENTS.md`. The location, loading every area in every session, the
starting areas (communication, writing, design, art, code, working) and the
evidence rule are the owner's choices (2026-11-08).

Rejected: a profile inside a repository (this template is public, and tastes
span projects); per-project auto-memory (other projects never load it);
loading areas on demand through a skill (cheaper, but easily skipped);
evidence that expires with each pass (a taste inferred from two sessions
weeks apart could never qualify).

## Consequences

Every session in every project carries the profile, at most 6000 bytes (about
1.5k tokens), and the cap forces merges instead of growth. The template ships
only the mechanism; the profile, digest, pool and reports live under
`~/.claude/taste/` and never enter a repository, and apply refuses a taste
folder inside a git work tree. Every synced project can run the pass and all
share one state, so the state carries a format version that an older copy
refuses to write. The project dream's digest gains the same owner filter, so
another session's brief no longer counts as the owner's words. Open: Codex
transcripts, and the owner's rewrites of Claude's text (an `edited_text_file`
attachment shows a file after any outside change, not the owner's edit).
