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
