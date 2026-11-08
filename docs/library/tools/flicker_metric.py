#!/usr/bin/env python3
"""Measure temporal instability (flicker, residual sampling noise) in near-still stretches of a frame sequence.

Purpose: put a number on "does this shot shimmer" so seed, sample-count and denoiser changes can be compared
(A/B) instead of judged by eye, and so a near-still stretch (a hold, a slow drift) can be gated.
Inputs: DIR of PNG frames (--pattern, --first, --last); optional --window A-B stretches (default: the whole
range), --grid CxR or --region x,y,w,h (full-resolution pixels; default: the whole frame), --reference
REF_DIR (a high-sample render of the same frames) and --compare DIR_B (the same metric for a second render).
Metric: per region, T(t) = mean over the region's pixels of |L(t) - (L(t-1) + L(t+1)) / 2| for the interior
frames of a window, L = Rec. 709 luma in [0, 1]. This second difference cancels a linear brightness drift
and very slow motion; independent per-frame noise of standard deviation s gives T about 1.2 x s. It is NOT a
motion-compensated (warping-error) metric: real motion inside a window reads as instability, so use windows
that are near-still (for example the holds that motion_check reports). Reported per region and window: mean T,
p95 T (nearest rank) and the 5 worst frames with values.
Outputs: findings and a summary on stdout (`flicker_metric: PASS|FAIL ...`), optional --json report.
Exit codes: 0 pass, 1 a region's mean T in a window is over --threshold (for --compare, only for DIR A),
2 could not run (bad arguments, missing or unreadable frame, a window with fewer than 3 frames).
Dependencies: Python 3.10+ standard library and render_common.py in the same folder; optional numpy and
Pillow fast paths (RENDER_TOOLS_PURE=1 forces the stdlib path; results agree).
Assumptions: all frames share one resolution; a mean over a long window can dilute a single spike, so read
the worst-frame list as well as the mean.
Origin: new (metric choice from the research: temporal second difference; warping-error metrics need
optical flow and are out of scope for v1).
"""

from __future__ import annotations

import argparse
import math
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import render_common as rc  # noqa: E402

TOOL = "flicker_metric"
DEFAULT_THRESHOLD = 0.004
WORST_N = 5


# ------------------------------------------------------------------------------------ region maths
def _grid(lum):
    np = rc._numpy()
    return np.array(lum, dtype=np.float64) if np is not None else lum


def _t_value(prev, cur, nxt, r):
    x0, y0, x1, y1 = r
    np = rc._numpy()
    if np is not None:
        c = cur[y0:y1, x0:x1]
        return float(np.mean(np.abs(c - (prev[y0:y1, x0:x1] + nxt[y0:y1, x0:x1]) / 2.0)))
    total, n = 0.0, 0
    for y in range(y0, y1):
        for p, c, q in zip(prev[y][x0:x1], cur[y][x0:x1], nxt[y][x0:x1]):
            total += abs(c - (p + q) / 2.0)
            n += 1
    return total / n


def _d_value(a, b, r):
    x0, y0, x1, y1 = r
    np = rc._numpy()
    if np is not None:
        return float(np.mean(np.abs(a[y0:y1, x0:x1] - b[y0:y1, x0:x1])))
    total, n = 0.0, 0
    for y in range(y0, y1):
        for p, q in zip(a[y][x0:x1], b[y][x0:x1]):
            total += abs(p - q)
            n += 1
    return total / n


def resolve_regions(specs, width, height, stride):
    """specs: [(name, (x, y, w, h) full-res px | None for the whole frame)] -> [(name, (x0, y0, x1, y1) sampled)]."""
    out = []
    for name, rect in specs:
        x, y, w, h = (0, 0, width, height) if rect is None else rect
        if w < 1 or h < 1 or x < 0 or y < 0 or x + w > width or y + h > height:
            raise rc.CannotRun(f"region {name} ({x},{y},{w},{h}) is outside the {width}x{height} frame")
        sx0, sy0 = -(-x // stride), -(-y // stride)
        sx1, sy1 = -(-(x + w) // stride), -(-(y + h) // stride)
        if sx1 <= sx0 or sy1 <= sy0:
            raise rc.CannotRun(f"region {name} holds no pixel at --stride {stride}")
        out.append((name, (sx0, sy0, sx1, sy1)))
    return out


class Series:
    """Lazy luma frames of one folder; keeps only what the sliding window needs."""

    def __init__(self, directory, pattern, stride):
        self.dir, self.pattern, self.stride = str(directory), pattern, stride
        self.files = rc.scan_frames(directory, pattern)
        self.cache, self.size = {}, None

    def get(self, n):
        if n not in self.cache:
            if n not in self.files:
                raise rc.CannotRun(f"frame {n} is missing from {self.dir} (pattern {self.pattern})")
            img = rc.read_png(self.files[n])
            if self.size is None:
                self.size = (img.width, img.height)
            elif self.size != (img.width, img.height):
                raise rc.CannotRun(f"frame {n} is {img.width}x{img.height}, expected "
                                   f"{self.size[0]}x{self.size[1]}")
            self.cache[n] = _grid(rc.luma(img, self.stride))
        return self.cache[n]

    def drop_below(self, n):
        for k in [k for k in self.cache if k < n]:
            del self.cache[k]


def measure(series, ts, specs, ref=None):
    """{t: [T per region]} (and {t: [diff to ref per region]}) for the interior frames `ts` (ascending)."""
    out, out_ref, regions = {}, {}, None
    for t in ts:
        prev, cur, nxt = series.get(t - 1), series.get(t), series.get(t + 1)
        if regions is None:
            regions = resolve_regions(specs, series.size[0], series.size[1], series.stride)
        out[t] = [_t_value(prev, cur, nxt, r) for _, r in regions]
        if ref is not None:
            rl = ref.get(t)
            if ref.size != series.size:
                raise rc.CannotRun(f"reference frame {t} is {ref.size[0]}x{ref.size[1]}, expected "
                                   f"{series.size[0]}x{series.size[1]}")
            out_ref[t] = [_d_value(cur, rl, r) for _, r in regions]
        series.drop_below(t - 1)
        if ref is not None:
            ref.drop_below(t)
    return out, out_ref, [n for n, _ in regions]


def p95(values):
    s = sorted(values)
    return s[max(0, math.ceil(0.95 * len(s)) - 1)]


def summarize(per_t, ts, idx):
    vals = [per_t[t][idx] for t in ts]
    worst = sorted(((v, t) for v, t in zip(vals, ts)), key=lambda p: (-p[0], p[1]))[:WORST_N]
    return {"mean": sum(vals) / len(vals), "p95": p95(vals), "frames": len(vals),
            "worst": [{"frame": t, "value": v} for v, t in worst if v > 1e-12]}


# ----------------------------------------------------------------------------------------- parsing
def parse_window(text):
    m = re.fullmatch(r"\s*(\d+)\s*-\s*(\d+)\s*", text)
    if not m or int(m.group(2)) < int(m.group(1)):
        raise rc.CannotRun(f"bad --window {text!r}: expected A-B with A <= B")
    return int(m.group(1)), int(m.group(2))


def parse_region(text):
    m = re.fullmatch(r"\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*", text)
    if not m:
        raise rc.CannotRun(f"bad --region {text!r}: expected x,y,w,h in pixels")
    return tuple(int(g) for g in m.groups())


def build_specs(args):
    specs = []
    if args.grid:
        m = re.fullmatch(r"\s*(\d+)\s*x\s*(\d+)\s*", args.grid)
        if not m or int(m.group(1)) < 1 or int(m.group(2)) < 1:
            raise rc.CannotRun(f"bad --grid {args.grid!r}: expected CxR, for example 4x3")
        specs.append(("grid", (int(m.group(1)), int(m.group(2)))))
    for i, text in enumerate(args.region or [], 1):
        specs.append((f"region{i}", parse_region(text)))
    return specs


def expand_grid(specs, first_size):
    """Turn a grid spec into region rectangles once the frame size is known."""
    out = []
    for name, v in specs:
        if name != "grid":
            out.append((name, v))
            continue
        cols, rows = v
        w, h = first_size
        if cols > w or rows > h:
            raise rc.CannotRun(f"--grid {cols}x{rows} is finer than the {w}x{h} frame")
        for r in range(rows):
            for c in range(cols):
                x0, x1, y0, y1 = w * c // cols, w * (c + 1) // cols, h * r // rows, h * (r + 1) // rows
                out.append((f"r{r}c{c}", (x0, y0, x1 - x0, y1 - y0)))
    return out


# ----------------------------------------------------------------------------------------- the run
def run(args):
    if args.first > args.last:
        raise rc.CannotRun(f"--first {args.first} is after --last {args.last}")
    if args.stride < 1:
        raise rc.CannotRun("--stride must be >= 1")
    if args.threshold < 0:
        raise rc.CannotRun("--threshold must be >= 0")
    windows = [parse_window(w) for w in args.window] or [(args.first, args.last)]
    for a, b in windows:
        if a < args.first or b > args.last:
            raise rc.CannotRun(f"window {a}-{b} lies outside --first {args.first} --last {args.last}")
        if b - a + 1 < 3:
            raise rc.CannotRun(f"window {a}-{b} has {b - a + 1} frame(s); at least 3 are needed")
    specs = build_specs(args)
    a_series = Series(args.dir, args.pattern, args.stride)
    b_series = Series(args.compare, args.pattern, args.stride) if args.compare else None
    ref = Series(args.reference, args.pattern, args.stride) if args.reference else None
    ts = sorted({t for a, b in windows for t in range(a + 1, b)})
    a_series.get(ts[0] - 1)  # read one frame first so the frame size is known
    expanded = expand_grid(specs or [("full", None)], a_series.size)
    per_a, per_ref, names = measure(a_series, ts, expanded, ref)
    per_b = None
    if b_series:
        per_b = measure(b_series, ts, expanded)[0]
        if b_series.size != a_series.size:
            raise rc.CannotRun(f"--compare frames are {b_series.size[0]}x{b_series.size[1]}, "
                               f"expected {a_series.size[0]}x{a_series.size[1]}")
    return windows, names, ts, per_a, per_b, per_ref


def build_parser():
    ap = argparse.ArgumentParser(
        prog=TOOL, description="Temporal instability (second difference of luma) of near-still frame stretches.")
    ap.add_argument("dir", help="folder holding the frames")
    ap.add_argument("--first", type=int, required=True)
    ap.add_argument("--last", type=int, required=True)
    ap.add_argument("--pattern", default="frame_####.png", help="file name, # run = frame number")
    ap.add_argument("--window", action="append", default=[], metavar="A-B",
                    help="near-still stretch to measure (repeatable); default the whole --first..--last range")
    ap.add_argument("--grid", metavar="CxR", help="split the frame into C columns by R rows (regions r<row>c<col>)")
    ap.add_argument("--region", action="append", metavar="x,y,w,h",
                    help="a region in full-resolution pixels (repeatable); default the whole frame")
    ap.add_argument("--stride", type=int, default=2, help="sample every S-th pixel (default 2)")
    ap.add_argument("--threshold", type=float, default=DEFAULT_THRESHOLD,
                    help=f"finding when a region's mean T exceeds this (default {DEFAULT_THRESHOLD}; "
                         "E7, uncalibrated: calibrate per project)")
    ap.add_argument("--reference", metavar="REF_DIR",
                    help="high-sample reference frames (same names): also report mean |L - L_ref| (noise)")
    ap.add_argument("--compare", metavar="DIR_B", help="second render of the same frames: print A vs B and the ratio")
    ap.add_argument("--json", metavar="OUT", help="write a machine report")
    return ap


def main(argv=None) -> int:
    args = build_parser().parse_args(argv)
    try:
        windows, names, ts, per_a, per_b, per_ref = run(args)
        findings, rows = [], []
        for a, b in windows:
            wts = list(range(a + 1, b))
            for i, name in enumerate(names):
                s = summarize(per_a, wts, i)
                row = {"window": [a, b], "region": name, "mean": s["mean"], "p95": s["p95"],
                       "frames": s["frames"], "worst": s["worst"]}
                worst = ", ".join(f"{w['frame']}={w['value']:.5f}" for w in s["worst"]) or "none"
                print(f"window {a}-{b} region {name}: mean T {s['mean']:.5f}, p95 {s['p95']:.5f}, "
                      f"worst frames {worst}")
                if per_ref:
                    rv = [per_ref[t][i] for t in wts]
                    row["reference"] = {"mean": sum(rv) / len(rv), "max": max(rv),
                                        "per_frame": {str(t): per_ref[t][i] for t in wts}}
                    print(f"  vs reference: mean |L - L_ref| {row['reference']['mean']:.5f}, "
                          f"max {row['reference']['max']:.5f}")
                if per_b:
                    sb = summarize(per_b, wts, i)
                    ratio = s["mean"] / sb["mean"] if sb["mean"] > 0 else None
                    row["compare"] = {"mean": sb["mean"], "p95": sb["p95"], "ratio_a_over_b": ratio}
                    shown = f"{ratio:.3f}" if ratio is not None else ("1.000" if s["mean"] == 0 else "inf")
                    print(f"  A vs B: A mean {s['mean']:.5f}, B mean {sb['mean']:.5f}, ratio A/B {shown}")
                if s["mean"] > args.threshold:
                    findings.append({"kind": "flicker", "window": [a, b], "region": name,
                                     "message": f"window {a}-{b} region {name}: mean T {s['mean']:.5f} exceeds "
                                                f"threshold {args.threshold} (worst frames {worst})"})
                rows.append(row)
        summary = (f"(windows {len(windows)}, regions {len(names)}, threshold {args.threshold}"
                   f"{', compared with B' if per_b else ''})")
        return rc.finish(TOOL, findings, summary, args.json, {
            "directory": os.path.abspath(args.dir), "pattern": args.pattern, "threshold": args.threshold,
            "stride": args.stride, "windows": [list(w) for w in windows], "regions": names, "results": rows})
    except rc.CannotRun as e:
        rc.error(TOOL, str(e))
        return rc.CANNOT


if __name__ == "__main__":
    sys.exit(main())
