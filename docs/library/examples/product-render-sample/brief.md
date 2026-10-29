# Brief: sample scene (primitive shapes only)

Version 3, 2026-10-29 (v1 art-director HOLD, v2 APPROVE WITH CHANGES; the
changes answer both reviews, see RECORD.md). Recorded by the advisor;
stage 0 of `docs/library/procedures/product-render.md`.

| Field | Value | Source |
|---|---|---|
| Kind | one-shot mechanism demo film, no cuts, no freeze frames, no end card; the closing title (frames 84-120) is the only camera stop | this brief |
| Purpose | prove the pipeline end to end on a scene with no real product | task A11 |
| Message (one sentence) | A clear lid on a dark box opens on its hinge to show the ball inside. | this brief |
| Audience | template maintainers | task A11 |
| Runtime | 5.0 s (120 frames at 24 fps) | this brief |
| Platform | local review only; no upload, no publication | kernel rule 15 |
| Aspect, resolution | 16:9; final 960 x 540; preview 480 x 270; animatic 480 x 270 | presets/ |
| Captions | none (no audio, no speech) | this brief |
| Colour pipeline | SDR, Rec. ITU-R BT.709 display; render view transform AgX, look None; display-referred PNG frames encoded with view transform Standard (applied once) | procedure rule 5 |
| Deadline | none; inside the task budget | TASK.md |
| Deliverables | final MP4 (H.264) plus a bundle; preview MP4; check stills; animatic | stage table |
| References | waived for this internal pipeline check: no real product exists, so no reference photos are collected; the stage 4 look is judged against the art-director real-world cue list only; the look lock does not demonstrate photoreal fidelity; no external image is used or shown | art-director finding |
| CMF (stand-in) | scene.py materials: base matte black #272729 roughness 0.55 sheen 0; lid clear acrylic IOR 1.49, absorption tint 0.93/0.98/0.99 at density 3, cut edges satin roughness 0.35; pin brushed metal roughness 0.25 anisotropy 0.6; ball #E78959 roughness 0.35; floor #303035 roughness 0.4 | scene.py |
| Look words | dark studio, clear acrylic, satin cut edges, matte black, brushed pin | lessons map |
| Must show | the lid opening on its hinge; the ball seen through the clear lid | this brief |
| Hard nos | no product, brand or person; no film grain; the camera never fully stops except on the closing title | lessons map |
| Labels | "HINGE" right of the pin, frames 50 to 80, 6-frame fades (0.25 s); Inter, Blender's bundled default font, SIL Open Font License 1.1 (per `license/license.md` in the Blender 5.2.3 portable; that the VSE text strip uses it when no font is set is unverified), regular, white #FFFFFF, no leader, 28 px (5.2 percent of frame height) | labels.json |
| Title | "SAMPLE SCENE" in the lower third, over the matte black front wall of the box, from frame 84 to 120 (1.5 s; read twice at 3 words/s needs 1.33 s), no fade | labels.json |
| Unverified figures | the 3 words/s reading rate and the 5 percent safe margin are tool defaults, UNVERIFIED; a researcher sources a reading rate and SMPTE ST 2046-1 before any real project | render_overlay --help |
| Honesty label | CG render: carried by the bundle README and the file names (local review only, no publication); previews carry PREVIEW with resolution and samples | art-director check |
| Known limits | primitive hinge: the lid meets a plain pin, with no knuckles, so the real-hinge cue is not shown | art-director finding |
