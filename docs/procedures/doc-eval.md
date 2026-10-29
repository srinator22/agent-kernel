# Doc eval - can a fresh agent find the answers, and decline the rest?

The docs are an index an agent navigates, not a pile it loads. This procedure
tests that layout the way it is used: a context-free agent answers a fixed
question set by navigation, and an independent judge scores the answers
against a key. Trap questions (out of scope or a false premise) must be
declined; a docs set that answers them invites confident fabrication.

Run during each maintenance pass (`docs/procedures/maintain.md`) and after a
change that moves docs or edits the AGENTS.md rules index or a procedure's
pointers.

1. `scripts/doc-eval.sh check` is green: the table in
   `tests/docs/questions.md` is well formed and every source path exists.
2. Run `scripts/doc-eval.sh brief` and give its output, verbatim and alone,
   to a fresh `explore` agent (cheap tier on purpose: the docs should work for
   the weakest navigator). It never receives `tests/docs/questions.md`, the
   key, or this conversation.
3. Judge: give a fresh `reviewer` the answers and `tests/docs/questions.md`.
   Per question it returns one word and a reason: answerable rows CORRECT
   (agrees with the key, cites a file that states it), WRONG, or MISSED (a
   decline); trap rows DECLINED or FABRICATED. An answer that cites
   `tests/docs/` is LEAKED and scores as WRONG.
4. Pass bar: every trap DECLINED, and at least 90 percent of answerable rows
   CORRECT. Record the counts and the date where the run was asked for (the
   maintenance summary or the task's Progress log).
5. For each WRONG, MISSED or FABRICATED row, fix the cause at the owning
   layer: a missing rules-index line, a procedure that does not point to its
   detail, an ambiguous sentence, or a stale key (fix the key in the same
   change). Do not add the answer to the doc only to pass the question.
   Re-run steps 2 and 3 on the fixed docs with fresh agents.
6. Grow the set when a real question went unanswered in a session: add it as
   a row (and a trap when an agent fabricated). Keep ids and order neutral.
