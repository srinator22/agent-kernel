---
name: mesh-to-cad
description: Convert a triangle mesh (STL export, vendor model, cleaned 3D scan) into verified CAD - closed, named, coloured STEP solids with true lines, arcs and revolves where the mesh allows, and a parametric Inventor part. Use when a part exists only as a mesh and CAD, STEP, Parasolid or an editable model is needed, or when the human runs /mesh-to-cad. Do not use for raw point clouds, for freeform surface fitting, or when the source CAD can be obtained instead.
---

Follow docs/procedures/mesh-to-cad.md exactly. Record the source (path,
units, exporter or scanner, sha256) before stage 1; build with
`mesh_brep.py`; never deliver before `mesh_verify.py` passes on the exact
files delivered; get fresh-context independent checks (per body, slices,
dimensions and colours) before calling the result accurate; quote every
tool's output verbatim; deliver solids and zero-thickness surfaces in
separate files; report faults found in the source as known limits, never
correct them silently.

Adopting this skill: copy `docs/library/procedures/mesh-to-cad.md` to
`docs/procedures/` and the mesh tools from `docs/library/tools/` (with their
tests and `mesh_fixtures.py`) to `tools/mesh2cad/`. Record the CadQuery
version and, if used, the Inventor version and template path in Project
decisions. Until the procedure is copied, read it from
`docs/library/procedures/mesh-to-cad.md`.
