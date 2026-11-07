#!/usr/bin/env python3
"""Mesh-to-CAD verify: check STEP files against the source STL using only those files.

Purpose: the acceptance check of the mesh-to-CAD procedure, independent of how the STEP was made
(mesh_brep, Inventor or another CAD tool). Reports per body whether it is a closed valid solid,
and the two-sided distance between the STL and the CAD:
  - STL vertices to CAD: the reconstruction error (STL vertices lie on the true surface);
  - CAD surface samples to STL facets: includes the STL's own chord error on curves.
Inputs: one or more solids STEP files (each body must be a closed solid), optional surfaces STEP
files (distance only), the STL.
Outputs: a report on stdout; `--json` writes it to a file.
Exit codes: 0 all gates pass, 1 a gate failed, 2 could not run.
Dependencies: CadQuery 2.x (OCP) and mesh_core.py. trimesh, when installed, is used for the
distance queries (much faster); otherwise the stdlib index in mesh_core gives the same values.
Assumptions: the tessellation used for distances has a linear deflection of 2e-4 mm by default,
so distances below about 1e-4 mm are at the checker's own resolution.
Origin: ported from the verification scripts of a one-off board conversion; generalised.
"""

from __future__ import annotations

import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mesh_core as mc  # noqa: E402


def read_bodies(path):
    """Top-level bodies of a STEP file: name, shape, solid count, free edges, validity, coloured faces."""
    try:
        from OCP.STEPCAFControl import STEPCAFControl_Reader
    except ImportError as e:
        raise mc.CannotRun("CadQuery (OCP) is not installed") from e
    from OCP.IFSelect import IFSelect_RetDone
    from OCP.TCollection import TCollection_ExtendedString
    from OCP.TDataStd import TDataStd_Name
    from OCP.TDF import TDF_Label, TDF_LabelSequence
    from OCP.TDocStd import TDocStd_Document
    from OCP.TopAbs import TopAbs_SOLID
    from OCP.XCAFDoc import XCAFDoc_ColorSurf, XCAFDoc_DocumentTool

    import mesh_brep as mb

    if not os.path.isfile(path):
        raise mc.CannotRun(f"no such STEP file: {path}")
    doc = TDocStd_Document(TCollection_ExtendedString("doc"))
    r = STEPCAFControl_Reader()
    r.SetNameMode(True)
    r.SetColorMode(True)
    if r.ReadFile(path) != IFSelect_RetDone:
        raise mc.CannotRun(f"cannot read STEP: {path}")
    r.Transfer(doc)
    st = XCAFDoc_DocumentTool.ShapeTool_s(doc.Main())
    ct = XCAFDoc_DocumentTool.ColorTool_s(doc.Main())

    def name(lab):
        a = TDataStd_Name()
        return a.Get().ToExtString() if lab.FindAttribute(TDataStd_Name.GetID_s(), a) else ""

    out = []

    def walk(lab):
        if st.IsAssembly_s(lab):
            ch = TDF_LabelSequence()
            st.GetComponents_s(lab, ch)
            for i in range(1, ch.Length() + 1):
                ref = TDF_Label()
                if st.GetReferredShape_s(ch.Value(i), ref):
                    walk(ref)
            return
        s = st.GetShape_s(lab)
        subs = TDF_LabelSequence()
        st.GetSubShapes_s(lab, subs)
        coloured = sum(1 for i in range(1, subs.Length() + 1) if ct.IsSet(subs.Value(i), XCAFDoc_ColorSurf))
        solids = mb.subshapes(s, TopAbs_SOLID)
        out.append(dict(name=name(lab), shape=s, solids=len(solids), free_edges=mb.free_edges(s),
                        valid=all(mb.is_valid(x) for x in solids) and bool(solids), coloured_faces=coloured,
                        volume=sum(mb.volume(x) for x in solids)))

    roots = TDF_LabelSequence()
    st.GetFreeShapes(roots)
    for i in range(1, roots.Length() + 1):
        walk(roots.Value(i))
    return out


def _distances(cad_tris, stl_tris):
    stl_pts = list({p for t in stl_tris for p in t})
    cad_pts = mc.sample_points(cad_tris)
    try:
        import numpy as np
        import trimesh

        T = trimesh.Trimesh(np.array([p for t in cad_tris for p in t]), np.arange(3 * len(cad_tris)).reshape(-1, 3), process=False)
        M = trimesh.Trimesh(np.array([p for t in stl_tris for p in t]), np.arange(3 * len(stl_tris)).reshape(-1, 3), process=False)
        d1 = np.abs(trimesh.proximity.closest_point(T, np.array(stl_pts))[1])
        d2 = np.abs(trimesh.proximity.closest_point(M, np.array(cad_pts))[1])
        return sorted(d1.tolist()), sorted(d2.tolist())
    except ImportError:
        a, b = mc.TriIndex(cad_tris), mc.TriIndex(stl_tris)
        return sorted(a.distance(p) for p in stl_pts), sorted(b.distance(p) for p in cad_pts)


def _pct(sorted_vals, q):
    return sorted_vals[min(len(sorted_vals) - 1, int(q * len(sorted_vals)))] if sorted_vals else float("nan")


def verify(solid_steps, stl, surface_steps=(), lin=2e-4, log=print):
    import mesh_brep as mb

    stl_tris = mc.read_stl(stl)
    bodies, cad_tris = [], []
    for p in solid_steps:
        for b in read_bodies(p):
            b["file"] = os.path.basename(p)
            bodies.append(b)
            cad_tris += mb.tessellate(b["shape"], lin, 0.05)
    for p in surface_steps:
        for b in read_bodies(p):
            cad_tris += mb.tessellate(b["shape"], lin, 0.05)
    if not cad_tris:
        raise mc.CannotRun("the STEP files hold no geometry")
    d1, d2 = _distances(cad_tris, stl_tris)
    lo = [min(p[k] for t in cad_tris for p in t) for k in range(3)]
    hi = [max(p[k] for t in cad_tris for p in t) for k in range(3)]
    slo = [min(p[k] for t in stl_tris for p in t) for k in range(3)]
    shi = [max(p[k] for t in stl_tris for p in t) for k in range(3)]
    rep = dict(
        bodies=len(bodies),
        solids=sum(b["solids"] for b in bodies),
        valid_bodies=sum(1 for b in bodies if b["valid"]),
        open_bodies=[b["name"] or f"#{i}" for i, b in enumerate(bodies) if b["free_edges"] or not b["solids"]],
        invalid_bodies=[b["name"] or f"#{i}" for i, b in enumerate(bodies) if not b["valid"]],
        solid_volume=sum(b["volume"] for b in bodies),
        bbox_diff=max(max(abs(a - b) for a, b in zip(lo, slo)), max(abs(a - b) for a, b in zip(hi, shi))),
        stl_to_cad_max=d1[-1],
        stl_to_cad_p99=_pct(d1, 0.99),
        cad_to_stl_max=d2[-1],
        cad_to_stl_p99=_pct(d2, 0.99),
    )
    for k, v in rep.items():
        log(f"{k}: {v}")
    return rep


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("step", nargs="+", help="solids STEP file(s); every body must be a closed valid solid")
    ap.add_argument("--stl", required=True)
    ap.add_argument("--surfaces", nargs="*", default=[], help="surface STEP file(s): distance only")
    ap.add_argument("--max-vertex", type=float, default=1.5e-4, help="gate: STL vertices to CAD, mm")
    ap.add_argument("--max-chord", type=float, default=2e-3, help="gate: CAD samples to STL facets, mm")
    ap.add_argument("--json", help="write the report here")
    args = ap.parse_args(argv)
    try:
        rep = verify(args.step, args.stl, args.surfaces)
    except mc.CannotRun as e:
        print(f"CANNOT: {e}", file=sys.stderr)
        return mc.CANNOT
    fails = []
    if rep["open_bodies"]:
        fails.append(f"open bodies: {rep['open_bodies'][:10]}")
    if rep["invalid_bodies"]:
        fails.append(f"invalid bodies: {rep['invalid_bodies'][:10]}")
    if rep["stl_to_cad_max"] > args.max_vertex:
        fails.append(f"STL vertices to CAD {rep['stl_to_cad_max']:.3e} > {args.max_vertex}")
    if rep["cad_to_stl_max"] > args.max_chord:
        fails.append(f"CAD to STL {rep['cad_to_stl_max']:.3e} > {args.max_chord}")
    rep["fails"] = fails
    if args.json:
        with open(args.json, "w") as fh:
            json.dump(rep, fh, indent=1)
    for f in fails:
        print("FAIL:", f)
    print("PASS" if not fails else "FAIL")
    return mc.FAIL if fails else mc.PASS


if __name__ == "__main__":
    sys.exit(main())
