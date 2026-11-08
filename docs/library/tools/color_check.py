#!/usr/bin/env python3
"""Check a PNG frame sequence for bit depth, alpha, crushed or clipped pixels and exposure pops between frames.

Purpose: catch colour and exposure defects across a whole sequence: a few frames saved at the wrong bit depth,
an unwanted alpha channel, blacks or highlights lost to clipping, a sudden brightness jump between neighbours.
Usage: python color_check.py DIR --first N --last M [--pattern frame_####.png] [--bitdepth 8|16] [--no-alpha]
       [--clip-frac 0.01] [--jump 0.08] [--stride 4] [--no-crush-check] [--json OUT]
Inputs: PNG files DIR/<pattern> for first..last (all must exist and decode; otherwise exit 2).
  --bitdepth: expected bit depth (default: that of the first frame). --stride: sample every Nth pixel in x and y.
Findings (exit 1): bit depth differs from the expected one; an alpha channel where --no-alpha was given; the
  fraction of sampled pixels with any colour channel at 0 (crushed) or at the maximum (clipped) above
  --clip-frac (default 0.01); mean luma (Rec. 709, 0..1) change between consecutive frames above --jump
  (default 0.08, exposure pop). A deliberately black background trips the crush check: pass --no-crush-check.
Outputs: one finding per line, then `color_check: PASS ...` or `color_check: FAIL n finding(s) ...`; --json adds
  per-frame mean luma, crushed and clipped fractions.
Exit codes: 0 pass, 1 findings, 2 could not run (bad arguments, missing or unreadable frame).
Dependencies: Python 3.10+ standard library via render_common; optional numpy and Pillow fast paths
  (RENDER_TOOLS_PURE=1 forces the stdlib path; results agree).
Assumptions: thresholds are starting values, not published standards; calibrate per project. Alpha is not
counted as a colour channel.
Origin: new.
"""

from __future__ import annotations

import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import render_common as rc  # noqa: E402

TOOL = "color_check"


def clip_fractions(img, stride: int) -> tuple:
    """(crushed fraction, clipped fraction) over sampled pixels, colour channels only."""
    if stride < 1:
        raise rc.CannotRun(f"--stride must be >= 1, got {stride}")
    c, mv = img.channels, img.maxval
    ncol = 1 if c < 3 else 3
    rows = img.rows[::stride]
    np = rc._numpy()
    if np is not None:
        if img.bitdepth == 8:
            arr = np.frombuffer(b"".join(bytes(r) for r in rows), dtype=np.uint8)
        else:
            arr = np.array([list(r) for r in rows], dtype=np.int64)
        arr = arr.reshape(len(rows), img.width, c)[:, ::stride, :ncol]
        total = arr.shape[0] * arr.shape[1]
        return (float((arr == 0).any(axis=2).sum()) / total, float((arr == mv).any(axis=2).sum()) / total)
    low = high = total = 0
    step = c * stride
    for row in rows:
        for x in range(0, img.width * c, step):
            px = row[x:x + ncol]
            total += 1
            if 0 in px:
                low += 1
            if mv in px:
                high += 1
    return low / total, high / total


def mean_luma(img, stride: int) -> float:
    rows = rc.luma(img, stride)
    n = sum(len(r) for r in rows)
    return sum(sum(r) for r in rows) / n


def analyse(directory, pattern, first, last, stride) -> list:
    nums = list(range(first, last + 1))
    missing = [n for n in nums if not os.path.isfile(rc.frame_path(directory, pattern, n))]
    if missing:
        raise rc.CannotRun(f"{len(missing)} frame(s) missing in {directory}: {rc.format_ranges(missing)}")
    out = []
    for n in nums:
        img = rc.read_png(rc.frame_path(directory, pattern, n))
        crushed, clipped = clip_fractions(img, stride)
        out.append({"frame": n, "bitdepth": img.bitdepth, "alpha": img.channels in (2, 4),
                    "luma": mean_luma(img, stride), "crushed": crushed, "clipped": clipped})
    return out


def findings_for(rows, args) -> list:
    F = []
    want = args.bitdepth if args.bitdepth else rows[0]["bitdepth"]
    bad = [r["frame"] for r in rows if r["bitdepth"] != want]
    if bad:
        F.append({"kind": "bitdepth", "message": f"frames {rc.format_ranges(bad)} are not {want} bit "
                                                 f"(expected {want}, from {'--bitdepth' if args.bitdepth else 'the first frame'})"})
    if args.no_alpha:
        bad = [r["frame"] for r in rows if r["alpha"]]
        if bad:
            F.append({"kind": "alpha", "message": f"frames {rc.format_ranges(bad)} have an alpha channel"})
    if not args.no_crush_check:
        bad = [r for r in rows if r["crushed"] > args.clip_frac]
        if bad:
            F.append({"kind": "crushed", "message": (
                f"{len(bad)} frame(s) have more than {args.clip_frac:g} of pixels at 0 in a colour channel: "
                f"{rc.format_ranges([r['frame'] for r in bad])} (worst {max(r['crushed'] for r in bad):.4f})")})
    bad = [r for r in rows if r["clipped"] > args.clip_frac]
    if bad:
        F.append({"kind": "clipped", "message": (
            f"{len(bad)} frame(s) have more than {args.clip_frac:g} of pixels at the maximum in a colour channel: "
            f"{rc.format_ranges([r['frame'] for r in bad])} (worst {max(r['clipped'] for r in bad):.4f})")})
    pops = [(b["frame"], b["luma"] - a["luma"]) for a, b in zip(rows, rows[1:]) if abs(b["luma"] - a["luma"]) > args.jump]
    if pops:
        F.append({"kind": "exposure-pop", "message": "mean luma jumps by more than " + f"{args.jump:g} into frame(s) "
                  + ", ".join(f"{n} ({d:+.3f})" for n, d in pops[:10]) + (" ..." if len(pops) > 10 else "")})
    return F


def make_parser() -> argparse.ArgumentParser:
    ap = argparse.ArgumentParser(
        prog="color_check.py",
        description="Check a PNG sequence: bit depth, unexpected alpha, crushed or clipped pixels, exposure pops "
                    "between consecutive frames.",
        epilog="Exit: 0 pass, 1 findings, 2 could not run. Thresholds are starting values; calibrate per project.")
    ap.add_argument("dir", help="folder holding the frames")
    ap.add_argument("--first", type=int, required=True)
    ap.add_argument("--last", type=int, required=True)
    ap.add_argument("--pattern", default="frame_####.png", help="file name with one run of # (default frame_####.png)")
    ap.add_argument("--bitdepth", type=int, choices=[8, 16], help="expected bit depth (default: the first frame's)")
    ap.add_argument("--no-alpha", action="store_true", dest="no_alpha", help="an alpha channel is a finding")
    ap.add_argument("--clip-frac", type=float, default=0.01, dest="clip_frac",
                    help="max fraction of pixels at 0 or at maximum (default 0.01)")
    ap.add_argument("--jump", type=float, default=0.08, help="max mean luma change between frames (default 0.08)")
    ap.add_argument("--stride", type=int, default=4, help="sample every Nth pixel (default 4)")
    ap.add_argument("--no-crush-check", action="store_true", dest="no_crush_check",
                    help="skip the crushed-blacks check (deliberately black backgrounds)")
    ap.add_argument("--json", help="write the machine report here")
    return ap


def main(argv=None) -> int:
    args = make_parser().parse_args(argv)
    try:
        if args.first < 0 or args.last < args.first:
            raise rc.CannotRun(f"bad range --first {args.first} --last {args.last}")
        if not os.path.isdir(args.dir):
            raise rc.CannotRun(f"not a directory: {args.dir}")
        if not (0 <= args.clip_frac <= 1) or args.jump < 0:
            raise rc.CannotRun("--clip-frac must be in 0..1 and --jump >= 0")
        rows = analyse(args.dir, args.pattern, args.first, args.last, args.stride)
        findings = findings_for(rows, args)
    except rc.CannotRun as e:
        rc.error(TOOL, str(e))
        return rc.CANNOT
    return rc.finish(TOOL, findings, f"{len(rows)} frame(s) {args.first}-{args.last}", args.json,
                     {"dir": args.dir, "frames": rows})


if __name__ == "__main__":
    sys.exit(main())
