# Quarantined flaky tests

A flaky test is a defect, not noise (kernel rule 2). Parking a test here
removes it from the gate but never deletes it; each entry stays open as
its own task until the flake is fixed and the test returns to the suite.
A quarantined test may not be deleted.

Entry format:

- test path:
- observed flake behavior:
- date quarantined:
- owner task (BACKLOG.md item or task slug):

No quarantined tests.
