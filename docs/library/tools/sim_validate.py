#!/usr/bin/env python3
"""Validate a liquid simulation's volume series against what the shot says it should pour.

Purpose: catch the failures a liquid sim hides until the final render: silent under-emission (the inflow
emits a few percent of the intended volume and nothing complains), a leak through colliders, volume gain,
an emission rate that does not match the commanded flow, a particle count that falls while pouring, and a
render that used a different cache than the validated one.
Inputs: --series SERIES.json, either a render-extract/1 document (frames[].volumes of the object named by
--object, required then) or a plain list [{"frame": n, "volume": m3, "particles": optional int}];
--target-volume (m3) intended to be poured, --pour-start and --pour-end (frames); optional --tol,
--loss-tol, --drain-from, --flow-m3s with --fps, --cache DIR with --expect-hash.
Outputs: one finding per line on stdout, then `sim_validate: PASS|FAIL ...`; optional --json report.
Exit codes: 0 pass, 1 findings, 2 could not run (bad arguments, unreadable or malformed series, no sample at
the pour start or end frame, unreadable or empty cache folder).
Findings (kind): under-emission (volume at pour end < (1 - tol) x target; the emitted percentage is printed),
over-emission (volume at pour end > (1 + tol) x target), flow (growth per second over the pour differs from
--flow-m3s by more than tol), leak (after the pour and before --drain-from the volume falls more than
loss-tol x the pour-end volume below it), gain (after the pour the volume rises more than loss-tol x the
pour-end volume above it), particles (count falls during the pour), series (missing or duplicate frames),
cache (hash differs from --expect-hash).
Cache hash: sha256 over lines "<sha256 of file>  <relative path>" for every file under DIR, sorted by
relative path (forward slashes), files read in streaming blocks; so a renamed, edited, added or removed
file changes it.
Dependencies: Python 3.10+ standard library and render_common.py in the same folder.
Assumptions: volumes are cubic metres of the liquid object; the series is one sample per frame; the schema
check for render-extract/1 is minimal (schema string, frames list, per-frame frame number and volumes map).
Origin: new (the prior project tuned an inflow factor by eye after silent under-emission).
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import render_common as rc  # noqa: E402

TOOL = "sim_validate"
SCHEMA = "render-extract/1"


def _num(v, what):
    if isinstance(v, bool) or not isinstance(v, (int, float)) or not math.isfinite(v):
        raise rc.CannotRun(f"{what} must be a finite number, got {v!r}")
    return float(v)


def _int(v, what):
    if isinstance(v, bool) or not isinstance(v, int) or v < 0:
        raise rc.CannotRun(f"{what} must be a non-negative integer, got {v!r}")
    return v


def load_series(path, obj):
    """-> list of (frame, volume or None, particles or None) in file order; None volume = no sample."""
    try:
        with open(path, encoding="utf-8") as f:
            doc = json.load(f)
    except (OSError, ValueError) as e:
        raise rc.CannotRun(f"cannot read series {path}: {e}")
    rows = []
    if isinstance(doc, dict):
        if doc.get("schema") != SCHEMA:
            raise rc.CannotRun(f"series {path} is an object but its schema is {doc.get('schema')!r}, "
                               f"expected {SCHEMA}")
        if not obj:
            raise rc.CannotRun("--object is required when --series is a render-extract/1 document")
        frames = doc.get("frames")
        if not isinstance(frames, list) or not frames:
            raise rc.CannotRun("extract has no frames list (or it is empty)")
        seen_obj = False
        for i, fr in enumerate(frames):
            if not isinstance(fr, dict) or "frame" not in fr or not isinstance(fr.get("volumes"), dict):
                raise rc.CannotRun(f"extract frames[{i}] lacks 'frame' or a 'volumes' map")
            vol = fr["volumes"].get(obj)
            seen_obj = seen_obj or obj in fr["volumes"]
            rows.append((_int(fr["frame"], f"frames[{i}].frame"),
                         None if vol is None else _num(vol, f"volume of {obj} at frame {fr['frame']}"), None))
        if not seen_obj:
            raise rc.CannotRun(f"object {obj!r} has no volume in any extract frame (was it named with "
                               "--volume-objects when extracting?)")
    elif isinstance(doc, list):
        for i, e in enumerate(doc):
            if not isinstance(e, dict) or "frame" not in e or "volume" not in e:
                raise rc.CannotRun(f"series[{i}] must be an object with 'frame' and 'volume'")
            part = e.get("particles")
            rows.append((_int(e["frame"], f"series[{i}].frame"), _num(e["volume"], f"series[{i}].volume"),
                         None if part is None else _int(part, f"series[{i}].particles")))
    else:
        raise rc.CannotRun("series must be a render-extract/1 object or a list of samples")
    if not rows:
        raise rc.CannotRun("the series is empty")
    for fr, vol, _ in rows:
        if vol is not None and vol < 0:
            raise rc.CannotRun(f"negative volume {vol} at frame {fr}")
    return rows


def hash_cache(directory):
    """(sha256 hex, file count, byte count) of every file under the folder."""
    if not os.path.isdir(directory):
        raise rc.CannotRun(f"--cache {directory} is not a folder")
    rels = []
    for root, _, files in os.walk(directory):
        for name in files:
            rels.append(os.path.relpath(os.path.join(root, name), directory).replace(os.sep, "/"))
    if not rels:
        raise rc.CannotRun(f"--cache {directory} holds no files")
    h, total = hashlib.sha256(), 0
    for rel in sorted(rels):
        path = os.path.join(directory, *rel.split("/"))
        h.update(f"{rc.sha256_file(path)}  {rel}\n".encode("utf-8"))
        total += os.path.getsize(path)
    return h.hexdigest(), len(rels), total


def first_frames(fs, n=6):
    fs = sorted(fs)
    return rc.format_ranges(fs[:n]) + (f" (+{len(fs) - n} more)" if len(fs) > n else "")


def validate_args(a):
    if not (a.target_volume > 0 and math.isfinite(a.target_volume)):
        raise rc.CannotRun("--target-volume must be a positive number of cubic metres")
    if a.pour_start < 0 or a.pour_end <= a.pour_start:
        raise rc.CannotRun("--pour-start must be >= 0 and before --pour-end")
    if not 0 <= a.tol < 1 or a.loss_tol < 0:
        raise rc.CannotRun("--tol must be in [0, 1) and --loss-tol >= 0")
    if a.drain_from is not None and a.drain_from <= a.pour_end:
        raise rc.CannotRun("--drain-from must be after --pour-end")
    if (a.flow_m3s is None) != (a.fps is None):
        raise rc.CannotRun("--flow-m3s and --fps must be given together")
    if a.flow_m3s is not None and (a.flow_m3s <= 0 or a.fps <= 0):
        raise rc.CannotRun("--flow-m3s and --fps must be positive")
    if a.expect_hash is not None:
        if not a.cache:
            raise rc.CannotRun("--expect-hash needs --cache")
        if not re.fullmatch(r"[0-9a-fA-F]{64}", a.expect_hash):
            raise rc.CannotRun("--expect-hash must be 64 hexadecimal characters")


def check(a, rows):
    findings, numbers = [], {}

    def add(kind, msg):
        findings.append({"kind": kind, "message": msg})

    by_frame, dup = {}, set()
    for fr, vol, part in rows:
        if fr in by_frame:
            dup.add(fr)
        else:
            by_frame[fr] = (vol, part)
    if dup:
        add("series", f"duplicate frame(s) in the series (first sample used): {first_frames(dup)}")
    lo, hi = min(by_frame), max(by_frame)
    missing = [f for f in range(lo, hi + 1) if by_frame.get(f, (None,))[0] is None]
    if missing:
        add("series", f"{len(missing)} frame(s) without a volume sample between {lo} and {hi}: "
                      f"{first_frames(missing)}")
    v_start, v_end = by_frame.get(a.pour_start, (None,))[0], by_frame.get(a.pour_end, (None,))[0]
    if v_start is None or v_end is None:
        raise rc.CannotRun(f"no volume sample at --pour-start {a.pour_start} or --pour-end {a.pour_end}")
    pct = 100.0 * v_end / a.target_volume
    numbers.update({"volume_at_pour_start": v_start, "volume_at_pour_end": v_end, "emitted_percent": pct})
    if v_end < (1 - a.tol) * a.target_volume:
        add("under-emission", f"SILENT UNDER-EMISSION: volume at pour end (frame {a.pour_end}) is {v_end:.6g} m3, "
                              f"only {pct:.1f}% of the target {a.target_volume:.6g} m3 (allowed >= "
                              f"{100 * (1 - a.tol):.1f}%)")
    elif v_end > (1 + a.tol) * a.target_volume:
        add("over-emission", f"volume at pour end (frame {a.pour_end}) is {v_end:.6g} m3, {pct:.1f}% of the "
                             f"target {a.target_volume:.6g} m3 (allowed <= {100 * (1 + a.tol):.1f}%)")
    if a.flow_m3s is not None:
        rate = (v_end - v_start) / ((a.pour_end - a.pour_start) / a.fps)
        numbers["measured_flow_m3s"] = rate
        if abs(rate - a.flow_m3s) > a.tol * a.flow_m3s:
            add("flow", f"emission over frames {a.pour_start}-{a.pour_end} is {rate:.6g} m3/s, commanded "
                        f"{a.flow_m3s:.6g} m3/s ({100 * rate / a.flow_m3s:.1f}%, tolerance {100 * a.tol:.0f}%)")
    after = sorted((f, by_frame[f][0]) for f in by_frame if f > a.pour_end and by_frame[f][0] is not None)
    drop_lim, gain_lim = v_end * (1 - a.loss_tol), v_end * (1 + a.loss_tol)
    leaks = [(f, v) for f, v in after if v < drop_lim and (a.drain_from is None or f < a.drain_from)]
    gains = [(f, v) for f, v in after if v > gain_lim]
    if leaks:
        f, v = min(leaks, key=lambda p: p[1])
        add("leak", f"volume falls below {100 * (1 - a.loss_tol):.0f}% of the pour-end volume at "
                    f"{len(leaks)} frame(s) from frame {leaks[0][0]} (lowest {v:.6g} m3 at frame {f}, "
                    f"{100 * v / v_end:.1f}% of {v_end:.6g} m3): liquid leaks through a collider")
    if gains:
        f, v = max(gains, key=lambda p: p[1])
        add("gain", f"volume rises above {100 * (1 + a.loss_tol):.0f}% of the pour-end volume at "
                    f"{len(gains)} frame(s) from frame {gains[0][0]} (highest {v:.6g} m3 at frame {f}, "
                    f"{100 * v / v_end:.1f}%): volume gain is a solver artefact")
    pts = [(f, by_frame[f][1]) for f in range(a.pour_start, a.pour_end + 1)
           if f in by_frame and by_frame[f][1] is not None]
    drops = [(f, p, q) for (f0, p), (f, q) in zip(pts, pts[1:]) if q < p]
    if drops:
        f, p, q = drops[0]
        add("particles", f"particle count falls during the pour at {len(drops)} step(s), first at frame {f} "
                         f"({p} -> {q})")
    return findings, numbers


def build_parser():
    ap = argparse.ArgumentParser(prog=TOOL, description="Check a liquid sim's volume series against the intended pour.")
    ap.add_argument("--series", required=True, metavar="SERIES.json",
                    help="render-extract/1 document (needs --object) or a list of {frame, volume, particles?}")
    ap.add_argument("--object", help="object whose frames[].volumes entry is used (extract input)")
    ap.add_argument("--target-volume", type=float, required=True, metavar="V_M3", help="intended poured volume, m3")
    ap.add_argument("--pour-start", type=int, required=True, metavar="F1")
    ap.add_argument("--pour-end", type=int, required=True, metavar="F2")
    ap.add_argument("--tol", type=float, default=0.1, help="fraction; target and flow tolerance (default 0.1)")
    ap.add_argument("--loss-tol", type=float, default=0.05,
                    help="fraction of the pour-end volume lost or gained after the pour (default 0.05)")
    ap.add_argument("--drain-from", type=int, metavar="F", help="from this frame a falling volume is allowed")
    ap.add_argument("--flow-m3s", type=float, metavar="Q", help="commanded flow in m3/s (needs --fps)")
    ap.add_argument("--fps", type=float, help="frames per second (with --flow-m3s)")
    ap.add_argument("--cache", metavar="DIR", help="sim cache folder to hash")
    ap.add_argument("--expect-hash", metavar="SHA", help="validated cache hash; a mismatch is a finding")
    ap.add_argument("--json", metavar="OUT", help="write a machine report")
    return ap


def main(argv=None) -> int:
    a = build_parser().parse_args(argv)
    try:
        validate_args(a)
        rows = load_series(a.series, a.object)
        findings, numbers = check(a, rows)
        data = {"series": os.path.abspath(a.series), "target_volume_m3": a.target_volume, "tol": a.tol,
                "loss_tol": a.loss_tol, "pour": [a.pour_start, a.pour_end], "samples": len(rows), **numbers}
        if a.cache:
            digest, count, size = hash_cache(a.cache)
            print(f"cache: {count} file(s), {size} byte(s), sha256 {digest}")
            data.update({"cache": os.path.abspath(a.cache), "cache_sha256": digest, "cache_files": count})
            if a.expect_hash and digest != a.expect_hash.lower():
                findings.append({"kind": "cache", "message": f"cache hash {digest} differs from the expected "
                                 f"{a.expect_hash.lower()}: the render must use the validated cache"})
        summary = (f"(emitted {numbers['emitted_percent']:.1f}% of target, volume at pour end "
                   f"{numbers['volume_at_pour_end']:.6g} m3, {len(rows)} sample(s))")
        return rc.finish(TOOL, findings, summary, a.json, data)
    except rc.CannotRun as e:
        rc.error(TOOL, str(e))
        return rc.CANNOT


if __name__ == "__main__":
    sys.exit(main())
