#!/usr/bin/env python3
"""Mesh-to-CAD build: turn every body of an STL into a closed, valid B-rep solid and write STEP.

Purpose: the OpenCascade half of the mesh-to-CAD procedure. For each source body found by
mesh_core: build the exact plan (stacked prism or revolve) when it passes the gates, else a
faceted solid (triangles sewn, coplanar faces merged only where the merge stays on the mesh).
Zero-thickness patches that lie on a solid are imprinted into its faces and coloured there; the
rest go to a separate cosmetic-surfaces STEP. Open bodies are first closed where the exporter left
T-junction cracks (zip) or tiny planar holes (fill). Invalid faces whose hole touches the outer
boundary (seen where an exporter pinched a shell) are replaced by their triangulation.
Inputs: STL (mm); optional names JSON {"default": {"colour": "#hex"}, "<body id>": {"name", "colour"}}.
Outputs (in --out): solids.step (closed solids, body names, colours, imprinted face colours),
  surfaces.step (patches touching no solid, only when there are any), each/<id>_p<k>.step (one
  file per solid part) and each/<id>_surf.step (per-body patches) for CAD imports, features.json
  (exact plans for inventor_build), report.json (per part: representation, validity, errors in mm).
Exit codes: 0 every body passed its gates, 1 a body failed (named in report.json), 2 could not run.
Dependencies: CadQuery 2.x (OCP, OpenCascade 7.7+) and mesh_core.py beside this file.
Assumptions:
  - Gates (mm): an exact or merged body is kept only when every source vertex lies within 1e-4 of
    it and its surface within 2e-3 of the source facets (the chord error of tessellated curves);
    otherwise the next representation is tried. A faceted body without merging equals the mesh.
  - A patch belongs to a host when all its vertices and triangle centres lie within 1e-5 of that
    host's surface; anything farther is not guessed onto a part.
Origin: ported from a one-off conversion of a populated circuit board (155k triangles) to STEP
and Inventor, including the closed-solid repairs made after delivery; generalised.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from collections import Counter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mesh_core as mc  # noqa: E402

VERR_GATE = 1e-4
CERR_GATE = 2e-3
HOST_TOL = 1e-5
DEFAULT_COLOUR = "#9A9A9A"
CHUNK = 2000  # points per distance query


def _require_cadquery():
    try:
        import cadquery  # noqa: F401
    except ImportError as e:
        raise mc.CannotRun("CadQuery is not installed: uv pip install cadquery (see the toolchain note)") from e


# ---------------------------------------------------------------- OCC helpers
def subshapes(shape, kind):
    from OCP.TopExp import TopExp_Explorer

    out, e = [], TopExp_Explorer(shape, kind)
    while e.More():
        out.append(e.Current())
        e.Next()
    return out


def compound(shapes):
    from OCP.BRep import BRep_Builder
    from OCP.TopoDS import TopoDS_Compound

    c = TopoDS_Compound()
    b = BRep_Builder()
    b.MakeCompound(c)
    for s in shapes:
        b.Add(c, s)
    return c


def is_valid(shape) -> bool:
    from OCP.BRepCheck import BRepCheck_Analyzer

    return BRepCheck_Analyzer(shape).IsValid()


def free_edges(shape) -> int:
    from OCP.BRep import BRep_Tool
    from OCP.TopAbs import TopAbs_EDGE, TopAbs_FACE
    from OCP.TopExp import TopExp
    from OCP.TopoDS import TopoDS
    from OCP.TopTools import TopTools_IndexedDataMapOfShapeListOfShape

    m = TopTools_IndexedDataMapOfShapeListOfShape()
    TopExp.MapShapesAndAncestors_s(shape, TopAbs_EDGE, TopAbs_FACE, m)
    n = 0
    for i in range(1, m.Extent() + 1):
        if BRep_Tool.Degenerated_s(TopoDS.Edge_s(m.FindKey(i))):
            continue
        if m.FindFromIndex(i).Extent() == 1:
            n += 1
    return n


def volume(shape) -> float:
    from OCP.BRepGProp import BRepGProp
    from OCP.GProp import GProp_GProps

    g = GProp_GProps()
    BRepGProp.VolumeProperties_s(shape, g)
    return g.Mass()


def tessellate(shape, lin=5e-5, ang=0.02):
    import cadquery as cq

    vs, fs = cq.Shape.cast(shape).tessellate(lin, ang)
    v = [p.toTuple() for p in vs]
    return [(v[a], v[b], v[c]) for a, b, c in fs]


def max_distance(points, tris) -> float:
    """Largest distance from points to the triangle surface; trimesh when installed (fast), else
    the stdlib index in mesh_core (same values)."""
    points = list(points)
    try:
        import numpy as np
        import trimesh

        T = trimesh.Trimesh(np.array([p for t in tris for p in t]), np.arange(3 * len(tris)).reshape(-1, 3), process=False)
        # chunks: long thin facets have large bounding boxes, and one query over every point at
        # once asked for a 9 GiB candidate array on a board outline with 144 holes
        return max(
            float(np.abs(trimesh.proximity.closest_point(T, np.array(points[k : k + CHUNK]))[1]).max())
            for k in range(0, len(points), CHUNK)
        )
    except ImportError:
        idx = mc.TriIndex(tris)
        return max(idx.distance(p) for p in points)


def errors(tris, shape):
    """(vertex error, chord error) in mm: source vertices to the B-rep, B-rep samples to the source."""
    t = tessellate(shape)
    if not t:
        return float("inf"), float("inf")
    return max_distance({p for tri in tris for p in tri}, t), max_distance(mc.sample_points(t), tris)


def _face(tri):
    from OCP.BRepBuilderAPI import BRepBuilderAPI_MakeFace, BRepBuilderAPI_MakePolygon
    from OCP.gp import gp_Pnt

    poly = BRepBuilderAPI_MakePolygon()
    for p in tri:
        poly.Add(gp_Pnt(*map(float, p)))
    poly.Close()
    f = BRepBuilderAPI_MakeFace(poly.Wire(), True)
    return f.Face() if f.IsDone() else None


def _solid_from_shell(sh):
    from OCP.BRepBuilderAPI import BRepBuilderAPI_MakeSolid
    from OCP.ShapeFix import ShapeFix_Solid
    from OCP.TopAbs import TopAbs_SHELL
    from OCP.TopoDS import TopoDS

    shells = subshapes(sh, TopAbs_SHELL)
    if len(shells) != 1:
        return None
    ms = BRepBuilderAPI_MakeSolid(TopoDS.Shell_s(shells[0]))
    fx = ShapeFix_Solid(ms.Solid())
    fx.Perform()
    return fx.Solid()


def faceted(tris, merge=True, tol=1e-4):
    """Sewn polyhedral solid; coplanar faces merged when the merge stays within 1e-5 of the mesh."""
    from OCP.BRepBuilderAPI import BRepBuilderAPI_Sewing
    from OCP.ShapeUpgrade import ShapeUpgrade_UnifySameDomain

    sew = BRepBuilderAPI_Sewing(tol)
    for t in tris:
        f = _face(t)
        if f is not None:
            sew.Add(f)
    sew.Perform()
    sh = sew.SewedShape()
    if merge:
        u = ShapeUpgrade_UnifySameDomain(sh, True, True, False)
        u.SetLinearTolerance(1e-5)
        u.SetAngularTolerance(1e-6)
        u.Build()
        merged = u.Shape()
        # the merge can flatten facets a few microns out of plane: keep it only if it stays on the mesh
        mt = tessellate(merged, 1e-4, 0.05)
        if mt and max_distance(mc.sample_points(mt), tris) < 1e-5:
            sh = merged
    return _solid_from_shell(sh)


def sheet_faces(tris):
    """Zero-thickness patches: one planar face per triangle, sewn only where edges coincide."""
    from OCP.BRepBuilderAPI import BRepBuilderAPI_Sewing

    sew = BRepBuilderAPI_Sewing(1e-6)
    n = 0
    for t in tris:
        if mc.norm(mc.cross(mc.sub(t[1], t[0]), mc.sub(t[2], t[0]))) < 1e-12:
            continue
        f = _face(t)
        if f is not None:
            sew.Add(f)
            n += 1
    if n == 0:
        return None
    sew.Perform()
    return sew.SewedShape()


# ---------------------------------------------------------------- exact features
def _p3(axis, level, p):
    import cadquery as cq

    q = [0.0, 0.0, 0.0]
    u, v = mc.UV[axis]
    q[u], q[v], q[mc.AX[axis]] = p[0], p[1], level
    return cq.Vector(*q)


def _wire(segs, to3, normal):
    import cadquery as cq

    if segs[0][0] == "C":
        return cq.Wire.assembleEdges([cq.Edge.makeCircle(segs[0][2], to3(segs[0][1]), cq.Vector(*normal))])
    edges = []
    for s in segs:
        if s[0] == "L":
            if mc.norm((s[2][0] - s[1][0], s[2][1] - s[1][1], 0.0)) > 1e-9:
                edges.append(cq.Edge.makeLine(to3(s[1]), to3(s[2])))
        else:
            edges.append(cq.Edge.makeThreePointArc(to3(s[1]), to3(s[2]), to3(s[3])))
    return cq.Wire.assembleEdges(edges)


def build_prism(rec):
    import cadquery as cq

    ax = rec["axis"]
    normal = [0.0, 0.0, 0.0]
    normal[mc.AX[ax]] = 1.0
    slabs = []
    for s in rec["slabs"]:
        a, b = s["z0"], s["z1"]

        def to3(p, a=a):
            return _p3(ax, a, p)

        face = cq.Face.makeFromWires(_wire(s["outer"], to3, normal), [_wire(i, to3, normal) for i in s["inner"]])
        d = [0.0, 0.0, 0.0]
        d[mc.AX[ax]] = b - a
        slabs.append(cq.Solid.extrudeLinear(face, cq.Vector(*d)))
    s = slabs[0]
    s = s.fuse(*slabs[1:], glue=False).clean() if len(slabs) > 1 else s.clean()
    return s.wrapped


def build_revolve(rec):
    import cadquery as cq

    ax = rec["axis"]
    k = mc.AX[ax]
    u, v = mc.UV[ax]
    cu, cv = rec["centre"]

    def to3(p):
        q = [0.0, 0.0, 0.0]
        q[u], q[v], q[k] = cu + p[0], cv, p[1]
        return cq.Vector(*q)

    edges = []
    for s in rec["profile"]:
        if s[0] == "L":
            if abs(s[2][0] - s[1][0]) + abs(s[2][1] - s[1][1]) > 1e-9:
                edges.append(cq.Edge.makeLine(to3(s[1]), to3(s[2])))
        else:
            edges.append(cq.Edge.makeThreePointArc(to3(s[1]), to3(s[2]), to3(s[3])))
    face = cq.Face.makeFromWires(cq.Wire.assembleEdges(edges))
    o = [0.0, 0.0, 0.0]
    o[u], o[v] = cu, cv
    d = list(o)
    d[k] += 1.0
    return cq.Solid.revolve(face, 360, cq.Vector(*o), cq.Vector(*d)).clean().wrapped


# ---------------------------------------------------------------- repairs
def _face_normal(face):
    """Outward unit normal of a planar face (the surface normal, flipped for a reversed face)."""
    from OCP.BRepAdaptor import BRepAdaptor_Surface
    from OCP.TopAbs import TopAbs_REVERSED

    ad = BRepAdaptor_Surface(face)
    d = ad.Plane().Axis().Direction()
    n = (d.X(), d.Y(), d.Z())
    return (-n[0], -n[1], -n[2]) if face.Orientation() == TopAbs_REVERSED else n
def repair_imbricated(solid):
    """Replace planar faces that fail validity (a hole wire touching the outer wire, a slit) by
    triangles over the same boundary vertices, resew, and keep the result only if it is a valid
    closed solid of the same volume. Returns (solid, faces_replaced)."""
    from OCP.BRep import BRep_Tool
    from OCP.BRepBuilderAPI import BRepBuilderAPI_Sewing
    from OCP.BRepTools import BRepTools, BRepTools_WireExplorer
    from OCP.TopAbs import TopAbs_FACE, TopAbs_WIRE
    from OCP.TopoDS import TopoDS

    if is_valid(solid):
        return solid, 0
    faces = subshapes(solid, TopAbs_FACE)
    bad = [f for f in faces if not is_valid(f)]
    if not bad:
        return solid, 0
    sew = BRepBuilderAPI_Sewing(1e-6)
    for f in faces:
        if not any(f.IsSame(b) for b in bad):
            sew.Add(f)
    for f in bad:
        face = TopoDS.Face_s(f)
        outer = BRepTools.OuterWire_s(face)

        def ring(w, face=face):
            ex = BRepTools_WireExplorer(TopoDS.Wire_s(w), face)
            pts = []
            while ex.More():
                p = BRep_Tool.Pnt_s(ex.CurrentVertex())
                pts.append((p.X(), p.Y(), p.Z()))
                ex.Next()
            return pts

        rings = [ring(outer)] + [ring(w) for w in subshapes(f, TopAbs_WIRE) if not w.IsSame(outer)]
        c, n, dmax = mc.plane_fit(rings[0])
        if dmax > 1e-6:
            return solid, 0
        bu, bv = mc._plane_basis(n)
        flat = [[(mc.dot(mc.sub(p, c), bu), mc.dot(mc.sub(p, c), bv)) for p in r] for r in rings]
        pts3 = [p for r in rings for p in r]
        try:
            tri_ids = mc.triangulate(flat[0], flat[1:])
        except ValueError:
            return solid, 0
        # wind every triangle like the face it replaces: sewing does not reorient faces next to
        # edges shared by more than two faces, and a mixed winding leaves the shell misoriented
        outward = _face_normal(face)
        for a, b, cc in tri_ids:
            tri = (pts3[a], pts3[b], pts3[cc])
            if mc.dot(mc.cross(mc.sub(tri[1], tri[0]), mc.sub(tri[2], tri[0])), outward) < 0:
                tri = (tri[0], tri[2], tri[1])
            t = _face(tri)
            if t is not None:
                sew.Add(t)
    sew.Perform()
    new = _solid_from_shell(sew.SewedShape())
    if new is None or not is_valid(new) or free_edges(new) or abs(volume(new) - volume(solid)) > 1e-9 * max(1.0, abs(volume(solid))):
        return solid, 0
    return new, len(bad)


def imprint(host, patch_groups):
    """Split the host's faces along patch outlines. patch_groups: [(patch_id, [faces])].
    Returns (solid, [(face, patch_id)]) or (host, []) when the split changes the solid."""
    from OCP.BRepAlgoAPI import BRepAlgoAPI_Splitter
    from OCP.BRepBuilderAPI import BRepBuilderAPI_MakeVertex
    from OCP.BRepExtrema import BRepExtrema_DistShapeShape
    from OCP.gp import gp_Pnt
    from OCP.TopAbs import TopAbs_FACE, TopAbs_SOLID
    from OCP.TopTools import TopTools_ListOfShape

    args, tools = TopTools_ListOfShape(), TopTools_ListOfShape()
    args.Append(host)
    for _, faces in patch_groups:
        for f in faces:
            tools.Append(f)
    sp = BRepAlgoAPI_Splitter()
    sp.SetArguments(args)
    sp.SetTools(tools)
    sp.SetFuzzyValue(1e-6)
    sp.Build()
    if not sp.IsDone():
        return host, []
    res = subshapes(sp.Shape(), TopAbs_SOLID)
    if len(res) != 1 or not is_valid(res[0]) or abs(volume(res[0]) - volume(host)) > 1e-9 * max(1.0, volume(host)):
        return host, []
    new = res[0]
    groups = [(pid, compound(fs)) for pid, fs in patch_groups]
    coloured = []
    for f in subshapes(new, TopAbs_FACE):
        t = tessellate(f, 1e-4, 0.1)
        if not t:
            continue
        a, b, c = t[0]
        p = gp_Pnt((a[0] + b[0] + c[0]) / 3, (a[1] + b[1] + c[1]) / 3, (a[2] + b[2] + c[2]) / 3)
        vtx = BRepBuilderAPI_MakeVertex(p).Vertex()
        for pid, comp in groups:
            d = BRepExtrema_DistShapeShape(vtx, comp)
            d.Perform()
            if d.Value() < 1e-7:
                coloured.append((f, pid))
                break
    return new, coloured


# ---------------------------------------------------------------- STEP
def write_step(path, root_name, items):
    """items: [(name, shape, hex colour, [(face, hex colour)])] -> AP214 STEP with names and colours."""
    from OCP.Interface import Interface_Static
    from OCP.Quantity import Quantity_Color, Quantity_TOC_RGB
    from OCP.STEPCAFControl import STEPCAFControl_Writer
    from OCP.STEPControl import STEPControl_AsIs
    from OCP.TCollection import TCollection_ExtendedString
    from OCP.TDataStd import TDataStd_Name
    from OCP.TDocStd import TDocStd_Document
    from OCP.TopLoc import TopLoc_Location
    from OCP.XCAFApp import XCAFApp_Application
    from OCP.XCAFDoc import XCAFDoc_ColorSurf, XCAFDoc_DocumentTool

    def col(h):
        h = h.lstrip("#")
        return Quantity_Color(*(int(h[k : k + 2], 16) / 255 for k in (0, 2, 4)), Quantity_TOC_RGB)

    app = XCAFApp_Application.GetApplication_s()
    doc = TDocStd_Document(TCollection_ExtendedString("MDTV-XCAF"))
    app.NewDocument(TCollection_ExtendedString("MDTV-XCAF"), doc)
    st = XCAFDoc_DocumentTool.ShapeTool_s(doc.Main())
    ct = XCAFDoc_DocumentTool.ColorTool_s(doc.Main())
    top = st.NewShape()
    TDataStd_Name.Set_s(top, TCollection_ExtendedString(root_name))
    for name, shape, hexc, face_cols in items:
        lab = st.AddShape(shape, False)
        TDataStd_Name.Set_s(lab, TCollection_ExtendedString(name))
        ct.SetColor(lab, col(hexc), XCAFDoc_ColorSurf)
        for f, fh in face_cols:
            ct.SetColor(st.AddSubShape(lab, f), col(fh), XCAFDoc_ColorSurf)
        comp = st.AddComponent(top, lab, TopLoc_Location())
        TDataStd_Name.Set_s(comp, TCollection_ExtendedString(name))
    st.UpdateAssemblies()
    Interface_Static.SetCVal_s("write.step.schema", "AP214IS")
    Interface_Static.SetCVal_s("write.step.unit", "MM")
    w = STEPCAFControl_Writer()
    w.SetColorMode(True)
    w.SetNameMode(True)
    w.Transfer(doc, STEPControl_AsIs)
    if w.Write(path) != 1:
        raise mc.CannotRun(f"STEP write failed: {path}")


# ---------------------------------------------------------------- pipeline
def build_solid(tris):
    """Best closed solid for one closed part -> (shape, plan or None, kind, verr, cerr)."""
    plan = mc.plan_body(tris)
    tried = []
    if plan is not None:
        try:
            s = build_prism(plan) if plan["kind"] == "prism" else build_revolve(plan)
            ve, ce = errors(tris, s)
            # true arcs sit up to one chord sag off the facets: allow the sag the plan's own
            # tessellation bound gives, never less than the faceted gate
            if is_valid(s) and ve < VERR_GATE and ce < max(CERR_GATE, 1.05 * plan.get("chord_limit", 0.0)):
                return s, plan, plan["kind"], ve, ce, ""
            tried.append(f"{plan['kind']} verr {ve:.1e} cerr {ce:.1e}")
        except Exception as e:  # an OCC failure on one body must not stop the run; it is reported
            tried.append(f"{plan['kind']} failed: {type(e).__name__}: {str(e)[:80]}")
    last = (None, float("inf"), float("inf"))
    for merge in (True, False):
        s = faceted(tris, merge=merge)
        if s is None:
            tried.append(f"faceted merge={merge}: no single shell")
            continue
        s, fixed = repair_imbricated(s)
        ve, ce = errors(tris, s)
        kind = ("faceted" if merge else "faceted(no-merge)") + ("+face-repair" if fixed else "")
        if ve < VERR_GATE and ce < CERR_GATE:
            return s, None, kind, ve, ce, "; ".join(tried)
        tried.append(f"faceted merge={merge} verr {ve:.1e}")
        last = (s, ve, ce)
    return last[0], None, "faceted(gate-fail: " + "; ".join(tried) + ")", last[1], last[2], "; ".join(tried)


def run(stl, out, names=None, mode="order", fill_area=1e-3, zip_tol=1e-4, log=print):
    _require_cadquery()
    os.makedirs(os.path.join(out, "each"), exist_ok=True)
    names = names or {}
    default_colour = names.get("default", {}).get("colour", DEFAULT_COLOUR)
    tris = mc.read_stl(stl)
    groups = mc.segment_bodies(tris, mode=mode)
    bodies = []
    open_left: list[int] = []
    for i, idx in enumerate(groups):
        part = [tris[k] for k in idx]
        filled = zipped = 0
        if zip_tol > 0 and not mc.Mesh(part).is_watertight():
            part, zipped = mc.zip_cracks(part, zip_tol)
        if fill_area > 0 and not mc.Mesh(part).is_watertight():
            part, filled = mc.fill_planar_holes(part, fill_area)
        solids, sheets = mc.split_parts(part)
        if any(n == 1 for n in mc.Mesh(part).edge_counts().values()):
            open_left.append(i)  # still open after repair: its triangles become surfaces; review it
        meta = names.get(str(i), {})
        bodies.append(dict(id=i, name=meta.get("name", f"body_{i:03d}"), colour=meta.get("colour", default_colour),
                           tris=part, solids=solids, sheets=sheets, filled=filled, zipped=zipped))

    # every closed part, indexed for host lookup
    host_index = []
    report, features = [], []
    shapes = {}
    for b in bodies:
        built = []
        for k, sp in enumerate(b["solids"]):
            s, plan, kind, ve, ce, rejected = build_solid(sp)
            built.append(s)
            if plan is not None:
                features.append(dict(plan, id=b["id"], part=k, name=b["name"], colour=b["colour"]))
            report.append(dict(id=b["id"], part=k, name=b["name"], kind=kind, valid=bool(s is not None and is_valid(s)),
                               free_edges=free_edges(s) if s is not None else None, verr=ve, cerr=ce,
                               volume=volume(s) if s is not None else None, mesh_volume=abs(mc.Mesh(sp).volume()),
                               holes_filled=b["filled"], cracks_zipped=b["zipped"], rejected=rejected))
            host_index.append((b["id"], k, mc.TriIndex(sp)))
            log(f"{b['id']:4d} {b['name']:<28} {kind:<22} verr {ve:.1e} cerr {ce:.1e}")
        shapes[b["id"]] = built
        if not b["solids"] and not b["sheets"]:
            report.append(dict(id=b["id"], part=None, name=b["name"], kind="empty", valid=False))

    # patches: imprint onto a host they lie on, else cosmetic surfaces
    on_host, floating = {}, []
    for b in bodies:
        if not b["sheets"]:
            continue
        pts = mc.sample_points(b["sheets"])
        host = None
        for hid, k, idx in host_index:
            lo, hi = idx.lo, idx.hi
            if any(p[j] < lo[j] - HOST_TOL or p[j] > hi[j] + HOST_TOL for p in pts[:3] for j in range(3)):
                continue
            if max(idx.distance(p) for p in pts) <= HOST_TOL:
                host = (hid, k)
                if hid == b["id"]:
                    break
        sf = sheet_faces(b["sheets"])
        faces = subshapes(sf, _topabs("FACE")) if sf is not None else []
        if host is not None and faces:
            on_host.setdefault(host, []).append((b["id"], faces))
        elif faces:
            floating.append((b, faces))
    face_cols: dict = {}
    by_id = {b["id"]: b for b in bodies}
    imprinted = 0
    for (hid, k), plist in on_host.items():
        new, coloured = imprint(shapes[hid][k], plist)
        if coloured:
            imprinted += len(plist)
            shapes[hid][k] = new
            face_cols.setdefault((hid, k), []).extend((f, by_id[pid]["colour"]) for f, pid in coloured)
            log(f"imprint {len(plist)} patch bodies on body {hid}: {len(coloured)} faces coloured")
        else:
            floating.extend((by_id[pid], fs) for pid, fs in plist)
            log(f"imprint on body {hid} failed: patches kept as surfaces")

    items = []
    for b in bodies:
        name = f"{b['id']:03d}_{b['name']}"
        parts = [(k, x) for k, x in enumerate(shapes[b["id"]]) if x is not None]
        if not parts:
            continue
        cols = [fc for k, _ in parts for fc in face_cols.get((b["id"], k), [])]
        shp = parts[0][1] if len(parts) == 1 else compound([x for _, x in parts])
        items.append((name, shp, b["colour"], cols))
        for k, x in parts:  # one file per part, for CAD tools that import body by body
            write_step(os.path.join(out, "each", f"{b['id']:03d}_p{k}.step"), name, [(name, x, b["colour"], face_cols.get((b["id"], k), []))])
    write_step(os.path.join(out, "solids.step"), os.path.splitext(os.path.basename(stl))[0], items)
    if floating:
        surf_items = []
        for b, faces in floating:
            surf_items.append((f"{b['id']:03d}_{b['name']}_surface", compound(faces), b["colour"], []))
            write_step(os.path.join(out, "each", f"{b['id']:03d}_surf.step"), surf_items[-1][0], [surf_items[-1]])
        write_step(os.path.join(out, "surfaces.step"), os.path.splitext(os.path.basename(stl))[0] + "_surfaces", surf_items)
    with open(os.path.join(out, "features.json"), "w") as fh:
        json.dump(features, fh, default=list)
    summary = dict(
        bodies=len(bodies),
        solids=sum(1 for r in report if r.get("valid")),
        kinds=dict(Counter(r["kind"].split("(")[0] for r in report if r.get("kind"))),
        solid_volume=sum(r["volume"] or 0.0 for r in report if r.get("part") is not None),
        imprinted_patch_bodies=imprinted,
        surface_bodies=len(floating),
        open_after_repair=open_left,
        exact_plan_rejected=[r["id"] for r in report if r.get("rejected") and not r["kind"].startswith("faceted(gate")],
        failed=[r["id"] for r in report if r.get("part") is not None and (not r["valid"] or r["free_edges"] or "gate-fail" in r["kind"])],
    )
    with open(os.path.join(out, "report.json"), "w") as fh:
        json.dump(dict(summary=summary, bodies=report), fh, indent=1)
    log(json.dumps(summary))
    return summary


def _topabs(name):
    from OCP import TopAbs

    return getattr(TopAbs, "TopAbs_" + name)


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("stl")
    ap.add_argument("--out", required=True, help="output folder (created)")
    ap.add_argument("--names", help="JSON: body id -> name and colour; key 'default' for the rest")
    ap.add_argument("--mode", default="order", choices=["order", "connectivity"], help="body segmentation (mesh_core)")
    ap.add_argument("--fill-area", type=float, default=1e-3, help="close planar holes up to this area (mm2); 0 = off")
    ap.add_argument("--zip-tol", type=float, default=1e-4, help="zip T-junction cracks within this distance (mm); 0 = off")
    args = ap.parse_args(argv)
    try:
        names = None
        if args.names:
            with open(args.names) as fh:
                names = json.load(fh)
        summary = run(args.stl, args.out, names, args.mode, args.fill_area, args.zip_tol)
    except (mc.CannotRun, OSError, json.JSONDecodeError) as e:
        print(f"CANNOT: {e}", file=sys.stderr)
        return mc.CANNOT
    return mc.FAIL if summary["failed"] else mc.PASS


if __name__ == "__main__":
    sys.exit(main())
