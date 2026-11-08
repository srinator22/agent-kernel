# Blender versions, Python API breaks, headless Cycles (research)

Retrieved 2026-10-29. Scope: pin a portable Blender per project for scripted product renders (stills, animation, short films).
Evidence scale: `docs/library/procedures/evidence-levels.md` (E2 vendor doc, E4 official docs/release notes/source, E6 tracker or independent test, E8 unverified).
Method limit: pages were read through a fetch tool that summarises text, so wording is paraphrased unless in code quotes. Nothing was installed or downloaded. Anything not seen on a primary page is marked "unverified".

## Sources (all retrieved 2026-10-29)

| ID | URL | Level |
|---|---|---|
| S1 | https://www.blender.org/download/lts/ | E4 |
| S2 | https://www.blender.org/download/ | E4 |
| S3 | https://developer.blender.org/docs/release_notes/ (index) | E4 |
| S4 | https://developer.blender.org/docs/release_notes/5.2/ and https://www.blender.org/download/releases/5-2/ | E4 |
| S5 | https://developer.blender.org/docs/release_notes/5.2/python_api/ | E4 |
| S6 | https://developer.blender.org/docs/release_notes/5.0/python_api/ | E4 |
| S7 | https://developer.blender.org/docs/release_notes/4.4/python_api/ | E4 |
| S8 | https://developer.blender.org/docs/release_notes/5.1/python_api/ | E4 |
| S9 | https://developer.blender.org/docs/release_notes/4.1/python_api/ and .../4.1/modeling/ | E4 |
| S10 | https://developer.blender.org/docs/release_notes/4.2/python_api/ and .../4.2/eevee/ | E4 |
| S11 | https://developer.blender.org/docs/release_notes/4.5/python_api/ | E4 |
| S12 | https://developer.blender.org/docs/release_notes/5.0/compositor/ , .../5.0/eevee/ , .../5.0/ , .../5.0/animation_rigging/ | E4 |
| S13 | https://developer.blender.org/docs/release_notes/4.4/animation_rigging/ | E4 |
| S14 | https://docs.blender.org/manual/en/latest/advanced/command_line/arguments.html and .../render.html (manual titled 5.2 LTS) | E4 |
| S15 | https://docs.blender.org/manual/en/latest/render/cycles/gpu_rendering.html | E4 |
| S16 | https://docs.blender.org/manual/en/latest/render/cycles/render_settings/sampling.html | E4 |
| S17 | https://projects.blender.org/blender/blender/raw/branch/blender-v5.2-release/intern/cycles/blender/addon/properties.py (branch tip, may be newer than tag 5.2.3) | E4 |
| S18 | same branch: .../intern/cycles/blender/addon/operators.py and .../ui.py | E4 |
| S19 | same branch: .../source/creator/creator_args.cc and .../source/creator/creator.cc | E4 |
| S20 | same branch: .../build_files/build_environment/cmake/versions.cmake | E4 |
| S21 | https://developer.blender.org/docs/release_notes/{4.0,4.5,5.0,5.1,5.2}/cycles/ | E4 |
| S22 | https://download.blender.org/release/Blender5.2/ (directory listing) | E4 |
| S23 | https://projects.blender.org/api/v1/repos/blender/blender/issues/101726 (+ /comments) ; web view returned 403 | E6 |
| S24 | https://www.openimagedenoise.org/ | E2 |
| S25 | https://docs.blender.org/api/current/bpy.types.SequenceEditor.html , bpy.types.Action.html , bpy.types.Scene.html | E4 |
| S26 | https://docs.nvidia.com/cuda/cuda-programming-guide/05-appendices/environment-variables.html (search-result summary only, page not opened) | E2 |
| S27 | https://devtalk.blender.org/t/taking-a-look-at-optix-7-3-temporal-denoising-for-cycles/18656 and https://www.cgchannel.com/2026/01/open-image-denoise-3-will-support-temporal-denoising/ (search snippets only, pages not opened) | E8 |

## 1. Releases and download

| Item | Finding | Source |
|---|---|---|
| Latest stable | 5.2.3, released 2026-10-22 (patch of 5.2 LTS). 5.2.0 released 2026-07-14. Index lists 5.3 as beta and 5.4 as alpha, not stable | S2 S3 S22 VERIFY 2026-10-29 |
| Current LTS lines | 5.2 LTS (2026-07-14, "maintained until July 2028"); 4.5 LTS (2025-07-15, "supported until July 2027"; latest 4.5.15, 2026-10-22) | S3 S4 S1 VERIFY 2026-10-29 |
| Older LTS | 4.2 LTS: index says released 2024-07-16 and supported until July 2026 (period has ended; last patch 4.2.23, July 2026). LTS page says 2024-07-14: sources disagree by 2 days. 3.6 LTS last patch 3.6.22 (April 2025); end dates for 3.x not stated | S3 S1 VERIFY 2026-10-29 |
| Non-LTS | 5.1 (2026-03-17), 5.0 (2025-11-18), 4.4 (2025-03-18), 4.3 (2024-11-19), 4.1 (2024-03-26), 4.0 (2023-11-14) | S3 VERIFY 2026-10-29 |
| LTS policy | Critical fixes through a 2-year span; the LTS page gives per-line end dates only for some lines | S1 VERIFY 2026-10-29 |
| Windows x64 portable | `blender-5.2.3-windows-x64.zip`, 405839452 (listing, unit not printed; download page says 387 MB) | S22 S2 VERIFY 2026-10-29 |
| Windows arm64 portable | `blender-5.2.3-windows-arm64.zip`, 274053356 (261 MB on download page) | S22 S2 VERIFY 2026-10-29 |
| Linux | `blender-5.2.3-linux-x64.tar.xz`, 385331224; download page states glibc 2.28 or newer | S22 S2 VERIFY 2026-10-29 |
| macOS | `blender-5.2.3-macos-arm64.dmg` only (346295881); no zip; page states macOS 13 or newer. Intel Mac support removed in 5.0 | S22 S2 S12 VERIFY 2026-10-29 |
| Checksums | `blender-5.2.3.sha256` and `.md5` exist in the listing. The download page's checksum links pointed at 5.2.2 files on retrieval day, so fetch the checksum from the release folder | S22 S2 VERIFY 2026-10-29 |
| Other forms | Windows installer/msi/msix, Steam, Snap, Microsoft Store (page-listed, not needed for portable pins) | S2 S22 VERIFY 2026-10-29 |

URL pattern for a pin is `https://download.blender.org/release/Blender5.2/<file>` (derived from the listing; individual file links not opened).

## 2. Python API breaks since 4.0 (scripted renders)

### 2a. Actions and F-curves

| Version | Old form | New form | Source |
|---|---|---|---|
| 4.4 | Action = flat F-curve list | Slotted actions: action has `layers`, `strips`, `slots`, channelbags. Old data upgrades to one slot "Legacy Slot" | S13 S7 VERIFY 2026-10-29 |
| 4.4 | `anim_data.action = act` always animated the datablock | Assignment may not auto-pick a slot, leaving it unanimated; set `anim_data.action_slot = act.slots[0]`. NLA strip and Action constraint assignment auto-pick first compatible slot | S7 VERIFY 2026-10-29 |
| 4.4 (deprecated) | `action.fcurves`, `action.groups`, `action.id_root` | `action.layers[0].strips[0].channelbag(action.slots[0]).fcurves` / `.groups`; `action.slots[0].target_id_type` | S7 VERIFY 2026-10-29 |
| 5.0 (removed) | `action.fcurves`, `.groups`, `.id_root` | `channelbag.fcurves`, `channelbag.groups`, `action_slot.target_id_type`; helpers `anim_utils.action_get_channelbag_for_slot(action, slot)` and `anim_utils.action_ensure_channelbag_for_slot(action, slot)` | S6 VERIFY 2026-10-29 |
| 5.0 | `fcurves.new(..., action_group="G")` | `channelbag.fcurves.new(..., group_name="G")`; new `channelbag.fcurves.ensure(...)` returns existing or creates | S6 VERIFY 2026-10-29 |
| 5.0 | `INSERTKEY_XYZ_TO_RGB` flag for `keyframe_insert` options | removed; `context.space_data.action` -> `context.active_action` | S6 VERIFY 2026-10-29 |
| 5.2 docs | n/a | `bpy.types.Action` lists `layers`, `slots`, `is_action_layered`, `is_action_legacy`, method `fcurve_ensure_for_datablock(...)`; `fcurves` not seen in the visible part of the (truncated) page | S25 VERIFY 2026-10-29 |
| 4.4 note | `rna_struct.keyframe_insert` | Unchanged signature; the 4.4 page says it still creates action, layer, strip, channelbag and slot automatically. No later change to it was listed on the 5.0, 5.1 or 5.2 Python pages | S7 S6 S8 S5 VERIFY 2026-10-29 |
| 5.0 | `driver_add` via Python added an F-curve modifier | now creates two keyframes instead | S12 VERIFY 2026-10-29 |

### 2b. Compositor

| Version | Old form | New form | Source |
|---|---|---|---|
| 4.4 | `RenderSettings.use_new_cpu_compositor`, `PreferencesExperimental.enable_new_cpu_compositor` | removed; new CPU compositor always used | S7 VERIFY 2026-10-29 |
| 5.0 | `scene.node_tree` | `scene.compositing_node_group`; create with `bpy.data.node_groups.new(name, "CompositorNodeTree")`, assign to the scene, use `NodeGroupOutput` and `tree.interface.new_socket(...)` | S6 VERIFY 2026-10-29 |
| 5.0 | `scene.use_nodes = True` | deprecated, always `True`, setting does nothing, removal planned 6.0. Same for `material.use_nodes` and `world.use_nodes` (default node trees now created with the datablock) | S6 VERIFY 2026-10-29 |
| 5.0 | Composite node | removed; Group Output replaces it (first input must be Color; others ignored) | S12 VERIFY 2026-10-29 |
| 5.0 | `CompositorNodeOutputFile`: `base_path`, `file_slots`, `layer_slots` | `directory`, `file_name`, `file_output_items`; `file_slots[0].path` -> `file_output_items[0].name`. Frame number appended only for animation renders; command-line render always counts as animation; `####` in name substitutes the frame in single renders | S6 S12 VERIFY 2026-10-29 |
| 5.0 | `CompositorNodeGamma` and other nodes with shader counterparts | `ShaderNodeGamma` etc.; deprecated compositor nodes and old combine/separate nodes removed; output socket "RGBA" -> "Color"; Z Combine renamed Depth Combine; Alpha Over inputs renamed Background/Foreground | S6 S12 VERIFY 2026-10-29 |
| 5.0 | pass names `DiffCol`, `IndexMA`, `Z` | `Diffuse Color`, `Material Index`, `Depth` | S6 VERIFY 2026-10-29 |
| 4.2 | Box/Ellipse Mask `width`/`height` | `mask_width`/`mask_height` (page: "same for height") | S10 VERIFY 2026-10-29 |

### 2c. Video sequencer (VSE)

| Version | Old form | New form | Source |
|---|---|---|---|
| 4.4 | `bpy.types.Sequence`, `*Sequence` types (e.g. `ColorSequence`, `TextSequence`, `SceneSequence`) | `Strip`, `*Strip` (`ColorStrip`, `TextStrip`, `SceneStrip`); also `SequenceElement` -> `StripElement` etc. | S7 VERIFY 2026-10-29 |
| 4.4 | `SequenceEditor.sequences` / `.sequences_all`, `MetaStrip.sequences`, `context.sequences`, `context.selected_sequences`, `context.active_sequence_strip` | `.strips` / `.strips_all`, `.strips`, `context.strips`, `context.selected_strips`, `context.active_strip`. Old names "remain until 5.0" | S7 VERIFY 2026-10-29 |
| 5.2 docs | n/a | `bpy.types.SequenceEditor` attribute list shows `strips`, `strips_all`, `active_strip`, `channels`, `meta_stack`; `sequences` not in the listing. An explicit 5.0 removal note was not found (the 5.0 VSE release-notes page returned 404) | S25 VERIFY 2026-10-29 |
| 4.4 | Text strip `align_x`/`align_y` | `anchor_x`/`anchor_y`; `alignment_x` now truly aligns | S7 VERIFY 2026-10-29 |
| 4.5 | `strips.new_effect(seq1=, seq2=)` | `input1=`, `input2=` | S11 VERIFY 2026-10-29 |
| 5.0 | `context.scene` as the sequencer scene | `context.sequencer_scene` / `workspace.sequencer_scene`; image/effect strips `end_frame` -> `length` | S6 VERIFY 2026-10-29 |
| 5.1 (deprecated, removal 6.0) | `frame_final_duration`, `frame_final_start`, `frame_final_end`, `frame_offset_start/end`, `frame_duration`, `frame_start`, `animation_offset_start/end` | `duration`, `left_handle`, `right_handle`, `left_handle_offset`, `right_handle_offset`, `content_duration`, `content_start`, `content_trim_start`, `content_trim_end` | S8 VERIFY 2026-10-29 |
| 4.2 | `SequenceTransform.filter` value `SUBSAMPLING_3x3` | `BOX` | S9 VERIFY 2026-10-29 |

### 2d. Auto smooth (4.1), EEVEE, and other 4.x/5.x breaks

| Version | Old form | New form | Source |
|---|---|---|---|
| 4.1 | `Mesh.use_auto_smooth`, `Mesh.auto_smooth_angle` | removed; sharpness is the `sharp_edge` attribute, set by "a modifier node group asset" (page wording) or operators labelled "Set Sharpness by Angle" (edit mode) and "Shade Smooth by Angle" (other modes). Python operator idnames not seen: unverified | S9 VERIFY 2026-10-29 |
| 4.1 | `create_normals_split()`, `calc_normals_split()`, `free_normals_split()` | removed; `Mesh.corner_normals` collection auto-updates; `MeshLoop.normal` read-only; use `normals_split_custom_set` / `normals_split_custom_set_from_vertices` | S9 VERIFY 2026-10-29 |
| 4.1 | Python 3.10 (not stated) | Python 3.11 | S9 VERIFY 2026-10-29 |
| 4.2 | EEVEE engine id (old id not given on page) | `BLENDER_EEVEE_NEXT`. Page says EEVEE was "rewritten"; an explicit "legacy EEVEE removed" sentence was not seen: unverified | S10 VERIFY 2026-10-29 |
| 4.2 | `scene.eevee.motion_blur_shutter`, `.motion_blur_position`, `scene.cycles.motion_blur_position` | `scene.render.motion_blur_shutter`, `scene.render.motion_blur_position`. Page also writes `scene.render.user_motion_blur` for the use flag: probable typo, unverified | S10 VERIFY 2026-10-29 |
| 4.2 | `Material.blend_method`; `light.cycles.cast_shadow`; `displacement_method` in cycles settings | `Material.surface_render_method`; `light.use_shadow`; `Material.displacement_method` (page, 4.2 and 4.1 notes respectively) | S10 S9 VERIFY 2026-10-29 |
| 4.2 | EEVEE bloom props (`scene.eevee.use_bloom`, `bloom_*`, `view_layer.eevee.use_pass_bloom`) | deprecated | S10 VERIFY 2026-10-29 |
| 4.2 | light probe types `CUBEMAP`/`PLANAR`/`GRID` (noted in the 4.1 page) | `SPHERE`/`PLANE`/`VOLUME` | S9 VERIFY 2026-10-29 |
| 4.2 | IDProperties loosely typed | statically typed; assignment converts where reasonable, else fails | S10 VERIFY 2026-10-29 |
| 5.0 | `BLENDER_EEVEE_NEXT` | `BLENDER_EEVEE`; `scene.eevee.gtao_distance` -> `view_layer.eevee.ambient_occlusion_distance`; `gtao_quality`, `use_gtao` removed | S6 S12 VERIFY 2026-10-29 |
| 5.0 | `scene['cycles']`, `obj['prop']` dict-style access to `bpy.props` storage | removed; use attribute access (`scene.cycles`), `obj.property_unset(...)`, `obj.bl_system_properties_get()`; `get` without `set` makes read-only, `set` without `get` is an error | S6 VERIFY 2026-10-29 |
| 5.0 | `image_settings.file_format = ...` alone | set new `media_type` member before `file_format` | S6 VERIFY 2026-10-29 |
| 5.0 | BGL module, `Image.bindcode` | removed | S6 VERIFY 2026-10-29 |
| 5.0 | `mathutils.Vector` float64 buffer | float32 buffer; matrices to numpy are non-contiguous | S6 VERIFY 2026-10-29 |
| 5.0 | UV selection per UV map; `BMLoopUV.select` | removed; shared `uv_select_vert/edge/face` | S6 VERIFY 2026-10-29 |
| 5.0 | Boolean solver `FAST` | `FLOAT` | S6 VERIFY 2026-10-29 |
| 5.0 | USD export `export_textures`, `visible_objects_only`; Alembic `Scene.alembic_export` | removed (`export_textures_mode`); USD `allow_unicode` now defaults true | S6 VERIFY 2026-10-29 |
| 5.0 | bundled helper modules (`bl_*`, `rna_info`, others) | made private | S6 VERIFY 2026-10-29 |
| 5.0 | log output format and background render progress text | changed; parsers may need updating | S6 VERIFY 2026-10-29 |
| 5.1 | Python 3.11 | Python 3.13 (build env of 5.2 branch: 3.13.13). 5.0's Python version not stated on pages read: unverified | S8 S20 VERIFY 2026-10-29 |
| 5.2 | `modifier["Socket_2"]`-style Geometry Nodes modifier input access | `modifier.properties.inputs.<identifier>.value`; attribute mode via `.type = "ATTRIBUTE"`, `.attribute_name`; Compare and Random Value socket identifiers changed (old/new not listed) | S5 VERIFY 2026-10-29 |
| 5.2 | `PreferencesFilePaths.active_asset_library` index == `asset_libraries` index | no longer matches ("All Libraries" and "Essentials" prepended) | S5 VERIFY 2026-10-29 |
| 5.2 | IDProperties nesting unlimited | limit 1024 levels | S5 VERIFY 2026-10-29 |
| 5.0 | Cycles: NVIDIA below sm_50 | dropped; Windows AMD minimum driver raised; blend-file compression on save now default | S12 S21 VERIFY 2026-10-29 |

Not found on primary pages: Cycles-specific Python property renames in 5.0, 5.1, 5.2 (those Cycles notes list none). 5.0 Cycles volume rendering default changed to null-scattering (look change, not API): `Render -> Volume -> Biased` restores the old method (S21 VERIFY 2026-10-29).

## 3. Headless command line (5.2 LTS manual)

| Flag | Behaviour as documented | Source |
|---|---|---|
| `-b`, `--background` | No UI; audio off by default in this mode | S14 VERIFY 2026-10-29 |
| `--factory-startup` | Skip user `startup.blend` (source help text: skip reading the startup file in the user's home) | S14 S19 VERIFY 2026-10-29 |
| `-P file.py` | Run a Python script | S14 VERIFY 2026-10-29 |
| `--python-expr "code"` | Run an expression as a script | S14 VERIFY 2026-10-29 |
| `--python-exit-code N` | "Set the exit-code in [0..255] to exit if a Python exception is raised (only for scripts executed from the command line), zero disables." Source initialises the value to 0 | S14 S19 VERIFY 2026-10-29 |
| `-o path` | Output path; `//` is blend-relative; each `#` = zero-padded frame digit; no `#` appends `####`; `{blend_name}` style templates supported | S14 VERIFY 2026-10-29 |
| `-F fmt` / `-x 1` | Format override (PNG, JPEG, TIFF, ... ; OPEN_EXR, FFMPEG, WEBP only if compiled in) / add file extension | S14 S15 VERIFY 2026-10-29 |
| `-E engine` | Engine; `-E help` lists engines | S14 VERIFY 2026-10-29 |
| `-s N` `-e N` | Start / end frame (accept +/- relative) | S14 VERIFY 2026-10-29 |
| `-f spec` | Render frame(s): single, comma list without spaces, `..` inclusive range, negative counts from end | S14 VERIFY 2026-10-29 |
| `-a` | Render start..end inclusive | S14 VERIFY 2026-10-29 |
| `-j N` | Frame jump after each rendered frame | S14 VERIFY 2026-10-29 |
| `-t N` | Threads 1..1024; 0 = system count | S14 VERIFY 2026-10-29 |
| `--cycles-device X` | CPU, CUDA, OPTIX, HIP, ONEAPI, METAL; `+CPU` suffix adds the CPU. Manual says Cycles options must come after `--` | S14 VERIFY 2026-10-29 |
| `--` | Stop Blender option parsing; rest available in `sys.argv` | S14 VERIFY 2026-10-29 |
| `--log "a,b"`, `--log-level L`, `--log-file path` | Categories with `*` wildcards and `^` exclude; levels fatal, error, warning, info, debug, trace; log to file | S14 S19 VERIFY 2026-10-29 |
| `--debug-cycles` | Cycles debug messages (source: enables logging filter `cycles.*`) | S14 S19 VERIFY 2026-10-29 |
| `-noaudio` | Force sound system None | S14 S19 VERIFY 2026-10-29 |

Order rule (manual): arguments execute in the order given; set `-o`/`-F`/`-x` after the blend file and before `-f`/`-a`; put `-f`/`-a` last; `blender -b f.blend -a -x 1 -o //r` does not work, `blender -b f.blend -x 1 -o //r -a` does. Flags are case sensitive (`-f` frame, `-F` format). Source: S14 VERIFY 2026-10-29.

Non-zero exit on Python exception: the documented route is `--python-exit-code N` (N in 1..255). Default stored value is 0 (S19), so without the flag an exception is not reflected in the exit code per the source; this is inference from "zero disables" plus the initialiser (see Interpretation). The code path that reads the value on failure was not seen. Exit code for non-Python render failures: unverified.

## 4. Cycles device selection from Python (`properties.py`, 5.2 branch tip)

| Item | Finding | Source |
|---|---|---|
| Prefs object | `bpy.context.preferences.addons['cycles'].preferences` (class `CyclesPreferences`, `bl_idname = __package__`) | S17 VERIFY 2026-10-29 |
| `compute_device_type` | Enum items `NONE`, `CUDA`, `OPTIX`, `HIP`, `METAL`, `ONEAPI`, each only if the build reports support; default is item index 0 except Apple Silicon (index 5) | S17 VERIFY 2026-10-29 |
| `devices` | Collection of `CyclesDeviceSettings`: `id` (persistent id), `name`, `type`, `use` (bool) | S17 VERIFY 2026-10-29 |
| Default `use` | New entries get `use = (type != 'CPU')` | S17 VERIFY 2026-10-29 |
| `get_devices()` | Marked "Deprecated: use refresh_devices instead"; calls `refresh_devices()` and returns None | S17 VERIFY 2026-10-29 |
| `refresh_devices()` | Queries CUDA, OPTIX, HIP, METAL, ONEAPI; "does not happen automatically on Blender startup due to unstable drivers" | S17 VERIFY 2026-10-29 |
| `get_devices_for_type(t)` | Returns entries of type `t` plus the CPU entries when GPUs exist | S17 VERIFY 2026-10-29 |
| Match key | An entry matches a detected device when both `id` and `type` equal | S17 VERIFY 2026-10-29 |
| Scene switch | `scene.cycles.device` enum `'CPU'` (default) or `'GPU'` | S17 VERIFY 2026-10-29 |
| UI path | Manual: pick backend, tick devices, set scene Device to GPU Compute | S15 VERIFY 2026-10-29 |
| Backends | CUDA (NVIDIA CC 5.0+); OptiX (CC 5.0+, driver at least 575, RT cores on RTX); HIP, oneAPI, Metal with their driver floors | S15 S21 VERIFY 2026-10-29 |
| Multi-GPU | Each GPU only sees its own memory; NVLink peer memory is the exception (preference "Distributed Memory Across Devices"; property `peer_memory`) | S15 S17 VERIFY 2026-10-29 |
| Env var | Manual device-selection text mentions no `CUDA_VISIBLE_DEVICES` or similar; NVIDIA doc says that variable limits which GPUs a CUDA process sees (by index or UUID, unset = all, empty = none, `CUDA_DEVICE_ORDER=PCI_BUS_ID` to fix order) | S15 S26 VERIFY 2026-10-29 |

Sketch (derived from S17; not executed here):

```python
import bpy, sys
p = bpy.context.preferences.addons['cycles'].preferences
p.compute_device_type = 'OPTIX'      # or 'CUDA'
p.refresh_devices()
for d in p.devices:
    d.use = (d.type == 'OPTIX' and d.id == TARGET_ID)   # CPU entries stay off
bpy.context.scene.cycles.device = 'GPU'
```

## 5. Denoising

| Item | Finding | Source |
|---|---|---|
| Denoisers | OpenImageDenoise ("typically provides the highest quality"), OptiX ("supports GPU acceleration on some older NVIDIA GPUs"), Automatic (prefers OIDN GPU when supported) | S16 VERIFY 2026-10-29 |
| OIDN version in 5.2 | `OIDN_VERSION 2.5.0` in the 5.2 release branch build environment (branch tip; shipped binary version not confirmed). Upstream OIDN lists v2.5.1 as latest, undated | S20 S24 VERIFY 2026-10-29 |
| OIDN GPU support | Intel Xe/Xe2/Xe3; NVIDIA Turing, Ampere, Ada, Hopper, Blackwell (Volta removed in 2.4.0); AMD RDNA 2 to 4; Apple M1+. NVIDIA drivers Windows 528.33+, Linux 525.60.13+. Blender manual: OIDN GPU on NVIDIA needs CC 7.0+; OptiX needs driver 575+. 5.2 notes: OIDN no longer GPU accelerated on RDNA2 | S24 S15 S21 VERIFY 2026-10-29 |
| Property names | `scene.cycles.denoiser` (items OptiX and OpenImageDenoise; default stored as integer 4 with comment about builds without OIDN), `use_denoising` (default True), `denoising_use_gpu` (default False), `denoising_input_passes` (`RGB`, `RGB_ALBEDO`, `RGB_ALBEDO_NORMAL`; default `RGB_ALBEDO_NORMAL`), `denoising_prefilter` (`NONE`, `FAST`, `ACCURATE`; default `ACCURATE`), `denoising_quality` (`HIGH`, `BALANCED`, `FAST`; default `HIGH`); view layer `denoising_store_passes` | S17 S18 VERIFY 2026-10-29 |
| Manual guidance | Use at least Albedo ("None can blur out details"); prefilter None assumes noise-free input, Fast blurrier, Accurate more detailed but slower; quality High best | S16 VERIFY 2026-10-29 |
| Animation | Manual: enable Animated Seed for animations "because a varying noise pattern is less noticeable". No manual statement on temporal stability of either denoiser | S16 VERIFY 2026-10-29 |
| Temporal | Denoise panel code has no "temporal" reference. Operator `bpy.ops.cycles.denoise_animation` ("Denoise Animation": uses scene/view layer settings; needs denoising data passes and multilayer OpenEXR output; props `input_filepath`, `output_filepath`) exists on the 5.2 branch; whether it is cross-frame is not stated | S18 S27 VERIFY 2026-10-29 |
| OptiX temporal (old) | A forum test from the OptiX 7.3 era reported a temporal OptiX mode loses detail for stability; page not opened, 2021-era | S27 VERIFY 2026-10-29 (E8) |
| OIDN temporal | A trade press report says OIDN 3 will add temporal denoising; not in any 5.x Blender note read | S27 VERIFY 2026-10-29 (E8) |
| OptiX denoiser change | 5.0: OptiX denoise quality improved (image flipped to top-left origin) | S21 VERIFY 2026-10-29 |
| 5.1 | "Improved denoising quality with textured transparency and roughness" | S21 VERIFY 2026-10-29 |

## 6. Determinism

| Item | Finding | Source |
|---|---|---|
| Seed | `cycles.seed` int 0..2147483647, default 0; `use_animated_seed` default False; manual: seed changes the noise pattern, animated seed changes it per frame | S17 S16 VERIFY 2026-10-29 |
| Sample subset | Manual offers Sample Subset (offset, length) for splitting samples across machines | S16 VERIFY 2026-10-29 |
| Adaptive | `use_adaptive_sampling` default True, `adaptive_threshold` 0.01 (0 = automatic), `adaptive_min_samples` 0 (automatic). No source read ties adaptive sampling to determinism | S17 VERIFY 2026-10-29 |
| Known non-determinism | Tracker issue 101726 "Cycles does not generate the exact same images when a scene is rendered twice": open, status Confirmed, Known Issue, reproduced again 2026-02-27. Reported on an NVIDIA 2070 Super and on CPU | S23 VERIFY 2026-10-29 (E6) |
| Cause (developers) | Multithreaded float atomic accumulation in mesh normal and tangent calculation (`BKE_mesh_calc_normals_poly_and_vertex`, `Mikktspace::generateTSpaces`); small differences then change later sampling; `blender -t 1` gave an exact match; a Nov 2023 commit helped, normal-map tangent determinism stayed open | S23 VERIFY 2026-10-29 (E6) |
| Cross-device | No primary page read states bit-identical output across CPU vs GPU, or across different GPU models. A search snippet of an old tracker task attributes a CPU/GPU mismatch to float precision on nearly overlapping transparent faces (closed not a bug); page not opened | S27-class snippet, E8: unverified |

## Interpretation (mine, not from sources)

- Pin: Blender 5.2.3 LTS windows-x64 zip is the natural default (LTS to July 2028, newest patch). 4.5 LTS (to July 2027) is the fallback only for scripts that cannot move to the 5.0 API removals. Templates should record version, file name, sha256 and bytes in a lockfile and verify before first run; never auto-update inside a project.
- Shim layer (`blender_compat`) minimum surface: action/channelbag access (`action.fcurves` gone in 5.0; prefer `fcurve_ensure_for_datablock` or channelbag helpers), compositor entry (`compositing_node_group`, Group Output, File Output item API), EEVEE id (`BLENDER_EEVEE` vs `BLENDER_EEVEE_NEXT` vs older), `strips` vs `sequences`, smooth-by-angle (operator or node asset), `scene['cycles']` dict access, `image_settings.media_type` ordering, GN modifier input access. Feature-detect with `hasattr` rather than version tuples where possible.
- Exit codes: always pass `--python-exit-code 1` and also wrap the script body in try/except calling `sys.exit(1)` (belt and braces). Prove it with a self-test script that raises, run on the pinned build, and record the measured exit code (E1) rather than relying on this inference. Parse logs from `--log-file`; since 5.0 changed progress text, avoid regex on progress lines.
- Pin one process to one GPU: select by `device.id` in the script (source-backed), not by list index, and switch CPU entries off explicitly because `get_devices_for_type` appends them. Under `--factory-startup` no saved prefs load, so set `compute_device_type` and `scene.cycles.device` explicitly (default device enum is CPU; default compute type is the first item). `CUDA_VISIBLE_DEVICES` is a plausible second layer for multi-process farms but its interaction with Cycles/OptiX device ids is untested here; measure before relying on it.
- Denoise defaults for stills: OIDN, Albedo+Normal, prefilter Accurate, quality High, `denoising_use_gpu = True` (default is False). The 4080 SUPER class (Ada) is listed by OIDN. For animation no primary source ranks OIDN vs OptiX on temporal stability; safest evidence-backed choice is OIDN with animated seed on (manual advice) plus denoising data passes stored, and a measured flicker test on a representative shot before committing. Treat `denoise_animation` as unproven for temporal benefit until measured.
- Determinism: expect repeatability on the same machine and build only when thread-ordering effects are absent; do not promise bit-identical frames across runs, GPUs or CPU vs GPU. Template should specify "same seed, same build, same device, same driver" as a reproduction recipe and verify with its own hash test (E1), with tolerance-based image compare (not byte compare) for acceptance. Animated seed trades identical noise per frame for less visible pattern.

## Open questions

1. Does `--python-exit-code 1` reliably return non-zero for exceptions raised inside `-P` scripts in 5.2.3, including exceptions inside handlers and operators? (Needs a measured self-test.)
2. What does `device.id` look like for CUDA and OptiX entries on Windows (PCI-based?), and is it stable across reboots and driver updates?
3. Does the 5.2 `denoise_animation` operator use cross-frame information? Is there any temporal denoising in shipped Blender 5.x?
4. Is OIDN 2.5.0 (branch build env) what the 5.2.3 binary ships?
5. Was `SequenceEditor.sequences` explicitly removed in 5.0 (no release-note line found)?
6. Exact Python idnames of the Smooth by Angle operators and the shipped asset name.
7. Same-frame bit-identity across runs on one GPU in 5.2.3 with `-t` default, and with adaptive sampling on: needs measurement.
8. LTS end dates for 3.x lines and the 4.2 release date conflict (2024-07-14 vs 2024-07-16).
9. Does `CUDA_VISIBLE_DEVICES` change which devices Cycles lists with OptiX on Windows?

## Bears on

| Template part | Findings that affect it |
|---|---|
| `blender_run` wrapper tool | Flag order (-o before -f/-a), `--python-exit-code`, `--log-file`/`--log-level`, `--` arg passing, version lockfile with sha256, portable zip names per OS, no macOS zip, exit-code self-test |
| `blender_compat` shim layer | Section 2 tables (actions/channelbags, compositing_node_group, File Output items, EEVEE ids, strips, auto smooth, dict-style props, media_type, GN modifier inputs, Python 3.11/3.13) |
| Render presets | Denoise property names and defaults (`denoising_use_gpu` default False), adaptive defaults, seed policy, volume default change in 5.0, `device`/`compute_device_type` setup |
| Render technical director agent | Determinism limits and acceptance by tolerance, denoise choice needing a measured flicker test, per-GPU pinning by device id, OptiX driver floor 575 |
| Release/pin policy and docs | LTS dates (5.2 to July 2028, 4.5 to July 2027), revalidate the pin when a new LTS ships or when a project upgrades |
| Researcher follow-ups | Open questions 1 to 9 as bounded measurement tasks (E1) |
