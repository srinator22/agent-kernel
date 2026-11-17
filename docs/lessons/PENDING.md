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
