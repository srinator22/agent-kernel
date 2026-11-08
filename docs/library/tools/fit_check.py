#!/usr/bin/env python3
"""Check clearances and collisions between parts at chosen animation states, at bounding-box level.

Purpose: a mechanism animated in a scene can pass through itself, jam against a neighbour, or be built at the
wrong scale, and none of that shows in a still. This reads the per-frame part bounds a Blender-side extract
already holds and flags collisions, thin gaps and scale errors before a render.
Inputs: EXTRACT.json (render-extract/1: objects[].dimensions, frames[].objects[name] with aabb_min, aabb_max
and optional samples) and --spec FIT.json: {"states": [frame numbers or "all"], "pairs": [["A", "B"], ...] or
"all", "clearance_m": 0.0005, "allowed_contacts": [["A", "B"]], "dimensions": {"A": {"expected_m": [x, y, z],
"tol": 0.02}}}. "all" pairs means every pair of parts present in the state. Minimal schema check only.
Method: per state and pair, the overlap volume of the two axis-aligned boxes and their box gap (0 when
touching or overlapping). When both parts carry `samples`, the smallest distance from either part's sample
points to the other part's box is a tighter (larger) gap estimate and replaces the box gap for the clearance
test. Dimensions are compared sorted (an axis order or orientation change does not matter) by relative error.
v1 limit: axis-aligned boxes plus vertex samples, not exact mesh distance. A pass means "no collision found
at box level", not proof of clearance; two interlocking concave parts will read as colliding and belong in
allowed_contacts. Sparse samples can overestimate a gap.
Outputs: findings on stdout, then `fit_check: PASS|FAIL ...` with the smallest gap seen; optional --json report
with every state and pair measured.
Exit codes: 0 pass, 1 findings, 2 could not run (bad spec or extract, a requested state not in the extract,
nothing to check).
Findings (kind): collision (box overlap, pair not in allowed_contacts), clearance (gap below clearance_m, pair
not in allowed_contacts), scale (dimensions differ from expected by more than tol), missing (a named part
absent from a state, from the object list, or without readable bounds).
Dependencies: Python 3.10+ standard library and render_common.py in the same folder.
Assumptions: units are metres; the extract's bounds are world-space bounds of the evaluated mesh.
Origin: new (no prior source).
"""

from __future__ import annotations

import argparse
import itertools
import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import render_common as rc  # noqa: E402

TOOL = "fit_check"
SCHEMA = "render-extract/1"
EPS = 1e-9  # metres: overlap thinner than this counts as touching (float noise)


def _vec3(v, what, nullable=False):
    if v is None and nullable:
        return None
    if not (isinstance(v, list) and len(v) == 3 and all(
            isinstance(x, (int, float)) and not isinstance(x, bool) and math.isfinite(x) for x in v)):
        raise rc.CannotRun(f"{what} must be three finite numbers{' or null' if nullable else ''}, got {v!r}")
    return [float(x) for x in v]


def load_extract(path):
    try:
        with open(path, encoding="utf-8") as f:
            doc = json.load(f)
    except (OSError, ValueError) as e:
        raise rc.CannotRun(f"cannot read extract {path}: {e}")
    if not isinstance(doc, dict) or doc.get("schema") != SCHEMA:
        raise rc.CannotRun(f"extract schema is {doc.get('schema') if isinstance(doc, dict) else None!r}, "
                           f"expected {SCHEMA}")
    if not isinstance(doc.get("objects"), list) or not isinstance(doc.get("frames"), list) or not doc["frames"]:
        raise rc.CannotRun("extract needs an 'objects' list and a non-empty 'frames' list")
    dims = {}
    for i, o in enumerate(doc["objects"]):
        if not isinstance(o, dict) or not isinstance(o.get("name"), str):
            raise rc.CannotRun(f"extract objects[{i}] needs a 'name'")
        dims[o["name"]] = _vec3(o.get("dimensions"), f"objects[{i}].dimensions", True)
    states = {}
    for i, fr in enumerate(doc["frames"]):
        if not isinstance(fr, dict) or isinstance(fr.get("frame"), bool) or not isinstance(fr.get("frame"), int) \
                or not isinstance(fr.get("objects"), dict):
            raise rc.CannotRun(f"extract frames[{i}] needs an integer 'frame' and an 'objects' map")
        parts = {}
        for name, o in fr["objects"].items():
            if not isinstance(o, dict):
                raise rc.CannotRun(f"frames[{i}].objects[{name!r}] must be an object")
            lo = _vec3(o.get("aabb_min"), f"frame {fr['frame']} {name} aabb_min", True)
            hi = _vec3(o.get("aabb_max"), f"frame {fr['frame']} {name} aabb_max", True)
            if lo is not None and hi is not None and any(a > b for a, b in zip(lo, hi)):
                raise rc.CannotRun(f"frame {fr['frame']} {name}: aabb_min is above aabb_max")
            samples = o.get("samples")
            if samples is not None:
                if not isinstance(samples, list):
                    raise rc.CannotRun(f"frame {fr['frame']} {name} samples must be a list")
                samples = [_vec3(s, f"frame {fr['frame']} {name} sample") for s in samples]
            parts[name] = (lo, hi, samples or None) if lo is not None and hi is not None else None
        states[fr["frame"]] = parts
    return dims, states


def load_spec(path, states):
    try:
        with open(path, encoding="utf-8") as f:
            sp = json.load(f)
    except (OSError, ValueError) as e:
        raise rc.CannotRun(f"cannot read spec {path}: {e}")
    if not isinstance(sp, dict):
        raise rc.CannotRun("spec must be a JSON object")
    want = sp.get("states", "all")
    want = [want] if want == "all" or isinstance(want, int) else want
    if not isinstance(want, list) or not want:
        raise rc.CannotRun("spec states must be 'all' or a list of frame numbers")
    frames = set()
    for s in want:
        if s == "all":
            frames.update(states)
        elif isinstance(s, int) and not isinstance(s, bool):
            frames.add(s)
        else:
            raise rc.CannotRun(f"spec states entry {s!r} must be a frame number or 'all'")
    absent = sorted(frames - set(states))
    if absent:
        raise rc.CannotRun(f"requested state frame(s) not in the extract: {rc.format_ranges(absent)}")
    pairs = sp.get("pairs", "all")
    if pairs != "all":
        if not isinstance(pairs, list) or any(not (isinstance(p, list) and len(p) == 2 and all(
                isinstance(n, str) for n in p) and p[0] != p[1]) for p in pairs):
            raise rc.CannotRun("spec pairs must be 'all' or a list of [name, name] with two different names")
    clear = sp.get("clearance_m", 0.0)
    if isinstance(clear, bool) or not isinstance(clear, (int, float)) or not math.isfinite(clear) or clear < 0:
        raise rc.CannotRun("spec clearance_m must be a number >= 0")
    allowed = sp.get("allowed_contacts", [])
    if not isinstance(allowed, list) or any(not (isinstance(p, list) and len(p) == 2) for p in allowed):
        raise rc.CannotRun("spec allowed_contacts must be a list of [name, name]")
    dims = sp.get("dimensions", {})
    if not isinstance(dims, dict):
        raise rc.CannotRun("spec dimensions must be an object")
    for name, d in dims.items():
        if not isinstance(d, dict):
            raise rc.CannotRun(f"spec dimensions[{name!r}] must be an object")
        _vec3(d.get("expected_m"), f"dimensions[{name!r}].expected_m")
        tol = d.get("tol", 0.02)
        if isinstance(tol, bool) or not isinstance(tol, (int, float)) or tol < 0 or not math.isfinite(tol):
            raise rc.CannotRun(f"dimensions[{name!r}].tol must be a number >= 0")
        if any(v <= 0 for v in d["expected_m"]):
            raise rc.CannotRun(f"dimensions[{name!r}].expected_m must be positive")
    if pairs != "all" and not pairs and not dims:
        raise rc.CannotRun("nothing to check: no pairs and no dimensions")
    return sorted(frames), pairs, float(clear), {frozenset(p) for p in allowed}, dims


def box_metrics(a, b):
    """(overlap volume, box gap) of two (lo, hi, samples) boxes."""
    ov, gap2 = 1.0, 0.0
    for i in range(3):
        o = min(a[1][i], b[1][i]) - max(a[0][i], b[0][i])
        if o > EPS:
            ov *= o
        else:
            ov = 0.0
            gap2 += max(0.0, -o) ** 2
    return ov, math.sqrt(gap2)


def point_box(p, box):
    return math.sqrt(sum(max(box[0][i] - p[i], 0.0, p[i] - box[1][i]) ** 2 for i in range(3)))


def sample_gap(a, b):
    """Smallest distance from either part's samples to the other part's box, or None without samples."""
    if not a[2] or not b[2]:
        return None
    return min(min(point_box(p, b) for p in a[2]), min(point_box(p, a) for p in b[2]))


def check(dim_actual, states, frames, pairs, clearance, allowed, dim_spec):
    findings, rows, min_gap = [], [], None

    def add(kind, msg):
        findings.append({"kind": kind, "message": msg})

    for name, d in sorted(dim_spec.items()):
        got, exp, tol = dim_actual.get(name, "absent"), sorted(d["expected_m"]), d.get("tol", 0.02)
        if got == "absent":
            add("missing", f"part {name!r} is not in the extract's object list (dimensions not checkable)")
        elif got is None:
            add("missing", f"part {name!r} has no readable dimensions")
        else:
            bad = [(g, e) for g, e in zip(sorted(abs(x) for x in got), exp) if abs(g - e) / e > tol]
            if bad:
                add("scale", f"part {name!r} dimensions {[round(x, 6) for x in got]} m differ from expected "
                             f"{d['expected_m']} m by more than {100 * tol:g}% (sorted compare; wrong scale or units?)")
    missing = {}
    collisions, thin = {}, {}
    for fr in frames:
        parts = states[fr]
        names = sorted(n for n, v in parts.items() if v is not None)
        todo = list(itertools.combinations(names, 2)) if pairs == "all" else [tuple(p) for p in pairs]
        for a, b in todo:
            lost = [n for n in (a, b) if parts.get(n) is None]
            if lost:
                for n in lost:
                    missing.setdefault(n, []).append(fr)
                continue
            ov, gap = box_metrics(parts[a], parts[b])
            sg = sample_gap(parts[a], parts[b])
            est = gap if sg is None else max(gap, sg)
            min_gap = est if min_gap is None else min(min_gap, est)
            rows.append({"frame": fr, "pair": [a, b], "overlap_volume_m3": ov, "box_gap_m": gap,
                         "sample_gap_m": sg})
            if frozenset((a, b)) in allowed:
                continue
            if ov > 0:
                collisions.setdefault((a, b), []).append((fr, ov))
            elif est < clearance:
                thin.setdefault((a, b), []).append((fr, est, gap))
    for n, fs in sorted(missing.items()):
        add("missing", f"part {n!r} is absent or has no readable bounds at state(s) {rc.format_ranges(fs)}")
    for (a, b), lst in sorted(collisions.items()):
        worst = max(lst, key=lambda p: p[1])
        add("collision", f"{a!r} and {b!r} overlap at state(s) {rc.format_ranges([f for f, _ in lst])} "
                         f"(largest box overlap {worst[1]:.6g} m3 at {worst[0]}); add the pair to "
                         "allowed_contacts if the contact is intended")
    for (a, b), lst in sorted(thin.items()):
        low = min(lst, key=lambda p: p[1])
        extra = "" if low[1] == low[2] else f" (box gap {low[2]:.6g} m)"
        add("clearance", f"{a!r} and {b!r} gap {low[1]:.6g} m{extra} is below clearance {clearance:.6g} m at "
                         f"state(s) {rc.format_ranges([f for f, _, _ in lst])} (smallest at {low[0]})")
    return findings, rows, min_gap


def build_parser():
    ap = argparse.ArgumentParser(
        prog=TOOL, description="Collision, clearance and scale check on a render-extract/1 file, at box level. "
        "v1 limit: axis-aligned boxes plus vertex samples, not exact mesh distance; a pass means no collision "
        "found at box level, not proof of clearance.")
    ap.add_argument("extract", metavar="EXTRACT.json", help="render-extract/1 document")
    ap.add_argument("--spec", required=True, metavar="FIT.json", help="states, pairs, clearance_m, allowed_contacts, dimensions")
    ap.add_argument("--json", metavar="OUT", help="write a machine report")
    return ap


def main(argv=None) -> int:
    a = build_parser().parse_args(argv)
    try:
        dim_actual, states = load_extract(a.extract)
        frames, pairs, clearance, allowed, dim_spec = load_spec(a.spec, states)
        findings, rows, min_gap = check(dim_actual, states, frames, pairs, clearance, allowed, dim_spec)
        gap_txt = "none measured" if min_gap is None else f"{min_gap:.6g} m"
        summary = f"(states {len(frames)}, pair checks {len(rows)}, smallest gap {gap_txt}, box level only)"
        return rc.finish(TOOL, findings, summary, a.json, {
            "extract": os.path.abspath(a.extract), "spec": os.path.abspath(a.spec), "states": frames,
            "clearance_m": clearance, "smallest_gap_m": min_gap, "measurements": rows})
    except rc.CannotRun as e:
        rc.error(TOOL, str(e))
        return rc.CANNOT


if __name__ == "__main__":
    sys.exit(main())
