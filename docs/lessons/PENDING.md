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

### Fakes of external CLIs come from observed output

- what happened: a CI watcher's tests used a fake gh written from
  assumptions; the real gh refuses "run view --job" while the run is still
  in progress, so the tested log-tail path printed a refusal in practice.
  Only a reviewer's live call found it, after two review rounds.
- what check should have caught it: each faked command of an external CLI
  is backed by one recorded real response (or refusal), named in the test
  header, so a fake cannot accept what the real tool rejects.
- what was added: none, this note is the guard; the ci-watch fake now
  refuses like gh 2.90.
- retire-when: test doubles for external CLIs are generated from recorded
  real responses.

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

### Inline generator scripts lose their escapes through the shell

- what happened: Python run inline through the Bash tool turned written
  escapes (\x, \n) into real bytes and newlines, so a test file got
  mojibake bytes instead of escape text; the new character gate caught it
  in the first full run, which cost one 10-minute gate cycle.
- what check should have caught it: the character gate (check.sh 4a) did;
  a faster lane would have caught it before the full run.
- what was added: generator scripts written with the file tool and run by
  path, backslashes built with chr(92).
- retire-when: the quick lane runs the character gate in seconds as part
  of every edit loop.

### A text-matching guard is reviewed against an explicit list of forms

- what happened: the destructive guard's criterion and rule doc promised
  "any spelling of the path"; five reviewer rounds each found a new
  spelling (keywords, an earlier cd, escaped spaces, rebuilt wrapper
  quotes), each a real gap, and the budget ran out once.
- what check should have caught it: the acceptance criterion should have
  listed the forms to refuse and the forms to allow, with the reviewer
  told that forms outside the list are limits, not defects.
- what was added: the rule doc now states the coverage list and the
  limits; ADR 0006 records the fail-toward-refusing policy.
- retire-when: two more guard-type tasks pass review in one round with a
  form list in their criteria.

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

### A worked example on real software finds what unit tests cannot

- what happened: the render library tools passed 440+ unit tests, yet taking
  a primitive sample scene through every stage on the real Blender build
  found 10 tool defects (a version banner printed after the script output,
  font sizes not scaled, an off-by-one title hold, done chunks with deleted
  frames skipped, a self-test that wrote no record, and more); the
  independent review found an eleventh (a failed command passing the render
  gate when every frame existed).
- what check should have caught it: a library procedure that drives an
  external tool ships with a worked example run end to end on that tool
  before it is called done; the example's record quotes every gate.
- what was added: docs/library/examples/product-render-sample/ and its
  RECORD.md; each defect has a failing-first regression test.
- retire-when: a profile rule requires a recorded end-to-end example for
  every procedure that drives an external program.

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

### Python from stdin hangs this machine's shell wrapper

- what happened: commands of the form `python - <<EOF` or `python -I -`
  hung until the 120 s timeout three times in one session (twice by the
  advisor, once by a worker), costing a background-task stop each time.
- what check should have caught it: the library hook
  `refuse_shell_stdin.py`, which refuses exactly this, adopted into the
  core settings for every session.
- what was added: none, this note is the guard.
- retire-when: the hook is wired in `.claude/settings.json` with its test.

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
