# Documentation questions

The question set for `docs/procedures/doc-eval.md`: can a fresh agent that
starts from `AGENTS.md` find each answer by navigation, and does it decline
the questions the docs do not answer? `scripts/doc-eval.sh check` validates
this table (in the always section of `scripts/check.sh`); `scripts/doc-eval.sh
brief` prints the questions without the answer key for the answering agent.

Kinds: `answerable` rows carry the answer key and the files that state it;
`trap` rows are out of scope or rest on a false premise, so the correct answer
is to decline, and their sources cell is `-`. Keep at least 5 answerable and 3
trap rows. Ids and row order must not reveal the kind (the brief prints both),
so number every row q01, q02 and mix the traps in. When a project changes its
docs, it updates the key in the same change.

| id | kind | question | answer key | sources |
|---|---|---|---|---|
| q01 | answerable | When does a pushed change count as done? | Only when every required check for the exact pushed SHA has reached terminal success; queued or running is not success. | AGENTS.md, docs/procedures/ship.md |
| q02 | answerable | Where does a proposed lesson go, and who approves it? | docs/lessons/PENDING.md; pending entries are not acted on until a human moves the approved entry into docs/lessons/INDEX.md. | AGENTS.md, docs/procedures/retro.md |
| q03 | answerable | What may a worker agent never do with git? | Commit or push; scripts/worker-git-guard.sh blocks both through the worker's hook. | docs/rules/orchestration.md, .claude/agents/worker.md |
| q04 | trap | Which Kubernetes namespace does the template deploy to? | Decline: the template has no deploy target; start records one per project. | - |
| q05 | answerable | How many approved lessons may exist at once? | 20 (hard cap, kernel rule 10). | AGENTS.md |
| q06 | answerable | What happens to a flaky test? | It is a defect: quarantined in docs/lessons/QUARANTINE.md and fixed as its own task, never deleted or skipped. | AGENTS.md, docs/lessons/QUARANTINE.md |
| q07 | answerable | How is a new decision record created? | With scripts/adr.sh new and a title, following docs/procedures/adr.md; it writes the next numbered file in docs/decisions/. | docs/procedures/adr.md |
| q08 | trap | Which Slack channel receives CI failure alerts? | Decline: not covered by the docs. | - |
| q09 | answerable | What does the reviewer need before it can give a ship verdict? | The diff, .work/TASK.md and the complete, untruncated verify output of scripts/check.sh; without the verify output it returns FAIL. | .claude/agents/reviewer.md, docs/procedures/ship.md |
| q10 | answerable | How should work that outlasts a session be run? | As a checkpointed, resumable background process (scripts/bg.sh) with a gitignored STATE file in .work/jobs/, not as an agent loop. | AGENTS.md, docs/procedures/longjob.md |
| q11 | trap | Which ORM does the template require for database access? | Decline: the template is stack-agnostic and names no ORM. | - |
| q12 | answerable | Which gate is meant to run while working, before the full gate? | scripts/check.sh --quick, or scripts/quickgate.sh, which runs it (the same lane); the always section is never skipped. | scripts/quickgate.sh, README.md |
| q13 | answerable | What must a ticked acceptance criterion in .work/TASK.md carry? | An arrow to an existing path (a test or file) or to judgment with a reason; scripts/tasklint.sh check enforces it. | scripts/new-task.sh, scripts/tasklint.sh |
| q14 | answerable | How is a file removed from the repository? | It is moved to .archive/ with a one-line reason during a maintenance pass, never deleted and never mid-task. | AGENTS.md, docs/rules/destructive-actions.md |
| q15 | trap | What did the template's 2025 penetration test find? | Decline: false premise; no such test is recorded. | - |
