# Lessons index

One approved lesson per line. Scan this file before non-trivial work and
open only matching entries; increment `used:` and update `last:` for each
lesson consulted (kernel rule 8). Hard cap: 20 approved lessons (kernel
rule 10); the maintain procedure archives on evidence - unused > 45 days
or retire-when met.

Format:

- [L001] <one-line, situation-triggered description> - <the lesson, one
  or two lines> (used: 0, last: -, retire-when: <condition>)

- [L001] Reviewing a change for a verdict - the reviewer receives the diff, `.work/TASK.md` and the verify output, and returns FAIL when that output is missing, truncated or not clean at every stage; the verdict ends with "Evidence checked"; the evidence must be newer than the files it describes (compare modification times or a hash), else NO-GO (used: 6, last: 2026-11-09, retire-when: recording a verdict in `.work/TASK.md` is impossible without an attached check log, or the gate record stores and compares input hashes (BACKLOG row))
- [L002] Reviewing a change that obeys its brief - also check the diff against the AGENTS.md rules index and the adopted profiles' rules (used: 4, last: 2026-11-09, retire-when: every promoted rule has a mechanical gate in `scripts/check.sh`)
- [L003] A worker reports its result - files touched, each check's command with its verbatim result ("could not run" said as such), conflicts; no version bump unless the brief says so (used: 4, last: 2026-11-07, retire-when: the advisor re-runs every worker check itself as a standing step)
- [L004] Blocking worker commits with a hook - match every shell the harness offers (`Bash|PowerShell`, VERIFY 2026-10-23) and keep the logic in `scripts/worker-git-guard.sh`, tested per shell (used: 1, last: 2026-10-29, retire-when: the harness enforces a per-agent deny list natively)
- [L005] Watching CI after a push - the monitor stays in the foreground at the maximum timeout, re-runs on timeout, prints both SHAs on a mismatch and the failing log tail verbatim (used: 5, last: 2026-11-09, retire-when: the harness resumes an agent when a background task exits)
- [L006] Waiting on CI for a commit - expect only the workflows the changed files and path filters can trigger, print them, fall back to "expect all" and say so; `scripts/ci-watch.sh --expect` overrides (used: 5, last: 2026-11-09, retire-when: the project has no path-filtered required workflows)
- [L007] Delegating a lookup to explore - return conclusions, quote a few lines at most, skip vendored, build and dependency folders unless asked (used: 2, last: 2026-11-07, retire-when: the harness truncates subagent output by size)
- [L008] Running the retro - record traps that cost time even with no escaped defect (the check may read "none, this note is the guard") and route durable decisions to `docs/decisions/` (used: 2, last: 2026-11-08, retire-when: each such trap has a mechanical check or the environment changes)
- [L009] Fixing any bug - show the new regression test failing for the stated root cause (file, function, condition) before the patch, with the repro command and output recorded (used: 5, last: 2026-11-09, retire-when: tooling enforces fail-first, for example mutation checks)
- [L010] Recording a decision - follow `docs/procedures/adr.md`; numbering and format drift between projects without it (used: 2, last: 2026-11-08, retire-when: `scripts/` generates and lints ADRs [met] 2026-10-23 by `scripts/adr.sh`)
- [L011] Faking an external CLI in a test - back each faked command with one recorded real response or refusal named in the test header (used: 0, last: -, retire-when: test doubles are generated from recorded real responses)
- [L012] Writing criteria for a text-matching guard - list the forms to refuse and the forms to allow; forms outside the list are limits, not defects (used: 0, last: -, retire-when: two more guard tasks pass review in one round with a form list)
- [L013] Finishing a library procedure that drives an external program - run it end to end on that program once and record every gate; unit tests alone missed a dozen defects (used: 0, last: -, retire-when: a profile rule requires a recorded end-to-end example per such procedure)
- [L014] Taking an outward action (merge, release, publish, rename or change visibility, upload, commit to a connected app) - the auto-mode check refuses unless the owner asked for that action in words or granted it in settings; name the action, ask for it, and continue other work meanwhile (used: 4, last: 2026-11-09, retire-when: Project decisions records a standing override for merging green, reviewed PRs)
- [L015] Running a shell command whose text contains a refused form (test strings, commit bodies, heredocs) - write the text to a file with the file tool and run by path; commit with git commit -F; for real deletes pass the literal absolute path, not a variable (used: 2, last: 2026-11-09, retire-when: the harness passes hook payloads that separate data from the command, or the guard parses heredoc bodies as data)
- [L016] Stopping work - stop by PID or task id, never by image name; after a stop confirm no child still writes to the log; start stopped work one at a time (used: 1, last: 2026-11-09, retire-when: the guard refuses kill-by-name with a test and a harness stop ends the whole process tree)
- [L017] Adding an ADR on a branch while others run in parallel - fetch main and number it after main's last ADR before merging (used: 0, last: -, retire-when: adr.sh check compares new numbers with origin/main)
