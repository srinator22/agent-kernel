---
name: memory-keeper
description: Record durable project knowledge after a confirmed defect, field observation, corrected assumption, regression defence or resolved investigation. Use as a secondary step only after new evidence changes future coding or reviews; do not use at the start of routine work.
---

# Memory keeper

Applies kernel rules 3, 8 and 9 to firmware evidence. Memory exists to change
future behaviour; trivia that creates no review, test or decision consequence
is not recorded.

1. Read AGENTS.md, the variant's open investigations file and
   `docs/DEFECT_MEMORY.md`.
2. Classify the evidence:
   - unconfirmed field behaviour: an open investigation entry
   - confirmed defect: a `docs/DEFECT_MEMORY.md` row (M, I, U or W prefix)
   - fixed project fact or choice: the Project decisions section of AGENTS.md,
     a `docs/decisions/` record, or the canonical domain document
   - a lesson no check can express: a proposal in `docs/lessons/PENDING.md`
     (what happened, what check should have caught it, what was added,
     retire-when); a human approves it into INDEX.md
3. For a confirmed defect record symptom and discovery route, root cause with
   exact numbers, fix, and the named permanent check (test, lint rule or
   assertion). Prose alone is not a defence. The row is written before the fix.
4. For field evidence record the exact file, firmware version, configuration,
   cycle and measurement, and where the raw file lives (see data-analysis
   rules DA-3, DA-8).
5. Link to canonical evidence; do not repeat long explanations. Update or
   close an existing entry instead of creating a duplicate.
6. Keep open decisions visible. Never turn a guess into a project fact;
   label unconfirmed items as hypotheses (kernel rule 14).
7. Keep documents concise and scan-first, plain hyphens only.
8. Run the repository check after the change and report the rows touched.

Common firmware defect shapes to look for when classifying: a model passed
while a library behaviour failed (FW-1, FW-3); a fix landed in one of two
shared lines (FW-13); a tunable setting with no range trained the gate to be
ignored (FW-12). Each belongs as a row with its guard, not as prose.
