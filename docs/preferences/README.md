# Preference registers

A register is a table of the owner's lasting preferences for one area of work. Each rule says where it came from and how it is guarded. Areas are free names: `film`, `ui`, `docs`, `code`, `communication`, `process`. One file per area: `docs/preferences/<area>.md`.

This README belongs to the template. Projects add their own area files next to it and never edit it. The template ships no rows; in template mode (before start has run) any other file in this folder fails the check.

## Rules table

A rules table starts with this header. The `Repeats` column is optional.

```
| ID | Rule | Source | Check | Repeats |
|---|---|---|---|---|
| UI-001 | Labels stay under three words. | 2026-11-08: "keep labels short" | Review | |
| UI-002 | Buttons use the brand colour. | 2026-11: "brand colour everywhere" | `test_brand.py::test_buttons` | 2 |
```

- **ID:** unique within the file.
- **Rule:** one plain sentence.
- **Source:** a date (`YYYY-MM` or `YYYY-MM-DD`) and the owner's own words in quotes. Inferred rules say so.
- **Check:** `Review`, optionally followed by a note, or one or more backticked references.
- **Repeats:** empty or a whole number. It changes only through an approved dream proposal.

A row copied from another project by `scripts/preferences.sh port` has the Source `YYYY-MM-DD: ported from <folder> (<original source>)` and the Check `Review (was <original check> in <folder>)`, or plain `Review` when the original was Review. Its Repeats is empty.

## Check grammar

A reference is backticked. Its first word is a path, relative to the repository root, or a file name that `git ls-files` finds exactly once. `path::name` also requires `name` to appear in that file. Any further words are arguments and are not checked. Several references may share a cell.

```
`scripts/render.sh check --all`
`test_brand.py::test_buttons`
`tests/test_a.py` and `tests/test_b.py::test_c`
```

## The ladder

A rule starts as `Review`: a reviewer looks for it. When feedback repeats a rule, the dream proposes moving it to a named check, a test or a script step that fails when the rule is broken. The move goes through a BACKLOG row or a test, and the `Repeats` count records how often the rule was repeated.

## Baselines

An approved deliverable is recorded as the baseline for its kind, and a new variant starts from it. A baselines table follows the rules table:

```
| Kind | Reference | Owns | Check |
|---|---|---|---|
| landing page | `docs/design/landing.md` 2026-11-08 | layout, palette | Review |
```

- **Reference:** an existing path or a commit that git resolves, plus a date.
- **Owns:** what a variant reuses without asking again.

## What the check does

`scripts/preferences.sh check` reads every table with these headers, skips fenced code blocks, and names the file, line and problem for each failure: a missing date, an empty rule, an unknown path, a missing `::name`, a non-integer `Repeats`, a duplicate ID, an unresolved baseline reference. `./scripts/check.sh` runs it.
