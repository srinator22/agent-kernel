---
name: simulation
description: Run or plan power-budget, sequencing, hold-up, thermal, trace-width, ratings and SPICE analyses for a PCB design and report margins against requirement IDs, with every input traced to the parameters file. Use when a margin is needed at the parameters, schematic or layout stage. Do not use for firmware simulation.
---

# PCB simulation

Purpose: show margins early, with every input traced to the parameters file
(PCB-4, PCB-12).

## What can be simulated at each stage

| Stage | Available | Tool (profile Tools list) |
|---|---|---|
| Parameters only | Rail and branch power budget by operating mode | `sim_power_budget` |
| Parameters only | Staggered start-up current against the supply; logic hold-up after input loss against fault-record time | `sim_sequencing`, `sim_holdup` |
| Parameters only | Copper width and temperature rise for the input, converter and motor paths | `calc_trace_width` |
| Parameters only | Part and board temperature rise at the maximum local ambient; parts with no thermal data flagged | `sim_thermal`, `sim_thermal_gaps` |
| Parameters only | Component ratings with derating margin | `check_ratings` |
| Schematic exists | SPICE: converter stage, regeneration clamp, input filters, inrush | a SPICE simulator (for example ngspice) when installed |
| Layout exists | Trace width and thermal re-run with real lengths and areas | same tools, updated parameters |

Check the SPICE simulator is installed before promising SPICE results.

## Procedure

1. Pick the requirement IDs the run addresses.
2. Check the parameters file holds every input, with source, bounds and
   status. Add a missing one there first, never inside a tool.
3. Run the tool (`--help` for arguments); keep the full output. Exit 2 is
   "could not run".
4. Report a margin table: requirement ID, quantity, value, limit, margin,
   inputs verified or design value.
5. For SPICE, store the testbench and netlist with the parameter values read
   from the parameters file, the models used, and the plots or raw results
   beside them (for example `analysis/spice/`).
6. Record in `analysis/<YYYY-MM-DD>_SIM_<topic>.md` through `pcb-doc-writer`.
7. A failing margin becomes a finding or an open question; do not change the
   parameter to pass.
8. Delegate runs and tool extensions to `pcb-simulation-engineer`.

## Never

- Present a simulation of design values as a measurement.
- Hard-code a number in two places.
- Tune an input until the margin passes.
- Claim SPICE results without the netlist and the models used.
