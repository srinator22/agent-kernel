# Component - research, record and track a part

Adopt by copying this file to `docs/procedures/component.md`, together with the
`researcher` agent, the `component` skill and
`docs/procedures/evidence-levels.md`. Paths below are defaults.

A part enters the project as a component record (one file in
`bom/components/` from a `TEMPLATE.md`) and a row in `bom/BOM.md` with state
`candidate`. States: candidate -> selected -> purchased -> received ->
measured -> tested; rejected and superseded are terminal from any state. No
purchase is made by any agent; the human purchases after approving
`selected` (kernel rule 15; the purchase is an outward-facing, cost-bearing
action).

1. Research (the `researcher` agent): fill every documentation field of the
   component template with its evidence level and source; store the datasheet
   under `datasheets/` with its manifest row and SHA-256 (a number without a
   stored datasheet is labelled unverified); record CAD and STEP
   availability, price in the local currency with the date (or the original
   currency, labelled), alternative vendors and compatibility with already
   selected parts.
2. Distinguish seller claims (E8), manufacturer datasheet values (E2) and
   independent measurements (E1 if reproducible, E6 if a community test) in
   the record. Performance tables from a seller are claims until measured on
   the project's own rig.
3. Candidate to selected: the comparison that supports the choice is a
   dated note in `docs/research/` and the human approves in chat. For parts
   on a power or safety path, run the project's component-selection or design
   review first if the project has one, and state side effects of the choice
   (for example a substitution that raises inrush above a fuse rating) at
   decision time, not after.
4. Received: the human records measured mass and key dimensions (E1) in the
   record; a difference from the datasheet beyond its stated tolerance is a
   knowledge record and triggers revalidation of dependents.
5. Measured and tested: experiment records link from the BOM row.
6. When CAD is unavailable, a simplified dimensionally accurate reference
   model is built from the datasheet drawing and labelled E2 with the
   drawing revision; its path is recorded.
7. Superseded or rejected rows stay in the BOM with the reason and date.
