---
name: box-design-review
description: Senior electrical engineering review of a control-box or system design (power architecture, wiring guide, enclosure layout, how boards integrate into the box) or of a BOM, before the design is finalised or the owner buys anything. Use when such a design is about to be called final and for every BOM or purchase list handed to the owner. Do not use for single-part questions (component-selection), the board milestone ladder (design-review) or firmware logic.
---

# Box design and pre-purchase review

No control-box design is called final, and no BOM is handed to the owner to
buy, without this review's verdict recorded. It exists because a fast-acting
fuse in front of a large bulk capacitor reached the owner as a purchase
without anyone attacking the whole branch, and blew at the first cold
power-up. Rules: PCB-7, PCB-10, PCB-17.

1. Name the scope: the design, its documents and their commit, the BOM or
   purchase list, and the decision the owner is about to make.
2. For every part chosen or changed since the last review, confirm the
   component-selection skill was applied; if not, apply it first.
3. Write one branch file per fused power branch in a scratch directory and run
   the power-branch calculator (`check_power_branch --strict`) on each; a
   branch it could not run on is a finding, with the arithmetic shown by
   hand meanwhile.
4. Run the project's wiring check (`<wiring-check>`, if one exists) against
   the wiring guide.
5. Dispatch the review: the `senior-ee-reviewer` agent with the scope, the
   calculator output and the BOM. For a single changed part also dispatch
   `component-reviewer`; the two run in parallel. Where agents are
   unavailable, perform the senior-ee-reviewer's ten passes yourself as a
   hostile reviewer of your own draft, and say so.
6. Check every reviewer claim that would change the decision against its
   cited source before relaying it. Do not relay a finding you have not
   checked, and do not drop one because it is inconvenient.
7. Record the review as `analysis/<YYYY-MM-DD>_EE_REVIEW_<topic>.md` through
   `pcb-doc-writer`: verdict, scope, findings with dispositions (fixed,
   accepted with the reason, or open as an open-question ID), BOM line table,
   calculator output. An escaped issue gets its ledger row (PCB-16).
8. Give the owner the verdict first, then blocking findings, then the options
   for each with cost. A HOLD means nothing is bought until it is cleared; say
   which lines are safe to buy now, if any.

The owner decides and buys. This review never orders, adds to a cart or
contacts a supplier.
