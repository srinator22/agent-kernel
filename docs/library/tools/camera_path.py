#!/usr/bin/env python3
"""Camera path through waypoints with a monotone spline (no overshoot), plus an overshoot and stop check.

Purpose: a Catmull-Rom path through camera waypoints overshoots between knots and can swing a camera through
a close-up or past a waypoint it should only ease through. A monotone piecewise cubic Hermite spline
(Fritsch-Carlson / PCHIP) never leaves the data range between two knots, and flat segments stay exactly flat
(a hold). This tool samples such a path per frame and checks a path for overshoot and undeclared stops.
Usage: python camera_path.py WAYPOINTS.json --fps F [--out ABS.json] [--check] [--spline pchip|catmull]
                             [--json OUT]
Inputs: WAYPOINTS.json, a list (or {"waypoints": [...]}) of
  {"frame": n, "pos": [x,y,z], "target": [x,y,z], "lens": mm, "hold": true (optional)}.
  Frames are integers and strictly increasing; lens is optional but all-or-none. A waypoint with "hold": true
  declares that the segment to its neighbour (either side) is a deliberate stop.
Outputs: --out writes {"fps", "spline", "first_frame", "last_frame", "samples": [{"frame", "t", "pos",
  "target", "lens"}]} with one sample per integer frame; t is seconds since the first waypoint. Outside the
  waypoint range the value is held. --check lists overshoot (a sample outside the [min, max] of its two
  bounding waypoints, per channel, by more than 1e-9) and zero-motion segments (same pos and target at both
  ends) that are not marked hold. --spline catmull samples the comparison spline, which overshoots.
Exit codes: 0 pass, 1 check findings, 2 could not run (bad waypoints, unsorted or duplicate frames).
Dependencies: Python 3.10+ standard library.
Assumptions: each channel (x, y, z of pos and target, lens) is interpolated independently against frame.
Origin: generic port of the camera path builder of a product film project (monotone spline after a
Catmull-Rom path overshot into a close-up).
"""

from __future__ import annotations

import argparse
import bisect
import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import render_common as rc  # noqa: E402

TOOL = "camera_path"
EPS = 1e-9


def _check_knots(xs, ys):
    if len(xs) != len(ys) or len(xs) < 2:
        raise rc.CannotRun("a spline needs at least two knots and equal-length xs, ys")
    if any(b <= a for a, b in zip(xs, xs[1:])):
        raise rc.CannotRun("knot positions must be strictly increasing")


def _hermite(xs, ys, ms):
    def at(x):
        if x <= xs[0]:
            return ys[0]
        if x >= xs[-1]:
            return ys[-1]
        i = bisect.bisect_right(xs, x) - 1
        h = xs[i + 1] - xs[i]
        s = (x - xs[i]) / h
        s2, s3 = s * s, s * s * s
        return ((2 * s3 - 3 * s2 + 1) * ys[i] + (s3 - 2 * s2 + s) * h * ms[i]
                + (-2 * s3 + 3 * s2) * ys[i + 1] + (s3 - s2) * h * ms[i + 1])
    return at


def _end_slope(h0, h1, d0, d1):
    """Three-point end slope, limited to keep the curve monotone (the SciPy PCHIP end rule)."""
    m = ((2 * h0 + h1) * d0 - h0 * d1) / (h0 + h1)
    if m * d0 <= 0:
        return 0.0
    if d0 * d1 <= 0 and abs(m) > 3 * abs(d0):
        return 3 * d0
    return m


def pchip(xs, ys):
    """Monotone piecewise cubic Hermite interpolant (Fritsch-Carlson): never overshoots the data between
    knots; a flat segment stays flat. Returns a callable; values outside the knots are held."""
    _check_knots(xs, ys)
    n = len(xs)
    h = [xs[i + 1] - xs[i] for i in range(n - 1)]
    d = [(ys[i + 1] - ys[i]) / h[i] for i in range(n - 1)]
    if n == 2:
        return _hermite(xs, ys, [d[0], d[0]])
    ms = [0.0] * n
    for i in range(1, n - 1):
        if d[i - 1] * d[i] > 0:
            w1, w2 = 2 * h[i] + h[i - 1], h[i] + 2 * h[i - 1]
            ms[i] = (w1 + w2) / (w1 / d[i - 1] + w2 / d[i])
    ms[0] = _end_slope(h[0], h[1], d[0], d[1])
    ms[-1] = _end_slope(h[-1], h[-2], d[-1], d[-2])
    return _hermite(xs, ys, ms)


def catmull_rom(xs, ys):
    """Cardinal (finite-difference) cubic Hermite spline through the knots, for comparison. It OVERSHOOTS
    the data between knots next to a flat or sharply changing segment; do not use it for camera paths."""
    _check_knots(xs, ys)
    n = len(xs)
    ms = [(ys[1] - ys[0]) / (xs[1] - xs[0])]
    ms += [(ys[i + 1] - ys[i - 1]) / (xs[i + 1] - xs[i - 1]) for i in range(1, n - 1)]
    ms.append((ys[-1] - ys[-2]) / (xs[-1] - xs[-2]))
    return _hermite(xs, ys, ms)


# -------------------------------------------------------------------------------------- waypoints
def _vec3(v, where):
    if not (isinstance(v, list) and len(v) == 3 and all(
            isinstance(x, (int, float)) and not isinstance(x, bool) and math.isfinite(x) for x in v)):
        raise rc.CannotRun(f"{where}: expected a list of 3 finite numbers")
    return [float(x) for x in v]


def parse_waypoints(data) -> list:
    """Validate a waypoint list; returns normalised dicts. Raises CannotRun."""
    if isinstance(data, dict) and "waypoints" in data:
        data = data["waypoints"]
    if not isinstance(data, list) or len(data) < 2:
        raise rc.CannotRun("waypoints: expected a list of at least two waypoints")
    out = []
    for i, w in enumerate(data):
        if not isinstance(w, dict):
            raise rc.CannotRun(f"waypoint {i}: expected an object")
        fr = w.get("frame")
        if isinstance(fr, bool) or not isinstance(fr, int):
            raise rc.CannotRun(f"waypoint {i}: 'frame' must be an integer")
        lens = w.get("lens")
        if lens is not None and not (isinstance(lens, (int, float)) and not isinstance(lens, bool)
                                     and math.isfinite(lens) and lens > 0):
            raise rc.CannotRun(f"waypoint {i}: 'lens' must be a positive number")
        out.append({"frame": fr, "pos": _vec3(w.get("pos"), f"waypoint {i} pos"),
                    "target": _vec3(w.get("target"), f"waypoint {i} target"),
                    "lens": None if lens is None else float(lens), "hold": bool(w.get("hold", False))})
    frames = [w["frame"] for w in out]
    dup = sorted({f for f in frames if frames.count(f) > 1})
    if dup:
        raise rc.CannotRun(f"waypoints: duplicate frame(s) {dup}")
    if frames != sorted(frames):
        raise rc.CannotRun("waypoints: frames must be in increasing order (unsorted input)")
    if len({w["lens"] is None for w in out}) > 1:
        raise rc.CannotRun("waypoints: 'lens' must be given on every waypoint or on none")
    return out


def load_waypoints(path) -> list:
    try:
        with open(path, "r", encoding="utf-8") as fh:
            data = json.load(fh)
    except (OSError, ValueError) as e:
        raise rc.CannotRun(f"cannot read waypoints {path}: {e}")
    return parse_waypoints(data)


def _channels(w):
    return list(w["pos"]) + list(w["target"]) + ([w["lens"]] if w["lens"] is not None else [])


CHANNEL_NAMES = ["pos.x", "pos.y", "pos.z", "target.x", "target.y", "target.z", "lens"]


def sample_path(waypoints, fps, spline="pchip") -> list:
    """One dict per integer frame from the first to the last waypoint frame."""
    if not fps or fps <= 0:
        raise rc.CannotRun("--fps must be > 0")
    wps = parse_waypoints(waypoints)
    make = {"pchip": pchip, "catmull": catmull_rom}.get(spline)
    if make is None:
        raise rc.CannotRun(f"unknown spline {spline!r}")
    xs = [float(w["frame"]) for w in wps]
    cols = list(zip(*[_channels(w) for w in wps]))
    fns = [make(xs, list(c)) for c in cols]
    first, last = wps[0]["frame"], wps[-1]["frame"]
    out = []
    for f in range(first, last + 1):
        v = [fn(float(f)) for fn in fns]
        out.append({"frame": f, "t": (f - first) / fps, "pos": v[0:3], "target": v[3:6],
                    "lens": v[6] if len(v) > 6 else None})
    return out


def check_path(waypoints, samples) -> list:
    """Findings (dicts kind, message) for overshoot and undeclared zero-motion segments."""
    wps = parse_waypoints(waypoints)
    by_frame = {s["frame"]: s for s in samples}
    findings = []
    for a, b in zip(wps, wps[1:]):
        ca, cb = _channels(a), _channels(b)
        for k, (va, vb) in enumerate(zip(ca, cb)):
            lo, hi = min(va, vb), max(va, vb)
            bad, worst = [], 0.0
            for f in range(a["frame"], b["frame"] + 1):
                s = by_frame.get(f)
                if s is None:
                    continue
                v = (s["pos"] + s["target"] + [s["lens"]])[k]
                excess = max(lo - v, v - hi)
                if excess > EPS:
                    bad.append(f)
                    worst = max(worst, excess)
            if bad:
                findings.append({"kind": "overshoot", "message": (
                    f"{CHANNEL_NAMES[k]} leaves [{lo:g}, {hi:g}] between waypoints {a['frame']} and "
                    f"{b['frame']} in frames {rc.format_ranges(bad)} (worst excess {worst:.6g})")})
        if a["pos"] == b["pos"] and a["target"] == b["target"] and not (a["hold"] or b["hold"]):
            findings.append({"kind": "stop", "message": (
                f"zero motion between waypoints {a['frame']} and {b['frame']} (pos and target identical) "
                "and neither is marked \"hold\": true")})
    return findings


def make_parser() -> argparse.ArgumentParser:
    ap = argparse.ArgumentParser(
        prog="camera_path.py",
        description="Sample a camera path through waypoints with a monotone spline (PCHIP) that never "
                    "overshoots, and check a path for overshoot and undeclared stops.",
        epilog="Exit: 0 pass, 1 check findings, 2 could not run.")
    ap.add_argument("waypoints", help="waypoints JSON: [{frame, pos, target, lens, hold}]")
    ap.add_argument("--fps", type=float, required=True, help="frames per second (for the t field)")
    ap.add_argument("--out", help="absolute path of the sampled path JSON to write")
    ap.add_argument("--check", action="store_true", help="report overshoot and undeclared stops (exit 1)")
    ap.add_argument("--spline", default="pchip", choices=["pchip", "catmull"],
                    help="pchip (default, monotone) or catmull (comparison, overshoots)")
    ap.add_argument("--json", help="write the machine report here")
    return ap


def main(argv=None) -> int:
    args = make_parser().parse_args(argv)
    try:
        if args.out:
            rc.require_abs(args.out, "--out")
        wps = load_waypoints(args.waypoints)
        samples = sample_path(wps, args.fps, args.spline)
        if args.out:
            rc.write_json_atomic(args.out, {"fps": args.fps, "spline": args.spline,
                                            "first_frame": samples[0]["frame"], "last_frame": samples[-1]["frame"],
                                            "samples": samples})
        findings = check_path(wps, samples) if args.check else []
        summary = f"{len(wps)} waypoints, {len(samples)} samples, spline={args.spline}" + (
            ", checked" if args.check else "")
        return rc.finish(TOOL, findings, summary, args.json,
                         {"waypoints": args.waypoints, "fps": args.fps, "spline": args.spline,
                          "samples": len(samples), "checked": args.check})
    except rc.CannotRun as e:
        rc.error(TOOL, str(e))
        return rc.CANNOT


if __name__ == "__main__":
    sys.exit(main())
