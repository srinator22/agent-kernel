---
name: bug-review
description: Full firmware review covering safety, timing, state machines, feedback, storage, control and documentation. Use for full bug reviews, final pre-test checks, regression audits, or an escaped defect; do not use for an ordinary focused code change.
---

# Firmware bug review

Specialises `docs/procedures/bughunt.md` for the embedded-firmware profile.
Rule IDs are in `docs/profiles/embedded-firmware/PROFILE.md`.

1. Read AGENTS.md, the variant's open investigations file, `docs/DEFECT_MEMORY.md`
   and the bughunt procedure completely. Write the chosen concerns into
   `.work/TASK.md`.
2. Read every maintained firmware tab completely before judging sequence,
   timing, pins, outputs or control. Run the quick gate before any edit and
   keep its output as the baseline.
3. Apply the review passes in order, one concern per pass, each traced on
   physical events rather than helper names:
   1. settings, version, mode, target and timings (FW-12)
   2. pin map against the BOM; polarity; startup latch levels (FW-17, FW-18)
   3. every state entry, transition, completion and re-entry
   4. stop, storage, feedback and other fault exits to safe idle (FW-20, FW-22)
   5. physical event order: every actuator, valve, motor and heater (FW-19)
   6. feedback freshness, arithmetic width, rollover, stale timeout
   7. control eligibility, bounds, reversal, carry-over
   8. storage naming, exclusive create, buffering, sync, close, recovery (FW-21)
   9. test-mode isolation and continuously commanded safety outputs
   10. build, warnings, logs, docs, version, fresh-clone build
4. Run the profile's recurring defect checklist (timestamp before a blocking
   call, button classified at the press edge, button held at boot, latched
   flag never cleared, startup applied before debounce, unreachable enum
   states, fault without reason code, asymmetric error tolerance, unguarded
   stream writes, file identity by name only). Each hit needs a trace test.
5. Review every mode, unit combination, first and later cycle, button timing,
   blocking return, timer assignment, fault exit and safe-idle output. Check
   logging capacity, overflow, sync, close and partial-run evidence.
6. Mechanical hunts a reader cannot match: execute the real firmware on the
   host simulator (FW-1), place each fault at every step of a run (FW-8), and
   build a fresh clone to expose untracked local state.
7. Separate confirmed defects from hardware questions and untested behaviour.
   A static review is never field validation.
8. Add a DEFECT_MEMORY row before each fix. Fix confirmed in-scope defects
   only, each with a regression that fails on the previous version (FW-7).
   When two lines share the code, fix both or record why not (FW-13).
9. Update open investigations, run the full gate, and add the simulator
   limits found to the bench list (FW-11).

Report: severity P0 to P3, evidence quoted, root cause, fix, regression
defence, checks run and not run, hardware not proven. Independent review
verdicts go to `.work/TASK.md`; fixes follow `docs/procedures/bugfix.md`.
