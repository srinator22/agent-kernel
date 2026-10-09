# Bughunt - proactive bug hunting

A scheduled or milestone pass that looks for defects nobody has reported.
Distinct from `docs/procedures/bugfix.md`, which reacts to one known
defect. Run at milestones, before first real use, and monthly on any
project with field or hardware exposure. Fixes use bugfix.md.

1. Choose the hunt from the profile checklist: each
   `docs/profiles/<profile>/PROFILE.md` lists the recurring defect
   patterns for that kind of project. Add rows from `docs/DEFECT_MEMORY.md`
   (what already bit this project). Write the chosen concerns into
   `.work/TASK.md` before starting.
2. Ten-pass review. One pass per concern, each by a reader with fresh
   context (parallel workers, disjoint concerns, kernel rule 16):
   1. timing and blocking paths   2. state and latches
   3. inputs at edges             4. error paths and reason codes
   5. resource exhaustion         6. concurrency and ordering
   7. units and precision         8. boundaries and adapters
   9. configuration and defaults  10. documentation versus behaviour
   Each pass traces actual events and values, not function names, and
   ends with a list of findings or "none, covered: <what was read>".
3. Mechanical hunts, the ones a reader cannot match:
   - fuzzing and fault sweeps: inject a fault at every step of a run,
     not at one convenient moment
   - property-based tests for invariants (round trips, ordering, bounds)
   - differential tests against a reference implementation or the
     previous version, on the same inputs
   - `git bisect` on any reproduced regression, to the exact commit
   - fresh-clone build and test, to expose untracked local state
   - mutation testing on changed files; a surviving mutant is a missing
     assertion
4. Cold read. A context-free agent reads the artefact as a newcomer and
   lists what they would doubt, add or refuse, with `file:line`. Every
   item is dispositioned: accepted (with a decision or BACKLOG task),
   rejected (with the reason), or already covered (with the pointer).
   No item is left unanswered.
5. Inspect one concrete failing item before accepting any summary
   verdict such as "placement-limited", "flaky" or "environmental".
   Reproduce the single case and read its actual output; a verdict that
   cannot be tied to one inspected item is a hypothesis (kernel rule 14).
6. Record. Every confirmed defect gets a row in `docs/DEFECT_MEMORY.md`
   before its fix, and a regression test with the fix (kernel rule 3).
   Add a retro entry (`docs/procedures/retro.md`) only if no check can
   express the lesson.
7. Output format. Findings are numbered and carry severity P0 to P3
   (scale in `docs/procedures/audit.md`). Confirmed defects (evidence,
   impact, reproduction, owning layer) are listed apart from risks and
   ideas. Evidence is quoted, never paraphrased. Close with the review
   record from `docs/DEFECT_MEMORY.md`: version, files, tests run and not
   run, remaining limits.
