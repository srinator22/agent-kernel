---
name: electronics-docs
description: Maintain and validate the electronics BOM, power rails, firmware pins, connector pinouts, signal types, component ratings and open safety gaps of a controller. Use for wiring changes, component substitutions, board planning, printable wiring guidance or electronics reviews; do not use for unrelated firmware logic.
---

# Electronics documentation

Keeps the written hardware record consistent with the firmware and the wiring.
For a board design under the hardware-pcb profile, that profile's checks own
the schematic and layout; this skill owns the system-level record (BOM, wiring
guide, pin map).

1. Read the variant's BOM, the firmware's user-input and pin sections, and its
   configuration contract (FW-12). Run the project's wiring check before and
   after every change.
2. Record installed facts separately from proposed parts and unknown ratings.
   Supplier maximum ratings are not verified installed capacity; say
   "unmeasured" until a measurement exists.
3. For every signal verify voltage, current, logic level, polarity, active
   state, common ground, pin, wire gauge, connector and protection.
4. Do not infer that an output operated from a command. State the feedback
   required to prove it: current, position, speed or airflow (FW-20).
5. Keep the safety gaps visible until physically resolved: fusing, flyback
   suppression, emergency isolation, reset-state biasing (FW-17), interaction
   of two 5 V sources (for example USB and an external rail), and connector
   pins nobody has documented.
6. When a part, value or limit changes, flag its electrical side effects at
   decision time (inrush against fuse I2t, logic-level mismatch, supply
   range), and route the choice through the component-selection and
   design-review steps if the project has them. A substitution made for
   convenience is the likeliest to skip this.
7. Update the configuration contract only after confirming an intentional
   hardware or firmware change; record the decision in `docs/decisions/`.
8. Keep the BOM and wiring guides scan-first: tables, pin maps, short warnings,
   each connector's viewing side stated.
9. Run the repository and configuration checks after the edits, then record the
   change and any new open gap in the open investigations file.

Output: what changed, which checks ran, which hardware facts remain
unmeasured and the bench step that would settle each.
