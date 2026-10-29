# Render capability recommendations (merge of six research reports)

Date: 2026-10-29. Role: render-research-lead (read-only merge pass; the
advisor saved it and made the corrections listed at the end).

Inputs, with the short alias each citation uses:
- VER = `docs/research/2026-10-29-blender-versions-api.md`
- ADD = `docs/research/2026-10-29-blender-addons.md`
- OUT = `docs/research/2026-10-29-outside-tools.md` (no source IDs; cited by section number plus vendor host)
- TEC = `docs/research/2026-10-29-render-techniques.md`
- SCA = `docs/research/2026-10-29-render-scale-out.md`
- GAP = `docs/research/2026-10-29-render-tool-gaps.md`

This document merges the six reports above. Every fact cites the report it
came from, by alias and that report's source ID. Nothing new was researched.

Conventions:
- E-levels are the ones each report assigned (`docs/library/procedures/evidence-levels.md`).
- "unverified" is carried over wherever the source report marked a fact that way.
- Every version, licence and price statement is VERIFY 2026-10-29.
- Effort (S/M/L) comes from GAP section 6 where given (upper bound of a range); elsewhere it is this merge's judgement.
- Recommendations are judgement, not source facts.

## 1. Recommendation table

### 1a. Blender platform and pipeline

| Problem | Option | Evidence | Licence and cost | Effort | Recommendation |
|---|---|---|---|---|---|
| Pinned Blender version | Technique: Blender 5.2.3 LTS portable zip (`blender-5.2.3-windows-x64.zip`, released 2026-10-22). Keep a lock record with version, file name, bytes and sha256; take the sha256 from the release folder, because on retrieval day the download page checksum links pointed at 5.2.2 | VER S2,S3,S22 E4 | free | S | ADOPT |
| LTS policy | Technique: pin per project, never auto-update. 5.2 LTS is maintained to July 2028; 4.5 LTS (to July 2027) only as a fallback for scripts that cannot take the 5.0 removals. Revalidate the pin when a new LTS ships | VER S1,S3,S4 E4 | free | S | ADOPT |
| Blender 5.3 | Technique: beta until 2026-11-04, stable planned 2026-11-10, not LTS. Only draw found is dispersion | ADD S6,S7 E2; TEC S5,S6 E4 | free | S | DEFER |
| API break: actions and channelbags | Build (blender_compat). 4.4 slotted actions; 5.0 removed `action.fcurves/.groups/.id_root`. Use channelbag helpers or `fcurve_ensure_for_datablock`, set `anim_data.action_slot` | VER S6,S7,S13,S25 E4 | free | S | BUILD |
| API break: compositor node group | Build (shim). 5.0 uses `scene.compositing_node_group`, Composite node replaced by Group Output; File Output uses `directory/file_name/file_output_items`; pass names changed (`Depth`, `Diffuse Color`) | VER S6,S12 E4 | free | S | BUILD |
| API break: VSE strips | Build (shim). 4.4 renamed `Sequence` to `Strip` and `.sequences` to `.strips`; 4.5 `input1/input2`; 5.0 `context.sequencer_scene`; 5.1 deprecated handle properties. An explicit 5.0 removal of `sequences` was not found (unverified) | VER S6,S7,S8,S11,S25 E4 | free | S | BUILD |
| API break: EEVEE id | Build (shim). `BLENDER_EEVEE_NEXT` in 4.2, `BLENDER_EEVEE` from 5.0. Feature-detect, not version tuples | VER S10,S6 E4 | free | S | BUILD |
| API break: auto smooth | Build (shim). 4.1 removed `use_auto_smooth`; sharpness from the `sharp_edge` attribute or Shade Smooth by Angle. Operator idnames unverified | VER S9 E4 | free | S | BUILD |
| Other 5.x breaks | Build (shim). Dict-style `scene['cycles']` removed; set `media_type` before `file_format`; Geometry Nodes modifier inputs move to `modifier.properties.inputs` in 5.2; log and progress text changed in 5.0, so do not regex progress lines | VER S5,S6 E4 | free | S | BUILD |
| Headless exit code on Python errors | Build (blender_run). Stored default for `--python-exit-code` is 0 (disabled): always pass `--python-exit-code 1`, wrap the script in try/except with `sys.exit(1)`, and scan the log for caught-and-printed tracebacks. Prove with a self-test that raises, on the pinned build. Exit code for non-Python render failures unverified | VER S14,S19 E4; GAP S1 E4 | free | S | BUILD |
| GPU device pinning | Technique in blender_run. Set `compute_device_type` and `scene.cycles.device='GPU'` explicitly (`--factory-startup` loads no prefs); `refresh_devices()`, enable one device by `device.id`, switch CPU entries off (`get_devices_for_type` appends them). The prior scripts enabled every non-CPU device. `CUDA_VISIBLE_DEVICES` with OptiX untested | VER S17 E4, S26 E2; GAP L2 E7 | free | S | BUILD |
| Denoiser for animation | Technique: OIDN with Albedo+Normal, Prefilter Accurate, Quality High, `denoising_use_gpu=True` (default False), store denoising passes. OIDN docs say the RT filter "is not temporally stable"; no source ranks OIDN against OptiX for animation. Whether `denoise_animation` uses cross-frame data is unproven; OIDN 3 temporal denoising rests on a press report only | VER S16,S17,S18 E4, S27 E8; TEC S7,S25 E4 | free | S | TRIAL |
| Seed policy (animated vs fixed) | Technique. The manual recommends Animated Seed for animation; the prior lesson says off to avoid vibrating grain. One old community test (OptiX 7.3, OIDN 1.4) partly supports off but saw structured patterns at low samples. The reports conflict with the lesson: settle with a measured A/B using flicker_metric on a locked-camera shot; the preset states the seed explicitly | TEC S7 E4, S30 E6; VER S16 E4; SCA S2 E4 | free | S | ASK OWNER |
| Determinism, same machine | Technique. Tracker issue 101726 open and Confirmed: renders differ run to run (threaded float atomics in normals and tangents); `-t 1` gave an exact match. Accept frames by tolerance image compare, not byte compare; add our own hash test | VER S23 E6; SCA S31 E6 | free | S | ADOPT |
| Determinism, across machines | Technique. No source states bit-identity across GPU models, drivers, OS or CPU vs GPU; reports of CPU/GPU differences with volumes and translucency. One hardware class, driver and build per shot, fixed denoiser and denoise device, never split a frame across CPU and GPU; 10-frame overlap compare before any mixed run | SCA S16,S20 E2, S31 E6, S32,S33 E8; VER S27 E8 | free | S | ADOPT |

### 1b. Simulation, assets, CAD, interchange

| Problem | Option | Evidence | Licence and cost | Effort | Recommendation |
|---|---|---|---|---|---|
| Liquids, primary | Add-on: FLIP Fluids built from official GitHub source; README says MinGW is the only supported Windows compiler (the prior project used MSYS2's MinGW). "Blender 4.5 to 5.2 compatible", latest v1.8.8 (2026-07-27). Paid-only content (Mixbox named) not in source; GitHub releases are demo builds | ADD S1,S2,S3 E2 | Add-on GPL-3.0, engine MIT, free from source; paid licence price unverified | M | ADOPT |
| Liquids, built-in | Technique: Mantaflow, in the 5.2 manual, also gas, smoke, fire. Maintenance unverified (2021 second-hand note: no active developer). ADD ranks FLIP Fluids first, OUT suggests Mantaflow first (reports differ) | ADD S4 E8, S5,S8 E2; OUT 5 (docs.blender.org) E2 | free | S | TRIAL |
| Liquids, outside tool | Outside tool: Houdini Indie, only if a Blender check shot fails. No benchmark shows Houdini beating Blender on liquids; cache-use terms unverified | OUT 1.1-1.3 (sidefx.com E2, forum E8) | USD 299 per year or USD 449 per 2 years | L | DEFER |
| Liquid meshing helper | Add-on: Splashsurf Studio v1.0.1 (meshes particle clouds, no sim). Binary shipping unverified. MantaPro unverified | ADD S16 E2, E8 | GPL-3.0-or-later, free | S | DEFER |
| Cloth | Technique: built-in Cloth Dynamics (5.2, experimental, may break between releases: pinning, stretch, bend, tearing) or legacy Cloth. Pin Blender per project; re-save Geometry Nodes assets for 5.2 | ADD S5,S8 E2 | free | M | ADOPT |
| Torn cloth edges | Add-on: Unravel v1.0.0 (2026-10-19, needs 5.2+), 536 downloads, 1 review | ADD S16 E2 | GPL-3.0-or-later, free | S | TRIAL |
| Paper (sheets, folds, rolls) | Build later. No paper-folding or roll add-on found (searches "paper", "fold", first page only); PolyZamboni only unfolds. Geometry Nodes simulation zones as building block, Thin Wall for paper shading | ADD S8,S10,S16 E2; TEC S1 E4 | free | L | DEFER |
| Materials library | Add-on plus build our own. Poly Haven assets CC0, but the site prohibits scraping without permission; its add-on GPL-3.0. No free procedural library on the extensions site, so build our own lookdev set (1c) | ADD S10,S15 E2 | CC0 assets, GPL-3.0 add-on, free | M | ADOPT |
| Camera rigs | Add-on: Add Camera Rigs v1.9.2 (4.2+; 5.2 testing not stated), plus our own camera_path library (1e) | ADD S14 E2; GAP L2 E7 | GPL-3.0-or-later, free | S | TRIAL |
| CAD import (STEP) | Add-on: STEP Importer extension v1.2.1 (2026-07-21, Blender 5.1+), converts through Cascadio to glTF; tessellation presets have no published numbers. Cascadio is a native OpenCASCADE prebuilt wheel: a third-party binary unless built from source, which conflicts with the official-source rule. Whether the zip bundles the wheel is unverified | ADD S11,S12 E2 | Extension page GPL-3.0-or-later, GitHub licence field null; Cascadio MIT per PyPI; free | M | ASK OWNER |
| CAD import, alternative | Outside tool: FreeCAD round trip (STEP to mesh to glTF or OBJ). Current release 1.1.4 (2026-09-28). Mesh-deviation controls unverified (wiki unreachable) | ADD S13 E2 | LGPL-2.1, free | M | TRIAL |
| Interchange: Alembic | Technique: baked geometry and cameras, no materials (face-set names only), no armatures. Time stored in seconds, so scene fps must match. Blender reads velocity from `.velocities`, Houdini writes `v`; a 2021 thread conflicts | ADD S5,S21 E2; OUT 6.1,6.3 (docs.blender.org E2, blenderartists E6) | free | S | ADOPT |
| Interchange: OpenVDB | Technique: volume sequences; Principled Volume reads density, color, temperature. Velocity-grid motion blur Cycles only, units must match the writer. Level sets not rendered as surfaces. EEVEE support unconfirmed | ADD S21 E2; OUT 6.1,6.3 E2 | free | S | ADOPT |
| Interchange: USD | Technique: scenes with Preview Surface or MaterialX materials (MaterialX export has no displacement); no layers, references or variants; no one-file-per-frame sequences. ADD prefers USD for animated scenes, OUT rates USD sequences weaker (reports differ) | ADD S5,S21 E2; OUT 6.1 E2 | free | S | TRIAL |

### 1c. Look: materials, light, camera, liquids, flicker

| Problem | Option | Evidence | Licence and cost | Effort | Recommendation |
|---|---|---|---|---|---|
| Transparent plastic | Build our own lookdev material. Parts a few mm thick: closed solid with Volume Absorption tint; Thin Wall only for film-thin parts. Acrylic n about 1.49 (Abbe 57-58); polycarbonate n about 1.58 (range 1.58-1.64, Abbe about 30), so set IOR explicitly. Glass needs the most bounces. Caustics: Filter Glossy, MNEE or off | TEC S1,S3,S4,S9,S10,S13 E4, S26,S27 E3, S28 E8 | free | M | BUILD |
| Frosted plastic | Technique: Glass or Principled transmission with roughness raised (roughness is "refraction sharpness"), Multiscatter GGX. No measured frosted roughness found (unverified); find by lookdev comparison | TEC S3,S15 E4 | free | S | TRIAL |
| Cut edges | Technique: edge finish follows the cutting process (laser gives a clear, flame-polished edge; sawn or routed a frosted one), separate edge material slot. Bevel node: shading only, about 20 percent slower, no OSL on OptiX, invalid with an MNEE caustic setup. Bevel modifier with Harden Normals and Weighted Normals. Node's temporal noise unmeasured | TEC S17,S18 E4, S37 E6, S38 E8 | free | S | TRIAL |
| Matte black | Technique: no sheen (sheen models fibre or dust). Keep colour components at 0.8 or less, brighten the lights. A base value that avoids grey is unverified | TEC S1,S9,S16 E4 | free | S | ADOPT |
| Brushed or anodised metal | Technique: Principled specular Anisotropy, Rotation and Tangent (Cycles only). Anodised values unverified | TEC S1 E4, excerpt E8 | free | S | TRIAL |
| Studio lighting | Build our own rig preset: area lights with Spread to emulate a grid (5.2 default unverified); light linking via Receiver and Shadow Blocker collections (lights only, not the world); per-object ray visibility; HDRI visible only in reflections via a Light Path Is Camera Ray / Is Glossy Ray mix. The Light Tree ignores ray visibility, so test before locking the rig | TEC S7,S10,S11,S12,S14,S15 E4, S35 E6 | free | M | BUILD |
| Real-lens camera | Build our own preset. No real-lens add-on found. 85-100 mm full-frame (practitioner opinion), F-Stop with Focus Object, Sensor Fit and Size, Shift, Lens Distortion node Dispersion for fringe. Vignette recipe unverified | ADD S10 E2; TEC S19,S20 E4, S36 E8 | free | S | BUILD |
| Dispersion (5.3 only) | Technique: Principled Dispersion Scale plus Abbe Number, Cycles only, 5.3 beta; adds colour noise (more samples, higher indirect clamp). Press report says RGB-based, not spectral (E8). Not in 5.2 LTS | TEC S1,S2,S5 E4, S40 E8 | free | S | DEFER |
| Liquid realism | Technique, documented values: water kinematic viscosity base 1.002, exponent 6; water IOR 1.333 (E8 source); Thin Film IOR 1.33; Speed Vectors plus Deformation Motion Blur; bake before render; Concavity Lower must not exceed Upper. Splash, wetting, drying and water-vs-gel settings unverified | TEC S1,S21,S22,S23,S24 E4, S28 E8 | free | M | TRIAL |
| Flicker remedies | Technique: enough samples; OIDN with prefiltered albedo and normal, High quality; clamp indirect separately, lowered gradually; Filter Glossy starting at 1.0; adaptive threshold; bake sims. A commercial 3-frame temporal median add-on (vendor claim, E8) is not adopted | TEC S4,S7,S9,S25 E4, S34 E6, S41 E8 | free (median add-on price unverified) | S | ADOPT |
| Flicker metric | Build (flicker_metric). Temporal std of luminance in masked static regions, plus warping error or RWE with optical flow from clean passes, against a high-sample reference. NVIDIA FLIP and VMAF do not measure temporal instability. Thresholds stay E7 until calibrated | TEC S32,S33 E3 preprint; GAP S9,S10 E4 | free | L | BUILD |

### 1d. Scale-out and outside tools

| Problem | Option | Evidence | Licence and cost | Effort | Recommendation |
|---|---|---|---|---|---|
| Multi-GPU in one machine | Technique: one Blender process per GPU on disjoint frame ranges, Overwrite off, Placeholders on. One process across two cards scaled 1.3-1.6x (vendor-run test). Scene must fit the smallest card (16 GB locally); consumer cards have no NVLink (E8) | SCA S1 E4, S3 E8, S4 E6, S5,S12 E8; GAP S2 E4 | free | S | ADOPT |
| Render queue, local | Build (render_chunks). Do not wrap Flamenco for a single GPU | GAP S1,S2,S5,S6 E4 | free | M | BUILD |
| Render queue, multi-machine | Outside tool: Flamenco (Manager plus Worker); needs shared storage and Blender at the same path on every machine. Current version and 5.x support unverified | ADD S17 E2, S20 E6; GAP S5,S6 E4 | GPL 3.0, free | M | DEFER |
| Rented GPUs | Outside service: RunPod per GPU-hour, community/secure: RTX 4090 USD 0.34/0.89, RTX 5090 USD 0.69/1.19, L40S USD 0.79/1.09, RTX A6000 USD 0.33/0.59. Lambda RTX A6000 USD 1.09. Vast.ai dynamic, unverified. RunPod and Lambda state no egress fees. A Docker image with the add-on baked in is the route (untested) | SCA S6,S7,S8,S11,S13 E2, S12,S14 E8 | USD per GPU-hour as listed | M | DEFER |
| Cost model | Technique (feeds render_estimate). 900 frames x 60 s = 15 h on a 4080 SUPER. Rented, community/secure: RTX 4090 USD 3.60/9.42, RTX 5090 USD 6.39/11.03, L40S USD 11.85/16.35, A6000 USD 8.48/15.17 (Lambda USD 28.02). Speed ratios cap these at E8; start-up, upload, storage, re-renders and tax excluded | SCA S6 E2, S27 E6, S29 E8 | USD | S | ADOPT |
| Managed farms | Outside service. GarageFarm USD 0.004/0.006/0.012 per OB-hour, FLIP Fluids named, custom plugins only at Medium/High priority, NDA, 28-day retention. RebusFarm 0.53 US cent per OB-hour (1 RP = USD 1.18), Blender up to 5.1, pre-bake required. Ranch EUR 0.005-0.010 per OB-hour excl. tax. Fox CPU USD 0.734-1.224 per node-hour, GPU rates unverified. The 4080 SUPER OB rating is unverified | SCA S15-S25 E2 | as listed | M | DEFER |
| Volunteer and legacy farms | SheepIt: volunteer machines, 2,048 MB limit, no own scripts, files go to other people's machines. Deadline 10 in maintenance mode from 2025-11-07 (secondary reports). CrowdRender newest support 5.1. Concierge Render identity unverified | SCA S22,S23 E2, S26 E8; ADD S18,S19 E2, S20 E6 | SheepIt free; others unverified | S | AVOID |
| Houdini Apprentice | Non-commercial only, 1920x1080 renders, watermark; old community reports say no Alembic export | OUT 1.1-1.3 (sidefx.com E2, forum E8) | free | S | AVOID |
| Houdini Indie, Core, FX | Indie commercial only under USD 100K gross revenue a year and under USD 1,000,000 funding in 24 months, no shared pipeline with commercial Houdini; cache-use terms unverified. Core and FX no revenue cap, Karma bundled | OUT 1.1-1.3 (sidefx.com) E2 | Indie USD 299/1 yr or USD 449/2 yr; Core USD 1995, FX USD 4495 perpetual node-locked (compare page garbled); AUP price unverified | L | DEFER |
| KeyShot | CAD LiveLinking (34 or 36 formats; the page states both), certified material libraries, turntables, exploded views. No liquid simulation documented | OUT 2.1,2.2 (keyshot.com) E2 | Studio Professional USD 1,299/yr, Business USD 1,599/yr, network rendering add-on USD 749/yr | M | DEFER |
| Maya with Arnold and Bifrost | Bifrost liquids with Alembic out. An old help page (E8) says unlicensed Arnold renders are watermarked and cannot batch | OUT 3 (third-party E6; autodesk E2/E8) | USD 2,010/yr or USD 255/month (E6, read by the source's author 2026-09-03); Indie price not public | L | DEFER |
| Cinema 4D with Redshift, Unreal | C4D 2027.0 adds Liquid FX, Alembic and USD. Unreal free under USD 1 million revenue, otherwise USD 1,850 per seat per year (2024 article); a claimed film exemption conflicts (E8) | OUT 4 (maxon.net E2, engadget E6) | Maxon price unverified (reseller USD 1,265 undated, E8) | L | DEFER |

### 1e. Tools from the tool-gaps final list

Runtimes (GAP section 6): STD = stdlib Python, PN = Pillow+numpy, BPY = inside Blender.

| Problem | Option | Evidence | Licence and cost | Effort | Recommendation |
|---|---|---|---|---|---|
| Run Blender headless | blender_run (STD), thin CLI wrapper | GAP S1 E4, L1 E6 | free | S | BUILD |
| Chunked renders, resume | render_chunks (STD): STATE file, one log per chunk, skips present frames | GAP S1,S2 E4, L2 E7 | free | M | BUILD |
| Frame audit | frame_audit (PN): blank, fireflies, duplicates, NaN for float images only; oiiotool optional, not installed | GAP S11 E4, L1 E6 | free | M | BUILD |
| Contact and review sheets | sheets (PN), one tool | GAP L2 E7, S11 E4 | free | S | BUILD |
| Encode | encode (BPY) with Blender's bundled FFmpeg libraries; view transform a parameter (the prior script forced Standard) | GAP L1 E6, L2 E7 | free | S | BUILD |
| Encode verify | encode_verify (STD): pure-Python MP4 box parser always, ffprobe when on PATH; exit 2 on fragmented MP4, variable `stts` or missing `moov` | GAP S7,S13 E4, L3 E6 | free | M | BUILD |
| Render estimate | render_estimate (STD), user-supplied dated price table, no shipped prices | GAP; SCA formula | free | S | BUILD |
| Deliverable bundle | bundle (STD): scripts, presets, README, sha256 manifest, Blender version and argv | GAP L2 E7 | free | S | BUILD |
| Colour check | color_check (PN), frame side; the double-transform rule lives in scene_lint | GAP L2 E7 | free | S | BUILD |
| Motion check | motion_check (STD core plus BPY extractor): stops, acceleration spikes, overshoot, label side flips | GAP L2 E7 | free | M | BUILD |
| Camera path | camera_path (STD), monotone Hermite (PCHIP) through waypoints | GAP L2 E7 | free | S | BUILD |
| Scene lint | scene_lint (STD core plus BPY extractor), diff against the named preset, TEC lint rules | GAP L2 E7; TEC S17,S23 E4 | free | M | BUILD |
| Version shims | blender_compat (BPY) plus a break table | GAP S4 E4; VER S5-S13 E4 | free | M | BUILD |
| Flicker metric | flicker_metric (PN), needs calibration (1c) | GAP S9,S10 E4; TEC S32,S33 E3 | free | L | BUILD |
| Simulation validation | sim_validate (PN or STD): volume vs poured, emission vs commanded flow; catches the silent under-emission the prior project fixed by eye with a hand-tuned factor. `.bobj` layout unverified | GAP L2 E7 | free | M | BUILD |
| Labels and overlay | overlay (PN plus BPY anchor export) with safe-area check; margin values unverified | GAP L2 E7 | free | L | BUILD |
| Fit and clearance | fit_check (PN core plus BPY extractor), coarse v1 on bounding boxes and sampled vertices | GAP L2 E7 | free | L | BUILD |
| Audio loudness | Only when a film with sound is requested; pyloudnorm needs SciPy (E8) | GAP S8 E4, S14 E8 | unverified | M | DEFER |

Suggested phases (GAP judgement): phase 1 blender_run, render_chunks,
frame_audit, sheets, encode, encode_verify, render_estimate, bundle; phase 2
color_check, motion_check, camera_path, scene_lint, blender_compat; phase 3
flicker_metric, sim_validate, overlay, fit_check.

## 2. Conflicts and corrections to the prior-project lessons

| Lesson as given | What the reports say | Proposed handling |
|---|---|---|
| Animated seed off, to avoid vibrating grain | Manual recommends on (TEC S7, VER S16, SCA S2 E4); one old test partly supports off but saw structured patterns (TEC S30 E6) | Keep as default to measure (A/B, decision 3) |
| Split cut edges from sheet faces; satin edges | Confirmed in kind, but finish depends on the process: laser clear, sawn or routed frosted (TEC S37 E6, S38 E8) | Reword: edge material follows the cutting process |
| Small bevel on every edge | Confirmed (TEC S17 E4); node vs geometry bevel open, node temporal noise unmeasured | Keep as rule; method to measure |
| Slight glass-like tint | No values found; Volume Absorption is the documented route (TEC S13 E4) | Reword: tint by absorption on closed solids, value from lookdev |
| Gridded softbox; rim lights read as a fake white sheet | Confirmed (TEC S35 E6, S14 E4) | Keep as rule |
| HDRI visible to glossy rays only | Supported via a Light Path mix; no world toggle found (TEC S11,S12 E4) | Keep as rule (shader-side switch) |
| Matte black needs no sheen | Consistent (TEC S1 E4) | Keep as rule |
| No film grain on finals; accurate denoise | Consistent (TEC S7,S25 E4) | Keep as rule |
| Roughly double samples for transparent and frosted | No source (TEC) | Keep as default to measure |
| Filter width about 1.75 px | Direction confirmed, value unsourced (TEC S8 E4) | Keep as default to measure |
| Clamp indirect; cap procedural detail | Clamping confirmed (TEC S4,S9 E4); detail cap consistent with the specular-aliasing paper (S31 E3), unmeasured in Cycles | Keep clamp as rule; cap as default to measure |
| Motion blur on | Documented; no source on its stability benefit (TEC S21 E4) | Keep as default to measure |
| A second instance on a saturated GPU adds nothing | Matches SCA S4 (E6): one process per GPU | Keep as rule |
| GPU setup enables every non-CPU device | Pin one device by `device.id`, CPU entries off (VER S17 E4) | Reword |
| Encode forces the Standard view transform | Double-transform trap (GAP L2) | Drop; parameter plus a lint rule |
| Quality knobs passed as environment variables | A named JSON preset is needed for lint and bundle (GAP section 4) | Drop; replace with presets |
| Chunk logs show only the last line, no traceback scan | blender_run must fail on a traceback (GAP section 2) | Drop |
| FLIP Fluids built via MSYS2 | README names MinGW only; MSYS2 packages MinGW (ADD S1 E2, interpretation) | Keep as rule; record the toolchain |

Conflicts between the reports themselves, kept as found:
- 4.2 LTS release date: 2024-07-14 on the LTS page, 2024-07-16 on the release index (VER S1/S3).
- GarageFarm trial credit USD 25 on one page, USD 50 on another (SCA S15/S16).
- SheepIt upload limit 2,048 MB in its FAQ, 750 MB in a blog (SCA S23).
- 4080 SUPER benchmark score 8,163 (SCA S27 E6) vs 9,232 (S29 E8).
- Liquid order: ADD puts FLIP Fluids first, OUT puts Mantaflow first.
- USD: ADD prefers it for animated scenes, OUT rates USD sequences weaker.

## 3. Decisions for the owner

Recommended option first.

1. STEP importer prebuilt wheel: (a) FreeCAD round trip as default, STEP Importer only as a trial recorded as an exception in an ADR once we know whether the zip bundles Cascadio; (b) accept STEP Importer with extensions.blender.org as the official channel; (c) build Cascadio and OpenCASCADE from source (heavy).
2. No ffprobe on this machine: (a) pure-Python MP4 parser always, ffprobe only if already on PATH; (b) the owner installs an ffmpeg build. Note: ffmpeg.org itself links third-party Windows builds (from the brief, not the reports), which sits awkwardly with the official-source rule.
3. Seed policy: (a) measured A/B with flicker_metric before any animation final, prior lesson (off) as interim default labelled unmeasured; (b) adopt animated seed now; (c) keep off as a rule.
4. Pinned Blender: (a) 5.2.3 LTS default, revisit 5.3 only for dispersion once stable; (b) move to 5.3 at release; (c) pin 4.5 LTS.
5. Liquid route order: (a) FLIP Fluids from source first, Mantaflow for gas and smoke, Houdini Indie only after a failed check shot; (b) Mantaflow first.
6. Houdini Indie caches: (a) a written answer from SideFX on Alembic, VDB and USD use before any use (needs a human contact); (b) do not use Houdini.
7. FLIP Fluids paid licence: (a) source build only; (b) buy a licence as a funding choice (price unverified).
8. Rented-GPU container test: (a) defer until a deadline needs the capacity; (b) one small paid RunPod test (GPU found, add-on and cache load).
9. Farm for confidential or add-on work: (a) no farm until an ADR plus a confirmed support reply exist; (b) allow GarageFarm at Medium/High priority.
10. Intermediate frame format: (a) 8-bit PNG for check and preview, 16-bit half-float EXR for finals; (b) PNG only (banding risk); (c) EXR only (needs an EXR reader in the audit).
11. CI dependencies: see the advisor note below.

## 4. Research to run next (bounded; E1 measurements on the pinned build unless stated)

1. Does `--python-exit-code 1` return non-zero for exceptions in `-P` scripts, handlers and operators on 5.2.3? (VER Q1) - blender-operator, via blender_run self-test.
2. `device.id` form for CUDA and OptiX on Windows, stability across reboots and driver updates, `CUDA_VISIBLE_DEVICES` with OptiX. (VER Q2,Q9) - render-wrangler.
3. Bit-identity across runs on one GPU with default `-t` and adaptive sampling on: hash test plus tolerance compare. (VER Q7) - render-wrangler, reviewed by render-technical-director.
4. Seed A/B: fixed vs animated seed with OIDN on a locked-camera shot, scored by flicker_metric against a high-sample reference. (TEC Q3) - render-technical-director plans, blender-operator runs, animation-adversarial-reviewer judges.
5. Does `denoise_animation` use cross-frame data; is OIDN 2.5.0 what 5.2.3 ships? (VER Q3,Q4) - researcher.
6. Does Overwrite-off plus Placeholders count a crash-truncated frame as present? (GAP Q5) - render-wrangler.
7. Installed defaults for Max Bounces, clamps, filter width, noise threshold, Spread and sensor size. (TEC Q2,Q8) - blender-operator (scene_lint extractor dump).
8. Does the Bevel node add temporal noise vs a modifier bevel plus Weighted Normals? (TEC Q4) - lookdev-artist, scored by flicker_metric.
9. Lookdev values for satin edge, frosted face, tinted clear plastic, anodised finish, matte black against real reference photos. (TEC Q5) - lookdev-artist, approved by art-director.
10. Per-frame size of a 10-frame liquid cache in Alembic, VDB and USD; motion-blur test of `.velocities` vs `v`. (OUT 6.2,6.3) - fx-simulation-artist.
11. Is the FLIP Fluids `.bobj` layout stable across versions; is volume meaningful for open films? (GAP Q6) - fx-simulation-artist.
12. Mantaflow maintenance in the 5.0-5.3 physics notes. (ADD Q5) - researcher.
13. Does the STEP Importer zip bundle Cascadio; tolerances behind its presets; FreeCAD mesh-export controls. (ADD Q1,Q2) - researcher.
14. Flamenco's current release and Blender 5.x support. (ADD Q4, GAP Q9) - researcher.
15. Houdini licence agreement on Indie cache use and the Indie file format. (OUT Q1,Q2) - researcher; a written vendor answer needs the owner.
16. 4080 SUPER Blender Open Data score or OB rating. (SCA Q1) - researcher, or a local benchmark by render-wrangler.
17. Final 5.3 dispersion defaults after the 2026-11-10 release. (TEC Q1) - researcher.
18. Smooth by Angle operator idnames; was `sequences` removed in 5.0? (VER Q5,Q6) - blender-operator.
19. Which PNG colour chunks Blender 5.2 writes; does oiiotool `--printstats` report NaN counts? (GAP Q10,Q11) - blender-operator.

## Advisor corrections to the merge pass

- List cells rewritten as plain text (the pass emitted escaped HTML line breaks).
- Research items 1-4, 6-11, 18, 19 re-routed to the new render roles; the pass
  sent lookdev and simulation measurements to read-only leads
  (art-director) or non-render roles that do not run Blender.
- Decision 8 reordered: a paid test is a cost change (kernel rule 15), so
  deferring is the default recommendation.
- Decision 10 reworded (the pass wrote "16-bit-free 8-bit PNG").
- Decision 11 replaced. The pass recommended Pillow and numpy as optional with
  skip guards in CI; a skip in CI means those tests never run there. The
  advisor's proposal is in `.work/TASK.md` (Decisions): stdlib-only tool
  cores with a small PNG codec, numpy as an optional fast path, so every
  tool test runs in CI with no new dependency (kernel rule 13).
- Spot checks, one cited item per report, by the advisor on 2026-10-29:
  VER - Blender LTS page (5.2.3 and 4.5.15 dated 2026-10-22), match;
  ADD - FLIP Fluids README ("Blender 4.5 to 5.2 compatible", GPL add-on, MIT
  engine, MinGW only), match; SCA - RunPod pricing (all eight rates), match;
  OUT - SideFX Indie page (USD 299 / 449, USD 100K revenue, USD 1,000,000
  funding in 24 months), match; TEC - Cycles sampling manual page (Animated
  Seed "a good idea to enable this when rendering animations"), match;
  GAP - `blender --help` on the installed 5.2.3 (`--python-exit-code`: "zero
  disables"), consistent with the stored default of 0.
