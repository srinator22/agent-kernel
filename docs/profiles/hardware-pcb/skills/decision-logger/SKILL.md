---
name: decision-logger
description: Add or supersede a design decision in the design folder's DECISIONS.md and sync REQUIREMENTS.md, OPEN_QUESTIONS.md, the parameters file and every design document that states the old term, before the decision is implemented. Use for any design choice - part, topology, connector, rating, geometry, policy, scope. Do not use for software architecture records in docs/decisions/.
---

# Decision logger

Purpose: a decision is logged before it is implemented, and a superseded one
leaves no stale statement behind (PCB-3, PCB-4).

## When to use

Any design choice: part, topology, connector, rating, geometry, policy, scope.

## Procedure

1. Read the `DECISIONS.md` summary table; take the next free sequential
   decision ID from the file (never from memory).
2. Write the entry in the existing format with these fields: date, status
   (Proposed, Accepted, Superseded by `<ID>`), decision, rationale,
   alternatives rejected, consequences and follow-ups, cross-links.
3. Add the row to the summary table (ID, date, title, status).
4. Superseding: mark the old entry `Superseded by <ID>` in both its body and
   the table; keep its text. Never delete.
5. Sync: update the affected rows of `REQUIREMENTS.md` (source column) and
   open or close questions in `OPEN_QUESTIONS.md` (`closed <date> by <ID>`).
6. Supersession sweep: when the decision replaces a part number, a connector,
   a rail topology or a geometry (holes, edges, zones), grep the whole design
   folder for the old term and list every file that still states it under
   consequences. Update `ARCHITECTURE.md`, the floorplan, layout plan, layout
   rules, sheet briefs, interface contract and pin map in the same change, or
   name the pass that will. Add the old term as a superseded-terms row for the
   doc-sync check and run `check_doc_sync` until it passes. A geometry change
   updates the parameters file first; the documents follow the table, never
   the reverse.
7. A bound change in the parameters file is itself a decision; log it here
   before the bound moves.
8. Status `Accepted` only on the user's instruction; otherwise `Proposed`.
9. Write the text through `pcb-doc-writer` from the facts supplied (PCB-8),
   then run `check_decisions` and `check_requirements`.

## Outputs

Updated `DECISIONS.md`, `REQUIREMENTS.md`, `OPEN_QUESTIONS.md` and swept
documents; passing checks.

## Never

- Implement in the CAD files before the entry exists.
- Delete or rewrite the history of a decision; supersede it.
- Mark a decision Accepted without the user's instruction.
- Leave a requirement citing a decision that no longer holds.
- Supersede a part or a geometry without the sweep of step 6; a stale
  statement in one design document is a defect.
