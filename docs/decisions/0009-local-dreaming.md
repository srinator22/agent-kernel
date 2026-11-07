# 0009 - Local dreaming

Date: 2026-11-07
Status: accepted

## Context

Memory in this template is written in the moment: the retro records what the
agent noticed during one task, lessons wait in PENDING.md for approval, and
Claude's auto-memory notes are written when Claude thinks of them. Nothing
checks that memory later against what actually happened. Evidence from the
local projects (survey, 2026-11-07): 26 lessons waited for approval across
three repositories; an auto-memory note in this repository stated a fact the
survey contradicted; four repositories had abandoned hand-written session
logs. Meanwhile Claude Code already keeps every session's full transcript
(one JSONL file per session), unread after the session ends.

Anthropic's agent-memory research names the missing step "dreaming": an
offline pass that reads notes against transcripts, corrects them, merges
duplicates and promotes what is stable. The Managed Agents Dreams API does
this for Managed Agents memory stores and sessions. Rejected for this
template: its inputs are Managed Agents sessions, not local Claude Code
transcripts; it is a research preview; it is not eligible for zero data
retention, so private work would sit in a hosted store. Also rejected: a
model reading raw transcripts (one session reached 125 MB) and a scheduled
dream that edits memory on its own (kernel rule 9 keeps a human approval
gate).

## Decision

A local dream in three parts. `scripts/dream.sh digest` (stdlib Python, no
model) reduces the transcript lines added since the last dream, selected by
each line's working directory, to numbered signals (corrections, denials,
hook blocks, interrupts, failed tool calls, then plain messages), capped at
40 KB; byte offsets make every line read once ever, and an empty digest
stops before any model runs. A read-only `dreamer` agent at the standard
tier reads that digest with the memory files and returns at most 12
numbered proposals with evidence. The human approves numbers, and only those
are applied. `scripts/dream.sh due` decides from file stats when a dream is
due; the Stop hook (no live task) and the retro offer it once a day for the
same state.

## Consequences

Memory gets checked against evidence without a human writing session logs,
and the approval gate is unchanged. Each dream costs one standard-tier pass
over at most 40 KB of signals plus the memory files; the digest itself costs
no tokens. Python becomes a requirement for dreaming (the hook treats a
missing Python as "not due"). The digest, its offsets and the reports stay
on the machine in the main checkout's `.work/dream/`, which writes its own
`.gitignore` because synced projects do not receive the template's, and
they quote transcripts. Compaction summaries are skipped: the model wrote
them, so they are not the human's words. Open: a fleet dream across projects and Codex transcripts
(BACKLOG).
