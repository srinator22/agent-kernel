---
name: test-data-analyst
description: Import, preserve, validate, analyse, compare and report test data from instrument files or device logs. Use for supplied test files, SD or log captures, sensor exports, load-case evidence, per-run or per-cycle grading questions, or data-backed control-algorithm questions; do not use for firmware-only work without test data.
---

# Test data analyst

Carries the data-analysis profile workflow (rules DA-1 to DA-16 in
`docs/profiles/data-analysis/PROFILE.md`; data classes in
`docs/rules/data-provenance.md`).

1. Preserve the supplied file unchanged; never edit or overwrite raw evidence
   (DA-1). Confirm the raw path is marked `-text` (DA-2).
2. Import with the project's import tool: copy, verify the SHA-256 against the
   source, never replace an existing file. Several files go into one session in
   one call. Write the session README row: path, hash, date, condition, version,
   load or configuration, `Unknown` when unknown (DA-3).
3. Confirm run identity from the data (a header line, session id or logged
   version), never from a folder or file name alone (DA-8).
4. Parse with the format's analyser. It lists malformed, impossible and partial
   rows with file and line; none is guessed, repaired or dropped silently
   (DA-4). Exit codes: 0 success, 1 read or parse error, 2 no usable data or
   needs review, and a count mismatch is 2 (DA-5). Output goes to a new
   directory; the analyser refuses an existing one (DA-14).
5. Keep record kinds apart: an operator decision logged by the device, an exact
   controller observation and a reconstructed trace are labelled separately,
   and a reconstruction is directional evidence only (DA-9).
6. Use a replay tool only for counterfactual command comparison, and state that
   recorded outputs cannot predict the plant's response to changed commands
   (DA-10).
7. Check malformed rows, counter overflow, impossible periods, missing events,
   partial runs, sample counts, order, cold or warm start and configuration
   version. Treat a configured interval, timeout or gap as a floor and derive
   the real interval from consecutive rows with its spread (DA-7).
8. Distinguish average error, stability failure, sensor noise, controller
   response and unknown disturbance. A sensor quirk found in data becomes a
   knowledge note with a detection run on load (DA-15).
9. Keep conclusions proportional to independent experiments; state the
   independent count; do not tune any parameter from one unexplained run
   (DA-11). Re-derive two headline numbers from the raw file independently.
10. Store concise identity, results, graphs, limitations and next evidence with
    the raw file. Every figure and table caption names source file, producing
    version and population (DA-6). Commit a dated report with an index row
    (DA-12); code needed a second time becomes a tested command (DA-13). Full
    raw captures stay out of git unless Project decisions says otherwise
    (DA-16).

Report: files and hashes, rows listed as malformed, per-run results, limits,
next evidence needed. Never present an inference as a measurement.
