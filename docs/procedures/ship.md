# Ship - the done-gate

Run when a logical change is ready to land. Nothing ships around this
procedure; a push is complete only when every required check for the exact
SHA is terminal-success (kernel rule 5).

1. Confirm scope: `git status`. Unrelated or untracked work is preserved and
   excluded; resolve every untracked file deliberately (stage it or ignore
   it, never leave it ambiguous).
2. Version: bump the single source-of-truth version file per semver (patch
   fix, minor feature, major breaking; pre-1.0 behavior per Project
   decisions). It comes before verification so the verified tree holds it.
3. Run `./scripts/check.sh` and keep its complete output (the verify
   output). Anything red: stop and fix first. A clean run ends with
   `check.sh: verified tree <id>` (`scripts/tree-id.sh`: the whole working
   tree, untracked files included, except `.work/` and `CHANGELOG.md`), so
   step 1 must leave nothing in the tree that the commit will not carry.
   While working, `./scripts/check.sh --fast` runs the quick lane
   (`--quick`: no mutation or production build, no ship-readiness lint)
   with only the self-tests the changed files map to; it is not the full
   gate. A pull request that changes a gate file needs the `gate-change`
   label from the owner (ADR 0018); agents never add it.
   In the template repository the full suite runs on CI (local runs take
   20-60 minutes on Windows), so the log of the `check` job for the exact
   head, ending with its `check.sh: verified tree <id>` line, is an
   acceptable verify output there.
   3a. A project with a `verify` skill (SW-15, template ADR 0016) runs it
   for any change that alters what the app does, shows or returns, and
   records a `verify:` line in the `.work/TASK.md` Progress log before
   step 4.
4. Reviewer gate: hand the reviewer agent the diff, `.work/TASK.md`, the
   verify output from step 3, complete and untruncated (never a summary of
   it), and the output of `scripts/lessons.sh match <the diff file or git
   revisions>`, the lessons whose trigger the diff matches. Without the
   verify output, or without its tree line, the reviewer returns FAIL. An
   independent review verdict, its first line the current verdict, holding
   `Reviewed tree: <id>` and ending with its "Evidence checked" list, is
   present in `.work/TASK.md` (kernel rule 5). `scripts/tasklint.sh ship`
   fails a PASS verdict whose tree differs from the current one: any change
   after the review needs a new one (make "Pending re-review" the first
   line of the section, run step 3 again, record the new verdict first).
   Quick-mode tasks may skip the reviewer only if the diff touches no logic
   (docs or config comments), and must say so explicitly. Once the verdict is
   recorded, `scripts/tasklint.sh final` must pass: it is `ship` plus a
   required PASS verdict, waived only for `Mode: quick`.
5. Regenerate `CHANGELOG.md` via git-cliff. Never hand-edit it; the detail
   lives in commit bodies (kernel rule 18).
6. Conventional commit. The body carries why, and for fixes the exact
   issue, the fix, and the files and functions touched (kernel rule 6).
7. Push per the recorded workflow (scripts/push-scan.sh refuses a push while
   `scripts/private-terms.sh check` fails). Then run `scripts/ci-watch.sh` in the
   foreground - delegate to the monitor agent when available. It prints the
   workflows the commit can trigger and waits for each; exit 3 means it
   timed out with checks still running, so run it again. When one push
   carried several commits, pass `--base <remote SHA before the push>`
   (for the first push of a new branch, the merge-base with the default
   branch) so the derivation sees every pushed file, as GitHub's path
   filters do. A push is complete only when every required check for the
   exact SHA is terminal-success. On failure: inspect logs, fix the root
   cause, verify locally, push the replacement, monitor the replacement
   SHA.
8. Release, when a coherent wave ships: move the version, create the
   annotated tag `vX.Y.Z`, push the tag, AND create the platform Release
   object (`gh release create`) with user-facing plain-language notes
   curated from the changelog. A tag alone does not appear in the Releases
   panel. Template-repo releases (before start runs) use annotated
   `template-vX.Y.Z` tags; per-project releases after start use `vX.Y.Z`.
9. Final handoff format: Outcome / Evidence (commands and terminal results)
   / Artifacts (commit, release, deployment) / Limitations / Next action
   only if required.

When checks are slow or costly, see `docs/procedures/ci-cost.md` before
changing a gate.
