# b18 unattended record

## Goal
Optional TASK.md field `Unattended: yes - <pre-approved actions>; report: <path>`, validated by tasklint, printed by session-context, scaffolded as a comment by new-task.sh, plus a stall rule in longjob.md.

## Acceptance criteria
- Parser/validation: tests/template/test_tasklint.sh (Unattended block).
- session-context line: tests/template/test_session_context.sh.
- new-task output: tests/template/test_new_task.sh.
- Stall rule: docs/procedures/longjob.md item 5 (20 minutes default).

## Decisions
- `Unattended: no` accepted as explicitly off; absent is fine.
- Refusal regex is conservative: any action text containing delet, force-push, --force, kernel, AGENTS.md or CLAUDE.md is refused, even when negated.
- new-task.sh writes the field as an HTML comment (stripped by tasklint, ignored by session-context) so a fresh scaffold stays valid.

## Progress log
- Implemented and ran the three touched test files.

## Open risks
- Negated phrasings ("never delete") are refused too; owners must word the actions positively.
