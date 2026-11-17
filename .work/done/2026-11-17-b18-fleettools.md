# b18 fleettools (G6)

## Goal
Close two rating rows: scripts/fleet-status.sh (fleet template versions) and scripts/rating.sh (numbers behind a rating, plus merged-PR cycle time added by the advisor).

## Acceptance criteria and evidence
- fleet-status lists path, ref, last sync date, releases behind, dirty count, missing, old url: tests/template/test_fleet_status.sh (37 cases, PASS).
- Read-only, offline, exit 0 when lagging, 1 on usage/list errors: same test (no-files-created, exit codes).
- rating.sh prints backlog by priority, lessons, skills, maintain date, tag, CI, cycle time, fleet; N/A with reason: tests/template/test_rating.sh (PASS), gh faked from recorded real responses.
- Real run of fleet-status.sh against the main checkout list: in the report.

## Decisions
- List resolution matches scripts/dream/fleet.py (root list, else main checkout via git-common-dir); fleet.sh itself only takes --list or the root list, and has no reusable function, so the logic is matched not sourced.
- Lessons and skills numbers come from scripts/lessons.sh stats (one definition of the cap).
- "Behind" counts template-v* tags (version sort), not synced-set commits (that is fleet.sh).
- Epoch maths in pure bash (macOS date has no -d).
- Exit 1 for fleet-status errors (brief), whereas fleet.sh uses 2.
- Last maintain pass = newest date-prefixed line of MAINTENANCE.log that is not a template-sync record; the template repo has no log, so N/A there.

## Progress log
- Found and fixed while building: GNU sed keeps a missing final newline, so the last merged PR was dropped; the read loop now accepts an unterminated last line (covered: fixture gh output has no trailing newline, n=3 asserted).

## Open risks
- Tests not run on Linux/macOS; Windows only.
- TCG_Researcher and VTOL show as missing: their Template line has a prose tail, so not exactly two tokens (fleet.sh calls that BAD-LINE).

## Advisor correction: state terms
- State is now ok | missing (folder or AGENTS.md absent) | no-template-line | bad-line (token count other than two; url and the readable ref still shown, behind computed from the ref). Fail-first run recorded in the report (8 failures on the old code), then PASS.
- A sha with no tag in its history uses the tags containing its merge-base with HEAD; a sha with no common history with HEAD stays "unknown".
- Real run: VTOL ref 90cf73a is on a history with a different root commit (git merge-base 90cf73a HEAD exits 1), so behind is "unknown" rather than guessed.
