# Toolchain: mesh to CAD

Tools for turning a triangle mesh into CAD, checked together on one
conversion (a populated circuit board STL, 155k triangles) on 2026-11-06.
Library item: one-project evidence, so plausible, not proven general
(`docs/library/README.md`). Used by `docs/library/procedures/mesh-to-cad.md`.
VERIFY versions and licences on the day; vendor statements below are claims
(E2), not tested here, unless the Checked column says so.

Do not use when the source CAD can be requested, or for raw point clouds.

## Used

| Role | Tool | Licence | Install | Checked with |
|---|---|---|---|---|
| B-rep kernel, STEP read and write | CadQuery 2.8.0 with cadquery-ocp 7.9.3.1.1 (OpenCascade) | Apache-2.0 (CadQuery), LGPL-2.1 with exception (OpenCascade) | `uv venv` (Python 3.13) then `uv pip install cadquery` | `test_mesh_brep.py` (8 tests) and the full conversion on Windows 11 |
| Fast distance queries (optional) | trimesh 5.2.0 with numpy | MIT, BSD-3 | `uv pip install trimesh` | same values as the stdlib index (`TriIndex`), which is used when trimesh is absent |
| Parametric part (optional) | Autodesk Inventor 2027 through COM (pywin32), or through the inventor-mcp server's `execute_python` | commercial; pywin32 PSF | Inventor installer; `uv pip install pywin32` | `inventor_build.py` on the same conversion: part saved, STEP exported, verified by `mesh_verify.py` |
| Core geometry | `mesh_core.py` (STL, segmentation, fitting, triangulation) | this repository | none (stdlib) | `test_mesh_core.py` in the template self-test |

No separate polygon triangulator is needed: `mesh_core.triangulate` handles
holes, holes touching the outer boundary and slits (an earcut package was used
once and replaced).

## Considered and not used

| Tool | What it does (source, retrieved 2026-11-06) | Why not |
|---|---|---|
| Inventor Mesh Enabler (free add-in) | converts mesh features to solid or surface base features, one B-rep face per triangle (Autodesk Marketplace page; Autodesk forum staff reply) | faceted only, no primitives; slow and may fail on very large meshes; useful as a visual overlay |
| Fusion Convert Mesh | Faceted, Prismatic (merges face groups) and Organic (needs an extension) modes (Autodesk Fusion blog; API enum page) | not scripted here; Prismatic is the closest commercial equivalent of the faceted path |
| Geomagic Design X | mesh segmentation, sketch-based rebuild, accuracy analyser, live transfer to CAD (trade press) | commercial; price and STEP route not verified |
| FreeCAD mesh workbench | mesh to shape to solid; its own wiki calls mesh repair limited | faceted only |
| Point2CAD | research code; needs points labelled by surface from a separate network | Docker route, licence statements conflict (CC-BY-NC 4.0 in the README, Apache-2.0 in the sidebar), no accuracy figures for this use |
| CAD-Recode | point cloud to CadQuery code, trained on synthetic sketch-and-extrude parts (arXiv 2412.14042) | dataset licence cc-by-nc-4.0; Docker route; no sub-0.01 mm accuracy claim |
| ComplexGen, ParSeNet, CAD-SIGNet, Text2CAD | research models; Text2CAD is text to CAD, not mesh to CAD | no repository, licence or accuracy information found for this use |

Deterministic fitting beat learned reconstruction for CAD-exported meshes:
the mesh vertices already lie on exact planes and circles, so fitting them
recovers the design values (radii and offsets to the 1e-4 mm grid), which a
learned model trained on synthetic parts does not promise.

## Install pitfalls

- CadQuery installs on Python 3.13 with uv on Windows (checked); keep it in
  its own virtual environment, not in the project's checked environment.
- Inventor: set `SilentOperation` before opening or importing anything; use
  the mm part template; see `inventor_build.py` for the API traps.
- Feeding Python a script on stdin (`python -` or a here-document) hung the
  shell twice during the port; write scripts to files and run them by path.
