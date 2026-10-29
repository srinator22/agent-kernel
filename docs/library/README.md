# Library

Optional, opt-in agents, skills and procedures that carry evidence from one
prior project. Nothing here is installed by default and nothing here is part of
a profile. A project copies an item in by hand, or at start when the interview
asks for it.

## The one-project-evidence rule

- A library item has been used in exactly one prior project. It is plausible,
  not proven general.
- A profile item needs evidence from two projects. Profiles hold learned
  practice; the library holds candidates for it.
- An item enters the library only as a generic version: no names of the source
  project, its organisation, people, parts, domain or record IDs (kernel rules
  12 and 20; `docs/rules/security.md`).
- The library never overrides a kernel rule, a `software` rule or a profile
  rule. Where a library item and a profile disagree, the stricter one applies.

## Layout

    docs/library/agents/<name>.md       Claude Code agent
    docs/library/agents/<name>.toml     Codex counterpart (same name)
    docs/library/skills/<name>/SKILL.md one skill per folder
    docs/library/procedures/<name>.md   procedure a skill follows
    docs/library/tools/<tool>           generic tool; tests in tools/tests/
    docs/library/hooks/<hook>           harness hook; tests in hooks/tests/
    docs/library/examples/<name>/       worked example of a procedure (records, no outputs)
    docs/library/README.md              this file

Every tools/ and hooks/ test runs in the template self-test
(`tests/template/test_profile_tools.sh`).

## Adopting an item

1. Read the item and any procedure it names. Check its Do-not-use clause.
2. Copy files, never link them:
   - agent: `.md` to `.claude/agents/`, `.toml` to `.codex/agents/`;
   - skill: the folder to `.claude/skills/` and the byte-identical copy to
     `.agents/skills/` (check.sh compares the two trees);
   - procedure: the file to `docs/procedures/`. A skill whose body says
     "Follow docs/procedures/<x>.md" needs its procedure copied there, and
     `docs/procedures/evidence-levels.md` if it cites evidence levels.
3. Adapt the default paths named in the procedure (record folders, ID
   prefixes) in the one copied file. Choose the project's language variant and
   currency convention (local currency with the date) where an item asks.
4. Record the adoption in Project decisions (one line: item, date, reason) and
   add a Codex counterpart for every Claude agent, or record why there is none
   (`docs/rules/models.md`, parity rule).
5. Mind the caps: kernel rule 10 allows 8 core skills plus the skills the
   adopted profiles declare. The template ships 5 core skills, so up to 3
   library skills fit in the free core slots; beyond that, retire an unused
   skill first. `scripts/lessons.sh check` enforces the cap.
6. Tier per agent: set `model:` in the copied agent per `docs/rules/models.md`;
   Codex files carry no `model =` line.

## Hooks

`hooks/refuse_shell_stdin.py` is a PreToolUse hook. It refuses a shell command
that feeds Python from stdin (`python -`) or uses a here-document: both hang or
break under some shell wrappers, and the habit recurs, so a written rule is not
enough. The refusal tells the agent to write the script to a file and run it by
path. An optional rule, `--check-pcbnew-getwidth` (or
`HOOK_CHECK_PCBNEW_GETWIDTH=1`), also refuses KiCad scripts that call a bare
`.GetWidth()`; enable it only where KiCad is scripted. Check it with
`python docs/library/hooks/refuse_shell_stdin.py --self-test`.

To adopt, copy the hook to `.claude/hooks/` and add a PreToolUse entry to
`.claude/settings.json` whose matcher covers every shell the harness offers
(`Bash|PowerShell`) and whose command is
`python "$CLAUDE_PROJECT_DIR/.claude/hooks/refuse_shell_stdin.py"`.

## Tools

Run the Python tests with
`python -I -m unittest discover -s docs/library/tools/tests` and the shell
tests with `bash docs/library/tools/tests/<test>.sh`. Every tool takes
`--help` and exits 0 pass, 1 check failed, 2 could not run.

| Tool | Use |
|---|---|
| `commit_unit.py` | One safe commit path: runs a gate command, commits only the named paths from a message file, pushes, never forces. |
| `check_defect_memory.py` | Validates `docs/DEFECT_MEMORY.md`: header, IDs sequential per prefix, no empty cells, status forms, `superseded by` targets, defence paths of fixed rows. |
| `kb_index.py` | Local SQLite full-text index and ranked search over Markdown and text; PDF and spreadsheet support when `pymupdf` or `openpyxl` is installed. Keep `.kb/` out of git. |
| `fixture-guard.sh` | Fails a commit that changes a golden fixture and the code it pins together without a marker line in the body (SC-3). |
| `check-project-readmes.sh` | Requires every folder under a projects directory to have a README with the required headings. |

Render tools (`product-render` procedure; copy the whole set with
`render_common.py`). Cores are stdlib Python with a small PNG codec; Pillow
and numpy are optional fast paths that the tests prove equal to the stdlib
path, so CI needs neither. Tools marked (Blender) run inside Blender through
`blender_run`; their pure parts are tested without it.

| Tool | Use |
|---|---|
| `render_common.py` | Shared module: PNG read and write, luma, frame names, absolute-path, git-tree and cloud-folder guards. |
| `blender_run.py` | Runs a script in the pinned portable Blender headless (`--factory-startup`, `--python-exit-code 1`); fails on a non-zero exit, traceback or version mismatch; `--self-test`. |
| `render_chunks.py` | Plans and runs chunked frame ranges as a resumable long job (STATE file, one log per chunk, skips present frames); `status` reports s/frame and ETA. |
| `frame_audit.py` | Expected vs present frames per chunk, resolution, black or blank frames, fireflies, size anomalies, duplicates. |
| `render_sheets.py` | Contact sheets, zoom crops and A/B compare sheets for reviewers. |
| `render_estimate.py` | Local hours from measured s/frame; cloud cost only from a user-supplied, dated price table. |
| `render_bundle.py` | Delivery folder per version: video, exact sources, records, README of commands, verified sha256 manifest. |
| `encode_verify.py` | MP4 checks by a pure-Python box parser (frames, fps, resolution, duration, bitrate, codec); ffprobe cross-check when on PATH. |
| `render_encode.py` | (Blender) Frames to MP4 through the VSE with the overlay track; view transform a parameter (Standard for display-referred PNG). |
| `blender_compat.py` | (Blender) Feature-detected shims for 4.x to 5.x API breaks, GPU pinning with CPU off; `--list` prints the break table. |
| `blender_extract.py` | (Blender) Writes the render-extract/1 JSON (settings, lights, materials, objects, per-frame camera, bounds, anchors, volumes) the checkers read. |
| `camera_path.py` | Monotone (pchip) camera path through waypoints; `--check` finds overshoot and undeclared stops. |
| `motion_check.py` | Camera stops outside declared holds, acceleration spikes, waypoint overshoot, label side flips. |
| `scene_lint.py` | Scene settings against a named preset, units, missing textures, transparent-material samples, light power, keyed-but-hidden objects. |
| `color_check.py` | Bit depth, unexpected alpha, clipped or crushed channels, exposure pops between frames. |
| `flicker_metric.py` | Temporal instability per region in near-still windows; A/B compare for seed and denoiser choices (threshold uncalibrated). |
| `sim_validate.py` | Liquid volume against the poured target (silent under-emission), leaks, gains, particle trend, cache hash. |
| `render_overlay.py` | Label track with side consistency, safe area, overlap and title hold; writes the track `render_encode` consumes. |
| `fit_check.py` | Box-level collisions, clearances and real-dimension scale checks at every keyframe state. |

## Graduating to a profile

An item graduates when a second project has used it and its evidence is
recorded (what it caught or saved, which gate or rule it supports):

1. Move the item into the owning profile folder (`docs/profiles/<profile>/agents/`,
   `skills/`, `tools/`), keep the Codex counterpart beside it, and list it in
   the profile's Agents and skills and Tools sections.
2. Give any rule it implies a profile rule ID and a Gates row (profile file
   contract in `docs/profiles/README.md`).
3. Remove the library copy in a maintenance pass, archived with a one-line
   reason (kernel rule 11), and note the move in the upstream lessons file.

An item with no second project after a maintenance cycle stays in the library;
one that proved unhelpful is archived with its reason.

## Items

| Name | Kind | What it does | Origin (kind of project only) |
|---|---|---|---|
| engineering-reviewer | agent (read-only, inherit tier) | Fresh-context adversarial review of engineering claims: units, sources, evidence levels, recomputed numbers, registered assumptions, limitations; PASS or FAIL verdict | a hardware R&D journal project |
| researcher | agent (standard tier) | Cited research on one bounded question; every fact has a URL, date and evidence level; writes only a dated report under `docs/research/` | a hardware R&D journal project |
| writer | agent (standard tier) | Turns recorded engineering work into drafts under `articles/`; never fabricates; proposes style preferences for human approval | a hardware R&D journal project |
| light-worker | agent (cheap tier) | One small, reversible, fully specified edit covered by existing checks; never commits; stops on any judgment call | a CAD add-in project |
| explorer | agent (Codex only) | Read-only exploration for Codex; the Claude counterpart is the core `explore` agent | a CAD add-in project |
| adr | skill | Graduated to core on 2026-10-23 (lesson L010): `docs/procedures/adr.md`, the core `adr` skill and `scripts/adr.sh`. Do not adopt this copy; it is archived at the next maintenance pass (BACKLOG) | two prior projects (a software and data project, a personal project), merged |
| article | skill | Drives the editorial pipeline from idea to approved; publishing needs explicit human permission | a hardware R&D journal project |
| component | skill | Tracks a candidate part through candidate, selected, purchased, received, measured, tested with datasheet and evidence levels | a hardware R&D journal project |
| decision | skill | Logs an engineering design decision before implementation with evidence chain, dependents and revalidation marks | a hardware R&D journal project |
| experiment | skill | Pre-registers, runs and records a physical experiment with immutable hashed raw data | a hardware R&D journal project |
| evidence-levels | procedure | The E1 to E8 evidence scale, revalidation rule and the typed record ID placeholder pattern | a hardware R&D journal project |
| article | procedure | Nine-state writing and editorial workflow | a hardware R&D journal project |
| component | procedure | Part research and bill-of-materials state machine | a hardware R&D journal project |
| decision | procedure | Engineering decision log, approval, revalidation, supersession | a hardware R&D journal project |
| experiment | procedure | Pre-registration, run, process and record workflow | a hardware R&D journal project |
| refuse_shell_stdin | hook | Refuses shell commands that feed Python from stdin or use a here-document; optional KiCad `.GetWidth()` rule | a controller PCB project |
| commit_unit | tool | One safe commit path: gate, message file, pathspec-limited commit, push, never force | a controller PCB project |
| check_defect_memory | tool | Validates `docs/DEFECT_MEMORY.md` rows, IDs, status forms and defence paths | a controller PCB project |
| kb_index | tool | Local full-text index and ranked search over Markdown, text, and optionally PDF and spreadsheets | a controller PCB project |
| fixture-guard | tool | Fails a commit that changes a golden fixture and the code it pins without a marker line (SC-3) | a hardware R&D journal project |
| check-project-readmes | tool | Requires a README with the required headings in every project folder | a CAD add-in project |
| product-render | skill | Drives the staged CAD-to-film pipeline with four hold points and verified output | a product film project |
| product-render | procedure | Stages 0 to 9, stage record, Blender and GPU gates, lessons map; uses the render roster roles (ADR 0007) | a product film project |
| render tools | tools | The 19 render tools above, with tests | a product film project (ports where marked in each header; the rest new) |
| product-render-sample | example | Primitive-only scene taken through every stage, with its records | new (template demonstration) |

## Considered and not ported

| Candidate | Reason |
|---|---|
| wrap-up and session skills | The core `retro` procedure already updates the backlog and moves task state to `.work/done/`, and `scripts/session-context.sh` already reloads context at session start; a diary or session-log layer would duplicate both and add a second memory tier (kernel rule 8). |
| bugfix skill | `docs/procedures/bugfix.md` already carries the generic steps (reproduce, owning layer, failing test first, smallest fix, review, ship). The other versions only added a hand-written changelog entry, which conflicts with kernel rule 18 (generated changelog). |
| changelog generator and name-brainstorming skills | Third-party, unlicensed, redistribution not permitted. |
| no-dash and secret-scan scripts | `scripts/check.sh` already fails on en and em dashes, and its gitleaks step is mandatory (kernel rule 12); the scripts were a Node wrapper and a scan that passed when gitleaks was missing. |
| skill-structure checker | Its generic part (frontmatter, name equals folder, mirror, cap) is in `scripts/lessons.sh check`; the rest named one project's skills. |
| core agent variants (reviewer, worker, monitor, explore) | Their generic improvements were approved on 2026-10-23 and applied to the core agents (lessons L001 to L007 in `docs/lessons/INDEX.md`). |
| run-log analysers, firmware host simulator, board routing and placement scripts | Mostly one product's data and log schema; profiles list them as `port on adoption`. |
