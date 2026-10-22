---
name: safety-analysis
description: Analyse the hardware stop chain, reset, boot, brown-out and fault states, fusing, clamps and ratings of a PCB design against the safety and compliance requirement rows, from models first, then the read-only pcb-safety-analyst. Use for any change touching the stop chain, an output driver, fusing, the input stage or an enable, and before the schematic, layout and pre-order milestones. Do not use for firmware safety logic.
---

# PCB safety analysis

Purpose: findings tied to safety and compliance requirement IDs, from models
first, then an independent read-only analyst (PCB-9, PCB-17).

## When to use

Any change touching the stop chain, an output driver, fusing, the input stage
or an enable; before the schematic, layout and pre-order milestones.

## Procedure

1. Run the stop-chain fault model (`model_safety_chain`); keep the output.
2. Run the ratings check (`check_ratings`); keep the output. A missing tool is
   recorded as a gap, never assumed passing.
3. Delegate to `pcb-safety-analyst` with both outputs.
4. Make sure the analysis covers these invariants:
   - Stop chain: the emergency-stop input (dual channel where required) and
     guard interlocks remove the enables of the motor gate driver, the
     H-bridges, the high-voltage converter and the switched outputs with no
     controller in the path; the controller reads it back; no single fault
     keeps a drive enabled.
   - Reset, boot, brown-out and unpowered controller: every output off by an
     external pull-down or equivalent bias, including the motor driver's
     enable.
   - No automatic restart after power return or a stop reset.
   - A speed loop that must hold without the controller is independent of it,
     and a lost heartbeat stops the drive.
   - Fusing and a protected switch on each branch; fuse type and I2t against
     inrush and charge pulses (component-selection skill); clearances and
     creepage; flyback and regeneration clamps with the window check.
   - A USB or debug supply cannot energise servos, the motor bus or switched
     outputs.
5. Record the numbered findings (severity, requirement ID, evidence, action)
   in `analysis/<YYYY-MM-DD>_SAFETY.md` through `pcb-doc-writer`.
6. Open items go to `OPEN_QUESTIONS.md`: at least the formal stop-chain
   performance-level assessment and any driver behaviour at speed that is not
   published.

## Outputs

Findings list tied to requirement IDs; tool outputs quoted.

## Never

- Weaken or bypass the stop chain in software or in the netlist to pass a
  check.
- Rely on a standard figure in the project's notes as verified; it is
  unverified until checked against the standard text.
- Claim a performance level (ISO 13849-1) before the assessment is done.
- Use unpublished driver or converter behaviour as a safety argument; it is
  UNKNOWN until measured.
- Let the analyst edit design files.
