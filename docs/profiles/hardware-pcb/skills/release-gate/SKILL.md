---
name: release-gate
description: Run the PCB gate - <pcb-gate> --quick during work, the full gate before any commit of design files and before any order - interpret failures, give every WARN an owner and record the result. Do not use for the software or firmware release gates.
---

# PCB release gate

Purpose: run the board gate, interpret it honestly, record it (PCB-6, PCB-12,
PCB-15).

## When to use

- `<pcb-gate> --quick` during work (skips the CAD application and network
  steps).
- `<pcb-gate>` (full: ERC, DRC with zones refilled, analyzers) before any
  commit of design files and before any order.

## Procedure

1. Run the gate from the design folder. Capture the whole output, and compare
   `git status` before and after: a gate that rewrites a tracked file is a
   defect to log, not a side effect to keep.
2. Exit code: 0 pass, 1 a check failed, 2 the gate could not run (missing tool,
   missing CAD install, bad path). 2 is never a pass.
3. On 1: read the first failing step. Typical causes:
   - `check_manifest`: a file without a MANIFEST row, or a sha256 mismatch.
   - `check_decisions`: an ID gap, a missing field, a supersession not marked.
   - `check_requirements`: a requirement cites an unknown decision or question.
   - `check_parameters`: a value outside its bound, or no source document.
   - `check_doc_sync`: a superseded term or stale geometry still stated.
   - ERC or DRC: report violation counts and the first few items.
   Fix the cause in the source, not the check; then re-run.
4. On 2: report what could not run and why; do not call it a pass.
5. A `--quick` pass is not a release pass; say which was run.
6. WARN ownership: a PASS with WARN lines is not a clean result. For each
   WARN, and each INFO that states a number against a limit (a mode current
   against the supply, a junction temperature not computed, a pending part),
   name its owner: an open question, a requirement with a verification step,
   or a disposition line in the gate record. A WARN that outlives a milestone
   with no owner is reported to the user as a gap, not left in the log.
7. Record the result (command, date, exit code, output, steps skipped,
   dispositions) in `analysis/<YYYY-MM-DD>_GATE.md` through `pcb-doc-writer`.
8. Every failure gets a root cause, a fix and a prevention (kernel rule 3); a
   failure no check can catch becomes a ledger row (PCB-16) or a
   `docs/DEFECT_MEMORY.md` entry.

## Outputs

Gate record in `analysis/`; a fix list when failing.

## Never

- Bypass, comment out or loosen a check, or edit a bound in the parameters
  file, to get a pass (kernel rule 2). A bound change is a logged decision
  first (decision-logger).
- Report a pass when the exit code was not 0.
- Commit design files or order on a failing or `--quick`-only result.
- Hide a failure: quote the output.
