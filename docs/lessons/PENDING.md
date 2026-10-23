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
