#!/usr/bin/env python3
"""Dump camera, objects, lights, materials and render settings of a .blend file to render-extract/1 JSON.

Purpose: the checkers (motion_check, scene_lint, fit_check, ...) read plain JSON and need no Blender; this is
the Blender-side producer. It also holds the pure helpers they share: the frame-spec parser, the document
skeleton, the validator `validate_extract(doc)`, `load_extract(path)` and the atomic writer.
Usage (inside Blender, normally through blender_run):
  blender -b scene.blend --python-exit-code 1 -P blender_extract.py -- --out ABS.json
          [--frames 1-96|1,24,48] [--step 1] [--objects A,B] [--samples-every 0] [--volume-objects Liquid]
Inputs: an open .blend file; arguments after the bare "--".
Outputs: one JSON file (schema "render-extract/1"; units metres, seconds; screen anchors u right, v up, depth
in metres in front of the camera). A value that cannot be read is null, never invented. Per frame it records
the camera (location, forward vector, lens, focus distance, f-stop), tracked objects (location, world-space
bounds of the evaluated mesh, optional vertex samples), anchors and screen_boxes ([umin, vmin, umax, vmax] of
each tracked mesh's world bounds on screen; null when a corner is behind the camera). Tracked objects are those with a `label`
custom property, those that are animated, and those named in --objects. An anchor is the world-space bounds
centre of a mesh (the origin for other types) projected with world_to_camera_view. `--volume-objects` names
closed meshes whose evaluated volume (m^3, unsigned) is recorded per frame; a name that is not a mesh object
exits 2. --samples-every N keeps every Nth vertex of each tracked mesh (0 = none, the default). The focus
distance is the camera data value, or the distance along the view axis to the focus object when one is set.
Exit codes: 0 written, 2 could not run (bad arguments, not inside Blender, unreadable data). An uncaught
Python error exits 1 through --python-exit-code. Outside Blender only --help works.
Dependencies: Python 3.10+ standard library, plus bpy, bmesh, mathutils, bpy_extras inside Blender.
Assumptions: frame_set is called per frame; the file is left on its original frame. The version is recorded as
X.Y.Z (bpy.app.version_string carries an " LTS" suffix). Helpers import without bpy.
Origin: new.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import render_common as rc  # noqa: E402

TOOL = "blender_extract"
SCHEMA = "render-extract/1"
CYCLES_KEYS = ["device", "samples", "use_adaptive_sampling", "adaptive_threshold", "use_denoising",
               "denoiser", "denoising_input_passes", "denoising_prefilter", "seed", "use_animated_seed",
               "filter_width", "sample_clamp_direct", "sample_clamp_indirect", "max_bounces",
               "transmission_bounces", "denoising_quality", "denoising_use_gpu"]
SCENE_KEYS = ["name", "fps", "frame_start", "frame_end", "resolution", "resolution_percentage", "engine",
              "unit_system", "scale_length", "view_transform", "look", "exposure", "gamma", "motion_blur",
              "film_transparent"]
LIGHT_KEYS = ["name", "type", "energy", "color", "size", "spread", "visible_camera", "visible_glossy",
              "visible_transmission"]
MATERIAL_KEYS = ["name", "images", "transmission", "sheen", "roughness"]
OBJECT_KEYS = ["name", "type", "hide_render", "hide_viewport", "animated", "dimensions", "label"]
CAMERA_KEYS = ["location", "forward", "lens", "focus_distance", "fstop"]
FRAME_OBJECT_KEYS = ["location", "aabb_min", "aabb_max", "samples"]
MESH_TYPES = ("MESH", "CURVE", "SURFACE", "META", "FONT")


# ----------------------------------------------------------------------------------- pure helpers
def parse_frames(spec, frame_start: int, frame_end: int, step: int = 1) -> list:
    """Frame numbers from a spec like '1-96' or '1,24,48' (None = the scene range), sorted, unique, then
    every `step`-th one."""
    if step < 1:
        raise rc.CannotRun(f"--step must be >= 1, got {step}")
    if spec is None or str(spec).strip() == "":
        frames = list(range(frame_start, frame_end + 1))
    else:
        frames = sorted(set(rc.parse_frame_list(str(spec), "--frames")))
    if not frames:
        raise rc.CannotRun("no frames selected")
    return frames[::step]


def skeleton(blender_version=None) -> dict:
    """A complete render-extract/1 document with every value null or empty."""
    return {
        "schema": SCHEMA, "blender": blender_version,
        "scene": dict({k: None for k in SCENE_KEYS}, cycles={k: None for k in CYCLES_KEYS}),
        "lights": [], "materials": [], "objects": [], "frames": [],
    }


def _is_num(v) -> bool:
    return isinstance(v, (int, float)) and not isinstance(v, bool) and math.isfinite(v)


def _vec_problem(v, n, where):
    if v is None:
        return None
    if not (isinstance(v, list) and len(v) == n and all(_is_num(x) for x in v)):
        return f"{where}: expected a list of {n} finite numbers or null"
    return None


def _need_keys(d, keys, where, problems):
    if not isinstance(d, dict):
        problems.append(f"{where}: expected an object")
        return False
    missing = [k for k in keys if k not in d]
    if missing:
        problems.append(f"{where}: missing key(s) {', '.join(missing)}")
    return True


def screen_box(lo, hi, project):
    """[umin, vmin, umax, vmax] of the 8 corners of a world box through `project` (point -> (u, v, depth)),
    or None when any corner is at or behind the camera (the screen extent is then undefined)."""
    pts = [project([x, y, z]) for x in (lo[0], hi[0]) for y in (lo[1], hi[1]) for z in (lo[2], hi[2])]
    if any(p[2] <= 0 for p in pts):
        return None
    us, vs = [p[0] for p in pts], [p[1] for p in pts]
    return [min(us), min(vs), max(us), max(vs)]


def validate_extract(doc) -> list:
    """Problems found in a render-extract/1 document (empty list = valid). Never raises."""
    problems: list = []
    if not isinstance(doc, dict):
        return ["document is not a JSON object"]
    if doc.get("schema") != SCHEMA:
        return [f"schema is {doc.get('schema')!r}, expected {SCHEMA!r}"]
    for k in ("blender", "scene", "lights", "materials", "objects", "frames"):
        if k not in doc:
            problems.append(f"missing top-level key {k}")
    if problems:
        return problems
    if _need_keys(doc["scene"], SCENE_KEYS + ["cycles"], "scene", problems):
        sc = doc["scene"]
        _need_keys(sc.get("cycles"), CYCLES_KEYS, "scene.cycles", problems)
        res = sc.get("resolution")
        if res is not None and not (isinstance(res, list) and len(res) == 2 and all(_is_num(x) for x in res)):
            problems.append("scene.resolution: expected [width, height] or null")
        fps = sc.get("fps")
        if fps is not None and not (_is_num(fps) and fps > 0):
            problems.append("scene.fps: expected a positive number or null")
    for key, keys in (("lights", LIGHT_KEYS), ("materials", MATERIAL_KEYS), ("objects", OBJECT_KEYS)):
        if not isinstance(doc[key], list):
            problems.append(f"{key}: expected a list")
            continue
        for i, item in enumerate(doc[key]):
            _need_keys(item, keys, f"{key}[{i}]", problems)
    if not isinstance(doc["frames"], list):
        problems.append("frames: expected a list")
        return problems
    seen = set()
    for i, fr in enumerate(doc["frames"]):
        where = f"frames[{i}]"
        if not _need_keys(fr, ["frame", "camera", "objects", "anchors", "volumes"], where, problems):
            continue
        n = fr.get("frame")
        if not isinstance(n, int) or isinstance(n, bool):
            problems.append(f"{where}.frame: expected an integer")
        elif n in seen:
            problems.append(f"{where}.frame: duplicate frame {n}")
        else:
            seen.add(n)
        cam = fr.get("camera")
        if cam is not None and _need_keys(cam, CAMERA_KEYS, f"{where}.camera", problems):
            for k in ("location", "forward"):
                p = _vec_problem(cam.get(k), 3, f"{where}.camera.{k}")
                if p:
                    problems.append(p)
        for k in ("objects", "anchors", "volumes"):
            if not isinstance(fr.get(k), dict):
                problems.append(f"{where}.{k}: expected an object")
        if isinstance(fr.get("objects"), dict):
            for name, o in fr["objects"].items():
                if _need_keys(o, FRAME_OBJECT_KEYS, f"{where}.objects[{name}]", problems):
                    for k in ("location", "aabb_min", "aabb_max"):
                        p = _vec_problem(o.get(k), 3, f"{where}.objects[{name}].{k}")
                        if p:
                            problems.append(p)
        if isinstance(fr.get("anchors"), dict):
            for name, a in fr["anchors"].items():
                p = _vec_problem(a, 3, f"{where}.anchors[{name}]")
                if p:
                    problems.append(p)
        boxes = fr.get("screen_boxes")  # optional: on-screen extent of each tracked mesh
        if boxes is not None:
            if not isinstance(boxes, dict):
                problems.append(f"{where}.screen_boxes: expected an object")
            else:
                for name, b in boxes.items():
                    if b is None:
                        continue
                    p = _vec_problem(b, 4, f"{where}.screen_boxes[{name}]")
                    if p:
                        problems.append(p)
                    elif b[0] > b[2] or b[1] > b[3]:
                        problems.append(f"{where}.screen_boxes[{name}]: min greater than max")
        if len(problems) > 50:
            return problems
    return problems


def load_extract(path) -> dict:
    """Read and validate an extract file. Raises render_common.CannotRun listing the first problems."""
    try:
        with open(path, "r", encoding="utf-8") as fh:
            doc = json.load(fh)
    except (OSError, ValueError) as e:
        raise rc.CannotRun(f"cannot read extract {path}: {e}")
    problems = validate_extract(doc)
    if problems:
        raise rc.CannotRun(f"{path} is not a valid {SCHEMA} document: " + "; ".join(problems[:5])
                           + (f" (+{len(problems) - 5} more)" if len(problems) > 5 else ""))
    return doc


def write_extract(path, doc) -> None:
    rc.require_abs(path, "--out")
    problems = validate_extract(doc)
    if problems:
        raise rc.CannotRun("refusing to write an invalid document: " + "; ".join(problems[:5]))
    rc.write_json_atomic(path, doc)


# -------------------------------------------------------------------------------- Blender side
def _get(obj, name, default=None):
    try:
        v = getattr(obj, name)
    except Exception:
        return default
    return default if v is None else v


def _num(v):
    try:
        f = float(v)
    except (TypeError, ValueError):
        return None
    return f if math.isfinite(f) else None


def _vec(v):
    try:
        out = [float(x) for x in v]
    except (TypeError, ValueError):
        return None
    return out if all(math.isfinite(x) for x in out) else None


def _scalar(v):
    """JSON-safe scalar: bool/int/float/str as is, an enum set as a sorted list, anything else null."""
    if isinstance(v, (bool, int, str)):
        return v
    if isinstance(v, float):
        return v if math.isfinite(v) else None
    if isinstance(v, (set, frozenset)):
        return sorted(v)
    return None


def read_scene(sc, bpy) -> dict:
    r = sc.render
    out = skeleton()["scene"]
    fps_base = _num(_get(r, "fps_base", 1.0)) or 1.0
    out.update(
        name=sc.name, fps=(_num(r.fps) / fps_base) if _num(r.fps) else None, frame_start=sc.frame_start,
        frame_end=sc.frame_end, resolution=[r.resolution_x, r.resolution_y],
        resolution_percentage=r.resolution_percentage, engine=_scalar(r.engine),
        unit_system=_scalar(_get(sc.unit_settings, "system")), scale_length=_num(_get(sc.unit_settings, "scale_length")),
        view_transform=_scalar(_get(sc.view_settings, "view_transform")), look=_scalar(_get(sc.view_settings, "look")),
        exposure=_num(_get(sc.view_settings, "exposure")), gamma=_num(_get(sc.view_settings, "gamma")),
        motion_blur=_scalar(_get(r, "use_motion_blur")), film_transparent=_scalar(_get(r, "film_transparent")))
    cy = _get(sc, "cycles")
    if cy is not None:
        out["cycles"] = {k: _scalar(_get(cy, k)) if not isinstance(_get(cy, k), float) else _num(_get(cy, k))
                         for k in CYCLES_KEYS}
    return out


def read_lights(sc) -> list:
    out = []
    for o in sc.objects:
        if o.type != "LIGHT":
            continue
        d = o.data
        out.append({"name": o.name, "type": _scalar(_get(d, "type")), "energy": _num(_get(d, "energy")),
                    "color": _vec(_get(d, "color")),
                    "size": _num(_get(d, "size", _get(d, "shadow_soft_size"))), "spread": _num(_get(d, "spread")),
                    "visible_camera": _scalar(_get(o, "visible_camera")),
                    "visible_glossy": _scalar(_get(o, "visible_glossy")),
                    "visible_transmission": _scalar(_get(o, "visible_transmission"))})
    return out


def _input_value(node, names):
    for n in names:
        sock = node.inputs.get(n)
        if sock is not None:
            if getattr(sock, "is_linked", False):
                return None
            return _num(_get(sock, "default_value"))
    return None


def read_materials(bpy) -> list:
    out = []
    for m in bpy.data.materials:
        images, vals = [], {"transmission": None, "sheen": None, "roughness": None}
        tree = _get(m, "node_tree")
        for node in (tree.nodes if tree else []):
            img = _get(node, "image") if node.type == "TEX_IMAGE" else None
            if img is not None:
                raw = _get(img, "filepath", "")
                absp = bpy.path.abspath(raw) if raw else ""
                images.append({"path": raw or None, "abs": absp or None,
                               "exists": os.path.exists(absp) if absp else None})
            if node.type == "BSDF_PRINCIPLED":
                vals["transmission"] = _input_value(node, ["Transmission Weight", "Transmission"])
                vals["sheen"] = _input_value(node, ["Sheen Weight", "Sheen"])
                vals["roughness"] = _input_value(node, ["Roughness"])
        out.append({"name": m.name, "images": images, **vals})
    return out


def _label(o):
    try:
        v = o.get("label")
    except Exception:
        return None
    return None if v is None else str(v)


def _is_animated(o) -> bool:
    import blender_compat as compat
    for block in (o, _get(o, "data")):
        ad = _get(block, "animation_data") if block is not None else None
        if ad is not None and (ad.action is not None and compat.action_fcurves(ad.action) or
                               len(_get(ad, "drivers", [])) > 0):
            return True
    return False


def read_objects(sc) -> list:
    return [{"name": o.name, "type": o.type, "hide_render": bool(o.hide_render),
             "hide_viewport": bool(o.hide_viewport), "animated": _is_animated(o),
             "dimensions": _vec(o.dimensions), "label": _label(o)} for o in sc.objects]


def _mesh_world_points(oe):
    me = oe.to_mesh()
    try:
        mw = oe.matrix_world
        return [_vec(mw @ v.co) for v in me.vertices]
    finally:
        oe.to_mesh_clear()


def _mesh_volume(oe, bmesh) -> float:
    me = oe.to_mesh()
    try:
        bm = bmesh.new()
        try:
            bm.from_mesh(me)
            bmesh.ops.transform(bm, matrix=oe.matrix_world, verts=bm.verts)
            return float(bm.calc_volume(signed=False))
        finally:
            bm.free()
    finally:
        oe.to_mesh_clear()


def frame_record(sc, dg, bpy, bmesh, world_to_camera_view, tracked, volume_names, samples_every) -> dict:
    rec = {"camera": None, "objects": {}, "anchors": {}, "volumes": {}, "screen_boxes": {}}
    cam = sc.camera
    if cam is not None:
        mw = cam.matrix_world
        loc = mw.translation
        fwd = mw.to_quaternion() @ type(loc)((0.0, 0.0, -1.0))
        dof = _get(cam.data, "dof")
        focus, fo = _num(_get(dof, "focus_distance")), _get(dof, "focus_object")
        if fo is not None:
            focus = _num((fo.matrix_world.translation - loc).dot(fwd))
        rec["camera"] = {"location": _vec(loc), "forward": _vec(fwd), "lens": _num(_get(cam.data, "lens")),
                         "focus_distance": focus, "fstop": _num(_get(dof, "aperture_fstop"))}
    for o in tracked:
        oe = o.evaluated_get(dg)
        loc = _vec(oe.matrix_world.translation)
        item = {"location": loc, "aabb_min": None, "aabb_max": None, "samples": []}
        centre = loc
        if o.type in MESH_TYPES:
            pts = [p for p in _mesh_world_points(oe) if p is not None]
            if pts:
                lo = [min(p[i] for p in pts) for i in range(3)]
                hi = [max(p[i] for p in pts) for i in range(3)]
                item.update(aabb_min=lo, aabb_max=hi)
                centre = [(lo[i] + hi[i]) / 2 for i in range(3)]
                if samples_every > 0:
                    item["samples"] = pts[::samples_every]
        rec["objects"][o.name] = item
        if cam is not None and centre is not None:
            from mathutils import Vector
            uv = world_to_camera_view(sc, cam, Vector(centre))
            rec["anchors"][o.name] = _vec(uv)
            if item["aabb_min"] is not None:
                rec["screen_boxes"][o.name] = screen_box(
                    item["aabb_min"], item["aabb_max"],
                    lambda q: tuple(world_to_camera_view(sc, cam, Vector(q))))
    for name in volume_names:
        rec["volumes"][name] = _num(_mesh_volume(bpy.data.objects[name].evaluated_get(dg), bmesh))
    return rec


def run_extract(args) -> dict:
    import bmesh
    import bpy
    from bpy_extras.object_utils import world_to_camera_view
    sc = bpy.context.scene
    names = [n for n in (args.objects or "").split(",") if n.strip()]
    vol_names = [n for n in (args.volume_objects or "").split(",") if n.strip()]
    missing = [n for n in names + vol_names if n not in sc.objects]
    if missing:
        raise rc.CannotRun("object(s) not in the scene: " + ", ".join(missing))
    if [n for n in vol_names if sc.objects[n].type != "MESH"]:
        raise rc.CannotRun("--volume-objects must name mesh objects: " + ", ".join(vol_names))
    frames = parse_frames(args.frames, sc.frame_start, sc.frame_end, args.step)
    doc = skeleton(".".join(str(n) for n in bpy.app.version))  # version_string adds " LTS"
    doc["scene"] = read_scene(sc, bpy)
    doc["lights"], doc["materials"], doc["objects"] = read_lights(sc), read_materials(bpy), read_objects(sc)
    by_name = {o["name"]: o for o in doc["objects"]}
    tracked = [o for o in sc.objects if o.name in names or (o.type not in ("CAMERA", "LIGHT") and (
        by_name[o.name]["animated"] or by_name[o.name]["label"] is not None))]
    original = sc.frame_current
    try:
        for f in frames:
            sc.frame_set(f)
            dg = bpy.context.evaluated_depsgraph_get()
            rec = frame_record(sc, dg, bpy, bmesh, world_to_camera_view, tracked, vol_names, args.samples_every)
            rec["frame"] = f
            doc["frames"].append(rec)
    finally:
        sc.frame_set(original)
    return doc


def make_parser() -> argparse.ArgumentParser:
    ap = argparse.ArgumentParser(
        prog="blender_extract.py",
        description="Run inside Blender (blender -b FILE.blend --python-exit-code 1 -P blender_extract.py -- ARGS, "
                    "normally through blender_run): write a render-extract/1 JSON of camera, lights, materials, "
                    "objects and settings per frame.")
    ap.add_argument("--out", required=True, help="absolute path of the JSON file to write")
    ap.add_argument("--frames", help="frames to record: 1-96 or 1,24,48 (default: the scene range)")
    ap.add_argument("--step", type=int, default=1, help="keep every Nth selected frame (default 1)")
    ap.add_argument("--objects", help="comma list of extra object names to track")
    ap.add_argument("--samples-every", type=int, default=0, dest="samples_every",
                    help="keep every Nth vertex of tracked meshes as samples (default 0 = none)")
    ap.add_argument("--volume-objects", dest="volume_objects",
                    help="comma list of closed mesh objects whose evaluated volume is recorded per frame")
    return ap


def script_args(argv) -> list:
    argv = list(sys.argv if argv is None else argv)
    return argv[argv.index("--") + 1:] if "--" in argv else argv[1:]


def main(argv=None) -> int:
    args = make_parser().parse_args(script_args(argv))
    try:
        rc.require_abs(args.out, "--out")
        if args.samples_every < 0:
            raise rc.CannotRun("--samples-every must be >= 0")
        try:
            import bpy  # noqa: F401
        except ImportError:
            raise rc.CannotRun("bpy is not available: run this script inside Blender (see blender_run)")
        doc = run_extract(args)
        write_extract(args.out, doc)
    except rc.CannotRun as e:
        rc.error(TOOL, str(e))
        return rc.CANNOT
    print(f"{TOOL}: PASS wrote {args.out} frames={len(doc['frames'])} objects={len(doc['objects'])}")
    return rc.PASS


if __name__ == "__main__":
    sys.exit(main())
