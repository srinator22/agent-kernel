# Lessons index

One approved lesson per line. Scan this file before non-trivial work and
open only matching entries; increment `used:` and update `last:` for each
lesson consulted (kernel rule 8). Hard cap: 20 approved lessons (kernel
rule 10); the maintain procedure archives on evidence - unused > 45 days
or retire-when met.

Format:

- [L001] <one-line, situation-triggered description> - <the lesson, one
  or two lines> (used: 0, last: -, approved: YYYY-MM-DD, retire-when: <condition>,
  trigger: <globs>)

`approved:` is the date the owner approved the lesson (required, right after
`last:`). `scripts/lessons.sh check` fails a lesson with `used: 0` more than
45 days after that date: archive it in a maintain pass or record a use.

The trigger field is optional and comes last: space-separated path globs a
diff can show (`*` also crosses `/`), each optionally prefixed `A:` (added),
`M:` (modified) or `D:` (deleted). `scripts/lessons.sh match <diff file or git
revisions>` prints the lessons whose trigger matches a changed path, and the
reviewer applies them (ADR 0017). A lesson no diff can reveal carries none.

- [L011] Faking an external CLI in a test - back each faked command with one recorded real response or refusal named in the test header (used: 0, last: -, approved: 2026-11-08, retire-when: test doubles are generated from recorded real responses, trigger: tests/*fake*)
- [L012] Writing criteria for a text-matching guard - list the forms to refuse and the forms to allow; forms outside the list are limits, not defects (used: 0, last: -, approved: 2026-11-08, retire-when: two more guard tasks pass review in one round with a form list, trigger: scripts/*guard*.sh scripts/private-terms.sh)
- [L013] Finishing a library procedure that drives an external program - run it end to end on that program once and record every gate; unit tests alone missed a dozen defects (used: 0, last: -, approved: 2026-11-08, retire-when: a profile rule requires a recorded end-to-end example per such procedure, trigger: docs/library/procedures/*)
- [L014] Taking an outward action (merge, release, publish, rename or change visibility, upload, commit to a connected app) - the auto-mode check refuses unless the owner asked for that action in words; name the action, ask for it, and continue other work meanwhile (used: 6, last: 2026-11-17, approved: 2026-11-09, retire-when: the auto-mode check passes these actions without a per-action request, VERIFY at that time)
- [L015] Running a shell command whose text contains a refused form (test strings, commit bodies, heredocs) - write the text to a file with the file tool and run by path; commit with git commit -F; for real deletes pass the literal absolute path, not a variable (used: 4, last: 2026-11-17, approved: 2026-11-09, retire-when: the harness passes hook payloads that separate data from the command, or the guard parses heredoc bodies as data)
- [L016] Stopping work - stop by PID or task id, never by image name; after a stop confirm no child still writes to the log; start stopped work one at a time (used: 1, last: 2026-11-09, approved: 2026-11-10, retire-when: the guard refuses kill-by-name with a test and a harness stop ends the whole process tree)
- [L019] Needing Git Bash to leave a path unconverted for one command - set MSYS_NO_PATHCONV on that single git command only, never export it into a shell that runs scripts; session-context.sh warns when it is exported (used: 0, last: -, approved: 2026-11-10, retire-when: no script depends on MSYS path conversion being switched off, trigger: scripts/dream/* scripts/template-sync.sh scripts/doctor.sh scripts/find-python.sh scripts/*.cmd scripts/*.ps1)
- [L021] Launching parallel agents - brief each with a log and commit-message file name unique to the agent and repository (used: 1, last: 2026-11-17, approved: 2026-11-18, retire-when: a helper hands each agent its own scratch folder)
- [L022] Faking an outside-repo folder (per-user projects folder, home) in a test - create it next to the fixture repository, never inside it, or git lists it as untracked and the check passes through git (used: 0, last: -, approved: 2026-11-18, retire-when: the test helpers create outside-repo folders through one function, trigger: tests/template/*)
