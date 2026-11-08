# Upstream lessons - process lessons to send to the template

A lesson about how work is run (not what the product does) is recorded here
by `docs/procedures/retro.md`, then sent at maintenance as an issue or PR on
the template (`docs/procedures/upstream.md`). Clear sent entries and note the
link in the maintenance log. Product lessons stay in `PENDING.md`.

Entry format (all five fields required):

- what happened:
- what check should have caught it:
- what was added:
- retire-when:
- applies to: core | <profile name>

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
- applies to: core
