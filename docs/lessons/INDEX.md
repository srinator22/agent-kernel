# Lessons index

One approved lesson per line. Scan this file before non-trivial work and
open only matching entries; increment `used:` and update `last:` for each
lesson consulted (kernel rule 8). Hard cap: 20 approved lessons (kernel
rule 10); the maintain procedure archives on evidence - unused > 45 days
or retire-when met.

Format:

- [L001] <one-line, situation-triggered description> - <the lesson, one
  or two lines> (used: 0, last: -, retire-when: <condition>)

- [L001] Reviewing a change for a verdict - the reviewer receives the diff, `.work/TASK.md` and the verify output, and returns FAIL when that output is missing, truncated or not clean at every stage; the verdict ends with "Evidence checked" (used: 1, last: 2026-10-29, retire-when: recording a verdict in `.work/TASK.md` is impossible without an attached check log)
- [L002] Reviewing a change that obeys its brief - also check the diff against the AGENTS.md rules index and the adopted profiles' rules (used: 0, last: 2026-10-23, retire-when: every promoted rule has a mechanical gate in `scripts/check.sh`)
- [L003] A worker reports its result - files touched, each check's command with its verbatim result ("could not run" said as such), conflicts; no version bump unless the brief says so (used: 1, last: 2026-10-29, retire-when: the advisor re-runs every worker check itself as a standing step)
- [L004] Blocking worker commits with a hook - match every shell the harness offers (`Bash|PowerShell`, VERIFY 2026-10-23) and keep the logic in `scripts/worker-git-guard.sh`, tested per shell (used: 1, last: 2026-10-29, retire-when: the harness enforces a per-agent deny list natively)
- [L005] Watching CI after a push - the monitor stays in the foreground at the maximum timeout, re-runs on timeout, prints both SHAs on a mismatch and the failing log tail verbatim (used: 0, last: 2026-10-23, retire-when: the harness resumes an agent when a background task exits)
- [L006] Waiting on CI for a commit - expect only the workflows the changed files and path filters can trigger, print them, fall back to "expect all" and say so; `scripts/ci-watch.sh --expect` overrides (used: 0, last: 2026-10-23, retire-when: the project has no path-filtered required workflows)
- [L007] Delegating a lookup to explore - return conclusions, quote a few lines at most, skip vendored, build and dependency folders unless asked (used: 1, last: 2026-10-29, retire-when: the harness truncates subagent output by size)
- [L008] Running the retro - record traps that cost time even with no escaped defect (the check may read "none, this note is the guard") and route durable decisions to `docs/decisions/` (used: 0, last: 2026-10-23, retire-when: each such trap has a mechanical check or the environment changes)
- [L009] Fixing any bug - show the new regression test failing for the stated root cause (file, function, condition) before the patch, with the repro command and output recorded (used: 0, last: 2026-10-23, retire-when: tooling enforces fail-first, for example mutation checks)
- [L010] Recording a decision - follow `docs/procedures/adr.md`; numbering and format drift between projects without it (used: 0, last: 2026-10-23, retire-when: `scripts/` generates and lints ADRs [met] 2026-10-23 by `scripts/adr.sh`)
