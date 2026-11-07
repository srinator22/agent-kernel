# Mesh to CAD - a triangle mesh to verified, closed STEP solids and a parametric part

Adopt by copying this file to `docs/procedures/mesh-to-cad.md`, the
`mesh-to-cad` skill (`docs/library/skills/mesh-to-cad/`), and the tools
`mesh_core.py`, `mesh_brep.py`, `mesh_verify.py` and `inventor_build.py`
from `docs/library/tools/` with their tests (`test_mesh_core.py`,
`test_mesh_brep.py`, `test_inventor_build.py`, `mesh_fixtures.py`) to
`tools/mesh2cad/`; paths below use that location. Tools and versions are in
`docs/library/toolchains/mesh-to-cad.md`. Origin: one conversion of a
populated circuit board (STL export from a CAD tool, 155k triangles, 236
bodies) to STEP and a parametric Inventor part; one-project evidence, so
every step is plausible, not proven general.

Use it when a part exists only as a mesh: an STL or OBJ export from someone
else's CAD, a vendor model, or a 3D scan that has already been cleaned into a
closed mesh. Do not use it for raw scan point clouds (mesh them first, outside
this procedure), for freeform surfaces that need NURBS fitting (they stay
faceted here), or when the source CAD can be requested instead: ask first.

## What comes out

- `solids.step`: every body a closed, valid solid, named and coloured.
  Prismatic bodies (every face normal parallel or perpendicular to one axis)
  become stacked extrusions with true lines, arcs and circles; revolved bodies
  become revolves; the rest are faceted solids equal to the mesh.
- `surfaces.step`, only when needed: zero-thickness patches in the mesh that
  touch no solid. They have no volume, so they cannot be closed without
  inventing geometry; they are delivered apart, never mixed into the solids.
- A parametric `.ipt` (Inventor) with editable sketches and named heights,
  and a solids-only STEP exported from it.

## Record these before stage 1

- Source: path, format, units, who made it and how (exporter, scan and
  mesher), triangle count, sha256. Keep private sources out of git
  (`docs/rules/data-provenance.md`).
- Accuracy target in mm and the gates below if they change.
- Reference images for colours and names (datasheets, product photos), with
  their revision; a colour from a photo of another revision is labelled so.

## Stages

| # | Stage | Command | Gate |
|---|---|---|---|
| 1 | Inventory | `python tools/mesh2cad/mesh_core.py inventory <stl> --out inventory.json` | every body that should be solid is `solid` or `mixed`; counts look like the part (one body per component). If bodies are tangled, rerun stage 3 with `--mode connectivity` and compare |
| 2 | Names and colours | write `names.json`: `{"default": {"colour": "#hex"}, "<id>": {"name": "...", "colour": "#hex"}}` from the inventory (bounding boxes, volumes) and the references | every named body checked against a reference; generic names (`body_012`) for the rest |
| 3 | Build | `python tools/mesh2cad/mesh_brep.py <stl> --out build --names names.json` | exit 0; `report.json` summary `failed` empty; read every `faceted(gate-fail...)` row; every id in `open_after_repair` explained (a body meant to be solid that stayed open went to the surfaces file); every id in `exact_plan_rejected` read (its `rejected` field says why it is faceted) |
| 4 | Verify | `python tools/mesh2cad/mesh_verify.py build/solids.step --surfaces build/surfaces.step --stl <stl> --json verify.json` | PASS: no open or invalid body, STL vertices to CAD within the target (default 1.5e-4 mm), CAD to STL within 2e-3 mm; and the solid count and volume match the bodies the inventory and references say are solid. The distances alone pass when a solid is missing, because its triangles sit in the surfaces file |
| 5 | Independent checks | fresh-context reviewers, each with its own code and only the STEP and STL: per-body match (volume, bounding box, vertex error), slices on many planes (section area and outline), dimensions and colours against the references | each returns PASS with numbers; findings are fixed or listed as known limits |
| 6 | Parametric part | `python tools/mesh2cad/inventor_build.py --build-dir build --names names.json --ipt part.ipt --step part.step` (or run `build()` inside the inventor-mcp namespace) | exit 0; then `mesh_verify.py part.step --stl <stl>` passes the same gates |
| 7 | Design parameters | by hand in Inventor: user parameters for the dimensions a designer will change (outline, hole diameters and pitches), wired into the sketches; test one change and its revert | the changed feature moves, the revert restores, stage 4 still passes |
| 8 | Deliver | a folder with the STEP files, the `.ipt`, a README (files, representation per body, parameters, verification table, known limits) and the scripts | the README numbers are the verify output of the delivered files, not of an earlier build |

Run stage 3 and 6 as long jobs (`docs/procedures/longjob.md`) when the mesh
is large: the build took minutes per thousand bodies on one machine.

## Gates and what they mean

- STL vertices to CAD: the reconstruction error. Mesh vertices lie on the
  true surface, so every vertex must lie on the CAD surface. Exact bodies are
  accepted below 1e-4 mm; a body that fails falls back to faceted.
- CAD to STL facets: includes the mesh's own chord error on curves, so it is
  allowed up to the sag the plan's tessellation can have (fitted arcs turn at
  most 12 degrees per chord) and never less than 2e-3 mm.
- Volume: a prism plan must match the mesh volume within 1e-3 of it plus the
  area the chords can cut off; a revolve plan must put every vertex, at every
  angle, on its profile within 1e-4 mm.
- Closed: every body in a solids file has zero free edges and passes the
  OpenCascade validity check. A pinched shell (a face whose hole touches its
  outer edge) is repaired by replacing that face with triangles over the same
  boundary, accepted only when the volume is unchanged.
- Tessellation used by the checker has a deflection of 2e-4 mm: results below
  about 1e-4 mm are at the checker's own resolution; say so in the report.

## Pitfalls found (each now handled by a tool or a check)

| Pitfall | What happened | Handled by |
|---|---|---|
| float32 STL noise | vertices off by about 1e-6 of the coordinate size | weld 1e-5 mm, join 1e-4 mm, snap fitted values to 1e-4 only within 6e-6 |
| touching bodies merged | a library mesh split merged or over-split where bodies share faces (763 pieces from 236 bodies) | segmentation by triangle order, cut where a run closes (`segment_bodies`) |
| chords taken as the surface | fitting arcs through section points (on chords) gave radii a few microns small | fit through vertices; revolve profiles refitted to vertices (`refine_profile`) |
| a line absorbed into an arc | a straight edge next to a fillet became a huge-radius arc; the revolve was 3.7 % too big | chord-length ratio rule in `fit_loop`, volume and vertex gates |
| coplanar merge moved the surface | merging facets a few microns out of plane flattened them | merge kept only when the merged surface stays within 1e-5 mm of the mesh |
| double-sided sheets | markings and pads exported as front and back triangles, zero volume | twin removal; sheets on a part imprinted, others to `surfaces.step` |
| exporter crack | a zero-area slit with T-junctions (one side's vertices on the other side's edges) left a shell open | `zip_cracks` (`--zip-tol`, default 1e-4 mm): boundary vertices closer than the tolerance merge first, then edges split at T-junctions (splitting next to a near-duplicate vertex left a sliver edge on four faces and a misoriented shell); then `fill_planar_holes` for small planar holes (`--fill-area`, default 1e-3 mm2) |
| a fallback hiding a failure | a distance query ran out of memory on a board with 144 holes; the build caught it and quietly made the board faceted | chunked queries; every rejected exact plan is listed in `exact_plan_rejected` with its reason in the body's `rejected` field |
| a missing solid passing the distance check | the open shell went to the surfaces file, so every STL vertex still had CAD nearby | `open_after_repair` in the build report; stage 4 compares solid count and volume |
| pinched shell | the closed shell touched itself on one edge; one face failed validity | `repair_imbricated` |
| open parts in the delivered STEP | patches written next to solids looked like open parts to the customer | solids and surfaces in separate files; `mesh_verify` fails on any open body |
| Inventor traps | duplicate browser names, cm template, multi-body STEP import, invisible dialogs, SplitFaces failing | `inventor_build` (header lists each) |
| faults in the source | pins sat 0.124 mm off their holes in the source model | reproduced, never corrected; listed as a known limit |

## Report

Quote the verify output verbatim: bodies, solids, valid, open, volume,
both distances with max and p99. Distinguish built, verified by the tool,
and checked independently. List what is not reproduced (colours that are not
geometry in the mesh, patches in `surfaces.step`, faults in the source).
