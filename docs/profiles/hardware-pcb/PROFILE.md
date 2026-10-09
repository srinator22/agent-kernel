# Profile: hardware-pcb

## Purpose and risk

For a printed circuit board or electronics design delivered as files and,
later, as assembled hardware. Risk: a wrong footprint, polarity or stop-chain
behaviour on a board that costs hundreds of dollars to fabricate once, with no
second chance; stale documents that contradict the design; a layout that cannot
be routed. Sizing and process come from a prior controller PCB project.
Detail files: `LAYOUT_PROCESS.md` (order of layout work), `CHECKS.md` (ledger).

## Rules

- PCB-1 Every design file stays inside the design folder; its AGENTS.md states the scope.
- PCB-2 No document, no part: every number traces to a datasheet stored in `datasheets/` and listed in `MANIFEST.md` with sha256 and revision.
- PCB-3 A decision is logged (with a sequential decision ID) before it is implemented; superseded decisions are marked, never deleted, and add a superseded-term row for the doc-sync check.
- PCB-4 Design numbers live in one parameters file with a source and bounds per value; tools read it; a bound change is a logged decision first.
- PCB-5 Power and motor copper is hand-routed to written rules; autorouting is for signal nets only, on a copy, followed by DRC.
- PCB-6 The gate passes before any commit of design files and before any order; a `--quick` pass is not a release pass.
- PCB-7 No fabrication order, assembly order or purchase without explicit user instruction; a SHIP verdict is not that instruction.
- PCB-8 Documentation agents write from facts supplied in the prompt, never invent a number, write `TBD` and list it, and are reviewed before commit.
- PCB-9 Safety invariants: every output is off in hardware during reset, boot and unpowered controller; the stop chain is never bypassed by software; a closed speed loop does not depend on the controller.
- PCB-10 Component selection: for every connector, inlet, switch, sensor or module check for a manufacturer pre-wired or pigtail version and a solder-free option; state mating parts, termination type, conductor size and rating difference between bare and pre-wired before locking the part.
- PCB-11 The advisor commits with the pathspec form limited to the design folder; workers never commit.
- PCB-12 A failing check is quoted, not summarised; a figure not verified against its datasheet is labelled unverified.
- PCB-13 The design is `<letter>-draft` until manufacture; a revision letter needs the full gate, a review record, a fabrication package with sha256 manifest, title blocks and silkscreen at the letter, a release-table row, an annotated tag and the user's instruction.
- PCB-14 Silkscreen carries functional labels only (port names, pin 1, pole names, test points, LED names, fuse ratings, polarity, block titles); reference designators go on the fabrication layer and in documents.
- PCB-15 Every WARN, and every INFO that states a number against a limit, has an owner: an open question, a requirement with a verification step, or a disposition line in the dated gate record.
- PCB-16 Every escaped issue gets a ledger row (`CHECKS.md`) before its fix; a layout starts with routability (`LAYOUT_PROCESS.md`).
- PCB-17 Reviewers are read-only; findings are recorded unchanged; every external finding is dispositioned: accepted with a decision or question, rejected with the technical reason, or already covered with the reference.
- PCB-18 One writer at a time per shared file; one KiCad operator at a time on the live board file.

## Gates

Exit codes for every command: 0 pass, 1 check failed, 2 could not run (never a pass). Results are recorded in `analysis/<date>_GATE.md`. Commands are placeholders the project supplies.

| Gate | Command (wire in check.sh and CI) | Pass | Rule |
|---|---|---|---|
| Quick gate (during work, no CAD application) | `<pcb-gate> --quick` | exit 0; not a release pass | PCB-6 |
| Full gate (before commit of design files and before any order) | `<pcb-gate>` (adds ERC, DRC with zones refilled, analyzers) | exit 0, result recorded | PCB-6 |
| Doc-sync | `<pcb-gate>` step `check_doc_sync` | no superseded term or stale geometry unless the line says rejected, superseded, replaced, formerly, no longer or withdrawn | PCB-3 |
| WARN ownership | review of the dated gate record | every WARN and numeric INFO has an owner | PCB-15 |
| Review ladder (each milestone) | review, see Playbooks; findings in `analysis/<date>_REVIEW.md` | verdict SHIP, every finding dispositioned | PCB-17 |
| Hold points | review; stop until the owner answers in chat | owner reply recorded | PCB-7, PCB-13 |
| Ledger counts | `<check_ledger>` (`CHECKS.md`) | exit 0, counts equal rows | PCB-L3 |

Hold points: board STEP with tracks to the owner before silkscreen; owner confirmation after their own review before manufacturing outputs; usability and accessibility walk (three framed cold reads: installer, service technician, firmware engineer) before the hand-over set; a first article of a few assembled plus bare boards before any batch.

## Tools

All tools take `--help` and exit 0 pass, 1 fail, 2 could not run; numbers come from the parameters file. Status of every tool: `exists in a prior controller PCB project, port on adoption` (not installable, not checkable with --version). Pass criterion per tool:
- check_manifest: every file in datasheets/ has a row and the sha256 matches.
- check_decisions: IDs sequential, fields present, table status equals section status, supersession target exists and is marked.
- check_requirements: IDs unique; every cited decision and question exists.
- check_parameters: every value in bounds with a source document.
- check_doc_sync: superseded-terms table (term, superseding decision, history words), hole coordinates, connector-wall edge, and dash typography; FAIL on a stale term.
- check_bom: construction policy (size, capacitor type, datasheet, grade).
- check_part_roles: each named MPN fitted (FAIL if absent, WARN if only the alternate); unlisted MPN is WARN.
- check_ratings, calc_trace_width: ratings against operating values with derating margin; copper width and temperature rise for a current.
- check_connectors: allocation, pin counts, keying, cross-plug and mis-mating hazards.
- check_contract, check_indicators, check_test_points: netlist from kicad-cli against the interface contract, LED routing, test-point names.
- check_layout, check_stitching: outline, holes, port axes, spacing, bottom-side classes; stitching pitch with worst gap and location; INFO until layout starts.
- check_version: `<letter>-draft` format, serial format, silkscreen rule.
- sim_power_budget, sim_sequencing, sim_holdup: rail budget by mode, staggered start-up current against the supply with margin, logic hold-up after input loss against fault-record time.
- sim_thermal, sim_thermal_gaps: junction temperature at maximum ambient, including parts with no thermal data (flagged).
- model_safety_chain: stop chain fault model: stop-OK required, start required, no automatic restart.
- board_from_netlist: board from the kicad-cli netlist; `--update` keeps placement; never routes or moves.
- export_docs: branded schematic and layout PDFs with a cover of git short hash and uncommitted flag; a unit test fails if the committed drawing sheet differs from the generated one.
- kb_build, kb_search: full-text index of datasheets and documents.
- diag: one command over USB prints a pass/fail table against limits plus the three most likely causes; includes a no-hardware simulator.
- route_session, pns_driver: guided routing session and scripted push-and-shove driver (needs per-run desktop consent).
- Layout process tools (`build`, specs in `LAYOUT_PROCESS.md`): check_routability, fanout, place_groups, quick_dru, pass_progress.

## Playbooks

- `LAYOUT_PROCESS.md`, `CHECKS.md`; docs/procedures/bughunt.md. This profile lists no defect patterns of its own; the ledger of `CHECKS.md` and the generic hunts of bughunt.md steps 2 and 3 apply.
- Review ladder at each milestone (parts list, schematic, layout, pre-order), in this order, none skipped: 1 full gate and WARN ownership; 2 cold read by a context-free agent given only the folder path; 3 design verifier; 4 safety analyst; 5 DFM checker (parts list and pre-order); 6 reviewer last with the prior reports, verdict SHIP or HOLD. Findings go unchanged into `analysis/<date>_REVIEW.md` (ID, severity, source, requirement, status). The ladder runs twice before hand-over: the second pass on the fixed design with cold readers that did not see the first.
- Bring-up: paper bring-up by a firmware cold read of the commissioning sheet before parts are ordered.
- Typical session: read the rules, decision table and open questions; log the decision; update the parameters file; add the datasheet and sourcing; change the design with ERC and DRC after each change; simulate and safety-analyse what changed; quick gate; at a milestone the ladder and full gate; advisor commits by pathspec; order only on instruction.
- Verifier commissioning lens, every item present or missing with the refdes: power-loss capture, stuck-bus recovery, fallback programming path, rework and isolation links, test-fixture provisions, sensor openings and coating keep-outs, mechanism feedback inputs, resource headroom. The firmware pin map is compared with the netlist and every mismatch listed.

## Agents and skills

| Role | Tier | Writes |
|---|---|---|
| doc writer | cheap | Markdown in the design folder |
| researcher, KiCad operator, simulation engineer | standard | research and datasheets; board files; tools and analysis |
| DFM checker | standard, read-only | none |
| safety analyst, verifier, reviewer | strong, read-only | none |

Skills: datasheet-keeper, decision-logger, design-review, part-sourcing, release-gate, safety-analysis, simulation (`exists in a prior controller PCB project` as a plugin, port on adoption).

## Parameters and records

- Decision record fields: date, status, decision, rationale, alternatives rejected, consequences, cross-links; requirement IDs are grouped by prefix (power, mechanical, environment, safety, manufacturing, compliance, traceability, usability).
- Document map: why = DECISIONS; what = REQUIREMENTS; how = ARCHITECTURE; unknown = OPEN_QUESTIONS; box limits = ENCLOSURE_CONSTRAINTS; sources = MANIFEST; numbers = parameters; reviews and gates = analysis/.

## Done means

- Gate full pass, review ladder verdict SHIP, holds answered, ledger counts current.
- Output set: branded schematic PDF, layout PDFs, colour STEP and GLB, Blender stills, product one-pager, system BOM separate from the PCB BOM, commissioning cheat sheet, wiring document stating each connector's viewing side, firmware handover pack.

## Lessons carried in

- A board generated with AI assistance carried package mismatches that a gate before order would have caught; run the full gate before any order.
- Automated routing stalled for many hours over several passes because placement left no escape room; fan out first (`LAYOUT_PROCESS.md`).
- A large share of logged issues had neither a test nor a plan; a ledger row before the fix closes that (`CHECKS.md`).

## Sources

Sources: distilled from four prior projects of the template owner (embedded
firmware, controller PCB, vibration data analysis, CAD add-in); project records
stay in those repositories.
