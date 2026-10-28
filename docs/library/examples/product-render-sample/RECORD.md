# Render record: product-render-sample

Brief: `brief.md` version 2 (2026-10-29). Blender: 5.2.3 LTS portable
(from `blender_run`; the local install path is kept out of the repo, in the
output root's `blender.lock.json` with its sha256). Device: one NVIDIA
RTX 4080 SUPER, OptiX, pinned by device id with CPU off. Output root:
`C:/dev/work/_render/product-render-sample/` (outside the repo, not cloud
synced); nothing below it is committed. Standing approval for the four
holds of this primitive scene: owner, 2026-10-29 (task D3).

Commands: `run.md`. Tool output is quoted verbatim.

| Stage | Artifact (under the output root unless a repo path) | Preset, resolution, samples | Tool results (verbatim) | Verdict (who, date) | Hold (who, date) |
|---|---|---|---|---|---|
| 0 Brief v1 | `brief.md` v1 | - | - | art-director HOLD, 2026-10-29: ball likely hidden behind the front wall in beats 1-2 (camera at 11-15 degrees), title centred over the pin (estimated 1.2:1 contrast), label fading in during the fastest lid motion, detail beat not a detail, brief fields missing, look-lock filter width differing from final, stage 2-3 runs made before the stage 0-1 verdicts | - |
| 0 Brief v2, 1 Storyboard v2 | `brief.md` v2, `storyboard.md` v2, `waypoints.json`, `labels.json`, `presets/` | - | - | art-director APPROVE WITH CHANGES, 2026-10-29: brief v2 approved; storyboard v3 needed before the animatic: reframe W4-W5 so the ball is fully in frame and the title sits over the matte black front wall, describe what is behind the title, focus on HingePin from W3 (or about f/11), fade wording smoothstep 50-56 in and 74-80 out; record the built-in font name and licence; rows below are provisional until v3 | - |
| 2 Assets and fit (provisional runs before the v1 verdict superseded) | `blend/sample_check.blend`, `records/extract.json`, `records/fit.json` | check | `blender_run: PASS rc=0 blender=5.2.3`; `fit_check: PASS (states 5, pair checks 20, smallest gap 0 m, box level only)` | advisor: pass at box level; the 0 m gaps are the allowed contacts (ball on the box floor, lid on the pin) | - |
| 3 Camera and motion checks (v2 waypoints) | `records/motion.json`, `records/track.json` | - | `camera_path: PASS 5 waypoints, 120 samples, spline=pchip, checked`; `motion_check: PASS 120 frames, fps 24, median camera speed 0.2481 m/s, 0.2209 rad/s`; `render_overlay: PASS (labels 1, title yes, ...)` | advisor | - |
| Lint | `records/lint_check.json` | check | `scene_lint: PASS preset 'check', 3 light(s), 6 material(s), 10 object(s)`; advisory: film_grain cannot be checked from the extract | advisor | - |
| Pinned build gate | `records/selftest.json` | - | `blender_run: PASS self-test: failure detected (returncode, script-error, traceback) rc=1 blender=5.2.3` | advisor | - |

Tool defects found by running this example, each fixed at the tool with a
regression test (commits on the task branch):

- `blender_run` searched only the first 20 log lines for the version banner;
  5.2.3 prints it after the script's output, so a pinned run failed.
- `motion_check` called an eased lid move a spike because the shot median
  acceleration was 0 (the lid rests most of the shot).
- `scene_lint` rejected the presets' `label` and `notes` documentation keys.
- `render_overlay` always centred the title and never said when the title
  covers a subject (art-director finding); it now has `position`
  (`center`, `lower_third`) and prints an advisory per covered anchor.

Answers to the remaining v1 findings: `transparent_min_samples` equals the
preset samples by design here (the clear lid is in every frame, so every
preset is already the transparent case); the lint threshold fires when a
scene's samples are lowered below it. Frame 45 at stage 5 renders at the
preview preset with motion blur on.
