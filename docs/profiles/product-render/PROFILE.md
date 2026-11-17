# Profile: product-render

## Purpose and risk

For a project whose deliverable is a rendered still set, turntable, mechanism
demo, simulation shot or product film made in Blender from CAD. Risk: hours
of GPU time spent on a wrong look, a render that cannot resume, frames that
differ in hardware or settings, shimmer that only shows at full size, and a
delivered file nobody verified. Process and tools come from two prior render
projects; the staged procedure is `docs/library/procedures/product-render.md`
(copied to `docs/procedures/product-render.md` on adoption) and this profile
is the rule and gate layer over it. Stack with `scientific` only when a claim
shown in the film is quantitative.

## Rules

- RND-1 Blender is pinned per project in `render/scenes/blender.lock.json` (version, portable path, sha256); other versions are reached only through `blender_compat` plus a check render.
- RND-2 Frames, caches and videos go to absolute paths outside the repository and outside cloud-synced folders; the tools refuse relative output (exit 2).
- RND-3 Presets state every value (resolution, samples, denoiser, seed policy, filter width, clamps, motion blur); nothing is passed by environment variable.
- RND-4 Check stills at the riskiest frames, then a labelled preview (resolution and samples in the label), are approved by the human before any final; a full sequence is never rendered to find a problem.
- RND-5 No preview or final starts without a recorded `render-technical-director` GO that quotes `scene_lint`, the `blender_run --self-test` result, VRAM fit and a `render_estimate` from measured seconds per frame.
- RND-6 Every render is a chunked, resumable long job under `scripts/bg.sh` with its STATE file in `.work/jobs/render/`; one hardware class, driver and Blender build per shot, never CPU and GPU frames mixed.
- RND-7 Only frames that `frame_audit` passed per chunk are encoded; the view transform is applied once; the delivered file is verified by `encode_verify` and delivered by `render_bundle`.
- RND-8 The camera never fully stops except on a declared closing hold (`motion_check`); labels keep one side of their subject for their whole life (`render_overlay`, `motion_check --track`).
- RND-9 Parts that touch in CAD get a small real gap or an inset before rendering; coincident faces drop surfaces and blink (`fit_check`, `cad-asset-preparer`).
- RND-10 `flicker_metric` is read only on near-still windows; a window with camera or object motion is not a noise measurement and is checked by eye with crops.
- RND-11 The seed policy is stated by the preset and decided by a measured A/B on a locked-camera window; until measured, the record says "unmeasured".
- RND-12 Each stage writes a row in `render/records/<deliverable>.md` with the tools' output verbatim and a verdict; a row without a verdict blocks the next stage, and output labels (check, preview, final, delivered) are never merged.
- RND-13 Publishing, uploading and buying software or add-ons need the human (kernel rule 15); add-ons are built from official source and their build steps recorded.

## Gates

Exit codes: 0 pass, 1 check failed, 2 could not run (never a pass). Paths assume the tools are copied to `tools/render/`.

| Gate | Command | Pass | Rule |
|---|---|---|---|
| Tool tests (wired in `scripts/stack-check.sh` and CI) | `python -I -B -m unittest discover -s tools/render/tests -t tools/render/tests -p "test_*.py"` | exit 0; needs neither Blender nor a GPU | RND-2, RND-7 |
| Pinned build | `python tools/render/blender_run.py --lock render/scenes/blender.lock.json --self-test --log <abs log>` | exit 0, version and sha256 match | RND-1, RND-5 |
| Scene lint | `blender_run.py ... tools/render/blender_extract.py`, then `scene_lint.py <json> --preset <preset>` | exit 0 against the named preset | RND-3 |
| Motion | `motion_check.py <json> --holds <range> --waypoints <file>` | no stop outside a hold, no overshoot, no label side flip | RND-8 |
| Fit | `fit_check.py` at every keyframe state | exit 0 | RND-9 |
| Frame audit | `frame_audit.py --chunk` per chunk, then whole range | counts equal, no blank, firefly or duplicate finding | RND-7 |
| Encode verify | `encode_verify.py <mp4> --frames N --fps F --width W --height H` | exit 0 | RND-7 |
| Flicker | `flicker_metric.py <dir> --window A-B` on a near-still window | mean T at or under the threshold (default 0.004, uncalibrated, labelled E7) | RND-10 |
| Seed A/B | two `check` renders of one locked-camera window, `flicker_metric.py A --compare B` | numbers recorded; the preset states the winner | RND-11 |
| Stage record | review: reviewer reads the record | every row has a verdict; holds approved in the human's words | RND-4, RND-12 |
| Technical director GO | review | GO recorded before a preview or final | RND-5 |
| Outward actions | review: no publish, upload or purchase without the human | none found in the record | RND-13 |

Only the tool tests run in `stack-check.sh`. The gates that need Blender or a
GPU are run from the skill and their output is pasted into the record; they
are never wired as no-ops, and a gate that cannot run on the machine is
logged in `START_REPORT.md` with the reason.

## Tools

All render tools are library tools under `docs/library/tools/` (stdlib cores,
optional Pillow and numpy fast paths, tests in `tools/tests/`, run by the
template self-test). Copy the whole set with `render_common.py` to
`tools/render/`. Each is `exists`, with `--help`, exit 0 pass, 1 fail, 2 could
not run: render_common, blender_run, render_chunks, frame_audit,
render_sheets, render_estimate, render_bundle, encode_verify, render_encode
(Blender), blender_compat (Blender), blender_extract (Blender), camera_path,
motion_check, scene_lint, color_check, flicker_metric, sim_validate,
render_overlay, fit_check. The per-tool table is in `docs/library/README.md`.
Blender itself is a pinned portable build (RND-1), not a package install.

## Playbooks

- Staged pipeline, stage record and lessons map: `docs/library/procedures/product-render.md`.
- Worked example on a primitive scene: `docs/library/examples/product-render-sample/`.
- Toolchain for adjacent media work: `docs/library/toolchains/engineering-media.md`.
- Defect patterns for `docs/procedures/bughunt.md`, one per line:
  - A job script edited while its chain runs, or a chain stopped from outside the job runner, leaves chunks half done: trace `render_chunks status` against `frame_audit` after any stop.
  - A waiter that reads a job log returns only when the whole render ends: a mid-run stop or VRAM sample needs a poll on the STATE file, tested on a short chunk.
  - A progress window or log assumed visible is not: confirm it on screen once per job.
  - Touching CAD parts with coincident faces render with missing or blinking faces; the bounce limit is not the cause (a 4x change gave the same image): inset or gap the faces, then compare crops (RND-9).
  - A flicker FAIL on a moving window reads motion as noise (RND-10).
  - A done chunk whose frames were deleted is skipped by a naive resume: resume checks presence per frame.
  - Preview and final settings drift: `scene_lint` against the named preset at every GO.

## Agents and skills

- Skills: none shipped in this folder. The `product-render` skill stays in `docs/library/skills/product-render/` and start copies it from there, so its library slot is not counted twice.
- Roles come from the roster, `docs/roster/agents/` with Codex twins: leads `render-technical-director`, `render-research-lead`, `animation-adversarial-reviewer`, `cold-viewer`; specialists `blender-operator`, `cad-asset-preparer`, `lookdev-artist`, `cinematographer`, `animator`, `fx-simulation-artist`, `render-wrangler`; creative roles `art-director`, `storyboard-specialist`, `video-direction-reviewer`, `senior-video-editor`, `industrial-designer`. A role not adopted hands off to the advisor and the record says so.
- Reviewers are read-only (`animation-adversarial-reviewer` sees frames, sheets, crops and numbers only).
- No sound role until a film with audio is requested.

## Parameters and records

- Render output root and delivery root: absolute paths, outside the repository and cloud-synced folders, recorded in Project decisions.
- Named presets `check`, `preview`, `final` in `render/scenes/presets/`, each stating every value.
- `render/scenes/blender.lock.json`, `render/layout/<shot>.json` (waypoints), `render/assets/placements.json`.
- `render/records/<deliverable>.md`: the stage record (stage, artifact, preset and samples, tool results verbatim, verdict, hold approval), measured seconds per frame, output labels.
- `.work/jobs/render/` holds job STATE and logs and stays gitignored.

## Done means

- The stage record is complete: every row has a verdict, every hold has the human's approval, preview, final and delivered are reported separately with resolution, samples and measured seconds per frame.
- `frame_audit`, `color_check`, `encode_verify` and the render gates are quoted verbatim; the delivered file is re-verified from its delivered path and its sha256 manifest.
- `animation-adversarial-reviewer` and `cold-viewer` verdicts are recorded; the cold viewer's one sentence is compared with the brief's message.
- Retro lessons are proposed to `docs/lessons/PENDING.md`.

## Lessons carried in

- Check stills and a labelled preview before any final; the cheapest defect is found on three frames, not a sequence.
- Relative output paths and cloud-synced folders lost or duplicated frames; the tools refuse them.
- Mixed hardware or settings inside one shot show as shimmer; one class, one build, one preset per shot.
- Touching CAD parts drop or blink surfaces at the shared face; a small inset fixed it where more bounces did not.
- A flicker metric over a moving window flags motion, not noise; only near-still windows are numbers, the rest is crops.
- A fixed seed was the first lesson and the manual recommends an animated one; neither is measured on a moving shot yet (`unverified`).
- Long jobs fail in the harness, not the renderer: edits during a chain, stops from outside, log-reading waiters.

## Sources

Sources: distilled from two prior render projects of the template owner (a
product film of a transparent plastic product with a liquid-pour demo; a
mechanism reveal film and a release loop of a machine); project records stay
in those repositories, with no paths.
