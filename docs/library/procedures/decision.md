# Decision - engineering design decisions with evidence

Adopt by copying this file to `docs/procedures/decision.md`, together with the
`engineering-reviewer` agent, the `decision` skill and
`docs/procedures/evidence-levels.md`. Paths below are defaults.

Engineering design decisions are typed records in
`docs/engineering/DESIGN_DECISIONS.md`; process and architecture decisions are
ADRs under `docs/decisions/` (the `adr` skill). A decision is logged before it
is implemented, and only the human approves it (kernel rule 15; the AI
advises).

1. Draft the row: the decision, the records it rests on (assumptions,
   knowledge, hypotheses, experiments, literature, components, by ID, each
   with its evidence level), the alternatives rejected with the quantified
   reason, and the dependents to revalidate if the decision changes. Status:
   proposed.
2. Review: the `engineering-reviewer` agent checks the evidence chain and
   that no E7 or E8 input carries a conclusion stronger than it supports.
3. Human approval in chat; status becomes approved with the date. A
   rejected proposal stays as rejected with the reason.
4. Update the records: assumptions the decision validates or disproves
   change status; requirements it settles change status; open questions it
   answers are closed with the pointer.
5. Revalidation. When a cited record changes (a component replaced, a
   geometry revised, a model corrected, an assumption disproven), every
   decision and requirement listing it as a dependent is marked
   `revalidate <date>` in the same commit. The mark is cleared only by a
   recorded re-check. Nothing is silently kept.
6. Supersession. A changed decision is a new row that names the one it
   supersedes; the old row stays with `superseded by <ID>`. Superseded rows
   are never deleted.
