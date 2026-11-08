# Pending lessons - awaiting human approval

Proposed lessons land here. Unapproved entries are never acted on;
approval means a human moves the entry into `INDEX.md` (kernel rule 9).
Confirmed-good calls belong here too, not only corrections. Never record
what is derivable from the repo itself.

Entry format (all four fields required):

- what happened:
- what check should have caught it:
- what was added:
- retire-when:

### The live destructive guard reads the whole command line

- what happened: with scripts/destructive-guard.sh active as a PreToolUse
  hook, shell commands that only carried test strings or a commit body
  naming a refused form (rm -rf of the workspace, git push --force) were
  refused, including text inside heredocs and inline scripts. Four
  commands were refused and redone during the task that built the guard.
- what check should have caught it: none, this note is the guard; the
  over-block is the documented design (ADR 0006).
- what was added: test inputs written to a file with the file tool and
  run by path; commit bodies passed with git commit -F.
- retire-when: the harness passes hook payloads that separate data from
  the command, or the guard parses heredoc bodies as data.

### A Windows-green gate can hide a Linux exec-bit failure

- what happened: the kb-adaptations change merged straight to main on the
  owner's request after the full gate passed on Windows Git Bash; CI on
  Linux failed (run 40819768925) because a self-test fixture stub lacked
  the executable bit, which Git Bash ignores. Fixed in ee4ffdb, CI green.
- what check should have caught it: CI on the branch before the merge (the
  default gated merge), or a self-test assertion that every script the
  fixture writes is executable on disk.
- what was added: the fixture now runs chmod +x on each stub; the CI run
  that failed is the regression evidence.
- retire-when: scripts/selftest.sh runs in a CI matrix that includes
  Windows and Linux before merge (BACKLOG P2), or merges always wait for
  branch CI.

### A reviewer's GO must rest on evidence newer than the inputs

- what happened: the render technical director reviewed extracts and lints
  while the advisor was still changing the scene script (a reflection card
  was added mid-review), so the evidence described an older scene; it
  caught this itself from file modification times and returned NO-GO.
- what check should have caught it: a gate record quotes the hash of the
  scene script and presets it describes, and the gate fails when the
  current files hash differently.
- what was added: none, this note is the guard; the GO procedure re-ran
  extract, lint and measurement after every scene edit.
- retire-when: scene_lint or the stage record stores and compares the
  scene and preset hashes.

### Stop processes by PID, never by image name

- what happened: a worker stopped its own hung test with
  `taskkill /F /IM python.exe` and killed three python processes on the
  machine, which may have belonged to other sessions.
- what check should have caught it: the destructive-command guard refuses
  `taskkill /IM`, `Stop-Process -Name` and `pkill`/`killall` by name.
- what was added: worker briefs now say "stop only by PID or task id";
  scripts/destructive-guard.sh does not cover process kills yet.
- retire-when: the guard refuses kill-by-name with a test.

### ADR numbers collide across parallel branches

- what happened: this branch added ADR 0006 while another branch merged
  its own ADR 0006 to main; adr.sh check passed on each branch alone and
  only the merge showed the duplicate, which forced a renumber and edits in
  six files.
- what check should have caught it: none on one branch; the merge step
  re-runs adr.sh, which did catch it.
- what was added: none, this note is the guard: before a merge, fetch main
  and renumber new ADRs to follow main's last one.
- retire-when: ADRs are numbered at merge time by a script.

### Lookdev data points from the sample scene (one project, to confirm)

- what happened: a 12 cm product under area lights of 120, 40 and 60 W
  rendered washed out (matte black read light grey); 3, 0.8 and 2 W looked
  right. A closed clear lid was invisible until a reflection-only card
  (glossy only, no diffuse) sat at the camera's mirror angle. A reflection
  of an object inside clear acrylic reaches it as a transmission-type ray
  in Cycles, so hiding it needed both glossy and transmission visibility
  off. Fixed seed on a held window measured flicker 0.0000003 vs 0.00036 to
  0.00199 for animated seed.
- what check should have caught it: check stills at stage 4 did; no tool
  can judge a look.
- what was added: the sample's RECORD.md holds the numbers.
- retire-when: a second project confirms or corrects them, and the
  lookdev-artist or cinematographer agent carries the confirmed defaults.

### The auto-mode check blocks a merge the owner has not asked for in words

- what happened: after green CI and a PASS review, gh pr merge was refused
  as "merge without review" although the owner had said "do it"; it went
  through once the owner wrote "merge into main" (2026-11-07,
  template-updates). Seen again on 2026-11-07 (merge refused three times,
  a tag refused as a public surface) and passed after the owner wrote merge
  and release.
- what check should have caught it: none, this note is the guard: ask the
  owner for the merge explicitly when the PR is ready, and offer the merge
  action.
- what was added: none.
- retire-when: Project decisions records a standing override for merging
  green, reviewed PRs.

### A stopped background command can keep writing

- what happened: a fail-first run of test_check_always.sh in the live tree
  was stopped with the harness's task stop, but its child processes kept
  running and appended to the same log, so the log mixed two runs (2026-11-08,
  fleet-sync-fixes). Three processes were killed by PID and the run was
  repeated on a frozen copy of the pre-fix scripts with a separate log.
- what check should have caught it: none, this note is the guard: run
  fail-first evidence on a frozen copy with its own log, and after a stop,
  check that no child process is still running before reusing a log.
- what was added: none.
- retire-when: stopping a background task in the harness ends its whole
  process tree.

### tasklint reads only the first line of a criterion

- what happened: a ticked criterion written over several lines, with its
  "->" evidence on the last line, failed tasklint as having no evidence; a
  bare file name inside a parenthesis on the evidence line ("check.sh") was
  read as an evidence path that does not exist (2026-11-08,
  fleet-sync-fixes). Both were rewritten by hand.
- what check should have caught it: tasklint names an indented continuation
  line under a criterion, and the evidence paths it could not resolve, with
  the rule that evidence sits on the criterion's first line.
- what was added: none.
- retire-when: tasklint reads a criterion's continuation lines or reports
  them as such.
