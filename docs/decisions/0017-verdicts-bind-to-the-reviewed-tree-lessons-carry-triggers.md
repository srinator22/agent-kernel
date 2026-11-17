# 0017 - Review verdicts bind to the reviewed tree, and lessons carry diff triggers

Date: 2026-11-17
Status: accepted

## Context

A reviewer verdict said what was reviewed only in prose. Twice a verdict
rested on evidence older than the files it described: a template-updates
review failed on a verify output that predated the staged tree, and a GO
rested on a render older than a scene edit. Lesson L001 asked the reviewer
to compare modification times or a hash by hand, and named its own
retirement: "the gate record stores and compares input hashes". Separately,
the approved lessons were applied only when someone remembered to scan
`docs/lessons/INDEX.md`; nothing tied a lesson to the kind of change it is
about, so a reviewer could not tell which lessons a diff calls for.

## Decision

The verified tree is named and compared mechanically.

- `scripts/tree-id.sh` prints the git tree id of the working tree as it
  would be committed now: tracked files with their working-tree content,
  untracked files that are not ignored, deletions applied. It builds the
  tree in a temporary index seeded from a copy of the real one, so the real
  index is never written. `.work/` and `CHANGELOG.md` are left out: the task
  record holds the verdict itself, and the changelog is generated after the
  review (kernel rule 18).
- `scripts/check.sh` ends a clean run with `check.sh: verified tree <id>`,
  from an EXIT trap so both the template-mode and the project-mode exits
  print it. When the id cannot be computed the line reads `N/A - <reason>`
  and the run's result is unchanged.
- The reviewer copies the id into its verdict block as `Reviewed tree: <id>`
  and returns FAIL when the verify output has no tree line or an `N/A` one.
- `scripts/tasklint.sh ship` reads the Review verdict section. When its
  first line holds PASS, the first `Reviewed tree:` line must equal
  `scripts/tree-id.sh` now; a missing line, a different id or a failing
  tree-id.sh fails ship with the step to take. A FAIL or other first line
  (for example "Pending re-review") and a record under `.work/done/` are not
  compared. `check` never compares, since the tree moves during the work.
- docs/procedures/ship.md moves the version bump before verification, so the
  verified tree holds it.

Lessons carry an optional trigger, read from a diff.

- The INDEX.md line takes an optional last field inside the parenthesis:
  `, trigger: <token> <token>...`. A token is a bash glob over the
  repo-relative path (`*` crosses `/`), optionally prefixed `A:` (added; a
  rename or copy adds its new path), `M:` (modified) or `D:` (deleted).
  `scripts/lessons.sh check` validates the tokens; `use` and `expire` keep
  the field as it is.
- `scripts/lessons.sh match <diff file | git revisions>` prints one line per
  lesson whose trigger matches a changed path, in INDEX order, and a count on
  stderr. A diff file is read from its `diff --git` headers; otherwise the
  arguments go to `git diff --name-status -M` (only `--staged` and
  `--cached` among options).
- The advisor hands the match output to the reviewer with the verify output;
  the reviewer applies each named lesson and lists it in Evidence checked.
- Triggers are given only where a diff honestly shows the situation:
  L004, L005, L006, L007, L008, L011, L012, L013, L017, L018 and L019. A
  lesson about conduct (L001, L002, L003, L009, L014, L015, L016) carries
  none.

## Consequences

- A change made after a PASS review fails `tasklint.sh ship`, in the full
  local gate and in CI, until a new review records the new tree. The step is
  written into the failure message.
- The tree covers the whole working tree, so unrelated changes or untracked
  files left beside the commit make the CI tree differ from the reviewed one.
  ship.md step 1 already requires resolving them; now the gate shows it.
  Files a CI step creates before check.sh, if not ignored, would do the same.
- The verdict's first line must be the current verdict, as for the plan
  verdict. A record listing rounds oldest first with a FAIL on top escapes
  the comparison; that is a limit of the convention, not a check.
- Lesson L001's retire-when is met; it is marked `[met]`, and the next
  maintain pass archives it, since reviewer.md now carries its content.
- Content patterns (text inside a diff hunk) are not trigger tokens; a
  lesson that needs one stays without a trigger until a case shows the need.
- Upgrade note: a project mid-task whose Review verdict already reads PASS
  without a `Reviewed tree:` line fails `tasklint.sh ship` after the sync;
  re-run the review, or make "Pending re-review" the section's first line.
