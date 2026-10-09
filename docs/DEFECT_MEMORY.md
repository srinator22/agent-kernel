# Defect memory

Project memory of confirmed defects: what happened, why, and the check
that now prevents it. Rows describe this project's product and workflow,
so they are queryable memory, not resident rules. A fix without a row
here is not done (kernel rules 3 and 14). Update after every confirmed
defect and every corrected assumption; `docs/procedures/bughunt.md`
reads this table to choose hunts.

## ID scheme

- M-nnn module: logic inside one component
- I-nnn interface: between components, libraries, devices or formats
- U-nnn UI: what the operator or user sees and understands
- W-nnn workflow: build, CI, release, tooling, process

IDs are sequential per prefix and never reused. A superseded row stays and
gains "superseded by <ID>".

## Table format

| ID | Symptom and discovery route | Root cause | Permanent defence (the check) | Status |
|---|---|---|---|---|

- Symptom and discovery route: what was observed, and how it was found
  (pre-merge check, escaped past merge, human report, bughunt pass).
- Root cause: the mechanism at the owning layer, with exact numbers.
- Permanent defence: the named test, lint rule, assertion or script that
  fails if the defect returns. Prose alone is not a defence; if no check
  can express it, say so and link the retro entry.
- Status: open (row written, fix pending), fixed (fix and check landed,
  commit named), or accepted (risk kept, reason and owner stated).

## Rows

Replace the EXAMPLE rows with project rows; delete this sentence then.

| ID | Symptom and discovery route | Root cause | Permanent defence | Status |
|---|---|---|---|---|
| M-000 EXAMPLE | Export dropped the last record; found by a human reading the output | Loop bound used `< n - 1` | `test_export_includes_final_record` plus a property test on record counts | fixed (abc1234) |
| I-000 EXAMPLE | Run restarted after a power cycle and reused an old file; found by a fault sweep | Recovery matched on file name alone, not on session identity | Recovery requires the session id in the file header; `test_recovery_rejects_foreign_file` | fixed (def5678) |
| W-000 EXAMPLE | Release built locally but failed in a fresh clone; found at release review | An untracked local file was imported | Fresh-clone build step in `scripts/check.sh` | fixed (0123abc) |

## Review output record

Every review, hunt or audit ends with one record, kept in the report or
`.work/TASK.md`:

- Version and commit reviewed
- Files reviewed (paths, not "everything")
- Findings by severity P0 to P3, each numbered; confirmed defects apart
  from risks
- Exact fix, or the deferred evidence and its owner
- Tests run (command and result) and tests not run (with the reason)
- Build or gate result
- Remaining limits: what this review cannot see (hardware, field data,
  load, other platforms)
- Rows added or changed in this file
