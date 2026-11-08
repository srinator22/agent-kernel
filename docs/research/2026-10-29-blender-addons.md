# Blender add-ons and extensions for product work (Blender 5.2 LTS era)

Date: 2026-10-29. Role: researcher. Scope: one question, seven categories.
All sources below were retrieved 2026-10-29 in this session. Evidence levels per
`docs/library/procedures/evidence-levels.md`: E2 = maintainer/vendor page, a CLAIM of
the maintainer, not measured; E6 = independent report; E8 = unverified. No test, build
or install was performed. Every version, licence, price or compatibility statement is
marked `VERIFY 2026-10-29`.

Conventions: "S#" = source row below. "unverified" = not found on a primary page in
this session (reason given). Web pages were read through a summarising fetch tool, so
exact wording was not always visible; the primary URL is given for re-checking.

## Sources

| ID | URL | Level |
|---|---|---|
| S1 | https://github.com/rlguy/Blender-FLIP-Fluids (README, rendered) | E2 |
| S2 | https://api.github.com/repos/rlguy/Blender-FLIP-Fluids (+ /releases, /commits, /contents/) | E2 |
| S3 | https://github.com/rlguy/Blender-FLIP-Fluids/wiki/Release-Notes (first 100k chars read) | E2 |
| S4 | https://github.com/rlguy/Blender-FLIP-Fluids/wiki/FLIP-Fluids-Addon-vs-Blender-Mantaflow | E2 (vendor claims, interested party) |
| S5 | https://developer.blender.org/docs/release_notes/5.2/ and /physics/ and /pipeline_io/ | E2 |
| S6 | https://developer.blender.org/docs/release_notes/5.3/ (in development) | E2 |
| S7 | https://www.blender.org/download/ | E2 |
| S8 | https://docs.blender.org/manual/en/latest/physics/fluid/index.html and /physics/cloth/index.html (page titles and nav only; bodies not visible) | E2 |
| S9 | https://extensions.blender.org/api/v1/extensions/?search=material (list API, first 100k chars) | E2 |
| S10 | https://extensions.blender.org/add-ons/?q=step, ?q=camera, ?q=material, ?q=paper, ?q=fold, ?q=fluid, ?q="render queue" (search result lists) | E2 |
| S11 | https://extensions.blender.org/add-ons/step-importer/ ; https://github.com/Clonephaze/STEP-Importer (+ API, README) | E2 |
| S12 | https://github.com/trimesh/cascadio (+ API, contents) ; https://pypi.org/pypi/cascadio/json | E2 |
| S13 | https://api.github.com/repos/FreeCAD/FreeCAD (+ /releases/latest) | E2 |
| S14 | https://extensions.blender.org/add-ons/add-camera-rigs/ | E2 |
| S15 | https://polyhaven.com/license ; https://api.github.com/repos/Poly-Haven/polyhavenassets | E2 |
| S16 | https://extensions.blender.org/add-ons/unravel/ ; /add-ons/polyzamboni/ ; /add-ons/splashsurf-studio/ | E2 |
| S17 | https://flamenco.blender.org/ ; /usage/quickstart/ ; /development/building/ | E2 |
| S18 | https://www.crowd-render.com/ | E2 |
| S19 | https://aws.amazon.com/thinkbox-deadline/ | E2 |
| S20 | Search results: https://digitalproduction.com/2025/10/23/deadline-10-enters-maintenance-mode-for-studios/ ; https://cgpress.org/archives/deadline-to-enter-maintenance-mode-on-november-7-2025.html ; https://www.blendernation.com/2022/09/16/blenders-flamenco-3-officially-released/ | E6 (not opened, search snippets only) |
| S21 | https://docs.blender.org/manual/en/latest/files/import_export/usd.html ; /alembic.html ; /modeling/volumes/introduction.html (bodies at offsets 100k-200k) | E2 |

Not reachable: FreeCAD wiki (bot-block page), Superhive product pages (price not
obtained), Flamenco download page (403), projects.blender.org repo page (403).

## Context facts (Blender itself)

| Fact | Source | Level |
|---|---|---|
| Latest stable is Blender 5.2.3 LTS, released 2026-10-22; 5.3 expected 2026-11-10 `VERIFY 2026-10-29` | S7 | E2 |
| 5.3 is in beta until 2026-11-04 `VERIFY 2026-10-29` | S6 | E2 |
| 5.2 LTS release notes: geometry-node asset files must be re-saved for 5.2; Compare and Random Value socket identifiers changed `VERIFY 2026-10-29` | S5 | E2 |

## 1. Liquids

### FLIP Fluids (official source: github.com/rlguy/Blender-FLIP-Fluids)

| Item | Finding | Source / level |
|---|---|---|
| Licence of source | Add-on code GPL-3.0; simulation engine MIT; example scenes, media and some features (Mixbox colour blending named) under a "Standard Royalty Free" licence that is shipped only in the paid add-on, not on GitHub. Repo root holds LICENSE_GPLv3.md, LICENSE_MIT.md, LICENSE_Standard_Royalty_Free.md `VERIFY 2026-10-29` | S1, S2 / E2 |
| Paid binary | Licences sold on marketplaces (Superhive named); sales fund development. README says the add-on is "still completely usable without this content". Price: unverified (product page not reachable) | S1 / E2 |
| GitHub releases | Tagged "FLIP Fluids Demo": v1.8.8 (2026-07-27), v1.8.7 (2026-07-14), v1.8.6 (2026-03-24), v1.8.5 (2025-11-18), v1.8.4 (2025-07-14). These are demo builds, not source `VERIFY 2026-10-29` | S2 / E2 |
| Blender compatibility | "Blender 4.5 to 5.2 compatible"; release notes for 1.8.8 say 5.2 recommended and no known issues on 5.3 alpha at that date `VERIFY 2026-10-29` | S1, S3 / E2 |
| Maintenance | Last push 2026-08-24 (Discord link edit); last functional commit "Version 1.8.8 update!" 2026-07-27; prior "Version 1.8.7 update!" 2026-07-09; not archived; ~1971 stars; 5 open issues `VERIFY 2026-10-29` | S2 / E2 |
| Build requirements | C++17 compiler (MinGW on Windows, Clang macOS, GCC Linux), CMake, GNU Make, Alembic and Imath 3; Python 3.3+ optional for `build.py` | S1 / E2 |
| Windows | README: "MinGW is the only supported compiler for Windows OS" (MSYS2 not named in README) | S1 / E2 |
| Documented steps | Automated: `python build.py` from repo root (flags `-cmake-path`, `-make-path`, `-package-dependencies`). Manual: make `build/`, `cmake ..` (MinGW Makefiles generator on Windows), `make`. Output in `build/bl_flip_fluids/`; zip `flip_fluids_addon` to install | S1 / E2 |
| Vendor claims vs Mantaflow | Vendor says its engine rarely crashes, is liquid-only, better support/docs. Page last edited 2025-04-07, text written 2021. Names no concrete feature gap | S4 / E2 (interested party) |
| Risk | Source build lacks paid-only content (see licence row); build needs a C++ toolchain; project funded by paid sales | S1 / E2 |

### Built-in Mantaflow (Blender fluid modifier)

- Still documented in the Blender 5.2 LTS manual (Fluid and Liquid Settings pages exist; bodies not visible, so feature detail unverified) `VERIFY 2026-10-29` (S8, E2).
- 5.2 physics release notes cover cloth, hair, effectors and the XPBD solver only; no fluid or Mantaflow entry (S5, E2). Absence of a note is not proof of no change.
- Maintenance: the FLIP Fluids wiki quotes (as of 2021) a Blender developer saying Mantaflow had no active developer (S4, E8, second hand, dated). Current status: unverified.
- Gas/smoke and fire: Mantaflow handles them; FLIP Fluids is liquid only (S4, E2 vendor claim).

### Alternatives

| Candidate | Finding | Source / level |
|---|---|---|
| Splashsurf Studio (extension) | Meshes particle clouds into a surface. v1.0.1, Blender 4.5+, GPL-3.0-or-later, Win/Linux/macOS; published 2025-12-12, "last update 10 mo ago" (relative). Does not simulate. Whether it ships a compiled binary: unverified `VERIFY 2026-10-29` | S16 / E2 |
| MantaPro (paid add-on) | Exists per a Superhive FAQ title in search results; not opened. Licence, version, price unverified | E8 |
| New Geometry Nodes XPBD solver (5.2) | Cloth, hair and particles framework; nothing in the official notes about liquids | S5 / E2 |
| Extensions search "fluid" | No liquid simulator listed (9 results, unrelated except Splashsurf Studio) | S10 / E2 |

## 2. Cloth and paper

| Candidate | Licence | Maintenance / compat | Does better than built-in | Risks | Source / level |
|---|---|---|---|---|---|
| Cloth Dynamics modifier and node group (new in 5.2, built-in) | Blender (GPL) - licence of core not re-checked | Part of 5.2 LTS; marked experimental, "design isn't locked in", may break in future releases `VERIFY 2026-10-29` | Pinning, stretch and bend controls, tearing; usable as a node group; gravity and collision effectors built in | Experimental API; asset files with geometry nodes must be re-saved for 5.2 | S5 / E2 |
| Legacy Cloth modifier (built-in) | Blender | Documented in 5.2 LTS manual (nav entry); feature list not visible | Established workflow | Not evaluated here | S8 / E2 |
| Geometry Nodes hair (built-in, 5.2) | Blender | Empty Hair operator, Capture Rest Geometry modifier, fully procedural option; experimental | Hair attached to deforming surface | Experimental | S5 / E2 |
| Simulation zones (Geometry Nodes) | Blender | Listed in manual nav as "Simulation Nodes"; details not fetched | Procedural, art-directable simulation | Unverified here | S8 / E2 |
| Unravel (extension) | GPL-3.0-or-later | v1.0.0, published 2026-10-19, Blender 5.2 LTS and newer, 536 downloads, 1 review `VERIFY 2026-10-29` | Paints ragged tear holes and fraying threads on cloth, Geometry Nodes based, bakeable | Brand new, tiny review base; FBX/glTF cannot carry hair curves; single material on hair threads | S16 / E2 |
| ClothDrop Reborn (extension) | GPL-3.0-or-later | v2.0.3, min Blender 4.2.0 (tagline: single-click cloth simulation) `VERIFY 2026-10-29` | Convenience wrapper | Only listing read; claims unverified | S9 / E2 |
| PolyZamboni (extension) | GPL-3.0-or-later | v1.3.1 (2026-07-14), Blender 5.1+, 12,474 downloads `VERIFY 2026-10-29` | Unfolds meshes into printable papercraft nets | Not a physical folding simulation | S16 / E2 |
| Export Paper Model, Polyshell Builder (extensions) | not read | listing only | Net/panel unfolding | Not simulation; licence, version unverified | S10 / E2 |

Finding: no add-on that simulates paper folding, paper rolls or roll unwinding was found
in the extensions searches "paper" and "fold" (17 and 13 results; unfolding and game
tools only). The searches were limited to those two terms and the first result page.

## 3. Procedural materials and material libraries

| Candidate | Licence | Maintenance / compat | Notes | Source / level |
|---|---|---|---|---|
| Poly Haven assets (HDRIs, textures, 3D models) | CC0 for all assets; attribution not required; commercial use and redistribution allowed `VERIFY 2026-10-29` | Site terms prohibit scraping or data mining without permission; API has separate terms (not read) | Free, no account needed per licence page (account use unverified) | S15 / E2 |
| Poly Haven Blender add-on (repo Poly-Haven/polyhavenassets) | GPL-3.0 (GitHub API) | Last push 2026-10-02; not archived `VERIFY 2026-10-29` | Integrates assets in the asset browser. Whether it is listed on extensions.blender.org: unverified (guessed slug returned 404; "material" search did not show it) | S15 / E2 |
| MaterialHelper, [BAM] AutoMat, Material Batch Tools, Texture Wrangler (extensions) | Texture Wrangler GPL-3.0-or-later, v1.0.0, min 4.2.0; others not read | Listing only | Local asset management and batch material creation from texture folders; not material libraries | S9, S10 / E2 |
| Texture Pipeline Studio (extension) | GPL-3.0-or-later | v8.10.1, min Blender 4.5.0 `VERIFY 2026-10-29` | PBR assignment from resolution folders, LOD swap | S9 / E2 |
| Procedural material libraries on extensions.blender.org | - | None identified in the "material" search (32 results, first page only) | Gap | S10 / E2 |

Not found: any statement on Blender's bundled "Essentials" asset library (unverified).

## 4. Camera rigs and lens

| Candidate | Licence | Maintenance / compat | What it adds | Risks | Source / level |
|---|---|---|---|---|---|
| Add Camera Rigs (extension, repo waylow/add_camera_rigs) | GPL-3.0-or-later | v1.9.2, Blender 4.2 LTS and newer, first published 2024-05-14, "updated 6 days before capture" (relative date) `VERIFY 2026-10-29` | Dolly, Crane (arm height, length) and 2D rigs with UI | 5.2 testing not stated | S14 / E2 |
| Dolly Zoom (extension) | GPL-3.0-or-later | v1.0.0, min 4.2.0 `VERIFY 2026-10-29` | Dolly zoom for viewport and camera | Single-purpose | S9 / E2 |
| Camera Shift Sync, Turntable Camera, Camera Grid, Cameraide (extensions) | not read | listing only | Composition-preserving moves, turntable, camera switching, per-camera output settings | Versions, licences unverified | S10 / E2 |
| Photometric Light Plus (extension) | GPL-3.0-or-later | v1.0.1, min 4.5.0 | IES and EULUMDAT lights | Lighting, not camera | S9 / E2 |
| Real-lens (physical lens) camera add-ons | - | None found in the "camera" search (32 results, first page only) | Gap; any paid option unverified | S10 / E2 |

Built-in camera features (depth of field, sensor, lens, markers) were not fetched; not
stated here. Alembic import in 5.2 brings animated camera data in as F-Curves (S5, E2).

## 5. Render queue and farm managers

| Candidate | Licence | Maintenance / compat | One machine | Many machines | Builds from source free? | Source / level |
|---|---|---|---|---|---|---|
| Flamenco (Blender Studio) | GPL 3.0, "every component" `VERIFY 2026-10-29` | Described as in active development; current version and date: unverified (download page 403, repo page 403, releases API returned an empty list). Secondary 2022 article says it supports all Blender versions (E6, stale) | Manager and Worker can run on one computer (quickstart) | Needs shared storage at the same path on every machine and Blender in the same place; add-on served by the Manager | Yes in principle: Go, Mage (`go run mage.go build`), Node and Yarn; supported build OSes unverified | S17, S20 / E2, E6 |
| Deadline 10 (AWS Thinkbox) | Proprietary (assumed; primary licence terms not read: unverified) | Secondary reports: maintenance mode from 2025-11-07, security and critical fixes only, development moved to Deadline Cloud (E6). AWS page confirms only that the Thinkbox UBL Marketplace no longer functions and UBL moved to Deadline Cloud `VERIFY 2026-10-29` | Overkill | Full studio farm | No source found | S19, S20 / E2, E6 |
| CrowdRender (add-on) | Page says "open source licensed" but names no licence; free tier plus paid fund/subscription `VERIFY 2026-10-29` | Free version "up to Blender 4.3"; supporters "3.0 to 5.1"; 5.2 not listed; page carries a 2021 notice | Not useful | Pools CPUs and GPUs of several machines for one frame or animation; scene data travels over network | Unverified (no repo link read) | S18 / E2 |
| Render Queque, RenderCue, BLeQ (extensions) | not read | listing only; Render Queque batch-renders several .blend files, one process each | Queue of jobs on one machine | None | Unverified | S10 / E2 |

## 6. CAD import (STEP)

| Candidate | Licence | Maintenance / compat | Tessellation control | Builds free from source? | Source / level |
|---|---|---|---|---|---|
| STEP Importer (extension; GitHub Clonephaze/STEP-Importer) | Extension page: GPL-3.0-or-later. GitHub API licence field: null (mismatch) `VERIFY 2026-10-29` | v1.2.1 (2026-07-21), published 2026-06-16, Blender 5.1+, Win/Linux/macOS; repo created 2026-06-13, 21 stars `VERIFY 2026-10-29` | Presets Draft, Balanced, Fine, Ultra Fine plus Custom linear and angular tolerance; "Regenerate Part" re-tessellates; numeric preset values not published; imports .step, .stp, .iges; assemblies become nested collections; colours yes, PBR mapping deferred; no STEP export | Repo has `build.py`; build steps not documented in README. It converts via Cascadio to glTF then Blender's glTF importer | S11 / E2 |
| Cascadio (dependency) | MIT per PyPI metadata (v0.1.1; GitHub licence field null; `LICENSE` is a directory) `VERIFY 2026-10-29` | Last push 2026-10-21; wheels for win_amd64 and manylinux seen for older releases; 0.1.1 files not confirmed | Linear and angular tolerance parameters: not found on the page | README: builds OpenCASCADE via `scripts/build_occt.py`, scikit-build-core, cibuildwheel; OCCT source in `upstream/` with `patches/` | S12 / E2 |
| StepForge (extension) | not read | Tagline "imports and exports STEP/STP, written in pure Python"; page not reachable | Unverified | Unverified | S10 / E2 |
| FreeCAD round trip (STEP -> mesh -> OBJ/STL/glTF -> Blender) | LGPL-2.1 (GitHub API) `VERIFY 2026-10-29` | Release 1.1.4 (2026-09-28); last push 2026-10-28 | Mesh-from-shape deviation controls exist per general knowledge only; wiki unreachable, so unverified | Open source; build not researched | S13 / E2 |
| Blender built-in STEP | - | 5.2 pipeline_io notes list glTF, USD, Alembic, STL, images, movies only; 5.3 notes content not visible | - | - | S5, S6 / E2 |

Other: a DXF importer exists (CAD2Cube, GPL-3.0-or-later, v1.5.1) but is not STEP.

## 7. Interchange: Alembic, USD, OpenVDB (built into Blender 5.2 LTS manual)

| Format | What survives | What does not | Source / level |
|---|---|---|---|
| USD | Animation: import as Transform Cache constraint and Mesh Sequence Cache; export writes the evaluated mesh per frame. Materials: Preview Surface (simple trees only) or MaterialX export (most nodes). Instancing: scene instances import as collection instances, point instancers via Geometry Nodes; export instancing option is experimental. 5.2 adds colour-space tagging, NURBS exported as mesh | MaterialX export has no displacement; no layers, references or variants; only perspective cameras exported; only visible objects; hair exports parent strands only; Bendy Bones, absolute shape keys, UDIM in USDZ unsupported | S21, S5 / E2 |
| Alembic | Animated meshes (UVs, normals, colour attributes, face sets), transforms, custom properties, hair as curves, particles as points; instancing option; 5.2 imports visibility and animated cameras | No materials (only face-set names), no armatures, no particle systems; stores time in seconds | S21, S5 / E2 |
| OpenVDB | Volume objects, sequences, drag and drop; default Principled Volume reads grids named density, color, temperature; renders like smoke | EEVEE support: not confirmed in the page text read | S21 / E2 |

## Interpretation (the author's reading, not source statements)

1. FLIP Fluids source meets the template rule (official source, GPL/MIT code) and the
   prior MSYS2 build confirms the MinGW route works in practice; MSYS2 is just a
   packaging of MinGW, but the README does not say so. The source build omits the
   paid-only content, which the vendor says is optional. Buying a licence is a
   funding choice, not a technical need.
2. The GitHub "Demo" release binaries are prebuilt binaries of the official publisher;
   if used they would fall under "download from the official publisher" in the rule,
   but they are demo-limited. Build from source remains the template default.
3. Built-in tools now cover more than expected: 5.2 gives tearing cloth and hair in
   Geometry Nodes (experimental). The risk is API churn between point releases; pin the
   Blender version per project and record it.
4. The STEP Importer extension is the lowest-friction STEP path, but it is a young
   project (created June 2026), has an unclear GitHub licence field, and depends on
   Cascadio, a native OpenCASCADE wheel that is a third-party prebuilt binary unless
   built from the Cascadio source. Whether the extension zip bundles those wheels is
   not stated. Under the template rule this needs a decision: accept the extension
   platform as the official channel, or build Cascadio from source (heavy: OCCT).
5. For product geometry a FreeCAD (or other CAD) tessellation step may give more
   deterministic quality control than a preset; this is unverified until the FreeCAD
   mesh-export controls are read from a primary page.
6. On one machine, Flamenco's gain is queue and job tracking, not speed; its real value
   appears with a second machine and shared storage. A plain command-line Blender render
   covers a single job (not fetched in this session; common practice, E8).
7. USD is the better carrier for animated scenes with materials as plain Preview
   Surface; Alembic is geometry and camera only. For hero materials, re-link shaders in
   Blender after import.
8. Deadline is a poor fit: closed, in maintenance mode per secondary reports, and no
   source. CrowdRender's newest supported Blender (5.1, supporters only) trails 5.2.

## Ranked shortlist per category

| Category | Ranked |
|---|---|
| 1 Liquids | 1. FLIP Fluids built from official source. 2. Built-in Mantaflow (also gas/smoke; maintenance unverified). 3. Splashsurf Studio only as a meshing helper for particle data. MantaPro: unverified, skip |
| 2 Cloth and paper | 1. Built-in Cloth Dynamics / legacy Cloth (accept experimental status). 2. Unravel for torn edges (new, review first). 3. Geometry Nodes simulation zones for custom paper behaviour. No paper-folding or roll add-on found; PolyZamboni is unfolding only |
| 3 Materials | 1. Poly Haven assets (CC0) plus its add-on (GPL-3.0). 2. Texture Wrangler / Texture Pipeline Studio for organisation. No free procedural library found on the extensions site |
| 4 Camera | 1. Add Camera Rigs (dolly, crane). 2. Dolly Zoom. 3. Built-in camera and markers (not researched). Real-lens add-on: none found |
| 5 Render queue / farm | 1. Flamenco (official, GPL 3.0; verify version first). 2. Render Queque / RenderCue style queue add-ons for one machine (unread). 3. CrowdRender only if its Blender support catches up. Deadline last |
| 6 CAD import | 1. STEP Importer extension (resolve the prebuilt-wheel question). 2. FreeCAD round trip via mesh export. 3. StepForge (unverified) |
| 7 Interchange | 1. USD for scenes. 2. Alembic for pure baked geometry and cameras. 3. OpenVDB for volumes. All built in |

## Open questions

1. Does the STEP Importer extension zip bundle Cascadio wheels, and is the extensions
   platform acceptable as "official publisher" for a third-party native wheel?
2. What are the numeric linear and angular tolerances behind the STEP Importer presets, and
   how do they compare with FreeCAD mesh export settings (FreeCAD docs unreadable here)?
3. FLIP Fluids paid price and exactly which features the source build lacks (Mixbox named;
   full list not read).
4. Flamenco current release, Blender 5.2 and 5.3 compatibility, and Windows build support.
5. Is Mantaflow actively maintained in 5.x? Read the 5.0 to 5.3 release notes' physics pages.
6. Is the Poly Haven add-on distributed through extensions.blender.org, and under which licence file?
7. Will the 5.3 stable release (planned 2026-11-10) change Cloth Dynamics, USD or Alembic?
8. Are there maintained paper-roll or unwinding Geometry Nodes assets outside the extensions site?

## Bears on

| Template part | Effect |
|---|---|
| Add-on policy / allowlist (build from official source, official publisher only) | Cascadio wheel question; FLIP Fluids source vs Demo binaries; GitHub licence field mismatches |
| Blender version pin and compatibility table | 5.2.3 LTS vs 5.3 beta; FLIP Fluids 4.5-5.2; experimental Cloth Dynamics; re-save note for geometry node assets |
| Render procedure (queue, farm, single machine) | Flamenco optional; command-line default |
| Asset and material procedure | Poly Haven CC0 terms, no-scraping clause |
| CAD-to-render hand-off procedure | STEP route choice, tessellation tolerances recorded per part |
| Interchange / file-format guidance | USD vs Alembic loss list, OpenVDB for volumes |
| Start / interview skill (opt-in capability questions) | Ask whether liquids, cloth, farm and CAD import are needed before any build |
| Lessons / research index | Re-verify all `VERIFY 2026-10-29` items before relying on them |
