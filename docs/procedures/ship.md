# Ship - the done-gate

Run when a logical change is ready to land. Nothing ships around this
procedure; a push is complete only when every required check for the exact
SHA is terminal-success (kernel rule 5).

1. Confirm scope: `git status`. Unrelated or untracked work is preserved and
   excluded; resolve every untracked file deliberately (stage it or ignore
   it, never leave it ambiguous).
2. Run `./scripts/check.sh` and keep its complete output (the verify
   output). Anything red: stop and fix first.
3. Reviewer gate: hand the reviewer agent the diff, `.work/TASK.md` and
   the verify output from step 2, complete and untruncated; never a
   summary of it. Without that output the reviewer returns FAIL. An
   independent review verdict, ending with its "Evidence checked" list, is
   present in `.work/TASK.md` (kernel rule 5). Quick-mode tasks may skip
   the reviewer only if the diff touches no logic (docs or config
   comments), and must say so explicitly.
4. Version: bump the single source-of-truth version file per semver (patch
   fix, minor feature, major breaking; pre-1.0 behavior per Project
   decisions).
5. Regenerate `CHANGELOG.md` via git-cliff. Never hand-edit it; the detail
   lives in commit bodies (kernel rule 18).
6. Conventional commit. The body carries why, and for fixes the exact
   issue, the fix, and the files and functions touched (kernel rule 6).
7. Push per the recorded workflow. Then run `scripts/ci-watch.sh` in the
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
