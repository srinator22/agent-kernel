#!/usr/bin/env python3
"""Verify an MP4: frame count, frame rate, resolution, duration, bitrate and codec, in pure Python.

Purpose: an encode that "finished" can still be wrong: dropped or duplicated frames, a variable frame rate
that breaks an editor, the wrong resolution, a bitrate far from the target, an unexpected codec. This tool
reads the MP4 container itself (ISO base media file format) so it works with no ffmpeg installed, and
cross-checks against ffprobe when that is on PATH.

Usage:
  python encode_verify.py FILE.mp4 [--frames N] [--fps F] [--width W --height H] [--duration-tol 0.5]
                          [--min-kbps A] [--max-kbps B] [--codec avc1|hvc1|...] [--no-ffprobe]
                          [--ffprobe-cmd JSON_LIST] [--json OUT]

Inputs:
  FILE.mp4         a non-fragmented MP4 (moov with sample tables). --fps accepts 24, 29.97 or 30000/1001.
  --codec          the fourcc of the first sample entry (avc1, hvc1, hev1, av01, ...).
  --duration-tol   allowed difference, in frames, between frames/fps and the track duration (default 0.5).
  --ffprobe-cmd    JSON list replacing the ffprobe executable (default: ffprobe found on PATH).
Parsed boxes: ftyp, moov/mvhd (v0, v1), trak/tkhd (v0, v1; width and height as 16.16), mdia/mdhd (v0, v1),
hdlr, minf/stbl/stsd (first sample entry fourcc), stts (frame count, delta set), stsz (sample count, sizes).
Box sizes: 32-bit, size 1 = 64-bit largesize, size 0 = to the end of the file. The video track is the first
track whose handler is vide. Bitrate = sum of sample sizes x 8 / track duration in seconds. Edit lists are
not applied.
Findings (exit 1): frame count differs from --frames; stts and stsz sample counts disagree; variable frame
rate (more than one distinct stts delta); fps differs from --fps by more than 0.001; resolution mismatch;
duration mismatch beyond --duration-tol frames; bitrate outside the bounds; codec mismatch; any ffprobe
disagreement or ffprobe failure.
ffprobe run: ffprobe -v error -select_streams v:0 -count_packets -show_entries
stream=codec_name,width,height,r_frame_rate,nb_read_packets -of json FILE. When it is absent the line
"ffprobe not on PATH; parser only" is printed; that is not a failure.
Outputs: `encode_verify: info:` and `encode_verify: finding:` lines, then a summary line
`encode_verify: PASS ...` or `encode_verify: FAIL n finding(s) ...`. --json writes a machine report.
Exit codes: 0 pass, 1 findings, 2 could not run: not a file, no ftyp or moov, a moof box or mvex (fragmented
MP4 is not supported), no video track, a missing sample table, a truncated box, bad arguments.
Dependencies: Python 3.10+ standard library (ffprobe optional).
Assumptions: the file fits the single-moov layout written by common encoders; moov is read into memory, the
media data is only skipped over, so large files are fine.
Origin: new (no prior source).
"""

from __future__ import annotations

import argparse
import json
import math
import os
import shutil
import struct
import subprocess
import sys

TOOL = "encode_verify"
MAX_MOOV_BYTES = 512 * 1024 * 1024
FPS_TOL = 0.001
FFPROBE_NAMES = {"avc1": "h264", "avc3": "h264", "hvc1": "hevc", "hev1": "hevc", "av01": "av1",
                 "vp09": "vp9", "mp4v": "mpeg4"}


class Mp4Error(Exception):
    """The file cannot be verified (exit 2)."""


def err(message: str) -> None:
    print(f"{TOOL}: ERROR {message}", file=sys.stderr)


def iter_boxes(buf: bytes, start: int, end: int):
    """Yield (type bytes, payload start, box end) for the boxes in buf[start:end]."""
    pos = start
    while pos < end:
        if end - pos < 8:
            if not any(buf[pos:end]):
                return  # zero padding / QuickTime terminator
            raise Mp4Error(f"truncated box header at offset {pos}")
        size, typ = struct.unpack_from(">I4s", buf, pos)
        header = 8
        if size == 1:
            if end - pos < 16:
                raise Mp4Error(f"truncated largesize header at offset {pos}")
            size = struct.unpack_from(">Q", buf, pos + 8)[0]
            header = 16
        elif size == 0:
            size = end - pos
        if size < header:
            raise Mp4Error(f"invalid box size {size} for '{typ.decode('latin-1')}' at offset {pos}")
        if pos + size > end:
            raise Mp4Error(f"truncated box '{typ.decode('latin-1')}' at offset {pos}: "
                           f"needs {size} bytes, {end - pos} available")
        yield typ, pos + header, pos + size
        pos += size


def child(buf: bytes, start: int, end: int, typ: bytes):
    for t, ps, pe in iter_boxes(buf, start, end):
        if t == typ:
            return ps, pe
    return None


def need(buf: bytes, ps: int, pe: int, length: int, what: str) -> None:
    if pe - ps < length:
        raise Mp4Error(f"truncated {what} box: {pe - ps} bytes, needs {length}")


def read_top_level(path: str) -> tuple[bytes, bytes]:
    """Returns (ftyp payload, moov payload). Skips media data without reading it."""
    size = os.path.getsize(path)
    ftyp = moov = None
    with open(path, "rb") as fh:
        pos = 0
        while pos < size:
            fh.seek(pos)
            head = fh.read(8)
            if len(head) < 8:
                if not any(head):
                    break
                raise Mp4Error(f"truncated box header at offset {pos}")
            length, typ = struct.unpack(">I4s", head)
            header = 8
            if length == 1:
                ext = fh.read(8)
                if len(ext) < 8:
                    raise Mp4Error(f"truncated largesize header at offset {pos}")
                length = struct.unpack(">Q", ext)[0]
                header = 16
            elif length == 0:
                length = size - pos
            name = typ.decode("latin-1")
            if length < header:
                raise Mp4Error(f"invalid box size {length} for '{name}' at offset {pos}")
            if pos + length > size:
                raise Mp4Error(f"truncated box '{name}' at offset {pos}: needs {length} bytes, "
                               f"{size - pos} in the file")
            if typ in (b"moof", b"mfra"):
                raise Mp4Error(f"'{name}' box found: fragmented MP4 is not supported")
            if typ == b"ftyp" and ftyp is None:
                fh.seek(pos + header)
                ftyp = fh.read(min(length - header, 4096))
            elif typ == b"moov" and moov is None:
                if length - header > MAX_MOOV_BYTES:
                    raise Mp4Error(f"moov box of {length} bytes is implausibly large")
                fh.seek(pos + header)
                moov = fh.read(length - header)
            pos += length
    if ftyp is None:
        raise Mp4Error("no ftyp box: not an MP4 file")
    if moov is None:
        raise Mp4Error("no moov box: the file has no sample tables (unfinished or not an MP4)")
    return ftyp, moov


def time_header(buf: bytes, ps: int, pe: int, what: str) -> tuple[int, int]:
    """(timescale, duration) of an mvhd or mdhd box."""
    need(buf, ps, pe, 4, what)
    version = buf[ps]
    if version == 0:
        need(buf, ps, pe, 20, what)
        return struct.unpack_from(">II", buf, ps + 12)
    if version == 1:
        need(buf, ps, pe, 32, what)
        ts = struct.unpack_from(">I", buf, ps + 20)[0]
        return ts, struct.unpack_from(">Q", buf, ps + 24)[0]
    raise Mp4Error(f"unsupported {what} version {version}")


def parse_track(buf: bytes, ps: int, pe: int) -> dict | None:
    """Returns the video track facts, or None when the track is not video."""
    mdia = child(buf, ps, pe, b"mdia")
    if mdia is None:
        return None
    hdlr = child(buf, *mdia, b"hdlr")
    if hdlr is None:
        return None
    need(buf, *hdlr, 12, "hdlr")
    if buf[hdlr[0] + 8:hdlr[0] + 12] != b"vide":
        return None
    tkhd = child(buf, ps, pe, b"tkhd")
    mdhd = child(buf, *mdia, b"mdhd")
    minf = child(buf, *mdia, b"minf")
    stbl = child(buf, *minf, b"stbl") if minf else None
    if not (tkhd and mdhd and stbl):
        raise Mp4Error("video track lacks tkhd, mdhd or stbl")
    need(buf, *tkhd, 4, "tkhd")
    offset = {0: 76, 1: 88}.get(buf[tkhd[0]])
    if offset is None:
        raise Mp4Error(f"unsupported tkhd version {buf[tkhd[0]]}")
    need(buf, *tkhd, offset + 8, "tkhd")
    width, height = struct.unpack_from(">II", buf, tkhd[0] + offset)
    timescale, duration = time_header(buf, *mdhd, "mdhd")
    if timescale == 0:
        raise Mp4Error("mdhd timescale is zero")
    stsd, stts, stsz = (child(buf, *stbl, t) for t in (b"stsd", b"stts", b"stsz"))
    if not (stsd and stts and stsz):
        raise Mp4Error("video track lacks stsd, stts or stsz (stz2 is not supported)")
    need(buf, *stsd, 16, "stsd")
    if struct.unpack_from(">I", buf, stsd[0] + 4)[0] < 1:
        raise Mp4Error("stsd has no sample entry")
    codec = buf[stsd[0] + 12:stsd[0] + 16].decode("latin-1")
    need(buf, *stts, 8, "stts")
    n = struct.unpack_from(">I", buf, stts[0] + 4)[0]
    need(buf, *stts, 8 + 8 * n, "stts")
    pairs = struct.unpack_from(f">{2 * n}I", buf, stts[0] + 8)
    entries = [(pairs[i], pairs[i + 1]) for i in range(0, 2 * n, 2)]
    need(buf, *stsz, 12, "stsz")
    fixed, count = struct.unpack_from(">II", buf, stsz[0] + 4)
    if fixed:
        total_bytes = fixed * count
    else:
        need(buf, *stsz, 12 + 4 * count, "stsz")
        total_bytes = sum(struct.unpack_from(f">{count}I", buf, stsz[0] + 12))
    return {"width": width / 65536.0, "height": height / 65536.0, "timescale": timescale,
            "duration": duration, "codec": codec, "stts": entries, "stsz_count": count,
            "bytes": total_bytes}


def parse_mp4(path: str) -> dict:
    if not os.path.isfile(path):
        raise Mp4Error(f"not a file: {path}")
    ftyp, moov = read_top_level(path)
    brand = ftyp[:4].decode("latin-1") if len(ftyp) >= 4 else ""
    if child(moov, 0, len(moov), b"mvex"):
        raise Mp4Error("mvex box found: fragmented MP4 is not supported")
    mvhd = child(moov, 0, len(moov), b"mvhd")
    movie_ts, movie_dur = time_header(moov, *mvhd, "mvhd") if mvhd else (0, 0)
    video = None
    for typ, ps, pe in iter_boxes(moov, 0, len(moov)):
        if typ == b"trak":
            video = parse_track(moov, ps, pe)
            if video:
                break
    if video is None:
        raise Mp4Error("no video track (no trak with a vide handler)")
    video["brand"] = brand
    video["movie_timescale"], video["movie_duration"] = movie_ts, movie_dur
    return video


def parse_rate(text: str) -> float:
    try:
        if "/" in text:
            num, den = text.split("/", 1)
            value = float(num) / float(den)
        else:
            value = float(text)
    except (ValueError, ZeroDivisionError):
        raise argparse.ArgumentTypeError(f"not a frame rate: {text}")
    if not (math.isfinite(value) and value > 0):
        raise argparse.ArgumentTypeError(f"frame rate must be positive: {text}")
    return value


def facts_from(track: dict) -> dict:
    frames = sum(c for c, _ in track["stts"])
    total_delta = sum(c * d for c, d in track["stts"])
    deltas = sorted({d for c, d in track["stts"] if c > 0})
    ts = track["timescale"]
    media_seconds = track["duration"] / ts
    seconds = media_seconds if media_seconds > 0 else total_delta / ts
    fps = frames * ts / total_delta if total_delta else None
    return {"frames_stts": frames, "frames_stsz": track["stsz_count"], "deltas": deltas, "fps": fps,
            "width": track["width"], "height": track["height"], "codec": track["codec"],
            "brand": track["brand"], "timescale": ts, "media_seconds": media_seconds,
            "stts_seconds": total_delta / ts, "bytes": track["bytes"],
            "kbps": (track["bytes"] * 8 / seconds / 1000.0) if seconds > 0 else None}


def check(facts: dict, args) -> list[str]:
    findings = []
    frames = facts["frames_stts"]
    if facts["frames_stts"] != facts["frames_stsz"]:
        findings.append(f"stts counts {facts['frames_stts']} samples but stsz counts {facts['frames_stsz']}")
    if args.frames is not None and frames != args.frames:
        findings.append(f"frame count {frames}, expected {args.frames}")
    if len(facts["deltas"]) > 1:
        findings.append(f"variable frame rate: {len(facts['deltas'])} distinct frame durations "
                        f"{facts['deltas']} (timescale {facts['timescale']})")
    fps = facts["fps"]
    if fps is None:
        findings.append("stts holds no frame durations; the frame rate cannot be computed")
    elif args.fps is not None and abs(fps - args.fps) > FPS_TOL:
        findings.append(f"fps {fps:.4f}, expected {args.fps:.4f}")
    ref = args.fps or fps
    if ref:
        diff = abs(facts["media_seconds"] - frames / ref) * ref
        if diff > args.duration_tol:
            findings.append(f"duration {facts['media_seconds']:.4f} s differs from {frames} frames at "
                            f"{ref:.4f} fps ({frames / ref:.4f} s) by {diff:.2f} frame(s), "
                            f"tolerance {args.duration_tol}")
    for label, got, want in (("width", facts["width"], args.width), ("height", facts["height"], args.height)):
        if want is not None and got != want:
            findings.append(f"{label} {got:g}, expected {want}")
    if (args.min_kbps is not None or args.max_kbps is not None):
        kbps = facts["kbps"]
        if kbps is None:
            findings.append("bitrate cannot be computed (zero duration)")
        else:
            if args.min_kbps is not None and kbps < args.min_kbps:
                findings.append(f"bitrate {kbps:.1f} kbps is below the minimum {args.min_kbps:g}")
            if args.max_kbps is not None and kbps > args.max_kbps:
                findings.append(f"bitrate {kbps:.1f} kbps is above the maximum {args.max_kbps:g}")
    if args.codec and facts["codec"].strip() != args.codec.strip():
        findings.append(f"codec {facts['codec']}, expected {args.codec}")
    return findings


def run_ffprobe(cmd: list[str], path: str, facts: dict) -> tuple[list[str], dict | None]:
    argv = cmd + ["-v", "error", "-select_streams", "v:0", "-count_packets", "-show_entries",
                  "stream=codec_name,width,height,r_frame_rate,nb_read_packets", "-of", "json", path]
    try:
        done = subprocess.run(argv, capture_output=True, text=True, timeout=120, stdin=subprocess.DEVNULL)
    except (OSError, subprocess.TimeoutExpired) as exc:
        return [f"ffprobe could not run: {exc}"], None
    if done.returncode != 0:
        return [f"ffprobe failed (rc {done.returncode}): {done.stderr.strip()[:200]}"], None
    try:
        stream = json.loads(done.stdout)["streams"][0]
    except (ValueError, KeyError, IndexError, TypeError):
        return ["ffprobe output has no video stream"], None
    findings = []
    try:
        if int(stream["width"]) != int(facts["width"]) or int(stream["height"]) != int(facts["height"]):
            findings.append(f"ffprobe resolution {stream['width']}x{stream['height']} differs from "
                            f"parser {facts['width']:g}x{facts['height']:g}")
        if int(stream["nb_read_packets"]) != facts["frames_stts"]:
            findings.append(f"ffprobe counts {stream['nb_read_packets']} packets, parser {facts['frames_stts']}")
        if len(facts["deltas"]) == 1 and facts["fps"]:
            rate = parse_rate(str(stream["r_frame_rate"]))
            if abs(rate - facts["fps"]) > FPS_TOL:
                findings.append(f"ffprobe r_frame_rate {stream['r_frame_rate']} differs from parser "
                                f"{facts['fps']:.4f}")
    except (KeyError, ValueError, TypeError, argparse.ArgumentTypeError) as exc:
        findings.append(f"ffprobe output unusable: {exc}")
    want = FFPROBE_NAMES.get(facts["codec"].strip())
    if want and stream.get("codec_name") not in (None, want):
        findings.append(f"ffprobe codec {stream.get('codec_name')} differs from parser {facts['codec']}")
    return findings, stream


def make_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="encode_verify.py",
        description="Verify an MP4 with a pure-Python parser (and ffprobe when available): frame count, fps, "
                    "resolution, duration, bitrate, codec. Exit: 0 pass, 1 findings, 2 could not run.")
    p.add_argument("file", help="the .mp4 to verify")
    p.add_argument("--frames", type=int)
    p.add_argument("--fps", type=parse_rate, help="24, 29.97 or 30000/1001")
    p.add_argument("--width", type=int)
    p.add_argument("--height", type=int)
    p.add_argument("--duration-tol", type=float, default=0.5, help="frames (default 0.5)")
    p.add_argument("--min-kbps", type=float)
    p.add_argument("--max-kbps", type=float)
    p.add_argument("--codec", help="first sample entry fourcc, e.g. avc1 or hvc1")
    p.add_argument("--no-ffprobe", action="store_true")
    p.add_argument("--ffprobe-cmd", help="JSON list replacing the ffprobe executable")
    p.add_argument("--json", help="write a machine report here")
    return p


def main(argv=None) -> int:
    args = make_parser().parse_args(argv)
    if args.duration_tol < 0 or (args.frames is not None and args.frames < 0):
        err("--duration-tol and --frames must not be negative")
        return 2
    if args.min_kbps is not None and args.max_kbps is not None and args.min_kbps > args.max_kbps:
        err("--min-kbps is larger than --max-kbps")
        return 2
    ffprobe = None
    if not args.no_ffprobe:
        if args.ffprobe_cmd:
            try:
                ffprobe = json.loads(args.ffprobe_cmd)
                if not isinstance(ffprobe, list) or not ffprobe or not all(isinstance(x, str) for x in ffprobe):
                    raise ValueError("must be a non-empty list of strings")
            except ValueError as exc:
                err(f"--ffprobe-cmd: {exc}")
                return 2
        elif shutil.which("ffprobe"):
            ffprobe = [shutil.which("ffprobe")]
    try:
        facts = facts_from(parse_mp4(args.file))
    except (Mp4Error, struct.error) as exc:
        err(str(exc))
        return 2
    except OSError as exc:
        err(f"cannot read {args.file}: {exc}")
        return 2
    findings = check(facts, args)
    fps_text = f"{facts['fps']:.4f}".rstrip("0").rstrip(".") if facts["fps"] else "unknown"
    print(f"{TOOL}: info: {facts['frames_stts']} frames, {fps_text} fps, {facts['width']:g}x{facts['height']:g}, "
          f"codec {facts['codec']}, brand {facts['brand'].strip()}")
    kbps = f"{facts['kbps']:.1f} kbps" if facts["kbps"] is not None else "bitrate unknown"
    print(f"{TOOL}: info: duration {facts['media_seconds']:.4f} s, {facts['bytes']} sample bytes, {kbps}")
    probe_note = "parser only"
    stream = None
    if args.no_ffprobe:
        print(f"{TOOL}: info: ffprobe skipped (--no-ffprobe)")
    elif ffprobe is None:
        print(f"{TOOL}: info: ffprobe not on PATH; parser only")
    else:
        extra, stream = run_ffprobe(ffprobe, args.file, facts)
        findings += extra
        probe_note = "ffprobe cross-checked"
    for f in findings:
        print(f"{TOOL}: finding: {f}")
    status = "pass" if not findings else "fail"
    if args.json:
        try:
            with open(args.json, "w", encoding="utf-8") as fh:
                json.dump({"tool": TOOL, "status": status, "findings": findings, "file": args.file,
                           "facts": facts, "ffprobe": stream, "ffprobe_used": stream is not None}, fh, indent=2)
                fh.write("\n")
        except OSError as exc:
            err(f"cannot write {args.json}: {exc}")
            return 2
    tail = f"frames={facts['frames_stts']} fps={fps_text} {facts['width']:g}x{facts['height']:g} " \
           f"codec={facts['codec']} ({probe_note})"
    if findings:
        print(f"{TOOL}: FAIL {len(findings)} finding(s) {tail}")
        return 1
    print(f"{TOOL}: PASS {tail}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
