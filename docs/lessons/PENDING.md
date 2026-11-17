# Pending lessons - awaiting human approval

Proposed lessons land here. Unapproved entries are never acted on;
approval means a human moves the entry into `INDEX.md` with its
`approved: YYYY-MM-DD` date (kernel rule 9).
Confirmed-good calls belong here too, not only corrections. Never record
what is derivable from the repo itself.

Entry format (all four fields required):

- what happened:
- what check should have caught it:
- what was added:
- retire-when:

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

### The pull request's CI run is the full gate when local runs crawl

- what happened: a full local ./scripts/check.sh took over an hour on a
  loaded Windows machine, while CI ran the same script on the pushed head in
  about 2 minutes and also caught a Linux-only failure (2026-11-09, feedback
  loop).
- what check should have caught it: none, this note is the guard.
- what was added: push the branch, open the PR and use the CI run on the
  exact head as the check.sh evidence for the reviewer; run only the touched
  test files locally.
- retire-when: scripts/selftest.sh runs its test files in parallel and a
  local full gate takes under 10 minutes.

### A test that holds a banned character or an escape sequence

- what happened: the file-writing tools turned a typed backslash-u escape
  into the real dash or quote character in three projects, so the style scan
  failed at the ship gate, or passed locally while the file was untracked.
- what check should have caught it: a test helper that builds banned
  characters from chr() and a scan that also covers untracked files.
- what was added: nothing yet; build such characters with chr() at run time,
  or write the file by script and run check.sh --fast before commit.
- retire-when: the tools stop rewriting escapes, or the scan covers untracked
  files and a helper exists.

### Editing a gate script while the gate runs

- what happened: a gate script was edited while the full check was running
  it; bash reads a script as it executes, so the run ended at an unrelated
  line with a command-not-found error and cost minutes, though the committed
  script was fine.
- what check should have caught it: none; the guard is not to edit scripts/
  or tests/template/ files while check.sh or selftest.sh runs, and to rerun
  when the error names a line the file does not contain.
- what was added: nothing yet.
- retire-when: the gate copies its scripts to a scratch folder before
  running them.
