# Task: mesh-to-cad
Mode: standard
Branch: task/mesh-to-cad
Date: 2026-11-06

## Goal
Add a library item that converts a triangle mesh (STL from a CAD export or a cleaned 3D scan) into
CAD: exact B-rep solids with true lines and arcs where the mesh is prismatic or revolved, faceted
solids where it is not, named and coloured, written as STEP, with an optional parametric Inventor
part. Port the scripts from one prior conversion (a populated sensor board, 155k triangles) as
generic tools plus the procedure that ran them, including the closed-solid repairs found after
delivery, so the next conversion starts from tested tools instead of a scratch folder.

## Non-goals
- No machine-learning reconstruction (the learned tools found need labelled points, Docker and
  non-commercial licences; recorded in the toolchain note).
- No freeform surface fitting (NURBS); non-prismatic, non-revolved bodies stay faceted.
- No change to core procedures, profiles or the kernel. No source-project names, parts or data.
- No raw scan processing (point cloud to mesh); the input is a triangle mesh.

## Budget
- Wall-clock: one working session plus one full golden-master run (about 30 min of compute).
- Subagents / workflow runs: 1 reviewer at the ship gate.
- Retries per failing step: 2.
- Escalate to human when: the golden-master run cannot reproduce the delivered numbers, or the
  template self-test cannot run the stdlib tests.

## Assumptions
- [confirmed] The human asked for the scripts and the conversion process in the template repo as a
  reusable mesh/scan-to-parametric utility (2026-11-06, "convert to parametric from 3d scans or mesh
  could be a useful utility to have"; the New Project folders were attached).
- [verified] Library tool tests run in the self-test with stdlib Python only -> tests/template/test_profile_tools.sh
- [verified] The library holds generic versions only, no source names -> docs/library/README.md
- [verified] CadQuery 2.8.0 (cadquery-ocp 7.9.3.1.1) runs on Python 3.13 on Windows -> `python -c "import cadquery"` in the conversion venv

## Acceptance criteria
- [ ] Stdlib core: STL read (binary, ASCII), triangle-order body segmentation, twin-sheet
  removal, planar hole fill, plane sections, line/arc/circle loop fitting, prism and revolve
  plans, polygon triangulation with holes (including a hole touching the outer boundary), name
  plan for Inventor; tested without third-party packages -> docs/library/tools/tests/test_mesh_core.py
- [ ] OpenCascade build: synthetic box, slotted plate with fillets, revolved cup and a sheet on a
  host come out as closed valid solids within 1e-4 mm of the mesh; an imbricated face is repaired
  to a valid solid; STEP keeps names and face colours; skipped when CadQuery is absent ->
  docs/library/tools/tests/test_mesh_brep.py
- [ ] Golden master on the prior project's mesh (private, not in git): every body a closed valid
  solid (187), STL vertices to CAD max <= 1.3e-4 mm with the surfaces file, CAD to STL facets
  max <= 9e-4 mm -> judgment: source data is private; the run log is quoted in the Progress log
- [ ] Procedure, skill, toolchain note and README rows; no source names; plain hyphens;
  ./scripts/check.sh green -> judgment: check.sh output quoted in the Progress log

## Plan
| node | depends on | owner files | worker tier | status |
|---|---|---|---|---|
| N1 | - | docs/library/tools/mesh_core.py, docs/library/tools/tests/test_mesh_core.py | advisor | todo |
| N2 | N1 | docs/library/tools/mesh_brep.py, docs/library/tools/mesh_verify.py, docs/library/tools/tests/test_mesh_brep.py | advisor | todo |
| N3 | N1 | docs/library/tools/inventor_build.py | advisor | todo |
| N4 | N2 | .work/TASK.md | advisor | todo |
| N5 | N2, N3 | docs/library/procedures/mesh-to-cad.md, docs/library/skills/mesh-to-cad/SKILL.md, docs/library/toolchains/mesh-to-cad.md, docs/library/README.md | advisor | todo |
| N6 | N4, N5 | .work/TASK.md | reviewer | todo |

## Plan verdict

## Progress log
- 2026-11-06 task opened on a worktree from origin/main (526ff01).
- 2026-11-06 N1, N2, N3 written; plain python: 511 tests OK (8 skipped, CadQuery absent); CadQuery venv: 513 tests OK.
- 2026-11-06 golden run 1 (before zip_cracks): verify PASS (186 solids, all closed and valid, STL to CAD max 1.285e-4, CAD to STL max 8.93e-4) but solid volume 819.81 vs 934.13 delivered: the connector shell (114.32 mm3) stayed open (zero-area T-junction slit, not planar) and went to surfaces; distances hid it. Added zip_cracks, open_after_repair, and the count-and-volume gate in stage 4.
- 2026-11-06 golden runs 2 and 3: 187 solids, volume 934.13198, but the connector solid invalid (shell misoriented) and the board faceted, not a prism. Causes: (a) triangulate spliced a touching hole only at its rightmost vertex (regression test fails on the old code: 115.6 vs 99.2); (b) zip split next to a near-duplicate vertex, leaving a 1e-4 mm edge on four faces; (c) trimesh asked for a 9.41 GiB array on the board and the exception was swallowed into a faceted fallback. Fixed: splice at any coincident vertex; snap boundary vertices before splitting; chunked queries; rejections reported (exact_plan_rejected).
- 2026-11-06 golden run 4 (final code), build summary verbatim: {"bodies": 266, "solids": 187, "kinds": {"prism": 141, "faceted": 44, "faceted+face-repair": 1, "revolve": 1, "empty": 1}, "solid_volume": 934.1300759865212, "imprinted_patch_bodies": 25, "surface_bodies": 68, "open_after_repair": [221], "exact_plan_rejected": [], "failed": []}; build exit 0. Body 221 is a sub-0.1 micron sliver triangle that collapses when its vertices snap (kind empty). mesh_verify solids + surfaces: bodies 187, solids 187, valid 187, open [], invalid [], solid_volume 934.1300759631661, bbox_diff 3.32e-13, stl_to_cad max 1.2846e-4 p99 1.116e-4, cad_to_stl max 8.934e-4 p99 2.80e-4, PASS. Per-body volumes match the delivered conversion one to one (187 of 187 within 1e-6 relative; totals 934.1300760 vs 934.1300776).

## Review verdict
<!-- written ONLY by the independent reviewer -->

## Retro
<!-- filled by docs/procedures/retro.md -->
