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
