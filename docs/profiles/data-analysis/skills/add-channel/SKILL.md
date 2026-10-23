---
name: add-channel
description: Add a new input channel or signal (a new column, sensor axis, log field or derived series) to an import and analysis pipeline following the established pattern. Use when a source starts reporting something new, or when a new analysis view or report needs a channel the pipeline does not carry yet. Do not use for changing an existing channel's maths (use verify-core when the scientific profile is adopted).
---

# Add a channel

Args: the channel name (kebab-case). Rules: DA-1 to DA-8, DA-13 to DA-15 in
`docs/profiles/data-analysis/PROFILE.md`; `docs/rules/data-provenance.md`.

## Steps

1. Write down the channel contract before code: name, units, expected range,
   nominal and observed sample interval (derived from rows, DA-7), how a missing
   or invalid value is represented, and which source versions carry it. Record
   `Unknown` where unknown; never guess a unit or scale.
2. Get a real sample file that carries the channel and a fixture that does not,
   so older sources still load. Raw files stay unchanged and hash-verified
   (DA-1); the fixture is a small copy or a synthetic file written inline.
3. Extend the parser behind the project's existing parse boundary, not in a
   view or report script. Malformed, impossible or partial values are listed
   with file and line, never repaired or dropped silently (DA-4). Exit codes
   follow DA-5: 0 success, 1 read or parse error, 2 no usable data or needs
   review (a count mismatch returns 2).
4. Write the tests first: the channel present, absent, empty, malformed,
   duplicated and partial; one test pinning a computed value to a number worked
   out by hand with its units. If the channel needs new maths, add it as a
   tested function with a golden fixture (`verify-core`, SC-1 to SC-4, when the
   scientific profile is adopted).
5. Check for the known quirks of this kind of source (duplicated rows, bias or
   drift, clipping, unit mix-ups, clock steps). A quirk found is written up as a
   knowledge note with a detection that runs on load and prompts before any
   removal (DA-15).
6. Add the channel to the session record: the import tool's hash row and the
   labelled units list (DA-3), and run identity from the data, not the file
   name (DA-8). Keep different kinds of record labelled apart (DA-9).
7. If a view or report shows it, follow the project's layering: parse and
   compute in the core or analyser layer, render in a thin wrapper, no direct
   chart-library import in the view (`docs/rules/architecture.md`). Test the
   view with an injected synchronous compute seam, and add one end-to-end check
   that loads the fixture and asserts the channel renders. Every figure caption
   states source file, producing version and population (DA-6).
8. Run the project's verify command (`./scripts/check.sh`), read the output,
   then ship per `docs/procedures/ship.md`.

A script needed a second time is promoted to a tested command (DA-13).
