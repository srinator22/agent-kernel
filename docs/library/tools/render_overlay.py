#!/usr/bin/env python3
"""Plan an on-screen label track from camera-projected anchors and check it before anything is burned in.

Purpose: callout labels follow a feature on a moving camera. The failures this prevents: a label that jumps
to the other side of its subject mid-life (including during its fades), runs off the frame or out of the safe
area, sits on top of another label, tracks an anchor that is missing or behind the camera, or an end title
that is gone before it can be read twice.
Inputs: --spec LABELS.json (fps, resolution, font_px, labels [id, text, subject, side left|right|above|below,
in, out, fade (frames, default 6), offset_px (default 120)], optional title [text, in, hold_s, font_px, position center|lower_third]) and
--extract EXTRACT.json (render-extract/1: per-frame `anchors` {subject: [u, v, depth]}, u right and v up in
0..1, depth in metres; minimal schema check only).
Method: per frame of a label's life (in..out inclusive, fades included) the box is anchor + offset on the
declared side (text width = chars x 0.55 x font_px, height = 1.2 x font_px; pixel y runs down). A box that
would leave the safe area is moved back inside it in the written track (position clamping only; the exit is
still a finding). The label then counts as crossed to the other side when the clamped box edge passes the
anchor. Opacity is a smoothstep ramp over `fade` frames at in and at out.
Outputs: --out TRACK.json (absolute path; written on pass and on findings, not on exit 2): {fps, resolution,
items [{id, text, subject, side, frames [{frame, x, y, w, h, opacity}]}] (x, y = top-left, y down), title
{text, in, out, hold_s, hold_frames, words, min_hold_s, x, y, w, h, font_px}} - the format render_encode
consumes. Frames where the anchor is unusable are left out of an item. Findings on stdout, then
`render_overlay: PASS|FAIL ...`; optional --json report.
Exit codes: 0 pass, 1 findings, 2 could not run (bad arguments, malformed spec or extract, relative --out).
Findings (kind): safe, side, anchor, overlap, title, range (label frames absent from the extract), extract
(extract fps or aspect differs from the spec).
Dependencies: Python 3.10+ standard library and render_common.py in the same folder.
Assumptions: text size is an estimate, not font metrics; boxes are axis aligned; overlap is judged on frames
where both labels have opacity above 0.02.
Origin: generic port of the label/overlay post script of a product film project (labels keep one side for
their whole life, including fades; end title readable twice).
"""

from __future__ import annotations

import argparse
import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import render_common as rc  # noqa: E402

TOOL = "render_overlay"
SCHEMA = "render-extract/1"
SIDES = ("left", "right", "above", "below")
TITLE_POSITIONS = ("center", "lower_third")
CHAR_W, LINE_H, VISIBLE = 0.55, 1.2, 0.02


def smooth(t):
    t = min(max(t, 0.0), 1.0)
    return t * t * (3.0 - 2.0 * t)


def opacity(f, a, b, fade):
    if fade <= 0:
        return 1.0
    return min(smooth((f - a) / fade), smooth((b - f) / fade))


def place(side, px, py, w, h, off):
    if side == "right":
        return px + off, py - h / 2
    if side == "left":
        return px - off - w, py - h / 2
    if side == "above":
        return px - w / 2, py - off - h
    return px - w / 2, py + off


def crossed(side, x, y, w, h, px, py):
    return {"left": x + w > px, "right": x < px, "above": y + h > py, "below": y < py}[side]


def clamp(x, y, w, h, safe):
    sx0, sy0, sx1, sy1 = safe
    cx = sx0 if w >= sx1 - sx0 else min(max(x, sx0), sx1 - w)
    cy = sy0 if h >= sy1 - sy0 else min(max(y, sy0), sy1 - h)
    return cx, cy


def inside(x, y, w, h, safe):
    sx0, sy0, sx1, sy1 = safe
    e = 1e-9
    return x >= sx0 - e and y >= sy0 - e and x + w <= sx1 + e and y + h <= sy1 + e


def box_overlap(a, b):
    return min(a[0] + a[2], b[0] + b[2]) - max(a[0], b[0]) > 1e-9 and \
        min(a[1] + a[3], b[1] + b[3]) - max(a[1], b[1]) > 1e-9


# ------------------------------------------------------------------------------------- validation
def _load(path, what):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError) as e:
        raise rc.CannotRun(f"cannot read {what} {path}: {e}")


def _pos(v, what, integer=False, minimum=0.0):
    ok = isinstance(v, int) if integer else isinstance(v, (int, float))
    if isinstance(v, bool) or not ok or not math.isfinite(v) or v < minimum:
        raise rc.CannotRun(f"{what} must be a {'whole ' if integer else ''}number >= {minimum}, got {v!r}")
    return v


def validate_spec(spec):
    if not isinstance(spec, dict):
        raise rc.CannotRun("spec must be a JSON object")
    fps = _pos(spec.get("fps"), "spec fps", minimum=1e-9)
    res = spec.get("resolution")
    if not (isinstance(res, list) and len(res) == 2):
        raise rc.CannotRun("spec resolution must be [width, height]")
    res = [_pos(v, "spec resolution entry", True, 1) for v in res]
    font = _pos(spec.get("font_px"), "spec font_px", minimum=1e-9)
    labels, ids = spec.get("labels"), set()
    if not isinstance(labels, list):
        raise rc.CannotRun("spec labels must be a list")
    if not labels and not spec.get("title"):
        raise rc.CannotRun("spec has no labels and no title: nothing to check")
    clean = []
    for i, lb in enumerate(labels):
        if not isinstance(lb, dict):
            raise rc.CannotRun(f"labels[{i}] must be an object")
        for k in ("id", "text", "subject"):
            if not isinstance(lb.get(k), str) or not lb[k].strip():
                raise rc.CannotRun(f"labels[{i}].{k} must be a non-empty string")
        if lb["id"] in ids:
            raise rc.CannotRun(f"duplicate label id {lb['id']!r}")
        ids.add(lb["id"])
        if lb.get("side") not in SIDES:
            raise rc.CannotRun(f"labels[{i}].side must be one of {', '.join(SIDES)}")
        a, b = _pos(lb.get("in"), f"labels[{i}].in", True), _pos(lb.get("out"), f"labels[{i}].out", True)
        if b <= a:
            raise rc.CannotRun(f"labels[{i}] out {b} must be after in {a}")
        clean.append({**lb, "in": a, "out": b, "fade": _pos(lb.get("fade", 6), f"labels[{i}].fade", True),
                      "offset_px": _pos(lb.get("offset_px", 120), f"labels[{i}].offset_px")})
    title = spec.get("title")
    if title is not None:
        if not isinstance(title, dict) or not isinstance(title.get("text"), str) or not title["text"].split():
            raise rc.CannotRun("title.text must be a non-empty string")
        title = {**title, "in": _pos(title.get("in"), "title.in", True),
                 "hold_s": _pos(title.get("hold_s"), "title.hold_s", minimum=1e-9),
                 "font_px": _pos(title.get("font_px", font), "title.font_px", minimum=1e-9),
                 "position": title.get("position", "center")}
        if title["position"] not in TITLE_POSITIONS:
            raise rc.CannotRun(f"title.position must be one of {', '.join(TITLE_POSITIONS)}")
    return fps, res, font, clean, title


def validate_extract(doc):
    if not isinstance(doc, dict) or doc.get("schema") != SCHEMA:
        raise rc.CannotRun(f"extract schema is {doc.get('schema') if isinstance(doc, dict) else None!r}, "
                           f"expected {SCHEMA}")
    frames = doc.get("frames")
    if not isinstance(frames, list) or not frames:
        raise rc.CannotRun("extract has no frames list (or it is empty)")
    index = {}
    for i, fr in enumerate(frames):
        if not isinstance(fr, dict) or isinstance(fr.get("frame"), bool) or not isinstance(fr.get("frame"), int) \
                or not isinstance(fr.get("anchors"), dict):
            raise rc.CannotRun(f"extract frames[{i}] needs an integer 'frame' and an 'anchors' map")
        for subj, a in fr["anchors"].items():
            if a is None:
                continue
            if not (isinstance(a, list) and len(a) == 3 and all(
                    isinstance(v, (int, float)) and not isinstance(v, bool) and math.isfinite(v) for v in a)):
                raise rc.CannotRun(f"extract frame {fr['frame']} anchor {subj!r} must be [u, v, depth] or null")
        index[fr["frame"]] = fr["anchors"]
    scene = doc.get("scene") if isinstance(doc.get("scene"), dict) else {}
    return index, scene


# --------------------------------------------------------------------------------------- the plan
def plan(fps, res, font, labels, title, index, scene, safe_frac, wps):
    W, H = res
    safe = (safe_frac * W, safe_frac * H, W - safe_frac * W, H - safe_frac * H)
    findings, items, boxes = [], [], {}

    def add(kind, msg):
        findings.append({"kind": kind, "message": msg})

    sfps = scene.get("fps")
    if isinstance(sfps, (int, float)) and abs(sfps - fps) > 1e-6:
        add("extract", f"extract fps {sfps} differs from spec fps {fps}")
    sres = scene.get("resolution")
    if isinstance(sres, list) and len(sres) == 2 and all(isinstance(v, (int, float)) and v > 0 for v in sres) \
            and abs(sres[0] / sres[1] - W / H) > 1e-3:
        add("extract", f"extract resolution {sres[0]}x{sres[1]} has a different aspect than the spec "
                       f"{W}x{H}: anchors would land on the wrong pixels")
    for lb in labels:
        w, h = len(lb["text"]) * CHAR_W * font, LINE_H * font
        no_data, no_anchor, behind, unsafe, wrong = [], [], [], [], []
        frames_out = []
        for f in range(lb["in"], lb["out"] + 1):
            anchors = index.get(f)
            if anchors is None:
                no_data.append(f)
                continue
            a = anchors.get(lb["subject"])
            if a is None:
                no_anchor.append(f)
                continue
            if a[2] <= 0:
                behind.append(f)
                continue
            px, py = a[0] * W, (1.0 - a[1]) * H
            x, y = place(lb["side"], px, py, w, h, lb["offset_px"])
            if not inside(x, y, w, h, safe):
                unsafe.append(f)
            x, y = clamp(x, y, w, h, safe)
            if crossed(lb["side"], x, y, w, h, px, py):
                wrong.append(f)
            op = opacity(f, lb["in"], lb["out"], lb["fade"])
            frames_out.append({"frame": f, "x": x, "y": y, "w": w, "h": h, "opacity": op})
            boxes.setdefault(f, []).append((lb["id"], op, (x, y, w, h)))
        who = f"label {lb['id']!r}"
        if no_data:
            add("range", f"{who}: frames {rc.format_ranges(no_data)} are not in the extract")
        if no_anchor:
            add("anchor", f"{who}: anchor {lb['subject']!r} missing at frames {rc.format_ranges(no_anchor)}")
        if behind:
            add("anchor", f"{who}: anchor {lb['subject']!r} is behind the camera (depth <= 0) at frames "
                          f"{rc.format_ranges(behind)}")
        if unsafe:
            add("safe", f"{who}: box leaves the safe area ({100 * safe_frac:g}% margin) at frames "
                        f"{rc.format_ranges(unsafe)}")
        if wrong:
            add("side", f"{who}: crosses to the other side of its subject (declared {lb['side']}) at frames "
                        f"{rc.format_ranges(wrong)}")
        items.append({"id": lb["id"], "text": lb["text"], "subject": lb["subject"], "side": lb["side"],
                      "frames": frames_out})
    pairs = {}
    for f, lst in boxes.items():
        vis = [t for t in lst if t[1] > VISIBLE]
        for i in range(len(vis)):
            for j in range(i + 1, len(vis)):
                if box_overlap(vis[i][2], vis[j][2]):
                    pairs.setdefault((vis[i][0], vis[j][0]), []).append(f)
    for (p, q), fs in sorted(pairs.items()):
        add("overlap", f"labels {p!r} and {q!r} overlap at frames {rc.format_ranges(fs)}")
    out_title = None
    if title:
        words = len(title["text"].split())
        need = 2.0 * words / wps
        tw, th = len(title["text"]) * CHAR_W * title["font_px"], LINE_H * title["font_px"]
        tx = (W - tw) / 2
        if title["position"] == "lower_third":  # centred on 5/6 of the height, kept inside the safe area
            ty = min(H * 5 / 6 - th / 2, safe[3] - th)
        else:
            ty = (H - th) / 2
        hold_frames = int(round(title["hold_s"] * fps))
        out_title = {"text": title["text"], "in": title["in"], "out": title["in"] + hold_frames,
                     "hold_s": title["hold_s"], "hold_frames": hold_frames, "words": words,
                     "min_hold_s": need, "x": tx, "y": ty, "w": tw, "h": th, "font_px": title["font_px"],
                     "position": title["position"]}
        covered = {}
        for f in range(title["in"], title["in"] + hold_frames + 1):
            for name, a in (index.get(f) or {}).items():
                if a[2] > 0 and tx <= a[0] * W <= tx + tw and ty <= (1.0 - a[1]) * H <= ty + th:
                    covered.setdefault(name, []).append(f)
        out_title["advisories"] = [f"title box covers anchor {n!r} at frames {rc.format_ranges(fs)} "
                                   f"(check contrast, or use position lower_third)" for n, fs in sorted(covered.items())]
        if title["hold_s"] < need:
            add("title", f"title hold {title['hold_s']:g}s is shorter than the {need:.2f}s needed to read "
                         f"{words} word(s) twice at {wps:g} words/s")
        if not inside(tx, ty, tw, th, safe):
            add("safe", f"title box ({tw:.0f}x{th:.0f}px) does not fit the safe area")
    return findings, items, out_title


def build_parser():
    ap = argparse.ArgumentParser(prog=TOOL, description="Plan and check a camera-following label track.")
    ap.add_argument("--spec", required=True, metavar="LABELS.json", help="labels, fps, resolution, title")
    ap.add_argument("--extract", required=True, metavar="EXTRACT.json", help="render-extract/1 with anchors")
    ap.add_argument("--out", required=True, metavar="TRACK.json", help="absolute path of the track file to write")
    ap.add_argument("--safe", type=float, default=0.05,
                    help="safe-area margin as a fraction of width and height "
                         "(default 0.05, default, standard margin values unverified)")
    ap.add_argument("--wps", type=float, default=3.0,
                    help="assumed reading speed in words per second (default 3.0, unverified)")
    ap.add_argument("--json", metavar="OUT", help="write a machine report")
    return ap


def main(argv=None) -> int:
    a = build_parser().parse_args(argv)
    try:
        rc.require_abs(a.out, "--out")
        if not 0 <= a.safe < 0.5 or a.wps <= 0:
            raise rc.CannotRun("--safe must be in [0, 0.5) and --wps must be positive")
        fps, res, font, labels, title = validate_spec(_load(a.spec, "spec"))
        index, scene = validate_extract(_load(a.extract, "extract"))
        findings, items, out_title = plan(fps, res, font, labels, title, index, scene, a.safe, a.wps)
        track = {"fps": fps, "resolution": res, "items": items}
        if out_title:
            track["title"] = out_title
        rc.write_json_atomic(a.out, track)
        for note in (out_title or {}).get("advisories", []):
            print(f"advisory: {note}")
        summary = f"(labels {len(items)}, title {'yes' if out_title else 'no'}, track {a.out})"
        return rc.finish(TOOL, findings, summary, a.json, {
            "spec": os.path.abspath(a.spec), "extract": os.path.abspath(a.extract), "track": a.out,
            "safe": a.safe, "wps": a.wps, "labels": len(items)})
    except rc.CannotRun as e:
        rc.error(TOOL, str(e))
        return rc.CANNOT


if __name__ == "__main__":
    sys.exit(main())
