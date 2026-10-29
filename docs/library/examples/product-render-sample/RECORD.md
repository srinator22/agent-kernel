# Render record: product-render-sample

Brief: `brief.md` version 3 (2026-10-29); storyboard version 3. Blender:
5.2.3 LTS portable (from `blender_run`; the local install path is kept out
of the repo, in the output root's `blender.lock.json` with its sha256).
Device: one NVIDIA RTX 4080 SUPER, OptiX, pinned by device id with CPU off;
Cycles warns "Driver version is too old" at start-up (driver 610.88) and
renders. Output root: `C:/dev/work/_render/product-render-sample/` (outside
the repo, not cloud synced); nothing below it is committed. Standing
approval for the four holds of this primitive scene: owner, 2026-10-29
(task D3). GPU shared with another session's CPU-bound bake and a small
crop render, with that session's agreement.

Commands: `run.md`. Tool output is quoted verbatim.

| Stage | Artifact (under the output root unless a repo path) | Preset, resolution, samples | Tool results (verbatim) | Verdict (who, date) | Hold (who, date) |
|---|---|---|---|---|---|
| 0 Brief v1 | `brief.md` v1 | - | - | art-director HOLD, 2026-10-29: ball likely hidden behind the front wall (camera at 11-15 degrees), title centred over the pin, label fading in during the fastest lid motion, detail beat not a detail, brief fields missing, look-lock filter width differing from final, stage 2-3 runs made before the stage 0-1 verdicts | - |
| 0-1 Brief v2, storyboard v2 | `brief.md`, `storyboard.md`, `waypoints.json`, `labels.json`, `presets/` | - | - | art-director APPROVE WITH CHANGES, 2026-10-29: brief v2 approved; storyboard v3 owed (ball cut off and title over it at the hold, focus on the box not the pin, fade wording, font licence) | - |
| 0-1 Brief v3, storyboard v3 | same files, v3 | - | screen positions at the hold from `blender_extract` screen boxes: ball y 178-429 px, pin y 47-98 px, title y 433-467 px | art-director, 2026-10-29: stage 3 framing confirmed on animatic and check frames 84 and 100 | owner standing approval (D3) |
| 2 Assets and fit (current scene) | `blend/sample_check.blend`, `records/extract.json`, `records/fit.json` | check | `blender_run: PASS rc=0 blender=5.2.3`; `fit_check: PASS (states 5, pair checks 20, smallest gap 0 m, box level only)` | advisor, 2026-10-29: pass at box level; the 0 m gaps are the allowed contacts (ball on the box floor, lid on the pin) | - |
| 3 Camera, motion, overlay (current scene) | `records/motion.json`, `records/track.json` | - | `camera_path: PASS 5 waypoints, 120 samples, spline=pchip, checked`; `motion_check: PASS 120 frames, fps 24, median camera speed 0.2452 m/s, 0.1481 rad/s` (notes: FocusTarget and LidPivot are EMPTY, not checked); `render_overlay: PASS (labels 1, title yes, ...)` with advisory "title box covers 'Base' (screen box) at frames 84-120" (intended: the title sits on the box front wall) | advisor, 2026-10-29 | - |
| 3 Animatic | `frames/animatic/`, `video/animatic.mp4`, `sheets/animatic_key.png` | animatic, 480 x 270, workbench | `render_chunks: PASS all 3 chunk(s) done, 120/120 frames present`, measured 0.087 s/frame; `frame_audit: PASS (frames expected 120, present 120; findings: none)`; `encode_verify: PASS frames=120 fps=24 480x270 codec=avc1 (parser only)` | art-director, 2026-10-29: framing confirmed; workbench draws the clear lid opaque, so ball-through-lid is judged on the check stills | owner standing approval (D3) |
| Lint (current scene) | `records/lint_check.json`, `lint_preview.json`, `lint_final.json` | check, preview, final | `scene_lint: PASS preset 'check', 4 light(s), 6 material(s), 12 object(s)`; `scene_lint: PASS preset 'preview', ...`; `scene_lint: PASS preset 'final', ...`; advisory: film_grain cannot be checked from the extract | advisor, 2026-10-29 | - |
| Pinned build gate | `records/selftest.json` | - | `blender_run: PASS self-test: failure detected (returncode, script-error, traceback) rc=1 blender=5.2.3` | advisor, 2026-10-29 | - |
| 4 Check stills, set 1 | `frames/check/` (overwritten) | check, 960 x 540, 128 spp | `blender_run: PASS ... seconds=14.0` | advisor, 2026-10-29: rejected on sight, overexposed (matte black read light grey, floor white); lights cut from 120/40/60 W to 3/0.8/2 W after one 8/2/4 W trial | - |
| 4 Check stills, set 2 | `sheets/check_key.png`, `sheets/check_crops_70.png` | check, 960 x 540, 128 spp | `color_check: PASS` on frames 1, 30, 45, 70, 84, 100 | art-director HOLD, 2026-10-29: closed clear lid invisible in frames 1 and 30 (no light at the mirror angle; the rim light is kept out of glossy by rule); ghost ball reflection in the open lid at frame 70 to watch; no vignette or fringe; label contrast to measure on preview crops 56-74; record behind the work | - |
| 4 Check stills, set 3 | `sheets/check_key.png`, `sheets/check_crops_70.png` | check, 960 x 540, 128 spp | `blender_run: PASS ... seconds=13.2`; `color_check: PASS` on frames 1, 30, 45, 70, 84, 100 | art-director APPROVE, 2026-10-29: look locked on set 3 (reflection-only card, glossy only, no diffuse, no transmission, 1.6 x 0.12 m, 3 W, puts a band across the closed lid in frames 1-30; the ball reads through the rest); preview checks owed: band sweep in 30-45 (no more than 3 bright transitions a second), ghost ball reflection in the open lid 56-84, label contrast on crops 56-74, a 2x pin crop at 100, flicker | - |
| Seed A/B | `frames/seed_fixed/`, `frames/seed_animated/`, `records/seed_ab.json` | check, frames 92-103 (camera held, subject still) | fixed seed mean T 0.0000000 to 0.0000003 across the 12 regions; animated seed mean T 0.00036 to 0.00199 (corrected 2026-10-29: an earlier brief to the technical director said 0.00090); `flicker_metric: PASS (windows 1, regions 12, threshold 0.004, compared with B)` | advisor, 2026-10-29: the fixed-seed default stands for held shots (measured); moving shots stay unmeasured (the metric is not motion compensated); seed recorded as "measured on a still window only" | - |
| GO for preview, attempt 1 | - | preview | - | render-technical-director NO-GO, 2026-10-29: the extracts, lints and timings predated the reflection card (the scene changed during the review); selftest record missing (a blender_run defect: --self-test ignored --record); no VRAM peak; seed range misquoted; lock without file name and size; denoise quality and device not in the presets | - |
| Answers to the NO-GO | `records/selftest.json`, `records/extract_{check,preview,final}.json`, `records/lint_{check,preview,final}.json`, `records/measure_{preview,final}.json`, `logs/vram_{preview,final}.txt` | check, preview, final | `blender_run: PASS self-test: failure detected (returncode, script-error, traceback) rc=1 blender=5.2.3` (record now written; tool fixed); `scene_lint: PASS preset 'check', 4 light(s), 6 material(s), 12 object(s)` and the same for 'preview' and 'final' on the current scene.py; presets now state denoising_quality HIGH and denoising_use_gpu true (extract records both); lock adds file blender.exe, 113041880 bytes, zip name; measured preview 3 frames (30, 45, 70) in 5.12 s with start-up, final 3 frames in 21.11 s (motion blur on); `render_estimate: PASS remaining 0.06 h (0:03:25)` at 1.71 s/frame and `0.23 h (0:14:05)` at 7.04 s/frame for 120 frames; VRAM: preview peak 6074 MiB (baseline 4077, scene about 1997), final peak 6315 MiB (baseline 4074, scene about 2241) of 16376 MiB; driver 610.88 kept for the whole shot | advisor, 2026-10-29 | - |

Tool defects found by running this example, each fixed at the tool with a
regression test (commits on the task branch):

- `blender_run` searched only the first 20 log lines for the version banner;
  5.2.3 prints it after the script's output, so a pinned run failed.
- `motion_check` called an eased lid move a spike because the shot median
  acceleration was 0 (the lid rests most of the shot); it now uses a local
  reference, and it skips invisible empties (a focus target).
- `scene_lint` rejected the presets' `label` and `notes` documentation keys.
- `render_overlay` always centred the title and judged cover by anchor
  points only, so it missed a ball whose centre was off frame; it now has a
  `position` option and tests on-screen boxes that `blender_extract` writes.

Answers to other findings: `transparent_min_samples` equals the preset
samples by design here (the clear lid is in every frame, so every preset is
already the transparent case); the lint threshold fires when a scene's
samples are lowered below it. Frame 45 at stage 5 renders at the preview
preset with motion blur on.
