# Backlog

Remaining work only. Done items move off at retro; discovered items enter
with a reason. Priorities P0-P3 per docs/procedures/audit.md.

| Item | Priority | Reason | Status |
| ---- | -------- | ------ | ------ |
| Reconcile docs/BLUEPRINT.md with post-build rounds recorded in BUILD_NOTES.md (Windows entries, Codex configs, self-test, session-context hook) | P3 | spec/reality drift | done 2026-10-09 (BLUEPRINT reconciled, tree-parity check) |
| Self-test: assert docs/procedures reference only existing docs/decisions files | P3 | generalizes the amendment-1 route-c defect (stale hardcoded ADR number) into a check per kernel rule 1 | done 2026-10-09 (check.sh ADR-reference step) |
| Profile skills for Claude and Codex: the skills each profile declares on its Skills: line, following the profile's procedures | P3 | profiles are pointer-only today; a skill makes selection discoverable in the harness | open |
| Run scripts/selftest.sh in a CI matrix that includes Windows | P2 | the self-tests are plain bash but only run on ubuntu CI; Windows is a supported entry (check.cmd) | open |
| template-sync real-run test against a published tag | P2 | tests/template/ covers fixtures; a real fetch and apply against a tag is unproven | open |
| Skills cap before start: with no Profiles line every profile's skills count (8 + 14 today); count only the software profile until start records the Profiles line | P3 | template mode is looser than any started project | open |
