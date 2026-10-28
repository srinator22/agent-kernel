#!/usr/bin/env python3
"""Audit a folder of rendered PNG frames: missing, unreadable, wrong size, black, fireflies, duplicates.

Purpose: catch the failures a long chunked render produces silently (a chunk that died, a frame written
black or half-written, a resolution change, a run of fireflies, a frozen frame) before frames are encoded.
Inputs: DIR with frames named by --pattern (`#` run = zero-padded frame number), --first and --last.
Outputs: one finding per line on stdout, then `frame_audit: PASS ...` or `frame_audit: FAIL n finding(s)
...` with frames expected, present and findings by kind; optional --json report. Errors go to stderr as
`frame_audit: ERROR ...`.
Exit codes: 0 pass, 1 findings, 2 could not run (bad arguments, missing folder, non-PNG frames).
Findings (kind): missing (grouped by chunk with --chunk K), unexpected (frames outside first-last),
unreadable (corrupt or truncated PNG), resolution (differs from --width/--height, or from the first
readable frame), black (mean luma < --black-mean), blank (luma std < --blank-std; not reported for a black
frame), firefly (see below), size (file size under --size-ratio or over 1/--size-ratio of the median of
the 5 frames centred on it, edges clamped; skipped with fewer than 3 frames), duplicate (a frame with the
same sha256 as the previous frame, unless both lie inside an --allow-duplicates A-B range).
Fireflies: a pixel counts when its luma is > 0.9 and exceeds the mean of its 8 neighbours by more than
0.5; the frame is flagged when counted pixels / evaluated pixels > --firefly-frac. Evaluated pixels are the
interior of the sampled grid; with --stride S only every S-th pixel is sampled (and neighbours are grid
neighbours), so use --stride 1 (the default) to catch single-pixel fireflies.
Dependencies: Python 3.10+ stdlib and render_common.py in the same folder; optional Pillow and numpy
fast paths (RENDER_TOOLS_PURE=1 forces the stdlib path; results agree).
Assumptions: PNG frames only. EXR or other formats exit 2 (NaN and EXR checks need an EXR reader).
Origin: new (no prior source).
"""

from __future__ import annotations

import argparse
import math
import os
import statistics
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import render_common as rc  # noqa: E402

TOOL = "frame_audit"
EXR_MSG = "NaN and EXR checks need an EXR reader (not available in the stdlib build)"
FIREFLY_MIN, FIREFLY_JUMP = 0.9, 0.5


def count_fireflies(lum: list) -> tuple:
    """(count, evaluated) over the interior of a luma grid."""
    h = len(lum)
    w = len(lum[0]) if h else 0
    if h < 3 or w < 3:
        return 0, 0
    np = rc._numpy()
    if np is not None:
        a = np.array(lum, dtype=np.float64)
        s = (a[:-2, :-2] + a[:-2, 1:-1] + a[:-2, 2:] + a[1:-1, :-2] + a[1:-1, 2:]
             + a[2:, :-2] + a[2:, 1:-1] + a[2:, 2:])
        c = a[1:-1, 1:-1]
        hit = (c > FIREFLY_MIN) & (c - s / 8 > FIREFLY_JUMP)
        return int(hit.sum()), (h - 2) * (w - 2)
    count = 0
    for y in range(1, h - 1):
        up, mid, dn = lum[y - 1], lum[y], lum[y + 1]
        for x in range(1, w - 1):
            v = mid[x]
            if v > FIREFLY_MIN:
                s = up[x - 1] + up[x] + up[x + 1] + mid[x - 1] + mid[x + 1] + dn[x - 1] + dn[x] + dn[x + 1]
                if v - s / 8 > FIREFLY_JUMP:
                    count += 1
    return count, (h - 2) * (w - 2)


def mean_std(lum: list) -> tuple:
    vals = [v for row in lum for v in row]
    if not vals:
        return 0.0, 0.0
    np = rc._numpy()
    if np is not None:
        a = np.array(vals, dtype=np.float64)
        return float(a.mean()), float(a.std())
    m = math.fsum(vals) / len(vals)
    return m, math.sqrt(math.fsum((v - m) ** 2 for v in vals) / len(vals))


def find(kind, message, frame=None):
    return {"kind": kind, "frame": frame, "message": message}


def chunk_groups(missing: list, first: int, last: int, k: int) -> list:
    out = {}
    for n in missing:
        out.setdefault((n - first) // k, []).append(n)
    return [(i, first + i * k, min(last, first + (i + 1) * k - 1), out[i]) for i in sorted(out)]


def audit(args) -> tuple:
    frames = rc.scan_frames(args.dir, args.pattern)
    present = sorted(n for n in frames if args.first <= n <= args.last)
    findings, info = [], {}
    missing = [n for n in range(args.first, args.last + 1) if n not in frames]
    if missing:
        if args.chunk:
            for i, a, b, ns in chunk_groups(missing, args.first, args.last, args.chunk):
                findings.append(find("missing", f"chunk {i} (frames {a}-{b}) is missing {len(ns)} frame(s): "
                                     f"{rc.format_ranges(ns)}", ns[0]))
        else:
            findings.append(find("missing", f"{len(missing)} frame(s) missing: {rc.format_ranges(missing)}",
                                 missing[0]))
    extra = sorted(n for n in frames if n < args.first or n > args.last)
    if extra:
        findings.append(find("unexpected", f"{len(extra)} frame(s) outside {args.first}-{args.last}: "
                             f"{rc.format_ranges(extra)}", extra[0]))
    want = (args.width, args.height) if args.width else None
    sizes, hashes = {}, {}
    for n in present:
        path = frames[n]
        sizes[n] = os.path.getsize(path)
        hashes[n] = rc.sha256_file(path)
        try:
            img = rc.read_png(path)
        except rc.CannotRun as e:
            findings.append(find("unreadable", f"frame {n}: {e}", n))
            continue
        if want is None:
            want = (img.width, img.height)
        if (img.width, img.height) != want:
            findings.append(find("resolution", f"frame {n} is {img.width}x{img.height}, expected "
                                 f"{want[0]}x{want[1]}", n))
        lum = rc.luma(img, args.stride)
        mean, std = mean_std(lum)
        fire, evaluated = count_fireflies(lum)
        info[n] = {"mean_luma": mean, "std_luma": std, "fireflies": fire, "bytes": sizes[n]}
        if mean < args.black_mean:
            findings.append(find("black", f"frame {n} is black (mean luma {mean:.4f})", n))
        elif std < args.blank_std:
            findings.append(find("blank", f"frame {n} is blank (luma std {std:.5f})", n))
        if evaluated and fire / evaluated > args.firefly_frac:
            findings.append(find("firefly", f"frame {n} has {fire} firefly pixel(s) "
                                 f"({fire / evaluated:.5f} of {evaluated} evaluated)", n))
    ok = [n for n in present if n in sizes]
    if len(ok) >= 3:
        for i, n in enumerate(ok):
            lo = max(0, min(i - 2, len(ok) - 5))
            med = statistics.median(sizes[m] for m in ok[lo:lo + 5])
            if med > 0 and (sizes[n] < args.size_ratio * med or sizes[n] > med / args.size_ratio):
                findings.append(find("size", f"frame {n} is {sizes[n]} bytes, median of nearby frames is "
                                     f"{med:g}", n))
    allowed = args.allow_duplicates
    dups = [n for n in present if n - 1 in hashes and hashes[n] == hashes[n - 1]
            and not any(a <= n - 1 and n <= b for a, b in allowed)]
    for a, b in rc.group_ranges(dups):
        findings.append(find("duplicate", f"frame(s) {a}-{b} identical to the previous frame "
                             f"({b - a + 1} frame(s))", a))
    order = {"missing": 0, "unexpected": 1}
    findings.sort(key=lambda f: (order.get(f["kind"], 2), f["frame"] if f["frame"] is not None else -1,
                                 f["kind"]))
    return findings, present, info


def build_parser():
    ap = argparse.ArgumentParser(prog=TOOL, description="Audit rendered PNG frames for missing, unreadable, "
                                 "black, firefly, size-anomaly and duplicate frames.")
    ap.add_argument("dir", help="folder holding the frames")
    ap.add_argument("--first", type=int, required=True, help="first expected frame number")
    ap.add_argument("--last", type=int, required=True, help="last expected frame number")
    ap.add_argument("--pattern", default="frame_####.png", help="file name, # run = frame number")
    ap.add_argument("--chunk", type=int, default=0, help="group missing frames by chunks of K frames")
    ap.add_argument("--width", type=int, help="expected width (needs --height)")
    ap.add_argument("--height", type=int, help="expected height (needs --width)")
    ap.add_argument("--stride", type=int, default=1, help="sample every S pixels (default 1)")
    ap.add_argument("--black-mean", type=float, default=0.01)
    ap.add_argument("--blank-std", type=float, default=0.002)
    ap.add_argument("--firefly-frac", type=float, default=0.0005)
    ap.add_argument("--size-ratio", type=float, default=0.5, help="file size outlier ratio, 0 < r < 1")
    ap.add_argument("--allow-duplicates", default="", metavar="A-B[,C-D]",
                    help="frame ranges allowed to repeat the previous frame (holds)")
    ap.add_argument("--json", metavar="OUT", help="write a machine report")
    return ap


def validate(args):
    if args.first < 0 or args.last < args.first:
        raise rc.CannotRun(f"bad range: --first {args.first} --last {args.last}")
    if args.stride < 1 or args.chunk < 0:
        raise rc.CannotRun("--stride must be >= 1 and --chunk >= 0")
    if (args.width is None) != (args.height is None) or any(v is not None and v < 1
                                                           for v in (args.width, args.height)):
        raise rc.CannotRun("--width and --height must be given together and be positive")
    if not 0 < args.size_ratio < 1:
        raise rc.CannotRun("--size-ratio must be between 0 and 1 (exclusive)")
    ext = os.path.splitext(args.pattern)[1].lower()
    if ext == ".exr":
        raise rc.CannotRun(EXR_MSG)
    if ext != ".png":
        raise rc.CannotRun(f"unsupported frame format {ext or '(none)'}: only PNG frames can be audited; "
                           + EXR_MSG)
    args.allow_duplicates = rc.parse_ranges(args.allow_duplicates, "--allow-duplicates") \
        if args.allow_duplicates else []
    rc._pattern_parts(args.pattern)
    if not os.path.isdir(args.dir):
        raise rc.CannotRun(f"not a directory: {args.dir}")


def main(argv=None) -> int:
    args = build_parser().parse_args(argv)
    try:
        validate(args)
        findings, present, info = audit(args)
        expected = args.last - args.first + 1
        counts = {}
        for f in findings:
            counts[f["kind"]] = counts.get(f["kind"], 0) + 1
        kinds = ", ".join(f"{k} {v}" for k, v in sorted(counts.items())) or "none"
        summary = f"(frames expected {expected}, present {len(present)}; findings: {kinds})"
        return rc.finish(TOOL, findings, summary, args.json, {
            "directory": os.path.abspath(args.dir), "pattern": args.pattern, "first": args.first,
            "last": args.last, "expected": expected, "present": len(present), "counts": counts,
            "frames": {str(n): v for n, v in info.items()}})
    except rc.CannotRun as e:
        rc.error(TOOL, str(e))
        return rc.CANNOT


if __name__ == "__main__":
    sys.exit(main())
