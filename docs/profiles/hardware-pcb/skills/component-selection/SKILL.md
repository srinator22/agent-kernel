---
name: component-selection
description: Select, size, substitute or re-rate an electrical component (capacitor, fuse, wire, connector, converter, supply, motor, driver, switch, relay, sensor) and present options with their side effects. Use before recommending any part or value, when a part changes for a convenience reason (terminals, size, stock, price), and whenever an operating limit that sized a part changes. Do not use for pure firmware logic or for a whole-box or BOM sign-off (use box-design-review).
---

# Component selection

A part is never chosen alone. Every value pushes on the parts around it: a
bigger capacitor is a bigger charge pulse through the fuse, a higher current
limit is a hotter fuse and wire, a smaller can is less ripple rating. This
skill makes those couplings explicit before the recommendation, not as a
buried bench "confirm" afterwards. Rules: PCB-2, PCB-10, PCB-12.

Origin case (generic): a bulk capacitor was enlarged only because a
screw-terminal can was wanted. Nobody restated the charge pulse, the
fast-acting fuse in front of it was sized on steady-state current alone, an
unpublished converter "soft start" was used as reassurance, and the fuse blew
at the first cold power-up. Later the drive's phase-current limit was raised
and nothing re-checked the fuse sized from the old limit.

## Procedure

1. **State the job and the sizing basis.** What the part must do, and every
   number that sizes it, each with its source: datasheet clause, firmware
   setting, a value commissioned into a driver's nonvolatile memory or a bench
   build, a measurement, or `UNKNOWN`.
2. **Coupling sweep.** List every part upstream and downstream whose rating or
   behaviour this choice changes, and every part whose sizing basis this
   choice depends on. Use the class checklists below; tick or answer each line.
3. **Disposition every manufacturer recommendation.** List each piece of
   design advice in the datasheets and manuals of the parts involved (bulk
   capacitance, zener or suppressor, regulated supply, cable length, ripple,
   heatsinking) and state for each: applied, not needed because, or open. A
   recommendation nobody evaluated is a finding; a suppressor suggested in a
   driver manual and never weighed by any review is the typical miss.
4. **Unknowns stay unknown.** Never use an unpublished behaviour (soft start,
   current limit, overshoot, internal capacitance) as a reassurance. Write it
   as `UNKNOWN`, say what failure it could hide, and name the measurement or
   the design margin that makes the choice safe without it.
5. **Calculate, do not assert.** For any power branch run the power-branch
   calculator (`check_power_branch <branch file> --strict`, shipped in this
   profile's `tools/`); running it is mandatory, not optional. Its `FAIL` and
   `UNKNOWN` lines go into the recommendation verbatim. Hand arithmetic (I2t,
   derating, window, every input's source) is a supplement for a case the
   tool does not model, never a substitute; exit 2 (could not run) stops the
   recommendation until it runs.
6. **Give options, not a verdict.** At least two realistic options,
   recommended first, in the output format below. A convenience substitution
   (terminals, size, stock) is presented as an option with its electrical cost
   stated.
7. **Adversarial review before presenting.** Dispatch the
   `component-reviewer` agent with the draft; where agents are unavailable,
   re-read the draft as a hostile reviewer against the checklists. Fold its
   findings in or say why each is rejected (PCB-17). A subagent cannot
   dispatch another agent: when you are one, do your own hostile re-read, say
   so in the report, and the advisor runs the reviewer on your draft before
   the owner sees it. A self-review never replaces that pass.
   - **Fetch documents from the command line, never a browser pane shared with
     the user**: opening a document link there can pop a save dialog on the
     user's screen. Download into a scratch directory and extract text (for
     example `pdftotext -layout`); a site that refuses is reported as UNKNOWN,
     not worked around. Published documents only; never contact a supplier.
   - **Requirements before candidates.** For anything larger than one part (a
     rail, a supply chain, a BOM), write the requirements first: operating
     profile, loads with sources, shall and should items, unknowns with the
     measurement that closes each, ranking order; then score every option
     against them in a compliance matrix.
   - **Brief research and review agents on the whole branch, not the question
     of the moment.** A brief that asks only "is the fuse right" gets a fuse
     answer; every brief also asks what else on the branch can fail and for
     the disposition of every manufacturer recommendation (step 3).
8. **Record the sizing basis** next to the part in the BOM or wiring guide
   ("sized from X = value, source"), so a later change to X is visibly a
   re-sizing trigger. A part choice is a logged decision (decision-logger).

**Re-sizing trigger.** When any operating limit changes (current limit, speed
target, supply voltage, duty, ambient), search the documents for parts sized
from it and re-run this procedure for each, before the new limit is used under
load. A limit may live in firmware, in a driver's nonvolatile memory or in a
bench build; check every place it can be set.

## Class checklists

**Capacitor (bulk, decoupling).** Voltage rating against rail maximum plus
converter overshoot and regeneration, at least 1.25x for electrolytics; ripple
current at the real frequency; temperature class and life at the enclosure's
real temperature; ESR; charge pulse `Q = C V` into the upstream fuse and
source (step 5); whether the source can sink energy (a boost cannot); bleed
and discharge time for service safety; mounting (clamp, not leads), polarity
marking, physical fit with the lid closed.

**Fuse.** It protects the **wire and the source**, not the load: rating at or
below the smallest conductor's ampacity and the holder's rating. Continuous
current at most about 75 percent of rating at 25 C, less when hot (use the
maker's temperature rerating curve). **Fast-acting versus time-delay against
the load's pulses:** capacitor charge, motor start, stall, acceleration at the
current limit; compare each pulse's I2t with the fuse's melting I2t after the
maker's pulse-cycle derating. Find the binding constraint before choosing the
type: a time-delay fuse fixes inrush only, and may not exist in the holder's
format at all. Sustained current against the datasheet's minimum opening
times, not only I2t. Wire protection against the fuse's standard test cable
(for blade fuses, ISO 8820-3). Holder run at no more than the maker's derating
(often about 60 percent of its rating). A clamp (TVS, zener) that conducts
holds the fuse under sustained current. DC voltage and interrupting rating at
the rail, including overshoot. Sized from which current limit, and where does
that limit live. **Live insertion** of a fuse or connector is the stiff-source
case: the source's own output capacitance dumps into the empty bulk capacitor.

**Motor and driver supply current.** Phase current is not supply current; a
PWM driver bucks, so supply current is roughly mechanical power plus losses
over supply voltage. Worst cases are acceleration at the current limit near
top speed, stall, and regeneration on a stop; stall draws little from the
supply. Peak versus RMS, and the time each lasts. Without a measurement, size
from the driver's published maximum supply current, cited by manual revision
and table.

**Wire and connector.** Ampacity in a bundle inside a closed box, voltage drop
at peak current, crimp and housing gauge range, pre-wired or pigtail and
solder-free versions (PCB-10), mating parts, contact rating per pin for the
real current.

**Converter or supply.** Continuous and peak output current, current-limit
behaviour (hiccup, foldback, constant current, none), soft start, output
overshoot at start and load release, ability to sink, input current at full
output, shared budget with other loads, behaviour into a large capacitive
load. A non-synchronous boost passes its input straight through inductor and
diode at power-up: the output capacitor charges to about the input voltage
with no soft start, limited only by the upstream supply. Short-circuit
behaviour decides whether a downstream fuse can ever clear (foldback below the
fuse rating means it never opens).

**Overvoltage and regeneration (zener, TVS, brake chopper, surge stopper).**
Name the source of the overvoltage first, because the fix differs:
- load-side regeneration is energy-limited (`E = 1/2 J w^2` of rotor plus
  load) and wants a shunt: bulk capacitance, or an active clamp (a precision
  shunt reference or comparator, for example the generic TL431 class,
  switching a MOSFET into a power resistor, which is a brake chopper);
- source-side overshoot is limited only by the source's current, for as long
  as it lasts, and wants a series element (surge stopper, eFuse) or a better
  source. A shunt clamp there fights the source's whole output and overheats
  or blows the fuse.

**Window check before any passive clamp:** it must not conduct at the rail
maximum (standoff at or above it, tolerance included) and must hold below the
load's absolute maximum **at the current it will carry**. A TVS clamps at
roughly 1.4 to 1.6 x its standoff; a power zener rises by its dynamic
impedance times the current. When load maximum over rail maximum is under
about 1.3, no passive zener or TVS protects the load; say so and offer the
active clamp or the series stopper.

**Switch, relay, MOSFET, H-bridge.** DC rating (much lower than AC), inductive
load and flyback path, inrush of the load, control logic level and fail-safe
state during reset (PCB-9).

**Sensor.** Supply and logic level, output type, pull-up location, cable
length and noise, fail-safe reading on a broken wire.

## Output format

```
Job: <one line>
Sizing basis: <number, source> ...
| Option | Part(s) | What it fixes | Side effects / couplings | Re-check | Cost, stock, pre-wired |
Recommended: <option> because <reason>; rejected: <option> because <reason>
Unknowns: <item: what it could hide, how resolved>
Watch at first power-up / first stop / first fault: <measurements>
```

Report every `FAIL` and `UNKNOWN` from the calculator. Never call a part
"verified" from a supplier maximum; installed capacity is measured.
