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

### Two ways a script loses its executable bit on Windows

- what happened: (a) a self-test fixture wrote a stub script at run time
  without the bit; Git Bash runs it anyway, so the Windows gate passed and
  Linux CI failed (run 40819768925). (b) on 2026-11-09 three tracked
  scripts (scripts/doctor.sh and two test files) were committed as 100644
  from a Windows worktree; every local test passed, and CI failed at
  check.sh step 5g ("scripts lost the executable bit"), which reads the git
  index and would fail on Windows too, but runs after the self-test step,
  so slow local runs never reached it.
- what check should have caught it: (a) lib.sh t_check_exec on every
  fixture (PR 12; it can only run where chmod sets the bit, so Linux CI);
  (b) step 5g extended to tests/template/ and run before the self-test step
  (BACKLOG row).
- what was added: fixtures run chmod +x on the scripts they write; the CI
  runs that failed are the regression evidence.
- retire-when: step 5g covers tests/template/ and runs before the
  self-tests, and t_check_exec runs in CI.

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
