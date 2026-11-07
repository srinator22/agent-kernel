#!/usr/bin/env python3
"""Mesh-to-CAD Inventor generator: rebuild a mesh_brep output as a parametric Inventor part.

Purpose: turn the exact plans in features.json into editable Inventor features (one sketch per
slab level with lines, arcs and circles, extruded and joined; full revolves), import every other
part from its per-part STEP, colour every body, hide the cosmetic surfaces, save the .ipt and
export a solids-only STEP. Each extrude distance becomes a named model parameter
(<body>_h<k>) so heights can be edited in Manage > Parameters.
Inputs: --build-dir (mesh_brep output: features.json, report.json, each/), --names (the same
names JSON, for colours of imported bodies), --template (an Inventor part template in mm).
Outputs: the .ipt at --ipt, and with --step a STEP AP214 exported from it.
Exit codes: 0 every part built, 1 some parts failed (listed), 2 could not run (no Windows COM,
no Inventor, missing inputs). `--dry-run` prints the plan without Inventor (any OS).
Dependencies: Python 3.10+ standard library for the plan; pywin32 and Autodesk Inventor (tested on
Inventor 2027) for the build.
Assumptions and Inventor API traps (found building a 900-feature part):
  - The API works in cm: every mm value is divided by 10.
  - Browser names are unique across sketches and features; reusing a sketch name for its extrude
    raises a bare COM error after the feature exists, and a retry makes duplicates. Names here get
    _s<k>, _e<k>, _rev and _profile suffixes.
  - A part from Documents.Add with no template is in cm; pass the mm template.
  - Sketch arcs run counter-clockwise: the arc's start and end may be swapped against the traversal.
  - Import one STEP per body: a multi-body STEP import loses names and solidity.
  - SilentOperation must be on before opening or importing, or a dialog blocks invisibly.
  - Hidden work surfaces are left out of the STEP export, so hiding the patches gives a solids-only
    STEP. Face colour imprints (split faces) are not reproduced: SplitFaces failed through the API.
Origin: ported from the Inventor generator of a one-off board conversion; generalised.
"""

from __future__ import annotations

import argparse
import glob
import json
import os
import re
import sys

PASS, FAIL, CANNOT = 0, 1, 2
MM = 0.1  # Inventor API length unit is cm
UV = {"z": (0, 1), "x": (1, 2), "y": (2, 0)}
AXI = {"x": 0, "y": 1, "z": 2}


# ---------------------------------------------------------------- pure plan (tested)
def safe_name(name: str) -> str:
    """A valid Inventor parameter name: letters, digits and underscores, not starting with a digit."""
    s = re.sub(r"[^A-Za-z0-9_]", "_", name)
    return s if s and not s[0].isdigit() else "B" + s


def group_slabs(rec) -> list[tuple[float, float, list]]:
    """Slabs sharing (z0, z1) go in one sketch and one extrude, ordered bottom up."""
    groups: dict = {}
    for s in rec["slabs"]:
        groups.setdefault((s["z0"], s["z1"]), []).append(s)
    return [(z0, z1, groups[(z0, z1)]) for z0, z1 in sorted(groups)]


def arc_end_order(start, end, target):
    """Inventor stores arcs counter-clockwise; return (traversal_start, traversal_end) of an arc
    whose stored ends are start and end, given the point the traversal should end at."""
    d = lambda a: (a[0] - target[0]) ** 2 + (a[1] - target[1]) ** 2  # noqa: E731
    return (end, start) if d(start) < d(end) else (start, end)


def plan(build_dir: str, names: dict | None = None) -> list[dict]:
    """Operations in build order: one per solid part (prism, revolve or import) and one per
    surface file. Every sketch and feature name is unique across the part."""
    names = names or {}
    default = names.get("default", {}).get("colour", "#9A9A9A")
    with open(os.path.join(build_dir, "report.json")) as fh:
        rows = json.load(fh)["bodies"]
    feats_path = os.path.join(build_dir, "features.json")
    feats = {}
    if os.path.exists(feats_path):
        with open(feats_path) as fh:
            for f in json.load(fh):
                feats[(f["id"], f["part"])] = f
    ops, used = [], set()

    def unique(n):
        base, k = n, 1
        while n in used:
            k += 1
            n = f"{base}_{k}"
        used.add(n)
        return n

    for r in rows:
        if r.get("part") is None:
            continue
        i, k = r["id"], r["part"]
        body = f"{i:03d}_{r['name']}" + (f"_p{k}" if k else "")
        colour = names.get(str(i), {}).get("colour", default)
        f = feats.get((i, k))
        if f is not None and f["kind"] == "prism":
            groups = group_slabs(f)
            ops.append(dict(op="prism", body=body, colour=f.get("colour", colour), axis=f["axis"],
                            groups=[dict(z0=z0, z1=z1, slabs=sl, sketch=unique(f"{body}_s{n}"), feature=unique(f"{body}_e{n}"),
                                         param=unique(f"{safe_name(body)}_h{n}")) for n, (z0, z1, sl) in enumerate(groups)]))
        elif f is not None and f["kind"] == "revolve":
            ops.append(dict(op="revolve", body=body, colour=f.get("colour", colour), axis=f["axis"], centre=f["centre"],
                            profile=f["profile"], sketch=unique(f"{body}_profile"), feature=unique(f"{body}_rev"),
                            plane=unique(f"WP_{body}_axis")))
        else:
            ops.append(dict(op="import", body=body, colour=colour, file=os.path.join(build_dir, "each", f"{i:03d}_p{k}.step")))
    for p in sorted(glob.glob(os.path.join(build_dir, "each", "*_surf.step"))):
        i = int(os.path.basename(p).split("_")[0])
        ops.append(dict(op="surface", body=os.path.basename(p)[:-5], colour=names.get(str(i), {}).get("colour", default), file=p))
    return ops


# ---------------------------------------------------------------- Inventor build (COM)
class Builder:
    def __init__(self, app, template: str):
        import win32com.client as W

        self.W = W
        self.C = W.constants
        self.app = app
        app.SilentOperation = True
        self.doc = W.CastTo(app.Documents.Add(self.C.kPartDocumentObject, template, True), "PartDocument")
        self.cd = self.doc.ComponentDefinition
        self.tg = app.TransientGeometry
        self.to = app.TransientObjects
        self.wp = {"x": self.cd.WorkPlanes.Item(1), "y": self.cd.WorkPlanes.Item(2), "z": self.cd.WorkPlanes.Item(3)}
        self.planes: dict = {}
        self.appearances: dict = {}

    def appearance(self, hexcol):
        if hexcol not in self.appearances:
            h = hexcol.lstrip("#")
            r, g, b = (int(h[k : k + 2], 16) for k in (0, 2, 4))
            a = self.doc.Assets.Add(self.C.kAssetTypeAppearance, "Generic", "m2c_" + h, "mesh2cad " + hexcol)
            for k in range(1, a.Count + 1):
                v = a.Item(k)
                if v.Name == "generic_diffuse":
                    self.W.CastTo(v, "ColorAssetValue").Value = self.to.CreateColor(r, g, b)
            self.appearances[hexcol] = a
        return self.appearances[hexcol]

    def plane(self, axis, off):
        key = (axis, round(off, 7))
        if key not in self.planes:
            if abs(off) < 1e-12:
                self.planes[key] = self.wp[axis]
            else:
                w = self.cd.WorkPlanes.AddByPlaneAndOffset(self.wp[axis], off * MM)
                w.Visible = False
                w.Name = f"WP_{axis}_{off:+.6f}".replace(".", "p").replace("+", "").replace("-", "m")
                self.planes[key] = w
        return self.planes[key]

    def draw_loop(self, sk, segs, to2):
        ents = []
        if segs[0][0] == "C":
            ents.append(sk.SketchCircles.AddByCenterRadius(to2(segs[0][1]), segs[0][2] * MM))
            return ents
        first = prev = None
        for k, s in enumerate(segs):
            start = prev if prev is not None else to2(s[1])
            last = k == len(segs) - 1
            if s[0] == "L":
                e = sk.SketchLines.AddByTwoPoints(start, first if last else to2(s[2]))
                sp_s, sp_e = e.StartSketchPoint, e.EndSketchPoint
            else:
                end_t = to2(s[3])
                e = sk.SketchArcs.AddByThreePoints(start, to2(s[2]), first if last else end_t)
                g0, g1 = e.StartSketchPoint.Geometry, e.EndSketchPoint.Geometry
                a, b = arc_end_order((g0.X, g0.Y), (g1.X, g1.Y), (end_t.X, end_t.Y))
                sp_s, sp_e = (e.StartSketchPoint, e.EndSketchPoint) if a == (g0.X, g0.Y) else (e.EndSketchPoint, e.StartSketchPoint)
            if first is None:
                first = sp_s
            prev = sp_e
            ents.append(e)
        return ents

    def extrude(self, profile, op, dist_mm, body=None):
        ed = self.cd.Features.ExtrudeFeatures.CreateExtrudeDefinition(profile, op)
        if body is not None:
            oc = self.to.CreateObjectCollection()
            oc.Add(body)
            ed.AffectedBodies = oc
        ed.SetDistanceExtent(f"{dist_mm:.10g} mm", self.C.kPositiveExtentDirection)
        return self.cd.Features.ExtrudeFeatures.Add(ed)

    def prism(self, op):
        ax = op["axis"]
        u, v = UV[ax]
        body = None
        for g in op["groups"]:
            sk = self.cd.Sketches.Add(self.plane(ax, g["z0"]))
            sk.Name = g["sketch"]

            def to2(p, sk=sk, z0=g["z0"]):
                q = [0.0, 0.0, 0.0]
                q[u], q[v], q[AXI[ax]] = p[0], p[1], z0
                return sk.ModelToSketchSpace(self.tg.CreatePoint(q[0] * MM, q[1] * MM, q[2] * MM))

            for s in g["slabs"]:
                self.draw_loop(sk, s["outer"], to2)
                for inner in s["inner"]:
                    self.draw_loop(sk, inner, to2)
            fe = self.extrude(sk.Profiles.AddForSolid(), self.C.kNewBodyOperation if body is None else self.C.kJoinOperation,
                              g["z1"] - g["z0"], body)
            fe.Name = g["feature"]
            self.W.CastTo(fe.Definition.Extent, "DistanceExtent").Distance.Name = g["param"]
            if body is None:
                body = fe.SurfaceBodies.Item(1)
        body.Name = op["body"]
        body.Appearance = self.appearance(op["colour"])

    def revolve(self, op):
        ax = op["axis"]
        u, v = UV[ax]
        k = AXI[ax]
        cu, cv = op["centre"]
        vname = "xyz"[v]
        wp = self.cd.WorkPlanes.AddByPlaneAndOffset(self.wp[vname], cv * MM)
        wp.Visible = False
        wp.Name = op["plane"]
        sk = self.cd.Sketches.Add(wp)
        sk.Name = op["sketch"]

        def to2(p):
            q = [0.0, 0.0, 0.0]
            q[u], q[v], q[k] = cu + p[0], cv, p[1]
            return sk.ModelToSketchSpace(self.tg.CreatePoint(q[0] * MM, q[1] * MM, q[2] * MM))

        ents = self.draw_loop(sk, op["profile"], to2)
        axis_line = None
        for s, e in zip(op["profile"], ents):
            if s[0] == "L" and abs(s[1][0]) < 1e-9 and abs(s[2][0]) < 1e-9:
                axis_line = e
        if axis_line is None:
            raise RuntimeError("revolve profile has no segment on the axis")
        rf = self.cd.Features.RevolveFeatures.AddFull(sk.Profiles.AddForSolid(), axis_line, self.C.kNewBodyOperation)
        rf.Name = op["feature"]
        b = rf.SurfaceBodies.Item(1)
        b.Name = op["body"]
        b.Appearance = self.appearance(op["colour"])

    def import_step(self, op, surface=False):
        icm = self.cd.ReferenceComponents.ImportedComponents
        b0, w0 = self.cd.SurfaceBodies.Count, self.cd.WorkSurfaces.Count
        icm.Add(icm.CreateDefinition(op["file"]))
        for n in range(b0 + 1, self.cd.SurfaceBodies.Count + 1):
            b = self.cd.SurfaceBodies.Item(n)
            b.Name = op["body"] if n == b0 + 1 else f"{op['body']}_{n - b0}"
            b.Appearance = self.appearance(op["colour"])
        for n in range(w0 + 1, self.cd.WorkSurfaces.Count + 1):
            w = self.cd.WorkSurfaces.Item(n)
            for m in range(1, w.SurfaceBodies.Count + 1):
                w.SurfaceBodies.Item(m).Appearance = self.appearance(op["colour"])
            w.Visible = False  # cosmetic patches stay out of the solids-only STEP export

    def export_step(self, path):
        tr = self.W.CastTo(self.app.ApplicationAddIns.ItemById("{90AF7F40-0C01-11D5-8E83-0010B541CD80}"), "TranslatorAddIn")
        ctx = self.to.CreateTranslationContext()
        ctx.Type = self.C.kFileBrowseIOMechanism
        opts = self.to.CreateNameValueMap()
        if tr.HasSaveCopyAsOptions(self.doc, ctx, opts):
            opts.SetValue("ApplicationProtocolType", 3)  # AP214: colours
        dm = self.to.CreateDataMedium()
        dm.FileName = path
        tr.SaveCopyAs(self.doc, ctx, opts, dm)


def build(app, ops, template, ipt, step=None, log=print):
    b = Builder(app, template)
    failed = []
    app.ScreenUpdating = False
    try:
        for n, op in enumerate(ops):
            try:
                if op["op"] == "prism":
                    b.prism(op)
                elif op["op"] == "revolve":
                    b.revolve(op)
                else:
                    b.import_step(op, surface=op["op"] == "surface")
            except Exception as e:  # one failed body must not stop the part
                failed.append((op["body"], str(e)[:200]))
            if n % 50 == 0:
                log(f"{n}/{len(ops)} operations")
    finally:
        app.ScreenUpdating = True
    b.doc.Update()
    b.doc.SaveAs(ipt, False)  # save before exporting: a failed export can take Inventor down
    if step:
        b.export_step(step)
    return failed


def default_template():
    hits = sorted(glob.glob(r"C:\Users\Public\Documents\Autodesk\Inventor *\Templates\*\Metric\Standard (mm).ipt"))
    return hits[-1] if hits else None


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--build-dir", required=True, help="mesh_brep output folder")
    ap.add_argument("--names", help="names JSON used for mesh_brep")
    ap.add_argument("--ipt", help="output part (.ipt)")
    ap.add_argument("--step", help="also export a solids-only STEP AP214 here")
    ap.add_argument("--template", default=None, help="Inventor part template in mm (default: newest Standard (mm).ipt)")
    ap.add_argument("--dry-run", action="store_true", help="print the plan, do not start Inventor")
    args = ap.parse_args(argv)
    try:
        names = None
        if args.names:
            with open(args.names) as fh:
                names = json.load(fh)
        ops = plan(args.build_dir, names)
    except (OSError, json.JSONDecodeError, KeyError) as e:
        print(f"CANNOT: {e}", file=sys.stderr)
        return CANNOT
    counts: dict = {}
    for o in ops:
        counts[o["op"]] = counts.get(o["op"], 0) + 1
    print("plan:", ", ".join(f"{k} {v}" for k, v in sorted(counts.items())))
    if args.dry_run:
        return PASS
    template = args.template or default_template()
    if not args.ipt or not template or not os.path.isfile(template):
        print("CANNOT: --ipt and an existing mm --template are required", file=sys.stderr)
        return CANNOT
    try:
        import win32com.client

        app = win32com.client.gencache.EnsureDispatch("Inventor.Application")
    except Exception as e:
        print(f"CANNOT: Inventor COM is not available: {e}", file=sys.stderr)
        return CANNOT
    failed = build(app, ops, template, os.path.abspath(args.ipt), os.path.abspath(args.step) if args.step else None)
    for body, err in failed:
        print(f"FAILED {body}: {err}")
    print(f"built {len(ops) - len(failed)} of {len(ops)} operations; saved {args.ipt}")
    return FAIL if failed else PASS


if __name__ == "__main__":
    sys.exit(main())
