# Toolchain: engineering analysis and marketing media

A set of free tools, installed and checked together, for a physical product
project that needs real engineering (strength, mechanisms, water) and turns
the results into product films, stills and web 3D. Library item: used in one
prior project (a consumer hardware product), so plausible, not proven
general (`docs/library/README.md`).

Use it in `docs/procedures/discover.md` step 2: for each activity below, check
whether the tool is already on the machine (`<tool> --version` or the check
in the table) before choosing or installing anything else. Record what you
find in the project's `docs/CAPABILITY_MAP.md` and a `docs/TOOLS.md` with
paths and run commands. Versions below were verified on 2026-10-31; VERIFY
current versions and licences on the day.

Do not use when the project is software only, or when a commercial solver
is already contracted and its results are the record.

## The chain

CAD -> analysis (CalculiX, OpenFOAM, DualSPHysics, PyChrono) -> results into
Blender (PyVista-Blender or a ParaView export) -> films and stills in the
project's look (`docs/library/procedures/product-render.md`) -> edit and social cuts (DaVinci Resolve) -> web 3D and AR
(model-viewer with glTF and USDZ). Solver output is never shown raw to
customers: it goes through the render step.

## Tools

| Activity | Tool | Licence | Install from | Checked with |
|---|---|---|---|---|
| Structural FEA (contact, large deflection, rubber, yield) | PrePoMax 2.6.0 GUI + CalculiX solver | GPL | official portable zip (prepomax.fs.um.si) | 100 x 10 x 10 mm steel cantilever, 100 N: tip 0.1904 mm vs beam theory 0.1905 mm |
| Water and air flow, free surface | OpenFOAM 14 (openfoam.org) | GPL | official apt repository inside WSL2 Ubuntu 24.04 on Windows | standard dam-break tutorial (incompressibleVoF) runs to 0.25 s, continuity error about 1e-9 |
| Splash and pour as particles (visual water) | DualSPHysics 5.4 | LGPL | dual.sphysics.org full package (the GitHub repository ships only the helper tools) | helper tools only; solver not yet checked |
| Mechanism motion (hinges, lids, tipping) | PyChrono 10.0.0 | BSD-3 | official `projectchrono` conda channel via Miniforge | a lid released flat swings 58 deg in 0.2 s about a revolute joint (hand estimate about 60 deg) |
| Results into the renderer | PyVista-Blender 0.1.0 (+ bpy as a Python module) | MIT | PyPI | stress-coloured mesh rendered in Cycles and saved as .blend |
| Results inspection and export | ParaView 6.2.0 | BSD | official Windows zip | `pvpython` imports `paraview.simple` |
| People in renders (body sizes, ergonomics) | MPFB 2.0.18 (MakeHuman for Blender) | code GPL, body assets CC0 | extensions.blender.org | installs and enables; checksum matched the listing |
| Edit, colour, social cuts | DaVinci Resolve (free) | free licence, check the EULA for commercial use | blackmagicdesign.com (download form asks for name and email, so the owner installs it) | not installed by an agent |
| Web 3D and AR | model-viewer | Apache 2.0 | pinned version from a CDN on the website | nothing to install |

## Pitfalls found on install

- PyChrono on Windows: running the conda env's `python.exe` without
  activating the env makes SDL "failed to load" error pop-ups. Run it through
  a small wrapper that puts the env's `Library\bin` folders on PATH first.
- The PyPI package named `pychrono` is not the official one; use the
  `projectchrono` conda channel.
- PrePoMax 2.6 runs without the separate ActiViz installer; the VTK files it
  needs are bundled.
- OpenFOAM from Git Bash: Git Bash rewrites `/mnt/c/...` paths and `$`
  inside commands sent to WSL. Set `MSYS_NO_PATHCONV=1`, put WSL commands in
  a script file, and strip CRLF line endings from it. OpenFOAM 14 tutorials
  may have no `Allrun`; run `blockMesh` and `foamRun` directly.
- WSL install needs one reboot only on a machine that never had it; set the
  Linux user's password yourself, never share it with an agent (agents can
  use `wsl -u root` for installs).
- Renders that launch Blender with `--factory-startup` must enable MPFB in
  the script; it is not loaded by default.

## Considered and not used

| Tool | Reason |
|---|---|
| FluidX3D | Free for non-commercial use only; commercial use needs a deal with the author. |
| OpenRadioss (drop tests) | Public access was being reorganised in 2026; revisit if a stable source appears. CalculiX covers simple quasi-static impact. |
| Code_Aster / Salome-Meca | Strong for extreme rubber deformation but a steep learning curve; keep as the fallback if CalculiX cannot converge. |
| Linear-only Python FEA (gmsh + scikit-fem) | Fine for quick linear checks; no contact, large deflection or rubber, so CalculiX is the main solver. |
