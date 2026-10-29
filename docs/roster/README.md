# Roster

Opt-in department agents for engineering projects: leads that plan, review
and decide, and specialists that each produce one kind of artifact. Nothing
here is installed by default. A project picks roles at start (Q7) or copies
them by hand (ADR 0005).

## Status and rules

- New roles with no project evidence yet, except where a role's Evidence
  line says it carries one product film project's evidence (the CG render
  department and the CG additions to the creative roles, ADR 0007). Each
  checklist is senior judgment, not learned practice; the first project
  that uses a role revises it and records what it caught. A role graduates
  to a profile or the library by the rules in `docs/library/README.md`.
- `scripts/lessons.sh check` requires each Codex twin to equal its `.md`
  body (only the read-only line may use the sandbox wording) and every
  backticked agent name in a Hand-offs section to be a shipped agent.
- Every role works inside the template's orchestration (kernel rule 16):
  the main session is the advisor and records verdicts; no role commits,
  pushes, orders, purchases, publishes, signs, or contacts suppliers,
  laboratories or customers (kernel rule 15).
- Evidence before claims (kernel rule 14): units and a source with every
  figure; UNKNOWN is never a reassurance; a simulation, prediction or plan
  is never reported as a measurement or test.
- A lead is read-only and ends with a verdict
  (`APPROVE | APPROVE WITH CHANGES | HOLD`, or `GO | NO-GO` at a gate). A
  specialist writes only its named folder and reports files written, checks
  run with verbatim results, and open items.

## Adopting a role

1. Copy `agents/<name>.md` to `.claude/agents/` and `agents/<name>.toml` to
   `.codex/agents/` (copy, never move); check the tier per
   `docs/rules/models.md`.
2. Record the adoption in Project decisions (role, date, reason). A
   specialist's folder is created with its first artifact.
3. Adopt the roles a role hands off to, or note which hand-offs go to the
   advisor instead. Each agent's Hand-offs section names them exactly.
4. `scripts/lessons.sh check` validates the shipped files here and the
   Codex parity rule after the copy.

## Roles already covered elsewhere

| Asked for | Use |
|---|---|
| Senior electronics and electrical engineer | `docs/profiles/hardware-pcb/agents/senior-ee-reviewer` (also the roster's senior electrical engineer) |
| Research specialist | `docs/library/agents/researcher` |
| Component selector (adversarial check) | `docs/profiles/hardware-pcb/agents/component-reviewer` |
| PCB DFM, board review, board safety | `pcb-dfm-checker`, `pcb-reviewer`, `pcb-safety-analyst` in the hardware-pcb profile |
| Scripts and articles | `docs/library/agents/writer` |

## Departments

### Leadership and programme

| Agent | Kind | Tier | Writes | Role |
|---|---|---|---|---|
| `rd-director` | lead | strong | none (read-only) | Director of R&D who owns technical strategy, the portfolio, stage-gate GO / NO-GO decisions (concept, feasibility, design freeze, pilot, release), technical risk appetite, build-versus-buy and resourcing calls |
| `senior-project-manager` | specialist | standard | `docs/plan/` | Senior project manager who writes the project plan as a dependency graph, the critical path, milestones, the risk register, planned-versus-actual status reports and change requests, in docs/plan/ |
| `design-lifecycle-manager` | specialist | standard | `docs/changes/` | Configuration and change-control manager who writes the revision scheme, baselines, engineering change requests and orders (ECR / ECO) with impact analysis, effectivity, obsolescence watch and release records tied to git tags, in docs/changes/ |
| `systems-engineer` | specialist | standard | `docs/requirements/` | Systems engineer who writes needs, requirements, interface control documents, the verification cross-reference matrix and the system budgets (mass, power, cost, error) with full traceability, in docs/requirements/ |

### Mechanical and product

| Agent | Kind | Tier | Writes | Role |
|---|---|---|---|---|
| `senior-mechanical-engineer` | lead | strong | none (read-only) | Senior mechanical engineer who leads engineering analysis and mechanism design review - load paths, hand calculations, safety factors against the governing failure mode, materials, joints, bearings, functional tolerances, thermal growth, vibration, sealing and maintainability |
| `senior-design-engineer` | lead | strong | none (read-only) | Senior design engineer who leads detailed CAD and drawing quality - GD&T per ASME Y14.5 or ISO 1101, datum schemes, tolerance stack-ups, default tolerances, fits, drawing completeness, model-to-drawing agreement, assembly sequence and part count |
| `simulation-analyst` | specialist | standard | `analysis/simulation/` | CAE specialist who runs and documents FEA, CFD, thermal and modal analyses with the question stated first, mesh convergence, justified loads and boundary conditions, and validation against a hand calculation or test |
| `product-designer` | specialist | standard | `docs/product/` | Product designer who writes user and stakeholder needs, use scenarios, product requirements in user terms, usability and misuse analysis, accessibility, service and installation journeys, and prototype test plans with real users |
| `industrial-designer` | specialist | standard | `docs/industrial-design/` | Industrial designer who writes form, ergonomics, CMF (colour, material, finish), control and label hierarchy, brand language, sketch and render briefs, and the design-intent hand-off to mechanical as surfaces and constraints with draft and parting lines considered |
| `dfm-specialist` | lead | strong | none (read-only) | Design-for-manufacture-and-assembly lead for mechanical parts who reviews process-specific rules (injection moulding, sheet metal, machining, additive, casting), DFA, cost drivers and tolerance cost |

### Electrical, electronics and firmware

| Agent | Kind | Tier | Writes | Role |
|---|---|---|---|---|
| `senior-pcb-designer` | lead | strong | none (read-only) | Senior PCB layout lead who sets and reviews the layout strategy before and during layout - stack-up and impedance, placement by function and current loop, return paths, high-current and high-voltage copper, decoupling, thermal copper, connectors, test points and routability |
| `component-selection-engineer` | specialist | standard | `docs/components/` | Component selection specialist who sizes, selects, substitutes or re-rates an electrical part by running the hardware-pcb component-selection skill (coupling sweep, power-branch calculation, derating, options with side effects, pre-wired and pigtail variants) and writes the selection note |
| `sourcing-lead` | lead | strong | none (read-only) | Supply-side lead who reviews whether a BOM can be bought and kept buildable - lifecycle, lead time, stock depth at two or more distributors, second sources and drop-in alternates (pin, footprint, electrical and firmware compatibility), cost at volume breaks, counterfeit risk and last-time-buy |
| `firmware-lead` | lead | strong | none (read-only) | Firmware architecture and review lead for microcontroller code that drives physical outputs - non-blocking state machines, safe states through reset, boot and fault, watchdog strategy, rollover-safe timing, settings split, logging, host simulation before bench, and version and release discipline - and co-owner of the hardware and firmware interface (pin map against netlist) |
| `mechatronics-integration-lead` | specialist | standard | `docs/integration/` | Mechatronics integration specialist who writes the interface control records (mechanical, electrical, data, software, thermal, one owner per interface), the integration and bring-up sequence, actuator and sensor sizing against the mechanism load, timing budgets, harness routing and end-to-end integration tests |

### Quality, safety and production

| Agent | Kind | Tier | Writes | Role |
|---|---|---|---|---|
| `qa-lead` | lead | strong | none (read-only) | Quality lead who owns the project quality system - quality plan, inspection and test plans per stage, measurable acceptance criteria, nonconformance with root cause and CAPA, first-article inspection, supplier quality, document control and the release quality gate |
| `test-validation-lead` | specialist | strong | `docs/test/` | Verification and validation specialist who turns each row of the verification matrix into a test plan with pre-registered pass criteria, sizes samples, specifies rigs and instrument uncertainty, stages EVT, DVT and PVT and environmental testing, and records results with the scientific-integrity status words, in docs/test/ |
| `reliability-engineer` | specialist | strong | `analysis/reliability/` | Reliability specialist who writes DFMEA and PFMEA (IEC 60812), fault trees for the top hazards, the derating policy, labelled MTBF predictions, accelerated life test plans, wear-out and maintenance analysis and field failure feedback, in analysis/reliability/ |
| `safety-compliance-lead` | lead | strong | none (read-only) | Product safety and regulatory lead - hazard analysis and risk reduction per ISO 12100, functional safety of control functions (ISO 13849-1, IEC 62061 or IEC 61508), electrical safety and EMC per target market, restricted substances, labelling, the technical file and the certification path |
| `manufacturing-engineer` | specialist | standard | `docs/manufacturing/` | NPI and production specialist who writes the process flow, work instructions, fixture and jig specifications, end-of-line test station limits, torque and inspection points, pilot build and yield records, rework rules, ESD and handling, traceability and labour time, in docs/manufacturing/ |
| `technical-writer` | specialist | standard | `docs/manuals/` | Technical writer for user, installation, service and assembly documentation, task-based and versioned against the release, with warnings ordered by severity in the safety-compliance-lead's wording, in docs/manuals/ |

### Creative and video

| Agent | Kind | Tier | Writes | Role |
|---|---|---|---|---|
| `art-director` | lead | strong | none (read-only) | Art director who sets and guards the visual direction of a video or visual deliverable (product demo, build log, explainer, test-footage reel, training video) - brief, style frames, palette and grade intent, typography, composition, motion and accessibility - and approves the storyboard and the cut against the brief |
| `senior-video-editor` | specialist | standard | `edit/` | Senior video editor who builds the cut from the approved brief, storyboard and footage log - assembly, rough and fine cut, edit decision list or timeline export, audio, captions and platform versions - writing only under edit/ |
| `storyboard-specialist` | specialist | standard | `storyboards/` | Storyboard specialist who turns an approved script and brief into a numbered shot list and storyboard - framing, angle, movement, duration, action, audio, on-screen text, transitions, coverage, B-roll - and states which shots exist in the footage log and which must be filmed, writing only under storyboards/ |
| `footage-analyst` | specialist | standard | `footage-logs/` | Footage analyst who logs raw video and audio without modifying it - ffprobe technical metadata, SHA-256 per source file, optional scene-change detection and thumbnails, timecoded technical defects and content tags from what is visible or audible - writing only under footage-logs/ |
| `video-direction-reviewer` | lead | strong | none (read-only) | Fresh-context video reviewer who evaluates a storyboard or a cut against the brief and the art direction - opening, single message, pacing and runtime, shot variety, continuity, audio, captions, accessibility and the factual accuracy of every engineering claim shown or said - and returns timecoded findings with a verdict |

### CG render (product stills, animation and film)

Run with the library `product-render` procedure and tools
(`docs/library/procedures/product-render.md`, ADR 0007). Render job state
lives in `.work/jobs/render/` (gitignored, `docs/procedures/longjob.md`);
frames, caches and videos live outside the repo and outside cloud-synced
folders. Evidence: one product film project for the roles marked one-project.

| Agent | Kind | Tier | Writes | Evidence | Role |
|---|---|---|---|---|---|
| `render-technical-director` | lead | strong | none (read-only) | one-project | Owns the render pipeline and quality bar - pinned portable Blender, colour management, check / preview / final presets, samples, denoise and seed policy, time budget per frame, determinism, folder layout - and gives GO / NO-GO before any preview or final with a measured time and cost estimate |
| `render-research-lead` | lead | strong | none (read-only) | new | Runs the research team with bounded briefs for `researcher`, merges reports into the recommendation table, spot-checks citations, and decides what to research next when a shot is not good enough |
| `animation-adversarial-reviewer` | lead | strong | none (read-only) | new | Fresh-context reviewer that sees only frames, sheets, tool numbers and the brief, never scripts, and tries to break the animation: stops, jerks, overshoot, pops, intersections, impossible physics, scale, flicker, label flips, timing, liquid realism |
| `cold-viewer` | lead | standard | none (read-only) | new | Shown only the finished film's frames with no brief, states in one sentence the message it took away; the advisor compares it with the brief |
| `blender-operator` | specialist | standard | `render/scenes/` | one-project | The only agent that edits scene scripts, .blend files and presets and runs Blender, always through `blender_run`; one operator at a time; never starts a preview or final without a recorded GO |
| `cad-asset-preparer` | specialist | standard | `render/assets/` | one-project | CAD to render meshes: export, units, part names, tessellation, bevels, placements, fit checks with clearances at every keyframe state, scale against real dimensions |
| `lookdev-artist` | specialist | standard | `render/lookdev/` | one-project | Materials from the CMF hand-off and real reference photos, the material library, turntable check stills per material |
| `cinematographer` | specialist | standard | `render/layout/` | one-project | Lighting rigs and camera paths: monotone splines through waypoints, lenses, depth of field, the never-fully-stop rule, safe areas for text |
| `animator` | specialist | standard | `render/anim/` | one-project | Mechanism motion from CAD kinematics and the real part's behaviour, timing curves, label track anchoring |
| `fx-simulation-artist` | specialist | strong | `render/fx/` | one-project | Liquids, cloth, paper and particles: solver choice, the simulation ladder, bakes as long jobs, cache validation by numbers, thin-feature rebuilds, a hand-off of what the sim can and cannot show |
| `render-wrangler` | specialist | cheap | `.work/jobs/render/` | one-project | Queues chunked renders and bakes as resumable long jobs, chains them, audits frame counts, reports measured s/frame and ETA, checks GPU use, estimates cloud cost on request |

The brief's `render/jobs/` folder for the wrangler moved to
`.work/jobs/render/`, where the longjob procedure keeps STATE files. The
CG additions in `art-director`, `storyboard-specialist`,
`video-direction-reviewer`, `senior-video-editor` and `industrial-designer`
carry the same one-project evidence; brand and typography stay with
`art-director`, and music and sound licences are recorded by
`senior-video-editor` until a film with audio needs a sound role.
