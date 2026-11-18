# 0020 - Template kernel changes are accepted per project, never by default

Date: 2026-11-18
Status: accepted

## Context

When a template release changed the AGENTS.md kernel block, template-sync
stopped at "KERNEL CHANGE" and the update procedure stopped with it, so a
project stayed at the last release before the change (three projects sat at
v0.5.0). The kernel header requires human approval for every kernel edit, and
rule 15 allows a standing override only when the human records it in that
project's Project decisions. One approval cannot cover other projects.

## Decision

- A kernel difference never blocks the rest of the sync: every non-kernel
  file is still applied, the kernel diff is written, "KERNEL CHANGE" is
  printed, the exit is 1, and the sync is not recorded in
  docs/lessons/MAINTENANCE.log, so the next run still sees the old ref as
  its base and the kernel as pending.
- `scripts/template-sync.sh --accept-kernel` copies the template's kernel
  block verbatim and runs `kernel-hash.sh --update`, but only when the
  project's kernel equals the kernel of the previously recorded ref (CRs
  ignored). A project with no recorded sync, an unknown recorded ref or a
  customized kernel still stops with a named reason.
- The human passes `--accept-kernel`, or records a standing override in the
  project's Project decisions: a "Standing overrides" line containing
  "template kernel accepted verbatim". `scripts/fleet-sync.sh` passes the
  flag only for projects with that line. Agents never record the override.

## Consequences

- Projects no longer strand behind a kernel change; the owner decides the
  kernel per project, in a reviewable branch, and nothing is committed or
  pushed by the tools.
- A customized kernel is never overwritten; the owner merges it by hand.
- A project whose own template-sync.sh predates the flag needs the
  template's script run once by hand before fleet-sync can accept for it.
