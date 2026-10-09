# Profile: embedded-firmware

## Purpose and risk

For code on a microcontroller that drives physical outputs (gates, motors,
fans, actuators) and logs to storage. Risk: models and source-text pins
describe the firmware but do not run it, so defects that live between the code
and a library, a timer, or a pin level survive to the field; unproven hardware
is coupled to proven code; a field machine cannot be rolled back to a known
build. Promote the hardware rules here into the AGENTS.md rules index.

## Rules

- FW-1 The real preprocessed sketch (or firmware source) is compiled for the
  host against fakes of the core and each library and executed; models and
  source-text pins are supplementary, never the only test.
- FW-2 No `#ifdef HOST` or simulator define is tested in firmware source; a
  check greps for it. The define exists for the fakes only.
- FW-3 Fakes reproduce the library's failure behaviour (timeouts, sticky write
  error, bus timeout flag, pulse limits, wraparound); each fake names the real
  source it mirrors and has a test pinning the modelled semantics.
- FW-4 Time is virtual and deterministic: the clock advances only when the
  firmware reads or waits, and a start-time option tests rollover.
- FW-5 The world is a JSON scenario (inputs over virtual time, replayable by
  hash); the simulator emits a trace of every pin, PWM, display, serial, file
  and interrupt event with its virtual time.
- FW-6 The oracle (documented behaviour, each assertion with the document it
  enforces, numbers read from the settings headers) is written before the
  tests; an ambiguous document is listed as `ORACLE?` and asserted only after
  the document or firmware is corrected.
- FW-7 Tests assert documented contracts on the trace, never internal
  variables; every behaviour change ships with a scenario, and a fix without
  one is incomplete.
- FW-8 Fault sweeps place each fault at every step of a complete run; a seeded
  fuzzer composes scenarios; a scenario that broke an invariant is kept under
  `scenarios/` with the finding ID in its file name.
- FW-9 The gate has a coarse default and a thorough mode (environment
  variables for sweep step and fuzz seed count) run before a release and after
  any fault-handling change.
- FW-10 A missing toolchain (arduino-cli, host C++ compiler) fails the gate; it
  never skips.
- FW-11 Every simulator limit is stated with a follow-up: electrical (rails,
  brown-out, reset pin levels) to bench list; mechanical motion to a feedback
  sensor or bench; real card and display timing to a measurement; 16-bit `int`
  to a source check and a 32-bit-`long` build assertion.
- FW-12 Settings are an exact-match contract; a value expected to change at the
  bench is declared tunable with a contract value, min and max. In range is a
  note, out of range fails, and a derived safety relation fails. Adding a
  tunable is a recorded decision, never a way to clear a gate.
- FW-13 When two firmware lines share code, a dual-fix rule applies: a fix to
  shared behaviour lands in both in the same change or is recorded not
  applicable with the reason; a contract test pins the shared functions
  textually identical after normalisation; shared tabs are byte-identical
  copies with a copy test; the fork commit is recorded.
- FW-14 Every released version has an annotated `<variant>-vX.Y.Z` tag whose
  commit carries matching VERSION and in-code version, and a
  `releases/<variant>/vX.Y.Z/` archive (binary, SHA256SUMS, BUILD_INFO);
  exceptions are explicit exact pairs, never patterns.
- FW-15 The code version is in the display and the first line of every log;
  `INSTALLED.md` records what runs on each machine, so rollback is upload of an
  archived binary, with no git archaeology.
- FW-16 Firmware is never uploaded without explicit instruction.
- FW-17 Software cannot control pins during reset or bootloader; external
  fail-safe biasing is required, and the pin state under reset is measured.
- FW-18 Inactive output levels are preloaded before `pinMode(..., OUTPUT)`.
- FW-19 Timing is rollover-safe: `now - start >= duration`; timers anchor after
  the physical event, with a fresh clock read after any blocking call.
- FW-20 A command is not feedback: every powered segment is supervised by fresh
  feedback, never-started and stale-after-start are separate states, and a
  failure latches a fault and forces safe idle.
- FW-21 Every blocking bus or storage operation is bounded, and every stream
  write is guarded by the error flag so a stalled device costs one timeout.
- FW-22 Every fault path carries a reason code that reaches the log and display.
- FW-23 State machines are non-blocking except one declared blocking routine;
  button and stop requests are serviced inside it.

## Gates

One gate script runs the rows in this order; quick stops after the static rows,
full adds scenarios, sweeps, exports and builds. Commands are placeholders the
project supplies.

| Gate | Command (wire in check.sh and CI) | Pass | Rule |
|---|---|---|---|
| Repository, settings and wiring contracts | `<contract-check>` | exit 0 | FW-12 |
| Fakes tests and sketch lint (no host define) | `<sim-runner> --fakes-test` and `grep -rnE "#ifdef HOST" <firmware-src>` | exit 0, no match | FW-2, FW-3 |
| Model, logging, run-numbering, runtime-safety, dual-fix tests | `<test-runner> models` | exit 0 | FW-13 |
| Version sync, release tags and archives (git reads only) | `<release-tag-check>` | exit 0 | FW-14 |
| Simulator scenarios per variant (full) | `<sim-runner> --scenario <file>` | exit 0, trace assertions hold | FW-6, FW-7 |
| Sweeps and seeded fuzzer (full) | `<sim-runner> --sweep --fuzz-seeds <n>` | invariants hold | FW-8, FW-9 |
| Target build and diagnostic builds (full) | `arduino-cli compile --fqbn <board> <sketch>` or the project build command | exit 0, memory reported | FW-1, FW-10 |
| Working version tagged (release flow) | `<release-tag-check> --require-current` | exit 0 | FW-14 |

## Tools

- arduino-cli, host C++ compiler (g++, clang++ or the ziglang package):
  `exists`; install check `--version`; absent means gate failure.
- Host simulator (build, fakes, world, scenario loader, runner), release gate
  script, release tag checker, release archive script, configuration contract
  checker with tunables: `exists in a prior embedded controller firmware
  project, port on adoption`.
- Run-log analysers (see data-analysis profile): `build` per log schema.

## Playbooks

- Full review passes: settings, pin map, every state entry and re-entry, fault
  exits, physical event order, feedback freshness, logging, test-mode
  isolation, clean-clone build.
- Recurring defect checklist, run on every change; each maps to a trace test:
  1. timestamp taken before a blocking call (refresh the clock after it);
  2. button classified at release, not at the press edge;
  3. button held at boot (consume first release, require a fresh press);
  4. latched flag never cleared on recovery;
  5. startup state not applied until debounce completes;
  6. enum states unreachable after a refactor;
  7. fault path with no reason code;
  8. asymmetric error tolerance (one lost request latches, one lost reply does not);
  9. stream writes not guarded by the error flag;
  10. file identity proven by the name, not by a header line.
- Field rollback and release: `docs/procedures/ship.md` plus archive step.

## Agents and skills

- Reviewer with fresh context on every behaviour change; a coder owns one
  firmware file at a time; the host simulator replaces bench for sequencing.
- Skills: bug-review, release-manager, test-data-analyst, electronics-docs,
  memory-keeper (`exists in a prior embedded controller firmware project`);
  each counts against the cap once the profile is adopted.

## Parameters and records

- Settings split by question: how fast or hard, how long or how often, and the
  sketch for hardware identity; settings live in headers, never extra tabs.
- Contract file per variant with `settings`, `tunable_settings`, derived relations.
- Defect memory, open investigations, CHANGELOG per variant, INSTALLED.md.

## Done means

- Scenario for the change, sweeps green, tags and archive present, bench
  list updated with what the simulator cannot prove, defect row added.

## Lessons carried in

- Models passed while a storage stall lived in library behaviour; only the
  compiled firmware against faithful fakes showed it.
- Tunable bench settings with no range trained the gate to be ignored; a
  contract value with min and max keeps the gate meaningful.
- A fix landed in one firmware line only was a defect in the other line.
- Rollback needed git archaeology; archived binaries and an installed-version
  record remove it. A first day of host simulation found many firmware
  findings that bench tests and models had not.

## Sources

Sources: distilled from four prior projects of the template owner (embedded
firmware, controller PCB, vibration data analysis, CAD add-in); project records
stay in those repositories.
