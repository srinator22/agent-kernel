---
name: datasheet-keeper
description: Fetch a datasheet, manual, drawing or standard, verify it, store it under datasheets/<subsystem>/ in the design folder and add its MANIFEST.md row. Use when a new part, standard or manual is proposed, or a MANIFEST row is missing or stale. Do not use for firmware or software documents.
---

# Datasheet keeper

Purpose: no document, no part (PCB-2). Every number in the design traces to a
stored, hashed document.

## When to use

A new part, standard or manual is proposed; a MANIFEST row is missing, stale
or fails `check_manifest`.

## Procedure

1. Find the manufacturer source URL (manufacturer site first; a distributor
   mirror only if the manufacturer blocks, and say so in the row).
2. Download from the command line into a scratch directory, not into the
   design folder yet. Never open document links in a browser pane shared with
   the user.
3. Verify: the file starts with `%PDF` (`head -c 4`), its size is plausible,
   and the title page matches the part and the revision.
4. Name it `<manufacturer>_<part>_<doc-type>_<revision>.pdf` and move it to
   `datasheets/<subsystem>/` (the project's subsystem list, for example motor,
   power, drivers, interface, controller, connectors, existing equipment).
5. Compute sha256.
6. Add the row to `datasheets/MANIFEST.md` in its existing column format:
   file, part, source URL, revision, pages, sha256, status.
7. Run `check_manifest` (or the gate's manifest step) until it passes.
8. Connectors, inlets, switches, sensors and modules: also look for the
   manufacturer pre-wired or pigtail version and the drawings of the mating
   parts, and store those too (PCB-10).

## Network limits

Some manufacturer sites time out or refuse scripted downloads. Report the
site, ask the user to download the file into the subfolder, then continue
from step 3. Record the blocked site as an open question so the next session
does not retry blindly.

## Outputs

Document in `datasheets/<subsystem>/`; MANIFEST row; passing manifest check.

## Never

- Store an HTML error page, a login page or a truncated file as a datasheet.
- Record a revision or page count not read from the document.
- Replace a file without keeping the old row marked superseded (PCB-3).
- Download from an untrusted site or run a downloaded executable.
