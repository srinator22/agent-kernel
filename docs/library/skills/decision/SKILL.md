---
name: decision
description: Log, review, approve or supersede an engineering design decision with its evidence chain and dependents, and mark revalidation when cited records change. Use before implementing any design choice, or when the human runs /decision. Do not use for architecture or process decisions about the repository itself (use the adr skill).
---

Follow docs/procedures/decision.md exactly. A decision is logged before it
is implemented and approved only by the human; superseded rows are never
deleted.

Adopting this skill: copy `docs/library/procedures/decision.md` and
`docs/library/procedures/evidence-levels.md` to `docs/procedures/`, and copy
the `engineering-reviewer` agent (and its Codex counterpart) from
`docs/library/agents/`. Until the procedure is copied, read it from
`docs/library/procedures/decision.md`.
