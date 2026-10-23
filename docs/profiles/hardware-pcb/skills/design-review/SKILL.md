---
name: design-review
description: Run the board review ladder at a PCB milestone (parts list, schematic, layout, pre-order) and record every finding unchanged with a disposition. Use at milestones only. Do not use for routine edits (release-gate --quick), single-part questions (component-selection), a control-box or BOM sign-off (box-design-review), or firmware work.
---

# PCB design review ladder

Purpose: independent, ordered review at each milestone, with the findings kept
in one record (PCB-17, PCB-15, PCB-6).

## When to use

Milestones only: parts list complete, schematic complete, layout complete,
before any order. The ladder runs twice before hand-over: the second pass on
the fixed design, with cold readers that did not see the first.

## Procedure

1. Name the milestone and the files under review. Confirm the working-tree
   state of the design folder is the one to be reviewed.
2. Gate: run the full gate `<pcb-gate>` (release-gate skill). Stop and fix if
   it fails; do not continue the ladder on a failing gate. List every WARN and
   every INFO that states a number against a limit; each needs an owner (an
   open question, a requirement, or a disposition in the review record). The
   doc-sync step must pass.
3. Cold read: delegate to a fresh agent with no conversation context, given
   only the design folder path and the question "assess this design's
   readiness for the next milestone and list what you would add or doubt".
   Its findings enter the record like any other rung. A review by an external
   tool or another model counts as a cold read and is filed the same way.
4. Delegate to `pcb-design-verifier`: end-to-end trace, logic levels, enables,
   commissioning lens, pin map against netlist.
5. Delegate to `pcb-safety-analyst` (safety-analysis skill): stop chain,
   reset states, fusing, clearances.
6. For the parts-list and pre-order milestones also delegate to
   `pcb-dfm-checker`.
7. Delegate to `pcb-reviewer` last, giving it every prior report. It returns
   `SHIP` or `HOLD`.
8. Collect every finding, unchanged, into `analysis/<YYYY-MM-DD>_REVIEW.md`
   through `pcb-doc-writer`: milestone, gate output, one table of findings
   (ID, severity, source, requirement or decision ID, status), verdict.
9. Disposition every finding, external ones included: accepted (with a new
   decision, an open question or a fix task), rejected with the technical
   reason, or already covered with the reference. Verify each against the
   files before acting on it: no performative agreement, no silent drop.
10. An escaped issue gets its ledger row before its fix (PCB-16,
    `docs/profiles/hardware-pcb/CHECKS.md`). Re-run from step 2 after fixes to
    any critical or high finding.

## Outputs

`analysis/<date>_REVIEW.md` with the gate result, findings, dispositions and
verdict.

## Never

- Skip a rung, or reorder so the reviewer sees no prior reports.
- Leave a gate WARN without an owner, or accept an external finding without
  checking it against the files.
- Soften or drop a finding; downgrade a severity without a recorded reason.
- Let the reviewer or the analysts edit design files.
- Treat `SHIP` as authority to order; ordering needs the user's instruction
  (PCB-7).
