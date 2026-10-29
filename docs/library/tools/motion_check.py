#!/usr/bin/env python3
"""Check camera and object motion in a render-extract/1 document: stops, acceleration spikes, overshoot, label flips.

Purpose: catch motion defects from numbers, before any frame is rendered: a camera that stalls where it should
glide, a one-frame acceleration spike, a camera path that swings past a waypoint, a label that jumps to the
other side of its subject. The camera of a finished film never fully stops except on a declared hold.
Usage: python motion_check.py EXTRACT.json [--holds 90-96,...] [--waypoints WP.json] [--stop-frac 0.02]
       [--spike 6.0] [--accel-floor 0.001] [--overshoot-tol 0.002] [--track TRACK.json] [--labels] [--json OUT]
Inputs: EXTRACT.json from blender_extract (at least 3 frames, a camera in every frame). --holds: frame ranges
  where a stop is declared. --waypoints: camera_path waypoints in the same world coordinates (metres).
  --track: the render_overlay track (items with per-frame box x, y, w, h in pixels, y down, and a side).
  --labels is accepted for compatibility; labels are checked whenever --track is given.
Checks (all speeds use the real frame spacing and the scene fps):
  stop      camera linear speed and angular speed of the forward vector are both below --stop-frac times
            their median over the shot (a zero median means the component never moves and counts
            as stopped), in an interval outside the holds (needs a moving camera).
  spike     acceleration magnitude from the second difference of position above --spike times the median of
            the 5 frames on each side (a local reference, so an eased move of an object otherwise at rest
            passes) and above --accel-floor (m/s^2): the camera and every tracked object in frames[].objects
            except EMPTY objects (never visible; the meshes they drive are tracked themselves).
  overshoot camera position between two waypoint frames leaves the waypoints' [min, max] per axis by more
            than --overshoot-tol metres.
  label     for each label and each frame of its life (fade frames included) the box centre must stay on the
            declared side of the subject's anchor (u times width, (1 - v) times height): left/right use x,
            above/below use y. Frames without an anchor are listed as a note; an item with none is a finding.
Outputs: one finding per line, then `motion_check: PASS ...` or `motion_check: FAIL n finding(s) ...`.
Exit codes: 0 pass, 1 findings, 2 could not run (bad document, fewer than 3 frames, camera missing in a frame).
Dependencies: Python 3.10+ standard library; blender_extract (validator) and camera_path (waypoints).
Assumptions: extract frames are strictly increasing in time; the camera forward vector is non-zero.
Origin: generic port of the on-screen motion dump and label side scoring of a product film project.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import statistics
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import blender_extract as bx  # noqa: E402
import camera_path as cp  # noqa: E402
import render_common as rc  # noqa: E402

TOOL = "motion_check"
SIDES = ("left", "right", "above", "below")
ZERO = 1e-9  # speeds at or below this count as zero (float noise)


def _sub(a, b):
    return [x - y for x, y in zip(a, b)]


def _norm(a):
    return math.sqrt(sum(x * x for x in a))


def _angle(a, b):
    na, nb = _norm(a), _norm(b)
    if na == 0 or nb == 0:
        raise rc.CannotRun("camera forward vector has zero length")
    c = sum(x * y for x, y in zip(a, b)) / (na * nb)
    return math.acos(max(-1.0, min(1.0, c)))


def accelerations(frames, points, fps) -> list:
    """[(frame, |a|)] at interior samples from velocities over the actual frame spacing."""
    out = []
    vels = []
    for (f0, p0), (f1, p1) in zip(zip(frames, points), zip(frames[1:], points[1:])):
        dt = (f1 - f0) / fps
        vels.append(([(b - a) / dt for a, b in zip(p0, p1)], dt))
    for i in range(1, len(vels)):
        (v0, dt0), (v1, dt1) = vels[i - 1], vels[i]
        out.append((frames[i], _norm(_sub(v1, v0)) / ((dt0 + dt1) / 2)))
    return out


SPIKE_WINDOW = 5  # neighbours on each side that set the local reference acceleration


def spike_frames(accs, factor, floor) -> tuple:
    """A spike is an acceleration above `factor` x the median of its neighbours (window of SPIKE_WINDOW
    each side, itself excluded) and above `floor`. A local reference, not the shot median: an object at
    rest for most of a shot has a median of 0, so any eased move would read as a spike."""
    vals = [a for _, a in accs]
    med = statistics.median(vals) if vals else 0.0
    bad = []
    for i, (f, a) in enumerate(accs):
        if a <= floor:
            continue
        neigh = vals[max(0, i - SPIKE_WINDOW):i] + vals[i + 1:i + 1 + SPIKE_WINDOW]
        ref = statistics.median(neigh) if neigh else 0.0
        if a > factor * max(ref, floor):
            bad.append((f, a))
    return bad, med


def camera_series(doc):
    frames = sorted(doc["frames"], key=lambda f: f["frame"])
    if len(frames) < 3:
        raise rc.CannotRun(f"need at least 3 frames in the extract, found {len(frames)}")
    fps = doc["scene"]["fps"]
    if not fps:
        raise rc.CannotRun("scene.fps is null in the extract; cannot compute speeds")
    for fr in frames:
        cam = fr["camera"]
        if cam is None or cam["location"] is None or cam["forward"] is None:
            raise rc.CannotRun(f"camera is unreadable (null) in frame {fr['frame']}")
    return frames, fps


def speed_series(frames, fps) -> tuple:
    nums = [f["frame"] for f in frames]
    locs = [f["camera"]["location"] for f in frames]
    fwds = [f["camera"]["forward"] for f in frames]
    lin, ang = [], []
    for i in range(len(frames) - 1):
        dt = (nums[i + 1] - nums[i]) / fps
        lin.append(_norm(_sub(locs[i + 1], locs[i])) / dt)
        ang.append(_angle(fwds[i], fwds[i + 1]) / dt)
    return nums, lin, ang


def in_holds(n, holds) -> bool:
    return any(a <= n <= b for a, b in holds)


def stop_findings(nums, lin, ang, holds, frac) -> tuple:
    med_l, med_a = statistics.median(lin), statistics.median(ang)
    notes, stopped = [], []
    if med_l == 0 and med_a == 0:
        return [], ["camera does not move at all: the stop check does not apply"], med_l, med_a
    for i in range(len(lin)):
        if in_holds(nums[i], holds) or in_holds(nums[i + 1], holds):
            continue
        if lin[i] <= max(frac * med_l, ZERO) and ang[i] <= max(frac * med_a, ZERO):
            stopped += [nums[i], nums[i + 1]]
    findings = []
    if stopped:
        findings.append({"kind": "stop", "message": (
            f"camera stops (linear and angular speed below {frac:g} x median) in frames "
            f"{rc.format_ranges(stopped)}; declare a hold with --holds or fix the path")})
    return findings, notes, med_l, med_a


def object_tracks(frames) -> dict:
    tracks = {}
    for fr in frames:
        for name, o in fr["objects"].items():
            if o.get("location") is not None:
                tracks.setdefault(name, []).append((fr["frame"], o["location"]))
    return tracks


def overshoot_findings(frames, wps, tol) -> list:
    findings = []
    for a, b in zip(wps, wps[1:]):
        for axis, name in enumerate("xyz"):
            lo, hi = sorted((a["pos"][axis], b["pos"][axis]))
            bad, worst = [], 0.0
            for fr in frames:
                if a["frame"] <= fr["frame"] <= b["frame"]:
                    v = fr["camera"]["location"][axis]
                    excess = max(lo - v, v - hi)
                    if excess > tol:
                        bad.append(fr["frame"])
                        worst = max(worst, excess)
            if bad:
                findings.append({"kind": "overshoot", "message": (
                    f"camera {name} leaves [{lo:.4g}, {hi:.4g}] between waypoints {a['frame']} and {b['frame']} "
                    f"in frames {rc.format_ranges(bad)} (worst {worst:.4g} m > tol {tol:g})")})
    return findings


def load_track(path) -> dict:
    try:
        with open(path, "r", encoding="utf-8") as fh:
            track = json.load(fh)
    except (OSError, ValueError) as e:
        raise rc.CannotRun(f"cannot read track {path}: {e}")
    res = track.get("resolution") if isinstance(track, dict) else None
    if not (isinstance(res, list) and len(res) == 2 and all(isinstance(x, (int, float)) and x > 0 for x in res)):
        raise rc.CannotRun(f"track {path}: 'resolution' must be [width, height]")
    if not isinstance(track.get("items"), list):
        raise rc.CannotRun(f"track {path}: 'items' must be a list")
    for it in track["items"]:
        if not isinstance(it, dict) or it.get("side") not in SIDES or not it.get("subject") \
                or not isinstance(it.get("frames"), list):
            raise rc.CannotRun(f"track {path}: each item needs subject, side ({'|'.join(SIDES)}) and frames")
        for fr in it["frames"]:
            try:
                [float(fr[k]) for k in ("frame", "x", "y", "w", "h")]
            except (KeyError, TypeError, ValueError):
                raise rc.CannotRun(f"track {path}: item {it.get('id')!r} frames need numeric frame, x, y, w, h")
    return track


def label_findings(frames, track) -> tuple:
    W, H = float(track["resolution"][0]), float(track["resolution"][1])
    anchors = {f["frame"]: f["anchors"] for f in frames}
    findings, notes = [], []
    for it in track["items"]:
        flips, unchecked, behind = [], [], []
        for fr in it["frames"]:
            n = int(fr["frame"])
            a = anchors.get(n, {}).get(it["subject"])
            if a is None:
                unchecked.append(n)
                continue
            if a[2] <= 0:
                behind.append(n)
                continue
            ax, ay = a[0] * W, (1.0 - a[1]) * H
            cx, cy = float(fr["x"]) + float(fr["w"]) / 2, float(fr["y"]) + float(fr["h"]) / 2
            ok = {"left": cx < ax, "right": cx > ax, "above": cy < ay, "below": cy > ay}[it["side"]]
            if not ok:
                flips.append(n)
        who = f"label {it.get('id')!r} ({it['subject']}, {it['side']})"
        if flips:
            findings.append({"kind": "label", "message": f"{who} is on the wrong side of its subject in frames "
                                                         f"{rc.format_ranges(flips)}"})
        if behind:
            findings.append({"kind": "label", "message": f"{who}: subject is behind the camera in frames "
                                                         f"{rc.format_ranges(behind)}"})
        if unchecked and len(unchecked) == len(it["frames"]):
            findings.append({"kind": "label", "message": f"{who}: no anchor for the subject in any of its frames; "
                                                         "cannot verify the side"})
        elif unchecked:
            notes.append(f"{who}: no anchor in frames {rc.format_ranges(unchecked)} (not checked)")
    return findings, notes


def make_parser() -> argparse.ArgumentParser:
    ap = argparse.ArgumentParser(
        prog="motion_check.py",
        description="Check camera and object motion in a render-extract/1 JSON: undeclared stops, acceleration "
                    "spikes, waypoint overshoot, label side flips.",
        epilog="Exit: 0 pass, 1 findings, 2 could not run.")
    ap.add_argument("extract", help="render-extract/1 JSON from blender_extract")
    ap.add_argument("--holds", default="", help="frame ranges where a stop is declared, e.g. 90-96,120-130")
    ap.add_argument("--waypoints", help="camera_path waypoints JSON; enables the overshoot check")
    ap.add_argument("--stop-frac", type=float, default=0.02, dest="stop_frac",
                    help="stop when speed < this x the median speed (default 0.02)")
    ap.add_argument("--spike", type=float, default=6.0, help="acceleration spike factor over the median (default 6)")
    ap.add_argument("--accel-floor", type=float, default=1e-3, dest="accel_floor",
                    help="ignore accelerations below this, m/s^2 (default 0.001)")
    ap.add_argument("--overshoot-tol", type=float, default=0.002, dest="overshoot_tol",
                    help="overshoot tolerance in metres (default 0.002)")
    ap.add_argument("--track", help="render_overlay track JSON; enables the label side check")
    ap.add_argument("--labels", action="store_true", help="accepted for compatibility (labels need --track)")
    ap.add_argument("--json", help="write the machine report here")
    return ap


def run(args) -> int:
    for name in ("stop_frac", "spike", "accel_floor", "overshoot_tol"):
        if not getattr(args, name) >= 0:
            raise rc.CannotRun(f"--{name.replace('_', '-')} must be >= 0")
    doc = bx.load_extract(args.extract)
    holds = rc.parse_ranges(args.holds, "--holds") if args.holds.strip() else []
    frames, fps = camera_series(doc)
    findings, notes = [], []
    nums, lin, ang = speed_series(frames, fps)
    f, n, med_l, med_a = stop_findings(nums, lin, ang, holds, args.stop_frac)
    findings += f
    notes += n
    bad, med = spike_frames(accelerations(nums, [fr["camera"]["location"] for fr in frames], fps),
                            args.spike, args.accel_floor)
    if bad:
        findings.append({"kind": "spike", "message": (
            f"camera acceleration spike (> {args.spike:g} x median {med:.4g} m/s^2) at frames "
            f"{rc.format_ranges([x for x, _ in bad])}, peak {max(a for _, a in bad):.4g} m/s^2")})
    # Empties are never seen; the visible meshes they drive are tracked by their own world positions.
    types = {o.get("name"): o.get("type") for o in doc.get("objects") or [] if isinstance(o, dict)}
    for name, pts in sorted(object_tracks(frames).items()):
        if types.get(name) == "EMPTY":
            notes.append(f"object {name} (EMPTY) not checked: it is not visible")
            continue
        if len(pts) < 3:
            notes.append(f"object {name}: fewer than 3 frames with a location (spike check skipped)")
            continue
        bad, med = spike_frames(accelerations([p[0] for p in pts], [p[1] for p in pts], fps),
                                args.spike, args.accel_floor)
        if bad:
            findings.append({"kind": "spike", "message": (
                f"object {name} acceleration spike (> {args.spike:g} x median {med:.4g} m/s^2) at frames "
                f"{rc.format_ranges([x for x, _ in bad])}, peak {max(a for _, a in bad):.4g} m/s^2")})
    if args.waypoints:
        findings += overshoot_findings(frames, cp.load_waypoints(args.waypoints), args.overshoot_tol)
    if args.track:
        f, n = label_findings(frames, load_track(args.track))
        findings += f
        notes += n
    else:
        notes.append("labels: no track given")
    for line in notes:
        print(f"note: {line}")
    summary = f"{len(frames)} frames, fps {fps:g}, median camera speed {med_l:.4g} m/s, {med_a:.4g} rad/s"
    return rc.finish(TOOL, findings, summary, args.json, {
        "extract": args.extract, "frames": len(frames), "fps": fps, "median_linear_speed": med_l,
        "median_angular_speed": med_a, "notes": notes, "holds": [list(h) for h in holds]})


def main(argv=None) -> int:
    args = make_parser().parse_args(argv)
    try:
        return run(args)
    except rc.CannotRun as e:
        rc.error(TOOL, str(e))
        return rc.CANNOT


if __name__ == "__main__":
    sys.exit(main())
