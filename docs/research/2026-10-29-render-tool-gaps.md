# Render tool gaps - what exists, what to build (2026-10-29)

Question: for the opt-in Blender product-render capability, which candidate library tools are already
covered by a maintained free tool, which runtime each tool we build needs, what verifies an encoded MP4
without ffprobe, what the candidate list misses, and the final recommended list.

Method: read a prior product film project's scripts (referred to only as "a product film project", by
role) and checked primary pages this session (2026-10-29). No Blender run, no render, nothing installed or
downloaded. One inline Python run (nothing written) parsed two previously encoded MP4s from that project.

## Source key (every external fact below cites one of these)

All rows: retrieved 2026-10-29. VERIFY 2026-10-29 applies to every version number and feature statement
that cites them. Evidence levels per `docs/library/procedures/evidence-levels.md`.

| ID | Source | Level | Note |
|---|---|---|---|
| S1 | https://docs.blender.org/manual/en/latest/advanced/command_line/arguments.html | E4 | page title says Blender 5.2 LTS manual |
| S2 | https://docs.blender.org/manual/en/latest/render/output/properties/output.html | E4 | 5.2 LTS manual, Output properties |
| S3 | https://docs.blender.org/api/current/bpy.types.MovieClip.html | E4 | API version selector shows 5.2 |
| S4 | https://developer.blender.org/docs/release_notes/5.0/python_api/ | E4 | 5.0 Python API breaking changes (first 100000 chars read of ~107000) |
| S5 | https://flamenco.blender.org/ | E4 | landing page |
| S6 | https://flamenco.blender.org/usage/quickstart/ | E4 | quickstart |
| S7 | https://ffmpeg.org/ffprobe.html | E4 | ffprobe docs |
| S8 | https://ffmpeg.org/ffmpeg-filters.html | E4 | partly read (chars 0-100000, 200000-300000, 500000-600000 only) |
| S9 | https://github.com/NVlabs/flip | E4 | README, v1.7 stated |
| S10 | https://github.com/Netflix/vmaf | E4 | README |
| S11 | https://openimageio.readthedocs.io/en/latest/oiiotool.html | E4 | documents OpenImageIO 3.3.0; read chars 0-200000 |
| S12 | https://imagemagick.org/script/montage.php | E8 | returned only a redirect to /montage/; not read |
| S13 | https://www.loc.gov/preservation/digital/formats/fdd/fdd000155.shtml | E4 | names ISO/IEC 14496-12 as the base file format; no box detail |
| S14 | https://pypi.org/project/pyloudnorm/ | E8 | search-result snippets only; page not opened |
| S15 | https://pypi.org/project/OpenImageIO/ | E8 | search-result snippets only; page not opened |
| L1 | Local machine probe (this session) | E6 | reproducible commands, one machine |
| L2 | Prior project scripts, read only | E7 | behaviour inferred from code, never re-run here |
| L3 | Local parse test of two MP4s (see section 3) | E6 | two files, one encoder |

Anything not tied to a row above and not marked L is my own reasoning and is flagged "judgement" or
"unverified".

## 0. Local facts that differ from the brief (L1)

- System Python 3.13 also has numpy 2.3.1, scipy 1.16.0 and opencv-python-headless 5.0.0.93 besides
  Pillow 12.2.0. The brief listed only Pillow and numpy. These extras must not be assumed in CI or on
  another machine; treat scipy and OpenCV as optional cross-checks.
- No ffmpeg, ffprobe, oiiotool, idiff or ImageMagick was found on PATH.
- The portable Blender folder has `avcodec-62.dll` and `avformat-62.dll` under `blender.shared` (library
  files only, no ffmpeg executable). Blender encodes video through these.
- Template tool convention (L1, read from `docs/library/tools/`): stdlib Python, `--help`, exit 0/1/2,
  tests run as `python -I -m unittest discover -s docs/library/tools/tests`. Pillow/numpy tools are the
  first ones to need optional imports; they need a skip guard in tests.

## 1. What the prior project's scripts contain (L2, by role)

Generic logic worth porting:
- Compat shim: F-curve access across the 5.0 slotted-action break (channelbag lookup) and mesh
  auto-smooth after 4.1. Elsewhere inline `hasattr` branches choose between old and new APIs for the
  sequencer strip collection, the video media-type property, the compositor node tree vs node group, and
  the denoiser quality property. Matches the S4 breaks.
- Contact sheet (about 14 lines, Pillow): N-column grid, tile label = folder/file name.
- Review sheets (about 21 lines, Pillow): every Nth frame, 4x4 tiles, label = frame number and seconds.
  It assumes a 4-digit numeric file-name prefix and a fixed 30 fps.
- Encode script: runs inside Blender; builds an image strip from the frames, sets resolution from the
  first frame, FFMPEG/MPEG4/H264, constant-quality "perceptually lossless", slowest preset, audio none,
  view transform forced to Standard "because frames are already graded". That last line is a double
  view-transform trap worth linting.
- Chunk run scripts (two, near-duplicates): loop over "finish first last" specs, call Blender headless
  with `--factory-startup`, redirect each chunk to its own log, print elapsed seconds and only the last
  log line. They do not scan for tracebacks and do not write a STATE file. Quality knobs travel as
  environment variables (samples, seed, frame list, hide-list, several debug dump modes).
- Main shot script: global frame timeline, chunking by `FIRST LAST` arguments, frames named by global
  frame number so chunks never collide. It contains: (a) a camera path builder - monotone cubic Hermite
  (PCHIP tangents) through waypoints, "never overshoots a waypoint, stops only at the ends and at local
  extremes", keyed per frame, linear interpolation; (b) an on-screen-motion-per-frame dump that lists
  near-still runs below a threshold; (c) an anchor export - world_to_camera_view of tagged empties for
  every frame to JSON for the label overlay; (d) GPU device selection by trying OPTIX then CUDA and
  enabling every non-CPU device; (e) many one-off debug dumps behind environment variables.
- Post/overlay script (Pillow): callout labels (ring, leader line, text, soft shadow), animated in/hold/out
  timeline, side-lock chosen by scoring on how many visible frames each side fits inside the frame
  (labels once flipped sides mid-fade near an edge), centred spaced caption, fades, light-sweep wipe
  between two renders, title card.
- Placements: a JSON of CAD occurrences (name, part id, 4x4 matrix, units). Product specific; not generic,
  but the shape (occurrences plus units) suggests a generic "assembly placement" import format.
- Sim build and resurface: sets up a third-party FLIP fluid add-on domain, obstacles and an inflow sized
  from the commanded flow every frame; reads its per-frame `.bobj` cache directly with numpy+struct
  (layout observed in the code: int32 vertex count, float32 xyz, int32 triangle count, int32 index
  triples; velocity file same layout); rebuilds the thin film as a smoother sheet. The inflow code carries
  a hand-tuned factor with the comment that the solver "emits ~1/4 of its section" - evidence of silent
  under-emission found by eye, which sim_validate should catch automatically. The `.bobj` layout and the
  add-on were not verified against the add-on's own documentation this session (unverified).
- No script in the set checks anything automatically; all review was visual (contact sheets) and by dump
  modes read by a human.

## 2. Per candidate: existing tool or build

Verdict key: BUILD = no adequate maintained free tool found; WRAP = call an existing tool; HYBRID.

| Candidate | Existing tool (source) | Verdict |
|---|---|---|
| blender_run | Blender CLI covers `--background`, `--factory-startup`, `--python`, `--log-file`, and `--python-exit-code` ("sets the exit code (0-255) used when a Python exception occurs in a command-line script") [S1]. Not covered: finding the pinned portable build, scanning the log for tracebacks that were caught and printed, recording version and argv. | BUILD thin wrapper over the CLI |
| render_chunks | Blender `--frame-start/--frame-end/--render-anim`, `--cycles-device` (CPU, CUDA, OPTIX, HIP, ONEAPI, METAL, `+CPU` suffix) [S1]. Output option "Overwrite" off keeps existing files; manual hint for parallel renders: share a directory, disable Overwrite, enable Placeholders [S2]; the page does not describe resuming an interrupted animation [S2]. Flamenco: GPL 3.0 render management, Manager + Worker + shared storage, "runs on all major operating systems" [S5][S6]; pages do not state Blender 5.x support or chunk size [S5][S6] (unverified). | BUILD small driver; do not wrap Flamenco (multi-machine, overkill for one GPU). Reconsider if a second machine appears |
| frame_audit | oiiotool `--printstats` (stats on top image), `--fixnan` (repairs NaN/Inf), `--info -v` [S11]; whether `--printstats` reports NaN counts: unverified. ffmpeg `blackdetect` and `blackframe` find black stretches/frames in video [S8], but run on encoded video, not frames. Not installed here [L1]. | BUILD (Pillow+numpy). Optionally call oiiotool if present for EXR |
| flicker_metric | NVIDIA FLIP compares a test image to a reference; README does not mention video or temporal metrics [S9]. VMAF is a full-reference perceptual quality metric, used as an ffmpeg filter [S10]; needs a reference video (judgement: it measures encode quality vs a source, not temporal instability). ffmpeg lists a `deflicker` filter [S8]; description not read, by name it modifies video (unverified). | BUILD (numpy). Neither FLIP nor VMAF measures temporal instability |
| motion_check | No maintained tool found for camera/animation stop, accel-spike, overshoot or label-side checks (not an exhaustive search; unverified). | BUILD |
| contact_sheet, review_sheet | oiiotool `--mosaic` tiles images into a grid, `--text` draws text [S11]; ImageMagick montage: not read, only a redirect [S12] (unverified). Neither installed here [L1]. | BUILD in Pillow (about 40 lines; already exists as a 14+21 line port source) |
| scene_lint | None found (not exhaustive; unverified). | BUILD |
| fit_check | None found. Blender Python may offer BVH overlap queries; not checked this session (unverified). | BUILD, coarse v1 |
| sim_validate | None found; the add-on's own stats were not checked (unverified). | BUILD |
| encode_verify | ffprobe: container and stream info as JSON (`-of json`), `-count_frames` counts frames per stream [S7]. Not installed [L1]. | HYBRID: use ffprobe if on PATH, else built-in pure-Python parser (section 3) |
| render_estimate | No tool found. Blender log per-frame time format not verified this session (unverified). Cloud prices: no primary price page read; prices change often. | BUILD small; price table is user-supplied data with a date column, not shipped numbers |
| blender_compat | S4 is the authoritative break list; no reusable shim library found. | BUILD shim module plus a break table |

Corrections to the candidate list:
- Merge contact_sheet and review_sheet into one `sheets` tool (same code; review adds zoom crops).
- Split encode from encode_verify: encode must run inside Blender (its bundled FFmpeg libs), verify can be
  pure Python. The candidate list had only the verify half.
- "NaN outliers" can only occur in float images (EXR). If the pipeline writes 8-bit PNG, NaNs cannot
  appear in the file; firefly and blank-frame checks still apply. Decide the intermediate format first.
- fit_check as written ("collisions at each keyframe state") needs real mesh distance; a v1 using bounding
  boxes plus sampled vertices is feasible, an exact check is not worth building first.
- render_estimate must not hard-code prices (stale on arrival).

## 3. Verifying an encoded MP4 without ffprobe

Options, in order of recommendation:

A. Pure-Python ISO base media file format box parser (stdlib `struct`). Tested this session on two real
   Blender-encoded H.264 files (960x540 and 1920x1080, 30 fps), each with top-level boxes
   `ftyp, free, mdat, moov` and a single video track (L3, E6). Read: `mvhd` (timescale, duration),
   `tkhd` (width/height as 16.16 fixed point), `mdhd` (media timescale, duration), `hdlr` (track kind),
   `stsd` (sample entry `avc1`, coded width/height), `stts` (sample count and constant delta),
   `stsz` (sample count, total bytes). Derived: fps = media timescale / sample delta (15360/512 = 30),
   duration = mvhd duration / timescale, average bitrate = stsz bytes x 8 / duration. Run time about
   1 ms per file. Frame counts, fps and resolution on both files agreed with OpenCV's own readout (L3).
   Spec reference: ISO/IEC 14496-12 [S13]; the box layouts used were from my knowledge and confirmed only
   empirically on these two files, not from the spec text (unverified beyond L3).
   Reliability: exact for container metadata. It does not decode, so it cannot detect a corrupt bitstream,
   wrong colour range or primaries (the `colr` box could be added), or a stalled last frame. Must refuse
   (exit 2, "cannot verify") on fragmented MP4 (`moof`), variable `stts`, 64-bit sizes it does not handle,
   or a missing `moov`. Judgement: a muxer that writes `moov` last (as here) is fine for a seekable file.
B. ffprobe when present: `-of json -show_streams`, plus `-count_frames` to count decoded frames [S7].
   Strongest because it decodes. Not available here, and we may not install it [L1].
C. Blender's own FFmpeg through Python: `bpy.data.movieclips.load()` then read-only `fps` ("detected frame
   rate"), `frame_duration` ("detected duration ... in frames") and `size` (zero if image data cannot be
   loaded) [S3]. Needs a Blender launch (seconds), cannot run in CI, and the values are "detected" by
   Blender (so they are a second opinion from the same FFmpeg that wrote the file, not an independent
   one). Good as a local cross-check; a size of (0, 0) is a useful "could not decode" signal.
D. OpenCV `VideoCapture` (installed locally, 5.0.0.93): frame count, fps, size matched on both files (L3).
   Optional only; not baseline. Reliability of its frame-count property on other containers: unverified.

Recommended: A always; B when found; C or D as optional cross-checks. A disagreement among available
methods is exit 1; no method able to run is exit 2. Also assert the stream count (expect 1 video, 0 audio
unless the deliverable has audio) and compare frame count with the number of source frames.

## 4. Gaps the candidate list misses

1. Colour and view-transform check on output frames (new). Two parts: (a) scene side, in scene_lint:
   view transform, look, display device, and a "graded twice" rule (render with a look, then encode with
   a non-Standard transform); (b) frame side, Pillow+numpy: bit depth and mode, PNG colour-profile
   chunks present or not (exact chunks Blender writes: unverified), fraction of clipped whites and
   crushed blacks, histogram sanity. Frame-side checks only catch gross errors; they cannot prove the
   transform was right.
2. Label/overlay renderer (port, large): anchor export (Blender side) to JSON; callout drawing; animated
   timeline easing; side-lock by scoring visible frames; captions; fades; wipe; title card. Port hazards
   (L2): it looks up system fonts by Windows file names with a Pillow default fallback, so output
   differs across machines; one function reads a module-level table that is defined later in the file;
   all timing, text and layout are inline constants. Tests should assert geometry and timing (fits,
   side choice, easing, bounding boxes), not pixels.
3. Safe-area check (small, new): text and label bounding boxes must lie inside configurable margins.
   Standard margin values were not looked up this session (unverified); make them parameters.
4. Frame-to-frame duplicate detection (small, new, inside frame_audit): hash of pixel data for consecutive
   frames plus a downscaled-difference threshold for near duplicates (Cycles with differing seeds is never
   byte-identical). Reports runs; intentional holds are allowed by an allow-list.
5. Deliverable bundler (small, new): copies the scripts, preset files and a README beside each delivered
   version with a sha256 manifest, the Blender version and argv (from blender_run), and the repo revision.
   The prior project did this by hand (a manually numbered source folder with a README of commands).
6. Named preset file (small, new): the prior flow passed quality through environment variables. A JSON
   preset (samples, denoiser, clamp, resolution, motion blur, colour settings) is what scene_lint compares
   "settings vs named preset" against and what the bundler ships.
7. Audio loudness (defer): the prior deliverables have no audio track (encode script sets audio none; both
   parsed files have one video track only, L3). ffmpeg lists `ebur128` and `loudnorm` filters [S8];
   descriptions not read (unverified). pyloudnorm implements BS.1770 and depends on SciPy and NumPy
   (search snippets only, [S14], E8). Build only when a film with sound is requested; stdlib `wave`
   plus numpy K-weighting is possible but scipy-free filtering needs care.
8. Camera path builder (small, port): the monotone Hermite path is generic and testable (pure math).
   Ship as a library function used by motion_check's tests and by user scene scripts.

## 5. Runtime and CI-testability per tool to build

Runtimes: STD = stdlib Python; PN = system Python with Pillow + numpy; BPY = inside Blender's bundled
Python (bpy, numpy). "Core" = pure functions on plain data; "Extractor" = thin BPY code that dumps JSON.
Pattern recommended (judgement): every Blender-dependent tool is a BPY extractor (cannot run in CI) plus
a STD or PN core that works on the JSON and carries all the logic and tests.

| Tool | Runtime | Testable without GPU or Blender (synthetic) |
|---|---|---|
| blender_run | STD | argv building, executable discovery from env/config, traceback regex on canned logs, exit-code mapping; a stub executable (a tiny Python script printing a traceback or exiting 3) tests the subprocess path |
| render_chunks | STD | chunk planning, present-frame skipping on temp dirs, STATE write/resume/corruption, per-chunk log naming, driver against the stub executable |
| frame_audit | PN | synthetic frames: blank, black, wrong size, isolated bright pixels, truncated PNG, duplicate pairs, missing numbers, size outliers |
| flicker_metric | PN | synthetic stacks: static + noise vs static + clean vs moving; region grid and window selection |
| motion_check | core STD; extractor BPY | synthetic curves: stop, spike, overshoot, label side flip; extractor needs Blender (local lane) |
| sheets | PN | grid geometry, frame-number parsing, zoom crop bounds, label text |
| scene_lint | core STD; extractor BPY | rule engine on hand-built snapshot dicts (units, light power ranges, preset diff, hidden-but-keyed, missing paths via temp files) |
| fit_check | core PN; extractor BPY | clearance between synthetic boxes and point clouds at synthetic states |
| sim_validate | core PN/STD | synthetic per-frame tables, synthetic cache files written by the test (header + float32 + int32), hash change detection, closed-mesh volume of a cube/sphere |
| encode | BPY | none (needs Blender); only the argument and path handling is testable |
| encode_verify | STD | box parser on small synthetic MP4 byte strings built in the test (ftyp/moov/trak/stbl), error paths (fragmented, truncated, no moov) |
| render_estimate | STD | arithmetic, log/STATE parsing, price table schema validation |
| blender_compat | BPY | with fake bpy stand-ins only (hasattr branches); real check needs Blender (local lane) |
| color_check | PN | synthetic gradients, clipped images, mode and depth checks |
| overlay | PN | easing, fit and side-lock functions, bounding boxes on synthetic anchors; pixel output smoke test only |
| bundle | STD | temp tree, manifest hashes, refusal on missing inputs |

CI note (judgement): CI probably has stdlib Python only; whether it has Pillow and numpy is unverified
(see Open questions). Test classes for PN tools use a skip guard.

## 6. Recommended final tool list

Effort: S = under about 150 lines plus tests; M = a few hundred lines; L = large or needs calibration.
"Port" names the role in the prior project; "new" = no source.

| # | Name | Purpose | Runtime | Testable w/o GPU | Source | Effort |
|---|---|---|---|---|---|---|
| 1 | blender_run | find pinned portable Blender, run a script headless, capture log, fail on traceback, record version and argv | STD | yes | new (CLI per S1) | S |
| 2 | render_chunks | chunk frame ranges to an absolute path, skip present frames, STATE file, one log per chunk, optional device flag | STD | yes | port: chunk run scripts (role only), plus Blender Overwrite/Placeholders [S2] | M |
| 3 | frame_audit | expected vs present, size, blank/black, firefly outliers, file-size anomalies, duplicate runs, NaN only for float images | PN | yes | new | M |
| 4 | sheets | contact sheet, review sheet, zoom crops | PN | yes | port: contact sheet and review sheet scripts | S |
| 5 | encode | frames to H.264 MP4 with Blender's bundled FFmpeg | BPY | no | port: encode script (drop forced view transform to a parameter) | S |
| 6 | encode_verify | verify MP4: frame count, fps, resolution, duration, bitrate, stream count; ffprobe if present | STD | yes | new | S-M |
| 7 | render_estimate | s/frame x frames from logs/STATE; dated user-supplied price table | STD | yes | new | S |
| 8 | bundle | copy scripts, presets, README, manifest beside each delivered version | STD | yes | new | S |
| 9 | color_check | frame-side colour sanity (depth, mode, clip fractions); scene-side rules live in scene_lint | PN | yes | new | S |
| 10 | motion_check | speed, accel spikes, stops, overshoot past waypoints, label side changes | STD core + BPY extractor | core yes | port: camera path builder, on-screen-motion dump, label side scoring | M |
| 11 | camera_path (library) | monotone Hermite path through waypoints | STD | yes | port: camera path builder | S |
| 12 | scene_lint | units, scale, textures, colour management, preset diff, light power, hidden-but-keyed | STD core + BPY extractor | core yes | new (double-transform rule from the encode script note) | M |
| 13 | blender_compat | version shims and the 4.x-to-5.x break table | BPY | partly (fakes) | port: compat shim and inline version branches; table from S4 | M |
| 14 | flicker_metric | temporal instability per region in near-still windows | PN | yes | new; window selection ports the near-still run dump | M-L (needs calibration) |
| 15 | sim_validate | volume vs poured, emission vs commanded flow, count trend, cache hash, fail on under-emission | PN | yes | new; cache reader ports the sim script's `.bobj` reading | M |
| 16 | overlay | anchor export, callouts, captions, fades, wipe, safe-area check | PN + BPY anchor export | core yes | port: post/overlay script and the anchor export | L |
| 17 | fit_check | clearance at each keyframe state, coarse v1 | PN core + BPY extractor | core yes | new (prior had only a comment) | M-L |
| - | audio_loudness | deferred until a film with audio is requested | PN or ffmpeg | - | new | - |

Suggested order (judgement): phase 1 = 1, 2, 3, 4, 5, 6, 7, 8 (a working, checked pipeline); phase 2 = 9,
10, 11, 12, 13 (motion and scene correctness); phase 3 = 14, 15, 16, 17 (calibration-heavy or large).
Dropped from the candidate list as separate tools: review_sheet (merged), render_estimate stays but loses
its price table. Not wrapped: Flamenco, FLIP, VMAF, ImageMagick, oiiotool (optional helpers only).

## Open questions

1. Does the template CI image have Pillow and numpy? If not, frame tools run only in a local lane.
2. Is OpenCV (present locally, not baseline) acceptable as an optional MP4 cross-check, or excluded?
3. Does the human want to allow obtaining ffprobe (this research may not install anything)? Method A
   works without it, but B is stronger.
4. Firefly, flicker and clip thresholds need calibration against real renders; until then they are E7.
5. Does Blender's Overwrite-off/Placeholders option skip frames only by file existence? A frame left
   truncated by a crash would then count as present. Needs a local Blender test (not run here).
6. Is the third-party fluid cache layout stable across add-on versions, and is a closed-mesh volume
   meaningful for a thin open film? The reader and the check may need a cell-count method instead.
7. Intermediate frame format: 8-bit PNG (no NaN possible, banding risk) or EXR (needs an EXR reader in the
   audit; Pillow's EXR support was not checked)?
8. Which safe-area margins and which cloud price sources should the defaults use? Both unverified.
9. Flamenco: does it support Blender 5.x and set chunk size? Unverified; revisit only for multi-machine.
10. Does oiiotool `--printstats` report NaN/Inf counts? Unverified (S11 excerpt did not say).
11. Which exact PNG colour chunks does Blender 5.2 write? Unverified.

## Bears on

- Template ADR candidates: (a) BPY extractor + pure core split; (b) no hard dependency on ffprobe or
  ffmpeg, with a built-in MP4 parser and optional ffprobe; (c) optional-dependency policy for Pillow and
  numpy tools in CI.
- `docs/library/tools/` layout and the unittest convention; the new test lane for Blender-dependent
  smoke tests (local only).
- `docs/library/procedures/evidence-levels.md`: thresholds from uncalibrated metrics are E7 until
  checked against real renders.
- The video and art roles under `docs/roster/agents/` (video editor, video-direction reviewer, art
  director): they consume sheets, motion_check, frame_audit and encode_verify output.
- The opt-in render capability README and its preset file format (named presets replace environment
  variable knobs).
- Pinned Blender version (5.2.3 here; 5.2 documented as an LTS manual [S1]) and the compat table (S4).
