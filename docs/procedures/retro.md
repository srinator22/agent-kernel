# Retro - end-of-task learning capture

Run at the end of every non-quick task. Memory records only what external
signal confirmed (tests, CI, human reports); never what the repo already
tells you.

1. Classify each defect encountered during the task by discovery route:
   (a) caught pre-merge by checks, (b) escaped past merge, (c) reported by
   the human, (d) self-noticed and self-corrected.
2. Routes (a) and (d): record nothing; the system worked.
3. Routes (b) and (c): verify the failing-then-fixed regression test exists
   (kernel rule 3). If the cause cannot be expressed as any check, append
   one entry to `docs/lessons/PENDING.md` in the four-field format: what
   happened / what check should have caught it / what was added /
   retire-when.
3a. Traps that cost time: a CI-only gate, a command or environment trap,
   or a misleading tool message that cost the task time even though no
   defect escaped. Record each as one entry in `docs/lessons/PENDING.md`
   in the same four-field format. Prefer a check (kernel rule 1); when no
   check can express it, "what check should have caught it" may read
   "none, this note is the guard".
3b. Classify each lesson from steps 3, 3a and 4: product (what the product does;
   stays in `docs/lessons/PENDING.md`) or process (how work is run; goes to
   `docs/lessons/UPSTREAM.md` in the same four-field format plus
   `applies to: core` or `applies to: <profile>`).
4. Confirmed-good calls: if the human explicitly validated an approach worth
   repeating, that is a lesson too - same gate, same format, retire-when
   included.
4a. Durable decisions: a choice made during the task that a later session
   might re-debate (structure, tooling, data policy, method, scope) is
   not a lesson. Record it as an ADR in `docs/decisions/` per
   `docs/procedures/adr.md`, not in `docs/lessons/PENDING.md`.
5. Never record what the repo can already tell you (layout, conventions,
   history).
6. For each lesson consulted during the task run
   `scripts/lessons.sh use <Lnnn>`; it increments `used:` and updates
   `last:` in `docs/lessons/INDEX.md`.
7. Fill the Retro section of `.work/TASK.md`; update `BACKLOG.md` (done
   items off, discovered items on, with reasons); move TASK.md to
   `.work/done/YYYY-MM-DD-<slug>.md`; reset `.work/TASK.md` from the
   template (scripts/new-task.sh embeds it).
