---
name: adr
description: Record an architecture, tooling, data-policy or methodology decision as a numbered ADR in docs/decisions/NNNN-<slug>.md. Use when a decision has just been made that a future session might re-debate, or when the human says record this decision or write an ADR. Do not use for bug fixes or routine features (commit bodies and the changelog carry those), or for engineering design decisions with an evidence chain (use the decision skill).
---

# adr

Decisions worth recording: technology and structure choices, data and
provenance policy, model-selection and validation methods, scope boundaries,
workflow choices, anything that was debated or that a later session might
re-debate. The record is permanent and short.

## Steps

1. Find the next number: list `docs/decisions/`, take the highest `NNNN`
   prefix, add one, zero-pad to four digits. Read the newest existing ADR
   first and match its format exactly.
2. Create `docs/decisions/NNNN-<short-kebab-slug>.md` in the template's
   format:

   ```markdown
   # NNNN - Decision title

   Date: YYYY-MM-DD
   Status: accepted

   ## Context

   The situation and the forces at play, with the numbers that made the
   decision necessary. Facts, not justification. Name the version that
   shipped it, if any. Each alternative that was seriously on the table, and
   the specific reason it lost, goes here too; if nothing else was
   considered, say so and say why.

   ## Decision

   What was chosen, stated plainly in a few sentences.

   ## Consequences

   What gets easier, what gets harder, what we are now committed to,
   honest about the downsides, and any open question the decision leaves.
   ```

3. Keep it short and factual: plain hyphens only, quote the numbers,
   observational tone (kernel rule 20).
4. If the decision changes how the system is built, update
   `docs/ARCHITECTURE.md` in the same commit.
5. If it reverses an earlier ADR, change the old one's status line to
   `Status: superseded by NNNN` and add the date. That status line is the
   only edit ever made to an accepted ADR; its body is never rewritten.
6. Anything that cites the ADR (a procedure, rule or profile file) names it
   as `docs/decisions/NNNN`; `scripts/check.sh` verifies the cited file
   exists, so create the ADR in the same change as the citation.
7. Commit as `docs: add ADR NNNN <short title>` with a body that says why
   the decision was made (kernel rule 6). Never tag or push outside the
   project's recorded git workflow.
