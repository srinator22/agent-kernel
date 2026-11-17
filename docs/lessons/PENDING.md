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

### A path printed by Python under Git Bash is in Windows form

- what happened: a test built a fixture under /tmp and asserted the path a
  Python script printed, but Python printed it as C:/Users/.../Temp/..., so
  the assertion failed while the behavior was right (2026-11-08,
  taste-profile). The assertion now matches only the path-free part.
- what check should have caught it: none, this note is the guard: in shell
  tests, assert on the path-free part of a message, or convert both sides
  with cygpath -m before comparing.
- what was added: none.
- retire-when: the test helpers compare paths through one normalizing
  function.

### A fixture for an outside folder sits outside the fixture repository

- what happened: a test faked the per-user projects folder inside its fixture
  git repository; git listed the fake memory notes as untracked files, so
  the check passed through git and the memory comparison it meant to cover
  could be deleted with every check green (2026-11-08, dream outcome fixes;
  found by review round 1).
- what check should have caught it: a mutation run that removes the code
  path a new test is meant to cover; this one did, once run.
- what was added: the fake folder moved next to the fixture, not inside it.
- retire-when: the test helpers create outside-repo folders through one
  function that places them outside the fixture.

### Each parallel agent gets its own scratch file names

- what happened: several agents ran at once with the same scratchpad log and
  commit message file names; one repo's check log and one commit message
  were overwritten by another agent's (2026-11-08, three project dreams).
- what check should have caught it: none, this note is the guard.
- what was added: briefs name a log and message file unique to the agent
  and repository.
- retire-when: a helper hands each agent its own scratch folder.

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
