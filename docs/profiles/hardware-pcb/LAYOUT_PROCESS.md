# Layout process (hardware-pcb profile)

The order of layout work, learned the hard way on a prior controller board:
three automated routing passes each took many hours and closed only part of the
links. The cause was placement without escape room, not router weakness. The
fan-out cause was the leading hypothesis and was not yet proven on that board
when this was written (unverified). No figure from that project is carried
here; the thresholds below are rule parameters that live in the project's
parameters file.

## 1. Correct order

| Step | What | Done when |
|---|---|---|
| S0 | Rules and tools first: routability rule, parameters keys, the tools of section 5, stack-up read from the fabricator and stored with URL, date and sha256 | each tool has run once on a scratch copy and printed a baseline; the hypothesis share is recorded |
| S1 | Floorplan: connector walls fixed by the enclosure; branding canvas, bottom keep-outs and 2 mm channels (rule areas `CH_*`) drawn before any part is placed; fan-out rings and one via spot per signal pin reserved around every fine-pitch IC; passives at courtyard gaps of 0.5 mm; locked movable groups per schematic sheet | routability checker FAIL 0 (rings, gaps, channels, escape test); layout checker FAIL 0; no courtyard overlap on either side |
| S2 | Scripted fan-out of every fine-pitch IC and every receptacle, stub plus via per pin, locked | 0 failed pins; no new DRC error; escape test FAIL 0 on the placed vias |
| S3 | Hand-routed, locked power copper (input path, converter loops, gate drive, shunts, outputs, stop chain) at the netclass widths; safety analyst reads the stop-chain copper before lock | all power nets connected and locked; quick DRC errors at or below the S2 baseline; new protected-copper baseline recorded |
| S4 | Pours and planes on a multilayer stack with alternating signal and plane layers (for example six layers: signal, ground, signal, power, ground, signal); power on one inner layer; no power pour on a routing layer under a logic block; GND and shield fills transparent to routing | every pour has a net, islands removed, corridor widths at or above the derated computed width |
| S5 | Signal routing, hybrid: autorouter on the channelled board (a capped, windowed run), a scripted router driver for short links, a guided human session for the rest | 0 unconnected; full-rule DRC 0 errors; schematic parity 0 violations; locked counts not below baseline |
| S6 | Stitching vias, perimeter fence, thermal arrays, dangling-item cleanup | stitching checker FAIL 0; full DRC 0 errors |
| S7 | Silkscreen from the functional label list; hold points of the profile apply (STEP to the owner before this step) | version checker silkscreen rule passes; labels match the label list |

A group is a CAD group of footprints moved and rotated as one unit and never
split or mirrored; edge-fixed items (connector-wall receptacles, power inlet,
stop-chain port, mounting holes) belong to no group and are never moved by a tool.

## 2. Router verdicts (qualitative, from a prior controller PCB project)

| Method | Verdict | Evidence |
|---|---|---|
| Autorouter, strip-first (remove routed copper, rerun) | Worse than the start; do not use | Open links rose sharply after the strip and never recovered within a capped run |
| Autorouter, additive only | Finisher for links a part move broke, not for the stuck set | Small net gain over several waves; most links broken by a moved part re-closed in minutes |
| Autorouter with DSN keepouts | Required | No DRC errors with them, many without |
| Whole-board rip-up (any router) | Worse than the start | Every rip-up run ended above its starting open count |
| Per-net routing, small same-net clearance | Useful; merge a net only where its cluster count fell, after DRC | A small gain over the plain run |
| Raster planners (Dijkstra, A*) | Stubs and short links only; they cannot shove | Placed most stubs; a rip-up test closed none |
| CAD router driven through API plus input events | A finisher for short links only; needs desktop consent per run because it takes the mouse and keyboard | Closed a small fraction of links, all short; a planner-guided follower closed none |

A person with a push-and-shove router, after a fan-out stage, is the method for
the remainder.

## 3. Diagnostics

1. Inspect one concrete failing item before accepting any "placement-limited"
   or "router-limited" verdict: open the pad, measure what encloses it and at
   what distance, name the enclosing net. A single pad inspection can reverse a
   verdict reached after hours of blind passes; a verdict row is refused unless
   an inspect row precedes it.
2. Quick DRC per batch: the real rule file with creepage minimums set to 0 mm
   (never delete a rule: some carry clearance constraints and exemptions).
   Full-rule DRC once per step. Zone refill is always on, in both.
3. Hard time cap and a progress file per pass: header with start time and cap
   written before the pass starts, rows of time, event, open links, DRC errors;
   a row after the cap is marked OVER CAP. Longer runs added nothing: each
   repeated long pass gained less than the one before.
4. Parallel operators by region on scratch copies, one project file each,
   merged net by net under one acceptance rule: 0 DRC errors, no locked item
   altered, no net with more pad clusters. One writer for the live board file.
5. Protected-copper baseline: a key of every protected and locked item recorded
   at the end of S3; later passes must keep it identical.
6. The pad-cluster census per net after every batch; no net may get worse.

## 4. Lessons applied (one line each)

- No fan-out stage before packing: fan-out rings and a script run before passives (S1, S2).
- Pours treated as obstacles: no power pour on a routing layer under logic (S4).
- Raster planners cannot shove: use an autorouter, a CAD router or a person (S5).
- Long blind passes: time cap and progress file per pass (section 3.3).
- Slow DRC: quick DRU per batch, full once per step (section 3.2).
- Verdict without inspection: one failing item inspected first (section 3.1).
- Canvas found after placement: branding area reserved before any part (S1).
- Strip-first rerun: never; additive only (section 2).
- Bottom-side clearance failures were placement mistakes: rules for class, part height limit, clearance from through-hole pins, no bottom part under connector walls, channels or canvas, one orientation per block (limits in the parameters file).

## 5. Tools to build at S0 (`build`; each takes `--help`, exits 0 pass, 1 fail, 2 could not run)

- check_routability: ring free of foreign courtyards, pads and copper on both sides; one legal via spot per signal pin (pad size and centre offset from the parameters file); passive gap at least 0.5 mm; no footprint in a channel or the canvas; escape test per pad within the parameterized escape distance; FAIL on a fine-pitch IC with no ring key; never writes the board. Pass: FAIL 0.
- fanout: stub and via per pin from the footprint and ring keys, DRC-aware, locked; skips exposed pads and no-connects. Pass: 0 failed pins, DRC errors at or below baseline, locked items rise by exactly the placed count.
- place_groups: snapshot, list, create, move, rotate, respace, lock, restore; refuses edge-fixed items and splitting. Pass: member distances unchanged after a move.
- quick_dru: copy of the rule files with creepage minimums zeroed, DRC with zone refill. Pass: the diff changes only creepage minimums, originals unchanged by hash.
- pass_progress: start refuses without a cap; OVER CAP marking; verdict refused without an inspect row.
- check_pours, check_routing_hygiene (proposed): corridor width, pour continuity, no unlocked wide GND track, net-less track or dangling stub.

## Sources

Sources: distilled from four prior projects of the template owner (embedded
firmware, controller PCB, vibration data analysis, CAD add-in); project records
stay in those repositories.
