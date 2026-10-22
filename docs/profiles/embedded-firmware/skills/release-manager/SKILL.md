---
name: release-manager
description: Prepare, verify, tag, archive and publish a firmware release, and record what is installed on each machine. Use for firmware version changes, test-day or field handoff, release-readiness checks, or explicit publication; do not use for ordinary unapproved local edits.
---

# Firmware release manager

Specialises `docs/procedures/ship.md` for firmware (rules FW-14 to FW-16 in
`docs/profiles/embedded-firmware/PROFILE.md`). A release is not complete until
its annotated tag and its archived build both exist. No firmware is uploaded to
a machine from an untagged version, and never without explicit instruction.

Before the steps: confirm the intended changes, inspect `git status`, and pick
the version impact (major for workflow or hardware breaks, minor for features
or control behaviour, patch for compatible fixes, tuning, docs or tools).
Synchronise the variant's VERSION file, in-code version string, source header,
README release line and a dated `## vX.Y.Z (YYYY-MM-DD)` changelog heading.
Regenerate generated files such as a single-file simulator export; never
hand-edit them.

1. The gate passes: `<gate> --variant <variant>` (full mode). Inspect the diff
   and confirm no raw data bytes changed.
2. VERSION, changelog and in-code strings agree, and the tag checker
   (`docs/profiles/embedded-firmware/tools/check_release_tags.py`, wired by the
   project with its prefix, archive root and version file) reports the new
   version as "pending release: tag before upload" and nothing as FAIL.
3. Commit only the intended files, following the recorded git workflow.
4. Tag that commit: `git tag -a <variant>-vX.Y.Z -m "<variant> vX.Y.Z: <summary>"`.
   Annotated only; never move or delete an existing tag.
5. Archive from the clean tagged tree with the project's archive script. It
   refuses a dirty tree; never bypass that for a release. The build info must
   say the tree was clean and name the tag at HEAD. The archive holds the
   binary, SHA256SUMS and BUILD_INFO.
6. Commit the archive, then run the tag checker with `--require-current`; it
   must pass.
7. Push the branch and the tag only with user authority, never force. Verify
   that local HEAD, the remote branch and the tag point to the intended commits
   and that CI for that SHA is terminal-success (kernel rule 5).
8. When the image is installed, record machine, version, tag, commit, date and
   image size in the variant's `INSTALLED.md`. Rollback is upload of an
   archived binary, with no git archaeology (FW-15).

Exceptions to the tag or archive rule are explicit exact version pairs in the
checker's exceptions file with a reason, never patterns, and are added only for
versions that predate the scheme.

State flash and RAM use, tests run, and hardware checks not performed.
Compilation is not hardware validation; require the bench checklist before
loaded operation. Final handoff uses the ship procedure format.
