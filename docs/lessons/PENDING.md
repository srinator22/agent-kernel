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

### Stop processes by PID, and confirm the tree is gone

- what happened: a worker killed three unrelated python processes with
  `taskkill /F /IM python.exe`; separately, a task stop left a test's child
  processes writing to the same log (2026-11-08, fleet-sync-fixes).
- what check should have caught it: the destructive guard refusing
  kill-by-name (BACKLOG P2); for the log, none, this note is the guard.
- what was added: briefs say stop only by PID or task id; fail-first runs
  use a frozen copy with its own log, and after a stop confirm no child is
  still running.
- retire-when: the guard refuses kill-by-name with a test and a harness
  stop ends the whole process tree.

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

### Scripts created on Windows lose the executable bit

- what happened: scripts/doctor.sh, tests/template/test_doctor.sh and
  tests/template/test_taste_project.sh were committed as 100644 from a
  Windows worktree (2026-11-09, v0.5.2); Git Bash runs them anyway, so every
  local test passed and only the Linux CI check failed ("scripts lost the
  executable bit").
- what check should have caught it: a pre-commit or check.sh quick-lane
  check that every staged or tracked *.sh under scripts/ and tests/template/
  is 100755 in the index, so the miss shows on Windows before the push.
- what was added: none; the PR CI caught it.
- retire-when: a local check on index modes runs before commit.

### Windows path behaviour shows only on the Windows runner

- what happened: dream.py matched sessions by path spelling; the runner
  records cwds as C:/Users/RUNNER~1/... with a long rest while the code
  resolved roots to the long form. Linux CI and this computer (a short user
  folder name) were green; main's Windows job failed after merge and two
  fix rounds were needed (2026-11-09, PR 6 and PR 8).
- what check should have caught it: running the selftest-windows job on the
  branch (gh workflow run ci.yml --ref <branch>) before merging any change
  to path matching, transcript discovery or Windows-specific scripts.
- what was added: the mixed-spelling test cases in test_dream.sh, which
  reproduce the runner's shape on any Windows machine with 8.3 names.
- retire-when: the Windows job runs on every pull request, or ship.md names
  the dispatch step for such changes.

### MSYS_NO_PATHCONV=1 breaks git -C for the native git.exe

- what happened: an advisor shell exported MSYS_NO_PATHCONV=1 (to stop Git
  Bash rewriting "ref:path" arguments) and then ran a template script; the
  script's `git -C /c/dev/...` reached git.exe unconverted and failed with
  "cannot read the git range" (2026-11-09).
- what check should have caught it: none, this note is the guard: set
  MSYS_NO_PATHCONV only on the single git command that needs it, never
  export it into a shell that runs scripts.
- what was added: none.
- retire-when: the scripts stop relying on MSYS path conversion, or a
  session-start warning flags the variable.
