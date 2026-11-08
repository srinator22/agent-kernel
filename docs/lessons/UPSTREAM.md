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

### Scripts and long text go through files, not the shell

- what happened: python run from stdin or a here-document hung until the
  120 s timeout, inline scripts turned written backslash escapes into real
  bytes, and literal commands over about 4 KB failed with "unexpected EOF
  while looking for matching quote" in the shell tool. It recurred in at
  least five sessions from 2026-08 to 2026-11.
- what check should have caught it: the library hook refuse_shell_stdin.py
  wired into the core settings; the character gate caught escape damage,
  but only in a full run.
- what was added: scripts and text are written with the file tool and run
  by path; backslashes are built with chr(92); literal-path commands stay
  under about 4 KB and are batched.
- retire-when: the stdin hook is wired with its test and the shell tool
  runs long commands or reports its length limit.
- applies to: core
