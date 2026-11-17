---
name: verify
description: Boot, drive and inspect the real application to confirm a change works the way a user meets it, not only in tests. Use before ship on any change that alters what the app does, shows or returns, when asked to run or verify the app, or when tests pass but the behaviour is in doubt. Does not replace ./scripts/check.sh; it runs after it.
---

# Verify the running app

Rule SW-15 in `docs/profiles/software/PROFILE.md`; kernel rules 5 and 14.
Tests can pass while the feature is broken (a mocked boundary, a missing
asset, a route never registered). This skill looks at the real thing.

## Project wiring

Start fills these from the project's stack (docs/procedures/start.md step 4).
A `{{` left in an installed copy means start did not finish.

- Kind: {{VERIFY_KIND: cli, web, service, library, or the nearest real run}}
- Build: {{VERIFY_BUILD: the command that builds what ships, or "none"}}
- Boot: {{VERIFY_BOOT: the command that starts the app, run through scripts/bg.sh when it keeps running}}
- Ready when: {{VERIFY_READY: the signal awaited, such as a port answering, a log line or the process exit}}
- Drive: {{VERIFY_DRIVE: how the changed path is exercised, such as commands with fixture inputs, browser steps or requests}}
- Inspect: {{VERIFY_INSPECT: what is read and compared, such as stdout and exit code, a screenshot and console errors, status and body}}
- Stop: {{VERIFY_STOP: how the app is stopped and how no leftover process is confirmed}}

## Steps

1. Name the claim. From the acceptance criteria in `.work/TASK.md`, write the
   behaviour this run must show and what output would show it broken.
2. Build from the working tree being shipped, never a stale build. Note the
   commit (`git rev-parse --short HEAD`) and whether the tree is dirty.
3. Boot per the wiring and await the ready signal; never a fixed sleep
   (Standards). A boot failure is a FAIL, not a skip.
4. Drive the changed path, one unchanged neighbouring path, and one bad input
   (empty, malformed or missing).
5. Inspect what the app actually produced. Read the output; for a screen,
   take the screenshot and look at it. Compare against the claim from step 1,
   normalizing only differences that cannot matter (timestamps, temp paths),
   and name each one normalized.
6. Stop the app by PID or task id, and confirm nothing it started still runs.
7. Record one line in the `.work/TASK.md` Progress log:
   `verify: <date> <commit>[+dirty] <kind> drove <what> -> <observed> PASS|FAIL`,
   with the path of any kept output or screenshot under `.work/`.
   A FAIL means the change is not done: fix it through
   `docs/procedures/bugfix.md`, then run this skill again.

## Report

The claim, the commands run, what was observed (quoted, short), PASS or FAIL,
and anything not driven with the reason ("N/A - reason", kernel rule 14).

## Adapting at start

Start deletes this section from the installed copy after filling the wiring.

| Kind | Boot | Drive | Inspect |
|---|---|---|---|
| cli | none; each command is one run | the documented commands on fixture inputs | stdout, stderr, exit code and written files against expected |
| web | the dev or production server through scripts/bg.sh | a browser (the harness browser tool or a pinned browser test runner) through the changed flow | a screenshot read by the agent, the page state, zero console errors |
| service | the service and its local dependencies through scripts/bg.sh | requests against the changed endpoints | status, body and the service log for the request |
| library | none | a shipped example or documented snippet against the built package installed in a clean environment | the example's output against its documented result |

A desktop, mobile or embedded app uses the nearest real run (a simulator,
an emulator, a device under test). When no real run is possible on the
project's machines, start records "N/A - reason" in `START_REPORT.md` and
the wiring says so; the skill is still installed so the gap stays visible.
