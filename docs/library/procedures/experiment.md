# Experiment - plan, run, record

Adopt by copying this file to `docs/procedures/experiment.md`, together with
the `experiment` skill and `docs/procedures/evidence-levels.md`. It is meant
to sit beside the scientific profile (SC rules) and, when logs are analysed,
the data-analysis profile (DA rules). Paths below are defaults.

Every physical test produces `experiments/<experiment ID>-<slug>/RECORD.md`
from `experiments/TEMPLATE.md`, an immutable `raw/` folder and a row in
`experiments/INDEX.md`. No automated agent energises hardware, uploads
firmware, operates test equipment or starts a hazardous activity; the human
does, by hand, after the safety checklist (the project's safety requirements
rows).

1. Pre-register. Before any hardware is powered: objective, hypothesis
   (hypothesis ID), hardware configuration, part revisions, firmware or
   software version, calibration state, test conditions, procedure and safety
   notes are written in RECORD.md. A test without a pre-registered hypothesis
   is an exploration and is labelled one.
2. Safety checklist in the record: restraint, guards, eye protection,
   emergency power isolation, standoff distance, stored-energy state,
   bystanders. Adapt the list to the hazards of the rig.
3. Run. The human operates. Raw captures go to `raw/` unchanged; the record
   lists each file with its SHA-256 and units (data-analysis profile DA-1,
   DA-3). Raw files are never edited; derived data is a new file with its
   derivation recorded.
4. Process with a tested command, writing to a new output directory (DA-13,
   DA-14, SC-14); the script version and settings go in the record. Malformed
   rows are listed, never dropped silently (DA-4).
5. Record results with uncertainty, limitations, observations and
   deviations from procedure (SC-16). A constrained-rig result states what
   the rig hides (for example translational forces, ground effect or cable
   loads).
6. Update the records in the same commit: the INDEX row; knowledge records
   for new measured facts (E1) with revalidate-when; the hypothesis status; a
   failed-experiment record for a negative or failed result; assumption rows
   validated or disproven; dependents of any changed record marked
   `revalidate` (decision procedure, step 5).
7. A recommended next action closes the record.
