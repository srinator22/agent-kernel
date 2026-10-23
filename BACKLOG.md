# Backlog

Remaining work only. Done items move off at retro; discovered items enter
with a reason. Priorities P0-P3 per docs/procedures/audit.md.

| Item | Priority | Reason | Status |
| ---- | -------- | ------ | ------ |
| Reconcile docs/BLUEPRINT.md with post-build rounds recorded in BUILD_NOTES.md (Windows entries, Codex configs, self-test, session-context hook) | P3 | spec/reality drift | done 2026-10-09 (BLUEPRINT reconciled, tree-parity check) |
| Self-test: assert docs/procedures reference only existing docs/decisions files | P3 | generalizes the amendment-1 route-c defect (stale hardcoded ADR number) into a check per kernel rule 1 | done 2026-10-09 (check.sh ADR-reference step) |
| Profile skills for Claude and Codex: the skills each profile declares on its Skills: line, following the profile's procedures | P3 | profiles are pointer-only today; a skill makes selection discoverable in the harness | done 2026-10-23 (profiles ship agents, skills and tools; ADR 0004) |
| Run scripts/selftest.sh in a CI matrix that includes Windows | P2 | the self-tests are plain bash but only run on ubuntu CI; Windows is a supported entry (check.cmd) | open |
| template-sync real-run test against a published tag | P2 | tests/template/ covers fixtures; a real fetch and apply against a tag is unproven | open |
| Skills cap before start: with no Profiles line every profile's skills count (8 + 21 today); count only the software profile until start records the Profiles line | P3 | template mode is looser than any started project | open |
| Test the shipped-set early-stop marker in scripts/lessons.sh (a forced early return must be reported) | P3 | review note 2026-10-23: the marker has no test, so a regression in it would pass silently | open |
| Port a generic import skeleton (copy with exclusive create, hash verify, session README row) into the data-analysis profile tools | P3 | the profile lists the import tool as port on adoption; about 60 percent of a prior tool is generic | open |
| Archive docs/library/skills/adr once the core adr procedure lands (maintenance pass, kernel rule 11) | P3 | the library copy duplicates the core skill after graduation | open |
| Library light-worker: replace its inline Bash-only commit hook with scripts/worker-git-guard.sh under matcher Bash\|PowerShell | P3 | lesson L004 was applied to the core worker only; an adopted light-worker keeps the PowerShell gap | open |
| Move the cited-ADR existence check (check.sh step 5h, template mode only) into scripts/adr.sh check so it runs after start | P3 | review 6 note: after start no gate verifies that a cited ADR exists | open |
| ci-watch.sh: parse an on: list that starts at column 0 (on:\n- push) | P3 | review 5 note: it reads as no push trigger; the grace window and open-run check are the only guards | open |
