# Profiles

A profile is a bundle a project selects at start. It carries what a project
type needs beyond the software baseline: rules to promote into the AGENTS.md
rules index, gates to wire into `scripts/check.sh` and CI, tools to install or
build, playbooks, an agent and skill set, parameters and record conventions,
and additions to the definition of done. Profiles hold learned practice from
real projects; each rule states the failure it prevents.

## Profiles

| Profile | Folder | Select when |
|---|---|---|
| software | `docs/profiles/software/` | Always on. Every project gets it. |
| scientific | `docs/profiles/scientific/` | Numbers, models, experiments, or validation claims are produced. |
| embedded-firmware | `docs/profiles/embedded-firmware/` | Code runs on a microcontroller that drives physical outputs. |
| hardware-pcb | `docs/profiles/hardware-pcb/` | A printed circuit board or electronics design is a deliverable. |
| data-analysis | `docs/profiles/data-analysis/` | Raw instrument files or logs are imported and analysed. |

## How start selects profiles

1. `docs/procedures/start.md` question 7 (risk profile) is answered with a list,
   not one value. `software` is added without asking; every other profile
   stacks on top of it.
2. Mapping from the answer: scientific/numerical adds `scientific`;
   embedded adds `embedded-firmware`; safety-sensitive adds the profile of the
   hardware involved (`embedded-firmware`, `hardware-pcb`, or both) and
   `scientific` if a claim is quantitative; a project that imports test logs
   adds `data-analysis`. When the answer is unclear, start asks one follow-up.
3. For each selected profile start, in order: copies its Rules into the
   AGENTS.md rules index as one line per rule file or ID range (the 180-line
   budget holds); wires every Gates row into `scripts/check.sh` and
   `.github/workflows/ci.yml`; turns each Tools row marked `build` into a
   BACKLOG item; scaffolds the Parameters and records files; copies
   the Done means list into the Project decisions section of AGENTS.md.
4. The selection is recorded in Project decisions as one line,
   `Profiles: software, scientific, ...`. A test can check that every name in
   that line has a folder here and every folder named has its gates wired.
5. A profile gate that cannot run on this machine is logged in
   `START_REPORT.md` with the reason. A gate is never wired as a no-op.
6. Stacking rule: when two profiles state different thresholds for the same
   thing, the stricter one applies. No profile may weaken a kernel rule or a
   `software` rule.

## Profile file contract

Every `PROFILE.md` has these sections, in this order, with these exact
headings: Purpose and risk; Rules; Gates; Tools; Playbooks; Agents and skills;
Parameters and records; Done means; Lessons carried in; Sources.

- Length is 60 to 160 lines. Longer material goes in a sibling file linked
  from Playbooks (for example `hardware-pcb/LAYOUT_PROCESS.md`).
- Each rule has an ID (`SW-n`, `SC-n`, `FW-n`, `PCB-n`, `DA-n`) and is one
  sentence a script or a test could enforce. A rule with no mechanical form
  says so in its Gates row as `review`.
- Each Gates row names the command, the pass criterion, and the profile rule
  it enforces. Wiring lines are shell commands, not prose.
- Each Tools row is marked `exists` (a named CLI or MCP server, with install
  check) or `build` (a tool spec with inputs, outputs, exit codes 0 pass, 1
  fail, 2 could not run). A tool taken from a prior project is labelled
  `exists in <kind of prior project>, port on adoption`.
- Defect patterns: the recurring-defect checklist a profile gives to
  `docs/procedures/bughunt.md`, kept under Playbooks (or Rules), one pattern per
  line, each mappable to a trace test or hunt. A profile that lists none says so
  and points at the generic hunts of bughunt.md steps 2 and 3.
- Lessons carried in state the lesson as a generic rule; incident specifics
  that would identify a source product are not shipped. Figures that were not
  verified are labelled `unverified`.
- Sources is one fixed line: distilled from four prior projects of the template
  owner (embedded firmware, controller PCB, vibration data analysis, CAD
  add-in); project records stay in those repositories, with no paths.
- Text uses plain hyphens only; the no-dash check of the software profile
  applies to profile files too.

## Proposing a change back

A project that learns something a profile should have said writes the proposal
under `docs/lessons/PENDING.md` as what happened, what check should have caught
it, what was added, and retire-when, then follows `docs/procedures/upstream.md`
to send it to the template. The proposal names the profile, the section, the
rule ID to add or amend, the evidence (a test, ledger row, or log), and the
gate that enforces it. A project never edits its synced copy of a profile
silently; local deviations are recorded in Project decisions.

## Adding a profile

New profiles need two real projects of evidence, the ten sections, and one
gate that a fresh project can run on day one. Add the folder, a row in the
table above, and the `docs/BLUEPRINT.md` tree entry in the same change.
