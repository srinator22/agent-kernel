#!/usr/bin/env python3
"""Shared helpers for the render tools: exit codes, path guards, a stdlib PNG codec, frame names, reports.

Purpose: one small module the image tools (frame_audit, render_sheets and later ones) import, so PNG
reading, frame-name handling and path safety are written once and tested once.
Inputs: PNG files (non-interlaced; colour types 0, 2, 3, 4, 6; 8 bit, and 16 bit for types 0, 2, 4, 6).
Outputs: Python values only; `--self-test` writes and reads one PNG in a temporary folder.
Exit codes (module constants PASS, FAIL, CANNOT): 0 pass, 1 check failed, 2 could not run.
Dependencies: Python 3.10+ standard library. Optional fast paths: Pillow (PNG decode) and numpy (luma);
setting RENDER_TOOLS_PURE=1 forces the stdlib path. Both paths return identical Image values.
Assumptions: pixels are held as rows of ints (row-major, channels interleaved); 16-bit PNGs other than
gray are always decoded by the stdlib path because Pillow reduces them to 8 bit.
Origin: new (no prior source).
"""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import os
import re
import struct
import sys
import tempfile
import zlib

PASS, FAIL, CANNOT = 0, 1, 2
PNG_SIG = b"\x89PNG\r\n\x1a\n"
LUMA_WEIGHTS = (0.2126, 0.7152, 0.0722)
MAX_RAW_BYTES = 1 << 30
_CLOUD_RE = re.compile(r"^(onedrive|dropbox|icloud|iclouddrive|google ?drive)([ ._-].*)?$", re.IGNORECASE)


class CannotRun(Exception):
    """The tool cannot do its job (bad argument, missing or unreadable input); callers exit 2."""


def pure_mode() -> bool:
    return os.environ.get("RENDER_TOOLS_PURE", "") not in ("", "0")


def _numpy():
    if pure_mode():
        return None
    try:
        import numpy
        return numpy
    except Exception:
        return None


def _pillow():
    if pure_mode():
        return None
    try:
        from PIL import Image
        return Image
    except Exception:
        return None


# ----------------------------------------------------------------------------------------- paths
def require_abs(path, what: str) -> str:
    if not path or not os.path.isabs(str(path)):
        raise CannotRun(f"{what} must be an absolute path, got {str(path)!r}")
    return str(path)


def _parents(path: str):
    p = os.path.abspath(path)
    while True:
        yield p
        up = os.path.dirname(p)
        if up == p:
            return
        p = up


def in_git_worktree(path) -> bool:
    """True when `path` or any parent folder holds a `.git` (a folder, or a file for linked worktrees)."""
    return any(os.path.exists(os.path.join(p, ".git")) for p in _parents(str(path)))


def cloud_synced(path) -> bool:
    """True when a path segment is a cloud-sync folder (OneDrive, Dropbox, iCloud, Google Drive)."""
    parts = re.split(r"[\\/]+", os.path.abspath(str(path)))
    return any(_CLOUD_RE.match(seg) for seg in parts if seg)


def check_output_path(path, what: str, allow_in_repo: bool = False) -> list:
    """Validate an output path: absolute; refuse inside a git work tree unless allowed. Returns warnings."""
    require_abs(path, what)
    if in_git_worktree(path) and not allow_in_repo:
        raise CannotRun(f"{what} {path} is inside a git work tree; use an output folder outside the repo "
                        "or pass --allow-in-repo")
    return [f"{what} {path} is in a cloud-synced folder; render output belongs on a local disk"] \
        if cloud_synced(path) else []


def sha256_file(path) -> str:
    h = hashlib.sha256()
    try:
        with open(path, "rb") as f:
            for block in iter(lambda: f.read(1 << 20), b""):
                h.update(block)
    except OSError as e:
        raise CannotRun(f"cannot read {path}: {e}")
    return h.hexdigest()


def write_json_atomic(path, obj) -> None:
    path = os.path.abspath(str(path))
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), suffix=".tmp")
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as f:
            json.dump(obj, f, indent=2, sort_keys=True)
            f.write("\n")
        os.replace(tmp, path)
    except OSError as e:
        raise CannotRun(f"cannot write {path}: {e}")


# ------------------------------------------------------------------------------------- reporting
def error(tool: str, msg: str) -> None:
    print(f"{tool}: ERROR {msg}", file=sys.stderr)


def finish(tool: str, findings: list, summary: str, json_path=None, data=None) -> int:
    """Print findings (dicts with kind, message) and the summary line; write the optional JSON report."""
    for f in findings:
        print(f"{f['kind']}: {f['message']}")
    status = "pass" if not findings else "fail"
    print(f"{tool}: PASS {summary}" if not findings else f"{tool}: FAIL {len(findings)} finding(s) {summary}")
    if json_path:
        report = {"tool": tool, "status": status, "findings": findings}
        report.update(data or {})
        write_json_atomic(json_path, report)
    return PASS if not findings else FAIL


# ------------------------------------------------------------------------------------ frame names
def _pattern_parts(pattern: str):
    runs = re.findall(r"#+", pattern or "")
    if len(runs) != 1:
        raise CannotRun(f"pattern {pattern!r} must contain exactly one run of '#' (e.g. frame_####.png)")
    if "/" in pattern or "\\" in pattern:
        raise CannotRun(f"pattern {pattern!r} must be a file name, not a path")
    pre, post = pattern.split(runs[0])
    return pre, len(runs[0]), post


def frame_path(directory, pattern: str, n: int) -> str:
    pre, width, post = _pattern_parts(pattern)
    if n < 0:
        raise CannotRun(f"frame number must be >= 0, got {n}")
    return os.path.join(str(directory), f"{pre}{n:0{width}d}{post}")


def scan_frames(directory, pattern: str) -> dict:
    """{frame number: path} for files in `directory` whose names match the pattern exactly."""
    pre, width, post = _pattern_parts(pattern)
    rx = re.compile("^" + re.escape(pre) + r"(\d+)" + re.escape(post) + "$")
    if not os.path.isdir(str(directory)):
        raise CannotRun(f"not a directory: {directory}")
    found = {}
    for name in sorted(os.listdir(str(directory))):
        m = rx.match(name)
        if not m or not os.path.isfile(os.path.join(str(directory), name)):
            continue
        digits = m.group(1)
        if len(digits) < width or (len(digits) > width and digits[0] == "0"):
            continue
        found[int(digits)] = os.path.join(str(directory), name)
    return found


def parse_ranges(text: str, what: str = "frame list") -> list:
    """'1,24,48' or '1-5,9' -> [(1, 1), (24, 24), (48, 48)] / [(1, 5), (9, 9)]."""
    out = []
    for tok in (text or "").split(","):
        m = re.fullmatch(r"\s*(\d+)\s*(?:-\s*(\d+)\s*)?", tok)
        if not m:
            raise CannotRun(f"bad {what} {text!r}: expected numbers or A-B ranges separated by commas")
        a = int(m.group(1))
        b = int(m.group(2)) if m.group(2) is not None else a
        if b < a:
            raise CannotRun(f"bad {what} {text!r}: range {a}-{b} runs backwards")
        out.append((a, b))
    return out


def parse_frame_list(text: str, what: str = "frame list") -> list:
    frames = []
    for a, b in parse_ranges(text, what):
        if b - a > 1_000_000:
            raise CannotRun(f"bad {what} {text!r}: range {a}-{b} is too large")
        frames.extend(range(a, b + 1))
    return frames


def group_ranges(numbers) -> list:
    out = []
    for n in sorted(set(numbers)):
        if out and n == out[-1][1] + 1:
            out[-1][1] = n
        else:
            out.append([n, n])
    return [(a, b) for a, b in out]


def format_ranges(numbers) -> str:
    return ", ".join(str(a) if a == b else f"{a}-{b}" for a, b in group_ranges(numbers))


# -------------------------------------------------------------------------------------- PNG codec
class Image:
    """Decoded PNG: width, height, channels (1-4), bitdepth (8 or 16), maxval, rows of interleaved ints."""

    def __init__(self, width, height, channels, bitdepth, rows):
        self.width, self.height, self.channels = width, height, channels
        self.bitdepth, self.maxval, self.rows = bitdepth, (1 << bitdepth) - 1, rows

    def pixel(self, x: int, y: int) -> tuple:
        c = self.channels
        return tuple(self.rows[y][x * c:(x + 1) * c])


def png_chunk(kind: bytes, body: bytes) -> bytes:
    return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body))


def _iter_chunks(data: bytes):
    if data[:8] != PNG_SIG:
        raise CannotRun("unreadable PNG: bad signature")
    pos, seen_end = 8, False
    while pos < len(data):
        if pos + 8 > len(data):
            raise CannotRun("unreadable PNG: truncated file (partial chunk header)")
        length, kind = struct.unpack(">I4s", data[pos:pos + 8])
        if pos + 12 + length > len(data):
            raise CannotRun(f"unreadable PNG: truncated file (chunk {kind.decode('latin-1')})")
        body = data[pos + 8:pos + 8 + length]
        crc = struct.unpack(">I", data[pos + 8 + length:pos + 12 + length])[0]
        if zlib.crc32(kind + body) != crc:
            raise CannotRun(f"unreadable PNG: bad CRC in {kind.decode('latin-1')} chunk")
        yield kind, body
        pos += 12 + length
        if kind == b"IEND":
            seen_end = True
            break
    if not seen_end:
        raise CannotRun("unreadable PNG: truncated file (no IEND chunk)")


_VALID_DEPTHS = {0: (8, 16), 2: (8, 16), 3: (8,), 4: (8, 16), 6: (8, 16)}
_RAW_CHANNELS = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}


def _paeth(a: int, b: int, c: int) -> int:
    p = a + b - c
    pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
    return a if pa <= pb and pa <= pc else (b if pb <= pc else c)


def _unfilter(raw: bytes, height: int, stride: int, bpp: int) -> list:
    rows, prev, pos = [], bytearray(stride), 0
    for _ in range(height):
        ft = raw[pos]
        line = bytearray(raw[pos + 1:pos + 1 + stride])
        pos += 1 + stride
        if ft == 1:
            for i in range(bpp, stride):
                line[i] = (line[i] + line[i - bpp]) & 255
        elif ft == 2:
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 255
        elif ft == 3:
            for i in range(stride):
                left = line[i - bpp] if i >= bpp else 0
                line[i] = (line[i] + ((left + prev[i]) >> 1)) & 255
        elif ft == 4:
            for i in range(stride):
                a = line[i - bpp] if i >= bpp else 0
                c = prev[i - bpp] if i >= bpp else 0
                line[i] = (line[i] + _paeth(a, prev[i], c)) & 255
        elif ft != 0:
            raise CannotRun(f"unreadable PNG: bad filter type {ft}")
        rows.append(line)
        prev = line
    return rows


def _decode_pillow(data, ct, depth, width, height, want_channels):
    Image_ = _pillow()
    if Image_ is None or (depth == 16 and ct != 0):
        return None
    try:
        im = Image_.open(io.BytesIO(data))
        im.load()
        if im.mode == "P":
            im = im.convert("RGBA" if "transparency" in im.info else "RGB")
        if depth == 16:
            if im.mode not in ("I;16", "I;16L"):
                return None
            buf = im.tobytes()
            n = width
            rows = [list(struct.unpack(f"<{n}H", buf[y * 2 * n:(y + 1) * 2 * n])) for y in range(height)]
            return Image(width, height, 1, 16, rows)
        ch = {"L": 1, "LA": 2, "RGB": 3, "RGBA": 4}.get(im.mode)
        if ch != want_channels or im.size != (width, height):
            return None
        buf, stride = im.tobytes(), width * ch
        return Image(width, height, ch, 8, [buf[y * stride:(y + 1) * stride] for y in range(height)])
    except Exception:
        return None


def read_png(path) -> Image:
    try:
        with open(path, "rb") as f:
            data = f.read()
    except OSError as e:
        raise CannotRun(f"unreadable PNG: cannot open {path}: {e}")
    return decode_png(data)


def decode_png(data: bytes) -> Image:
    ihdr, idat, plte, trns = None, [], None, None
    for kind, body in _iter_chunks(data):
        if ihdr is None and kind != b"IHDR":
            raise CannotRun("unreadable PNG: IHDR is not the first chunk")
        if kind == b"IHDR":
            if ihdr is not None or len(body) != 13:
                raise CannotRun("unreadable PNG: bad IHDR")
            ihdr = struct.unpack(">IIBBBBB", body)
        elif kind == b"IDAT":
            idat.append(body)
        elif kind == b"PLTE":
            plte = body
        elif kind == b"tRNS":
            trns = body
    if ihdr is None or not idat:
        raise CannotRun("unreadable PNG: missing IHDR or image data")
    width, height, depth, ct, comp, filt, interlace = ihdr
    if width < 1 or height < 1 or comp != 0 or filt != 0:
        raise CannotRun("unreadable PNG: bad IHDR values")
    if interlace != 0:
        raise CannotRun("unreadable PNG: interlaced PNG is not supported (re-save without interlacing)")
    if depth not in _VALID_DEPTHS.get(ct, ()):
        raise CannotRun(f"unreadable PNG: unsupported bit depth {depth} for colour type {ct}")
    raw_ch = _RAW_CHANNELS[ct]
    bps = depth // 8
    stride, bpp = width * raw_ch * bps, raw_ch * bps
    expected = height * (1 + stride)
    if expected > MAX_RAW_BYTES:
        raise CannotRun("unreadable PNG: image dimensions are implausibly large")
    if ct == 3:
        if plte is None or len(plte) % 3 or not 3 <= len(plte) <= 768:
            raise CannotRun("unreadable PNG: missing or bad PLTE palette")
        out_ch = 4 if trns is not None else 3
    else:
        out_ch = {0: 1, 2: 3, 4: 2, 6: 4}[ct]
    try:
        d = zlib.decompressobj()
        raw = d.decompress(b"".join(idat), expected + 1)
    except zlib.error as e:
        raise CannotRun(f"unreadable PNG: corrupt image data ({e})")
    if len(raw) > expected:
        raise CannotRun("unreadable PNG: image data longer than the header says")
    if len(raw) < expected or not d.eof:
        raise CannotRun("unreadable PNG: truncated image data")
    if ct != 3:  # palette files always use the stdlib path so a bad index is reported the same way
        fast = _decode_pillow(data, ct, depth, width, height, out_ch)
        if fast is not None:
            return fast
    rows = _unfilter(raw, height, stride, bpp)
    if ct == 3:
        alpha = list(trns) + [255] * (len(plte) // 3 - len(trns)) if trns is not None else None
        table = [bytes(plte[i * 3:i * 3 + 3]) + (bytes([alpha[i]]) if alpha else b"")
                 for i in range(len(plte) // 3)]
        try:
            rows = [b"".join([table[v] for v in row]) for row in rows]
        except IndexError:
            raise CannotRun("unreadable PNG: palette index out of range")
    elif depth == 16:
        n = width * raw_ch
        rows = [list(struct.unpack(f">{n}H", bytes(r))) for r in rows]
    else:
        rows = [bytes(r) for r in rows]
    return Image(width, height, out_ch, depth, rows)


def write_png(path, width, height, channels, rows, bitdepth=8, filter_type=0) -> None:
    """Write a PNG atomically. rows: `height` sequences of width*channels ints. filter_type 0-4 for tests."""
    ct = {1: 0, 2: 4, 3: 2, 4: 6}.get(channels)
    if ct is None or bitdepth not in (8, 16) or filter_type not in range(5):
        raise CannotRun(f"cannot write PNG: unsupported channels={channels} bitdepth={bitdepth} "
                        f"filter={filter_type}")
    n = width * channels
    if width < 1 or height < 1 or len(rows) != height or any(len(r) != n for r in rows):
        raise CannotRun("cannot write PNG: pixel rows do not match width, height and channels")
    bpp = channels * (bitdepth // 8)
    prev, out = bytes(n * (bitdepth // 8)), bytearray()
    try:
        for r in rows:
            cur = bytes(r) if bitdepth == 8 else struct.pack(f">{n}H", *r)
            out.append(filter_type)
            if filter_type == 0:
                out += cur
            else:
                for i, v in enumerate(cur):
                    a = cur[i - bpp] if i >= bpp else 0
                    b = prev[i]
                    c = prev[i - bpp] if i >= bpp else 0
                    pred = (0, a, b, (a + b) >> 1, _paeth(a, b, c))[filter_type]
                    out.append((v - pred) & 255)
            prev = cur
    except (ValueError, struct.error) as e:
        raise CannotRun(f"cannot write PNG: bad pixel value ({e})")
    blob = PNG_SIG + png_chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, bitdepth, ct, 0, 0, 0)) \
        + png_chunk(b"IDAT", zlib.compress(bytes(out), 6)) + png_chunk(b"IEND", b"")
    path = os.path.abspath(str(path))
    if not os.path.isdir(os.path.dirname(path)):
        raise CannotRun(f"cannot write {path}: folder does not exist")
    try:
        fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), suffix=".tmp")
        with os.fdopen(fd, "wb") as f:
            f.write(blob)
        os.replace(tmp, path)
    except OSError as e:
        raise CannotRun(f"cannot write {path}: {e}")


def luma(img: Image, stride: int = 1) -> list:
    """Rows of floats in [0, 1]: Rec. 709 weights on RGB, the value for gray, alpha ignored."""
    if stride < 1:
        raise CannotRun(f"stride must be >= 1, got {stride}")
    c, mv, w = img.channels, float(img.maxval), img.width
    wr, wg, wb = LUMA_WEIGHTS
    np = _numpy()
    rows = img.rows[::stride]
    if np is not None:
        if img.bitdepth == 8:
            arr = np.frombuffer(b"".join(bytes(r) for r in rows), dtype=np.uint8)
        else:
            arr = np.array([list(r) for r in rows], dtype=np.int64)
        arr = arr.reshape(len(rows), w, c)[:, ::stride, :].astype(np.float64)
        if c < 3:
            return (arr[:, :, 0] / mv).tolist()
        return ((wr * arr[:, :, 0] + wg * arr[:, :, 1] + wb * arr[:, :, 2]) / mv).tolist()
    step, out = c * stride, []
    for row in rows:
        if c < 3:
            out.append([v / mv for v in row[0::step]])
        else:
            out.append([(wr * r + wg * g + wb * b) / mv
                        for r, g, b in zip(row[0::step], row[1::step], row[2::step])])
    return out


def rgb8_rows(img: Image) -> list:
    """Rows of bytes (R,G,B per pixel, 8 bit): gray expanded, alpha ignored, 16 bit scaled to 8."""
    c, w, mv = img.channels, img.width, img.maxval
    out = []
    for row in img.rows:
        if img.bitdepth == 16:
            row = bytes([(v * 255 + 32767) // 65535 for v in row])
        row = bytes(row)
        if c < 3:
            plane = row[0::c]
            buf = bytearray(w * 3)
            buf[0::3] = buf[1::3] = buf[2::3] = plane
            out.append(bytes(buf))
        elif c == 3:
            out.append(row)
        else:
            buf = bytearray(w * 3)
            for k in range(3):
                buf[k::3] = row[k::4]
            out.append(bytes(buf))
    return out


def _self_test() -> int:
    with tempfile.TemporaryDirectory() as d:
        rows = [bytes([(x * 40 + y * 7 + k) % 256 for x in range(5) for k in range(4)]) for y in range(3)]
        p = os.path.join(d, "t.png")
        write_png(p, 5, 3, 4, rows)
        back = read_png(p)
        ok = (back.width, back.height, back.channels, back.bitdepth) == (5, 3, 4, 8) \
            and [bytes(r) for r in back.rows] == rows and len(luma(back)) == 3
    print("render_common: PASS self-test round-trips a PNG" if ok else "render_common: FAIL self-test mismatch")
    return PASS if ok else FAIL


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="Shared render-tool helpers (library module). "
                                 "Use --self-test to check the PNG codec; other tools import this file.")
    ap.add_argument("--self-test", action="store_true", help="write and read back a PNG; exit 0 on success")
    args = ap.parse_args(argv)
    if not args.self_test:
        error("render_common", "nothing to do: this is a library module (try --self-test)")
        return CANNOT
    try:
        return _self_test()
    except CannotRun as e:
        error("render_common", str(e))
        return CANNOT


if __name__ == "__main__":
    sys.exit(main())
