---
name: part-sourcing
description: Check part availability, lifecycle and alternates at the assembler's own parts library and broadline distributors, apply the pre-wired and solder-free rule, and record dated sourcing status. Use when a part is proposed or changed, before the parts-list milestone, before any order, and when a part goes out of stock. Do not use for buying parts.
---

# Part sourcing

Purpose: confirm each part can be built by the chosen assembler (PCB-2,
PCB-10). Sizing the part is component-selection; this skill checks that the
chosen part can be bought and placed.

## When to use

A part is proposed or changed; before the parts-list milestone and before any
order; when a part goes out of stock.

## Procedure

1. List the parts with their datasheets from `datasheets/MANIFEST.md`.
2. For each, check in this order: the primary assembler's parts library, the
   second assembler's sourcing, then broadline distributors. Record:
   manufacturer part number, supplier part number, stock, price break,
   minimum order, package, the assembler's part class (for example basic or
   extended), date checked and source page.
3. Lifecycle from the manufacturer page: active, NRND, last-time-buy,
   obsolete.
4. Alternates: at least one pin-compatible or footprint-compatible alternate
   for each Proposed critical part, with its datasheet differences.
5. PCB-10 for every connector, inlet, switch, sensor and module: the
   manufacturer pre-wired or pigtail version, the solder-free option, the
   mating parts, termination type, conductor size, and any rating difference
   between bare and pre-wired versions.
6. Parts the assembler cannot stock: state the consignment route and lead
   time, and record it as an open question until settled.
7. Record in `research/` (one note per subsystem) and update the sourcing
   status fields in the parameters file. Datasheets via datasheet-keeper.
8. Delegate the exact-package and BOM/CPL check to `pcb-dfm-checker`.

## Outputs

Dated sourcing table in `research/`; status fields updated; open items in
`OPEN_QUESTIONS.md`.

## Never

- Order, add to a cart, create an account, enter payment details or contact a
  supplier (PCB-7).
- Report stock without the date and the source.
- Pick a part without a datasheet in `MANIFEST.md`.
- Recommend a connector without the pre-wired check of PCB-10.
