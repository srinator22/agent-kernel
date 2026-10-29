# Product render - CAD to an approved, verified still set or film

Adopt by copying this file to `docs/procedures/product-render.md`, the
`product-render` skill (`docs/library/skills/product-render/`), the render
roles from `docs/roster/agents/` and the render tools from
`docs/library/tools/` (copy the whole set, with `render_common.py`, to
`tools/render/` and its tests to `tools/render/tests/`; paths below use that
location). Origin: a product film project (a still-render set and a one-shot
film of a transparent plastic product with a liquid-pour demo); one-project
evidence, so every step is plausible, not proven general. Facts about tools
and versions come from `docs/research/2026-10-29-render-recommendations.md`
(VERIFY 2026-10-29). A worked example on a primitive scene is in
`docs/library/examples/product-render-sample/`.

## Record these in Project decisions before stage 0

- Pinned Blender: version and portable path, in
  `render/scenes/blender.lock.json` (`{"version", "path", "sha256"}`); the
  default is the current LTS (5.2 LTS, maintained to July 2028, VERIFY
  2026-10-29). Port to another version only through `blender_compat` plus a
  check render.
- Render output root and delivery root: absolute paths outside the repo and
  outside cloud-synced folders. Frames, caches and videos never enter git.
- Named presets in `render/scenes/presets/` (`check`, `preview`, `final`):
  resolution, samples, adaptive threshold, denoiser and passes, seed policy,
  filter width, clamps, motion blur, film grain off. A preset states every
  value; nothing is passed as an environment variable.
- Roles adopted, or which hand-offs go to the advisor instead.

## Stage record

One file per deliverable, `render/records/<deliverable>.md`, written by the
advisor after every stage so the work survives compaction:

    # Render record: <deliverable>
    Brief: <path> (version, date)   Blender: <version from blender_run>
    | stage | artifact (path) | preset, resolution, samples | tool results (verbatim) | verdict (who, date) | hold approved (who, date) |
    Measured: s/frame <n> over <k> frames on <device>; ETA <h>; estimate <h> (render_estimate)
    Output labels: check | preview | final | delivered, each with its path

A row without a verdict blocks the next stage. A hold row needs the human's
approval in the human's own words, or a standing approval recorded in
Project decisions that names the deliverable.

## Stages

| # | Stage | Owner (checks) | Inputs | Output | Gate |
|---|---|---|---|---|---|
| 0 | Brief: message in one sentence, audience, runtime, platform, resolution, fps, deliverables, references, look words, must-show features, hard nos | advisor with `art-director` | the human request; real reference photos; any brand guide | brief file, reference board (`art-director`), CMF hand-off (`industrial-designer`) | art-director APPROVE |
| 1 | Storyboard and shot spec: TO RENDER shots, waypoints with lens, timing and easing, mechanism state per beat, risky frames | `storyboard-specialist` | approved brief | `storyboards/` | art-director APPROVE; `engineering-reviewer` on every claim shown |
| 2 | Assets and fit check | `cad-asset-preparer` | CAD; real dimensions; CMF hand-off | `render/assets/`, `placements.json` | `fit_check` exit 0 at every keyframe state |
| 3 | Animatic: workbench or EEVEE, real timing, real camera | `cinematographer`, `animator`, run by `blender-operator` | storyboard and waypoints; assets and `placements.json`; pinned Blender | animatic frames and video (labelled ANIMATIC) | `camera_path --check`, `motion_check`; **HOLD for the human** |
| 4 | Lookdev and lighting: check stills at key frames, `check` preset | `lookdev-artist`, `cinematographer`, run by `blender-operator` | animatic approval; CMF hand-off and reference board; `check` preset | check stills, `render_sheets contact` and `crops` | `scene_lint` against `check`; art-director locks the look; **HOLD** |
| 5 | Animation and FX: check frames at the riskiest moments only | `animator`, `fx-simulation-artist` | locked look; mechanism kinematics; FX brief | check frames; FX caches outside git | `sim_validate` exit 0 before any FX render; `animation-adversarial-reviewer` APPROVE |
| 6 | Preview video at reduced resolution and samples, labelled PREVIEW with both values | `render-wrangler`, `blender-operator` | everything above approved; `preview` preset; label track | preview frames, preview MP4 | `render-technical-director` GO first; `frame_audit`, `flicker_metric`, `encode_verify`; adversarial review; **HOLD** |
| 7 | Final render, chunked resumable jobs, overnight allowed | `render-wrangler` | preview approval; `final` preset; measured s/frame | final frames | `render-technical-director` GO with `render_estimate` from measured s/frame; `render_chunks status` all done |
| 8 | Frame QC, finishing, encode, verify | `render-wrangler`, `senior-video-editor`, `blender-operator` | final frames; overlay spec and encode settings in `edit/` | delivered MP4 per platform | `frame_audit` per chunk, `color_check`, `flicker_metric`, `render_overlay`, `render_encode`, `encode_verify`; `animation-adversarial-reviewer`, `video-direction-reviewer`, `cold-viewer` (its sentence compared with the brief's message); **HOLD** |
| 9 | Deliver and retro | advisor | verified delivered file; run records; exact sources | `<delivery root>/<version>/` by `render_bundle` | manifest verified; retro proposes lessons to `docs/lessons/PENDING.md` |

Rules for every render:

1. No preview or final without a recorded `render-technical-director` GO
   that quotes `scene_lint`, the `blender_run --self-test` result on the
   pinned build, VRAM fit and the `render_estimate` output.
2. Find problems with check frames at the riskiest moments (impacts, fastest
   motion, transparency over detail, text), never with a full sequence.
3. Every render runs as a long job: `scripts/bg.sh start <name> -- python
   tools/render/render_chunks.py run --state <abs STATE>` with the STATE file
   in `.work/jobs/render/` (`docs/procedures/longjob.md`). One process per
   GPU on disjoint frame ranges; chain jobs so an overnight run needs no one
   awake; never an agent loop (kernel rule 17).
4. One hardware class, driver and Blender build per shot; never mix CPU and
   GPU frames in a shot; accept repeat renders by tolerance compare
   (`render_sheets compare`), not byte compare (Cycles is not bit-identical
   between runs, VERIFY 2026-10-29).
5. Encode only frames `frame_audit` passed. Display-referred PNG frames
   encode with view transform Standard; scene-linear EXR with the render's
   transform. The view transform is applied once.
6. Deliver to a local folder; large files are not uploaded through
   connectors. Publishing or uploading needs the human (kernel rule 15).

## Gates that need Blender or a GPU

These run from the skill and their verbatim output goes in the stage
record; they are never wired into `scripts/check.sh` (a gate that cannot run
is reported, never a no-op). `check.sh` runs the tools' unit tests, which
need neither.

| Gate | Command (from the repo root) |
|---|---|
| Pinned build detects script errors | `python tools/render/blender_run.py --lock render/scenes/blender.lock.json --self-test --log <abs log>` |
| Scene extract and lint | `blender_run.py ... --blend <scene> --log <abs> tools/render/blender_extract.py -- --out <abs json>`, then `scene_lint.py <json> --preset render/scenes/presets/<name>.json` |
| Motion | `motion_check.py <json> --holds <closing title range> --waypoints render/layout/<shot>.json` |
| Renders | `render_chunks.py plan ...` then `run` under `scripts/bg.sh` |
| Encode and verify | `blender_run.py ... tools/render/render_encode.py -- ...`, then `encode_verify.py <mp4> --frames N --fps F --width W --height H` (ffprobe cross-check when on PATH) |
| Seed and denoiser A/B | two `check` renders of a locked-camera window, `flicker_metric.py A --compare B` |

## Lessons carried in (from one product film project)

Mechanised where a tool or test can express it (kernel rule 1); the rest is
a rule in the owning agent with the reason it stays prose.

| Lesson | Mechanised as | Where |
|---|---|---|
| Check stills, then a preview, approved before any final; every preview states resolution and samples | hold rows in the stage record; `render_sheets --label`; TD GO | this procedure, `art-director`, `render-technical-director` |
| Never render a full sequence to find a problem | prose: which frames are riskiest is judgment; the record lists them before the run | `storyboard-specialist`, `blender-operator` |
| Absolute output paths | tool check: relative output refused (exit 2) | `render_chunks`, `render_encode`, `render_bundle`, `render_common.require_abs` and their tests |
| Chunks with one log each; frame counts per chunk before encoding; chained jobs | tool check | `render_chunks` (STATE, per-chunk logs, resume), `frame_audit --chunk`, `render_encode` refuses missing frames |
| Measured s/frame and ETA; preview, final and delivered kept apart | tool check | `render_chunks status`, `render_estimate`; output labels in the record |
| Two instances on one busy GPU give nothing; never mix CPU and GPU frames | tool check | `render_estimate --processes-per-gpu` warning, `render_chunks plan` refuses overlapping ranges, `blender_compat.pin_gpu` turns CPU off |
| Pin a portable Blender; port through a compat layer and a check render | tool check | `blender_run --lock` version and sha256 check, `blender_compat` shims with tests |
| Caches and frame folders out of git and cloud-synced folders | tool check | `render_common` git-tree and cloud-folder guards; `.gitignore` for `.work/jobs/` |
| Build add-ons from official source; record build steps; bundle runtime libraries | prose: provenance of a build cannot be checked from the repo | `fx-simulation-artist`, `render-research-lead` |
| CG reads as artificial until: cut edges split from faces (finish follows the cutting process), a small bevel on every edge, subtle absorption tint, gridded softboxes, HDRI glossy-only, dark floor with readable shadows, real-lens camera | prose: look judgment on reference photos; partly linted (light visibility advisory) | `lookdev-artist`, `cinematographer`, `cad-asset-preparer`, `scene_lint` |
| Matte black needs no sheen | prose: which material is matte black is not machine-readable | `lookdev-artist` |
| Rim lights must not show in glossy or transmission on clear parts | advisory lint | `scene_lint` advisory; `animation-adversarial-reviewer` check |
| Hinges read real only with small knuckle gaps and real metals | tool check for gaps; prose for metals | `fit_check` (allowed contacts, clearance), `lookdev-artist` |
| Fit-check every part against real dimensions; consumables at real sizes | tool check | `fit_check` dimensions and clearances at every keyframe state |
| Monotone spline through waypoints (Catmull-Rom overshoots) | tool check | `camera_path` (pchip) and `--check`, `motion_check` overshoot |
| The camera never fully stops except on the closing title | tool check | `motion_check` stops outside declared holds |
| Move into a detail directly, no wide swing | prose: intent is judgment | `storyboard-specialist`, `cinematographer`, adversarial review |
| One shot, no cuts, no freeze frames, no end card; title held to read twice | tool check for the hold; prose for the one-shot choice (a brief decision) | `render_overlay` title hold, `art-director` |
| Labels keep one side of their subject for their whole life, including fades | tool check | `render_overlay`, `motion_check --track` |
| Mechanisms move like the real part; start edges tucked where reality hides them | prose: needs the real part's behaviour | `animator`, adversarial review |
| No film grain on finals | prose: grain lives in the compositor, which the extract does not read, so `scene_lint` can only print an advisory | `render-technical-director`, `blender-operator` |
| Enough samples for transparent and frosted parts (about double, to measure); accurate denoising; tight adaptive threshold | tool check against the preset; measured by `flicker_metric` | `scene_lint` (preset keys, `transparent_min_samples`, denoiser quality and device), `render-technical-director` |
| Sub-pixel detail and thin bright edges shimmer: cap detail, clamp indirect, filter width about 1.75 px (to measure), motion blur on | preset keys linted; measured | `scene_lint`, `flicker_metric`, `lookdev-artist` |
| Seed: the prior lesson said a fixed seed; the Cycles manual recommends Animated Seed | default to measure: the preset states it, an A/B decides | `flicker_metric --compare`, `render-technical-director` |
| Thin-skin colliders leak or float; colliders closed solids thicker than a few cells | tool check for the symptom (volume loss); prose for the cause | `sim_validate` leak check, `cad-asset-preparer`, `fx-simulation-artist` |
| Thin films need three or more cells, or a height-field sheet keeping part of the relief | prose: cell counts live inside the solver | `fx-simulation-artist` |
| A thin inflow jet silently under-emitted; validate volume against the target | tool check | `sim_validate` under-emission (fails with the emitted percentage) |
| A real pour: splash, low viscosity, surface tension, landing point over the feature, residue drying before the next beat | prose with a partial check (`--drain-from`) | `fx-simulation-artist`, adversarial review |
| A built stream handing over to the sim above the surface | prose: a staging choice | `fx-simulation-artist` |
| Bakes take about an hour; long jobs; bake once, render many | tool check | `render_chunks` under `scripts/bg.sh`, `sim_validate --cache --expect-hash` |
| Connector uploads of large videos fail; deliver locally | tool check | `render_bundle` (local, exclusive version folder) |
| Keep exact scripts, presets and assets beside each delivered version, with a README of commands | tool check | `render_bundle` (source copy, README, verified sha256 manifest) |
