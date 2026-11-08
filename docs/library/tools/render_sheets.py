#!/usr/bin/env python3
"""Make review sheets from rendered PNG frames: contact sheets, zoom crops and A/B comparisons.

Purpose: let a reviewer judge many frames at once without opening each (a grid of chosen frames), look at
detail (zoom crops of one frame), and compare two renders of the same frames (seed A/B, before/after, with
a difference row).
Subcommands:
  contact DIR --pattern P (--frames 1,24,48 | --every K --first N --last M) [--cols 4]
          [--thumb-width 320] [--label TEXT] --out ABS.png
      Grid of thumbnails (nearest-neighbour downscale), dark gray gutters, "F<n>" under each thumb.
      --label TEXT is a banner: uppercase letters, digits, space and hyphen only (else exit 2).
  crops FRAME.png --box x,y,w,h[;x,y,w,h] [--scale 2] --out ABS.png
      Zoom crops side by side, nearest-neighbour; a box outside the frame exits 2. Quote the ';'.
  compare DIR_A DIR_B --pattern P --frames LIST [--cols 4] [--thumb-width 320] --out ABS.png
      Per frame a column: row A, row B, and |A-B| x 4 (clipped to 255). Frames of different sizes are
      scaled to the thumbnail size of the first frame of A.
Inputs: PNG frames (8 or 16 bit; 16 bit is scaled to 8; alpha is ignored; gray is shown as RGB).
Outputs: one PNG at --out (absolute; refused inside a git work tree unless --allow-in-repo; a warning on
stderr for cloud-synced folders), a line `render_sheets: PASS wrote ...`; optional --json report.
Exit codes: 0 sheet written, 2 could not run (bad arguments, missing or unreadable frame, box outside the
frame, output path refused). This tool does not judge frames, so it never exits 1.
Dependencies: Python 3.10+ stdlib and render_common.py in the same folder; optional Pillow (decode) and
numpy (difference) fast paths; RENDER_TOOLS_PURE=1 forces the stdlib path and the sheets are identical.
Assumptions: frames are small enough to hold in memory; the sheet is limited to 60 million pixels.
Origin: new (no prior source); a generic port of the contact-sheet and review-sheet scripts of a product
film project (grid of chosen frames, zoom crops), written fresh.
"""

from __future__ import annotations

import argparse
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import render_common as rc  # noqa: E402

TOOL = "render_sheets"
BG, FG = (40, 40, 40), (235, 235, 235)
GUTTER, MAX_PIXELS, FONT_SCALE = 8, 60_000_000, 2

_GLYPHS = """
0 0E 11 13 15 19 11 0E
1 04 0C 04 04 04 04 0E
2 0E 11 01 02 04 08 1F
3 1F 02 04 02 01 11 0E
4 02 06 0A 12 1F 02 02
5 1F 10 1E 01 01 11 0E
6 06 08 10 1E 11 11 0E
7 1F 01 02 04 08 08 08
8 0E 11 11 0E 11 11 0E
9 0E 11 11 0F 01 02 0C
A 0E 11 11 1F 11 11 11
B 1E 11 11 1E 11 11 1E
C 0E 11 10 10 10 11 0E
D 1C 12 11 11 11 12 1C
E 1F 10 10 1E 10 10 1F
F 1F 10 10 1E 10 10 10
G 0E 11 10 17 11 11 0F
H 11 11 11 1F 11 11 11
I 0E 04 04 04 04 04 0E
J 07 02 02 02 02 12 0C
K 11 12 14 18 14 12 11
L 10 10 10 10 10 10 1F
M 11 1B 15 15 11 11 11
N 11 11 19 15 13 11 11
O 0E 11 11 11 11 11 0E
P 1E 11 11 1E 10 10 10
Q 0E 11 11 11 15 12 0D
R 1E 11 11 1E 14 12 11
S 0F 10 10 0E 01 01 1E
T 1F 04 04 04 04 04 04
U 11 11 11 11 11 11 0E
V 11 11 11 11 11 0A 04
W 11 11 11 15 15 15 0A
X 11 11 0A 04 0A 11 11
Y 11 11 0A 04 04 04 04
Z 1F 01 02 04 08 10 1F
- 00 00 00 1F 00 00 00
"""
FONT = {ln[0]: [int(h, 16) for h in ln[2:].split()] for ln in _GLYPHS.strip().splitlines()}
FONT[" "] = [0] * 7


class Canvas:
    def __init__(self, w, h, color=BG):
        if w * h > MAX_PIXELS:
            raise rc.CannotRun(f"sheet would be {w}x{h} px; reduce frames, columns or --thumb-width")
        self.w, self.h = w, h
        self.rows = [bytearray(bytes(color) * w) for _ in range(h)]

    def blit(self, x, y, rows):
        for dy, row in enumerate(rows):
            self.rows[y + dy][x * 3:x * 3 + len(row)] = row

    def text(self, x, y, s, scale=FONT_SCALE, color=FG):
        px = bytes(color) * scale
        for ch in s:
            glyph = FONT.get(ch)
            if glyph is None:
                raise rc.CannotRun(f"no glyph for {ch!r}")
            for gy, bits in enumerate(glyph):
                line = bytearray()
                for gx in range(5):
                    line += px if bits >> (4 - gx) & 1 else bytes(BG) * scale
                for sy in range(scale):
                    yy = y + gy * scale + sy
                    if 0 <= yy < self.h and x * 3 + len(line) <= len(self.rows[yy]):
                        self.rows[yy][x * 3:x * 3 + len(line)] = line
            x += 6 * scale


def text_width(s, scale=FONT_SCALE):
    return len(s) * 6 * scale


def resize_nn(rows, w, h, nw, nh):
    xmap = [min(w - 1, x * w // nw) for x in range(nw)]
    out = []
    for y in range(nh):
        src = rows[min(h - 1, y * h // nh)]
        buf = bytearray(nw * 3)
        for c in range(3):
            plane = src[c::3]
            buf[c::3] = bytes([plane[i] for i in xmap])
        out.append(bytes(buf))
    return out


def absdiff4(a, b):
    np = rc._numpy()
    if np is not None:
        d = np.abs(np.frombuffer(a, dtype=np.uint8).astype(np.int16) - np.frombuffer(b, dtype=np.uint8))
        return bytes(np.minimum(d * 4, 255).astype(np.uint8))
    return bytes([min(255, abs(p - q) * 4) for p, q in zip(a, b)])


def load_rgb(path):
    img = rc.read_png(path)
    return img.width, img.height, rc.rgb8_rows(img)


def thumb(path, tw, th):
    w, h, rows = load_rgb(path)
    return resize_nn(rows, w, h, tw, th)


def frame_file(directory, pattern, n):
    path = rc.frame_path(directory, pattern, n)
    if not os.path.isfile(path):
        raise rc.CannotRun(f"frame {n} not found: {path}")
    return path


def thumb_size(path, tw):
    w, h, _ = load_rgb(path)
    return tw, max(1, round(tw * h / w))


def check_label(label):
    if label is not None and not re.fullmatch(r"[A-Z0-9 -]+", label):
        raise rc.CannotRun("--label may contain only uppercase letters, digits, space and hyphen")


def sheet_size(nrows, ncols, tw, th, label=None):
    """(width, height) of a thumbnail grid sheet; refuses an oversized sheet before any work is done."""
    banner = (7 * FONT_SCALE + 16) if label else 0
    w, h = GUTTER + ncols * (tw + GUTTER), banner + GUTTER + nrows * (th + 7 * FONT_SCALE + 8 + GUTTER)
    if w * h > MAX_PIXELS:
        raise rc.CannotRun(f"sheet would be {w}x{h} px; reduce frames, columns or --thumb-width")
    return w, h


def compose(cells, nrows, ncols, tw, th, label=None):
    """cells: {(row, col): (thumb rows, caption)}. Returns a Canvas."""
    lh = 7 * FONT_SCALE + 8
    banner = (7 * FONT_SCALE + 16) if label else 0
    cw, ch = tw + GUTTER, th + lh + GUTTER
    cv = Canvas(*sheet_size(nrows, ncols, tw, th, label))
    if label:
        cv.text(GUTTER, 8, label)
    for (r, c), (rows, caption) in cells.items():
        x, y = GUTTER + c * cw, banner + GUTTER + r * ch
        cv.blit(x, y, rows)
        cv.text(x, y + th + 4, caption)
    return cv


def pick_frames(args):
    if args.frames and args.every:
        raise rc.CannotRun("use --frames or --every, not both")
    if args.frames:
        return rc.parse_frame_list(args.frames, "--frames")
    if args.every:
        if args.first is None or args.last is None or args.every < 1 or args.last < args.first:
            raise rc.CannotRun("--every K needs --first N --last M with K >= 1 and M >= N")
        return list(range(args.first, args.last + 1, args.every))
    raise rc.CannotRun("give --frames LIST or --every K --first N --last M")


def check_grid(args):
    if args.cols < 1 or args.thumb_width < 8:
        raise rc.CannotRun("--cols must be >= 1 and --thumb-width >= 8")


def cmd_contact(args):
    check_grid(args)
    check_label(args.label)
    nums = pick_frames(args)
    paths = [frame_file(args.dir, args.pattern, n) for n in nums]
    tw, th = thumb_size(paths[0], args.thumb_width)
    sheet_size(-(-len(nums) // args.cols), min(args.cols, len(nums)), tw, th, args.label)
    cells = {(i // args.cols, i % args.cols): (thumb(p, tw, th), f"F{n}")
             for i, (n, p) in enumerate(zip(nums, paths))}
    return compose(cells, -(-len(nums) // args.cols), min(args.cols, len(nums)), tw, th, args.label), nums


def cmd_compare(args):
    check_grid(args)
    nums = rc.parse_frame_list(args.frames, "--frames")
    pa = [frame_file(args.dir_a, args.pattern, n) for n in nums]
    pb = [frame_file(args.dir_b, args.pattern, n) for n in nums]
    tw, th = thumb_size(pa[0], args.thumb_width)
    cells, ncols = {}, min(args.cols, len(nums))
    sheet_size(-(-len(nums) // ncols) * 3, ncols, tw, th)
    for i, n in enumerate(nums):
        g, c = i // ncols, i % ncols
        ta, tb = thumb(pa[i], tw, th), thumb(pb[i], tw, th)
        cells[(g * 3, c)] = (ta, f"A F{n}")
        cells[(g * 3 + 1, c)] = (tb, f"B F{n}")
        cells[(g * 3 + 2, c)] = ([absdiff4(x, y) for x, y in zip(ta, tb)], f"DIFF X4 F{n}")
    return compose(cells, -(-len(nums) // ncols) * 3, ncols, tw, th), nums


def parse_boxes(text, fw, fh):
    boxes = []
    for part in text.split(";"):
        m = re.fullmatch(r"\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*", part)
        if not m:
            raise rc.CannotRun(f"bad --box {part!r}: expected x,y,w,h as integers")
        x, y, w, h = map(int, m.groups())
        if w < 1 or h < 1 or x + w > fw or y + h > fh:
            raise rc.CannotRun(f"--box {x},{y},{w},{h} is outside the {fw}x{fh} frame")
        boxes.append((x, y, w, h))
    return boxes


def cmd_crops(args):
    if not 1 <= args.scale <= 16:
        raise rc.CannotRun("--scale must be between 1 and 16")
    fw, fh, rows = load_rgb(args.frame)
    boxes = parse_boxes(args.box, fw, fh)
    if sum(w * args.scale + GUTTER for _, _, w, _ in boxes) * (max(h for *_, h in boxes) * args.scale + 40)             > MAX_PIXELS:
        raise rc.CannotRun("crops sheet would be too large; reduce --scale or the boxes")
    lh = 7 * FONT_SCALE + 8
    pieces = []
    for x, y, w, h in boxes:
        crop = [r[x * 3:(x + w) * 3] for r in rows[y:y + h]]
        pieces.append(resize_nn(crop, w, h, w * args.scale, h * args.scale))
    width = GUTTER + sum(len(p[0]) // 3 + GUTTER for p in pieces)
    cv = Canvas(width, GUTTER + max(len(p) for p in pieces) + lh)
    x = GUTTER
    for i, p in enumerate(pieces):
        cv.blit(x, GUTTER, p)
        cv.text(x, GUTTER + len(p) + 4, str(i + 1))
        x += len(p[0]) // 3 + GUTTER
    return cv, boxes


def build_parser():
    ap = argparse.ArgumentParser(prog=TOOL, description="Make contact sheets, zoom crops and A/B comparisons "
                                 "from PNG frames.")
    sub = ap.add_subparsers(dest="cmd", required=True)

    def common(p):
        p.add_argument("--out", required=True, help="absolute path of the PNG to write")
        p.add_argument("--allow-in-repo", action="store_true", help="allow writing inside a git work tree")
        p.add_argument("--json", metavar="OUT", help="write a machine report")

    c = sub.add_parser("contact", help="grid of chosen frames")
    c.add_argument("dir")
    c.add_argument("--pattern", default="frame_####.png")
    c.add_argument("--frames", help="e.g. 1,24,48 or 1-10,50")
    c.add_argument("--every", type=int)
    c.add_argument("--first", type=int)
    c.add_argument("--last", type=int)
    c.add_argument("--cols", type=int, default=4)
    c.add_argument("--thumb-width", type=int, default=320)
    c.add_argument("--label", help="banner text: A-Z, 0-9, space, hyphen")
    common(c)
    z = sub.add_parser("crops", help="zoom crops of one frame")
    z.add_argument("frame")
    z.add_argument("--box", required=True, help="x,y,w,h[;x,y,w,h] (quote the semicolon)")
    z.add_argument("--scale", type=int, default=2)
    common(z)
    a = sub.add_parser("compare", help="A over B with a difference row")
    a.add_argument("dir_a")
    a.add_argument("dir_b")
    a.add_argument("--pattern", default="frame_####.png")
    a.add_argument("--frames", required=True)
    a.add_argument("--cols", type=int, default=4)
    a.add_argument("--thumb-width", type=int, default=320)
    common(a)
    return ap


def main(argv=None) -> int:
    args = build_parser().parse_args(argv)
    try:
        warnings = rc.check_output_path(args.out, "--out", args.allow_in_repo)
        if not args.out.lower().endswith(".png"):
            raise rc.CannotRun("--out must end with .png")
        cv, detail = {"contact": cmd_contact, "crops": cmd_crops, "compare": cmd_compare}[args.cmd](args)
        for w in warnings:
            print(f"{TOOL}: WARNING {w}", file=sys.stderr)
        rc.write_png(args.out, cv.w, cv.h, 3, cv.rows)
        print(f"{TOOL}: PASS wrote {args.out} ({cv.w}x{cv.h} px, {args.cmd}, {len(detail)} item(s))")
        if args.json:
            rc.write_json_atomic(args.json, {"tool": TOOL, "status": "pass", "findings": [],
                                             "command": args.cmd, "out": args.out, "width": cv.w,
                                             "height": cv.h, "items": [list(d) if isinstance(d, tuple) else d
                                                                       for d in detail]})
        return rc.PASS
    except rc.CannotRun as e:
        rc.error(TOOL, str(e))
        return rc.CANNOT


if __name__ == "__main__":
    sys.exit(main())
