#!/usr/bin/env python3
"""Encode a numbered image sequence to an H.264 MP4 inside Blender (video sequencer), with optional label overlay.

Purpose: turn rendered frames into a video with Blender's built-in FFmpeg (no separate ffmpeg install) and,
optionally, burn in the text track written by render_overlay. The plan (what gets encoded, which strips) is
built by pure Python and tested without Blender; `apply_plan` runs it in Blender.
Usage (inside Blender, normally through blender_run):
  blender -b --factory-startup --python-exit-code 1 -P render_encode.py -- --frames ABS_DIR
      --pattern frame_####.png --first N --last M --fps F --out ABS.mp4 [--view-transform Standard]
      [--quality HIGH|MEDIUM|LOSSLESS] [--overlay track.json] [--size W H] [--allow-in-repo] [--dry-run]
Inputs: frames DIR/pattern for first..last (all must exist); optional overlay track JSON
  {"fps", "resolution", "font_px"(optional), "items": [{"id", "text", "frames": [{"frame", "x", "y", "w", "h",
  "opacity"}]}], "title": {"text", "in", "hold_s", "out"(optional), "x"/"y"(optional, top-left px),
  "frames"(optional, same shape as an item)}}. Frame numbers are the render's; frame `first` is encoded as
  video frame 1. x, y are the top-left of the text box in pixels, y down.
Outputs: the MP4 at --out (absolute, outside any git work tree unless --allow-in-repo); prints
  `ENCODED <path> <n> frames`. --dry-run prints the plan as JSON and needs no Blender.
View transform: the default is Standard because the input PNGs are display-referred (the render already
applied the view transform), so the encode scene must not apply AgX or Filmic a second time (the
double-transform trap: washed, flat video). Scene-linear input (EXR) needs the render's transform instead and
must be passed explicitly with --view-transform.
Quality: HIGH and MEDIUM are the constant-rate-factor presets of the same name; LOSSLESS maps to the
perceptually lossless preset (true lossless H.264 is poorly supported by players).
Exit codes: 0 encoded (or dry run), 2 could not run (missing frames, bad arguments, not inside Blender).
An uncaught Python error exits 1 through --python-exit-code.
Dependencies: Python 3.10+ standard library; bpy inside Blender (imported only in apply_plan).
Assumptions: PNG size is read from the first frame's IHDR; other formats need --size. Audio is off.
Origin: generic port of the encode script of a product film project (view transform made a parameter).
"""

from __future__ import annotations

import argparse
import json
import math
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import render_common as rc  # noqa: E402

TOOL = "render_encode"
QUALITY = {"HIGH": "HIGH", "MEDIUM": "MEDIUM", "LOSSLESS": "PERC_LOSSLESS"}
DEFAULT_VIEW_TRANSFORM = "Standard"


def png_size(path) -> tuple:
    try:
        with open(path, "rb") as fh:
            head = fh.read(24)
    except OSError as e:
        raise rc.CannotRun(f"cannot read {path}: {e}")
    if head[:8] != rc.PNG_SIG or head[12:16] != b"IHDR":
        raise rc.CannotRun(f"cannot read the size of {path}: not a PNG (pass --size W H)")
    w, h = struct.unpack(">II", head[16:24])
    if w < 1 or h < 1:
        raise rc.CannotRun(f"{path}: bad PNG size {w}x{h}")
    return w, h


def load_track(path) -> dict:
    try:
        with open(path, "r", encoding="utf-8") as fh:
            track = json.load(fh)
    except (OSError, ValueError) as e:
        raise rc.CannotRun(f"cannot read overlay track {path}: {e}")
    if not isinstance(track, dict) or not isinstance(track.get("items", []), list):
        raise rc.CannotRun(f"overlay track {path}: expected an object with an 'items' list")
    return track


def _keys_from_frames(frames, first, last, size, where):
    keys = []
    for fr in frames:
        try:
            n = int(fr["frame"])
            x, y, w, h = (float(fr[k]) for k in ("x", "y", "w", "h"))
            op = float(fr.get("opacity", 1.0))
        except (KeyError, TypeError, ValueError):
            raise rc.CannotRun(f"overlay {where}: each frame needs numeric frame, x, y, w, h (opacity optional)")
        if first <= n <= last:
            keys.append({"frame": n - first + 1, "x": x / size[0], "y": 1.0 - y / size[1],
                         "opacity": min(1.0, max(0.0, op)), "h_px": h})
    keys.sort(key=lambda k: k["frame"])
    return keys


def _text_strip(name, text, keys, font_px, channel):
    return {"kind": "text", "name": name, "text": str(text), "channel": channel, "frame_start": keys[0]["frame"],
            "length": keys[-1]["frame"] - keys[0]["frame"] + 1, "font_size": int(round(font_px)),
            "keys": [{k: v for k, v in key.items() if k != "h_px"} for key in keys]}


def overlay_strips(track, first, last, fps, size) -> tuple:
    """(strips, warnings) for the text strips of a track. Frames outside first..last are dropped."""
    warnings, strips, channel = [], [], 2
    if track.get("fps") is not None and abs(float(track["fps"]) - fps) > 1e-9:
        warnings.append(f"overlay fps {track['fps']} differs from encode fps {fps}")
    res = track.get("resolution")
    if res and [int(res[0]), int(res[1])] != [size[0], size[1]]:
        warnings.append(f"overlay resolution {res} differs from the video size {list(size)}; positions are "
                        "scaled by the track's own resolution")
    tsize = (float(res[0]), float(res[1])) if res else (float(size[0]), float(size[1]))
    for item in track.get("items", []):
        keys = _keys_from_frames(item.get("frames", []), first, last, tsize, f"item {item.get('id')!r}")
        if not keys:
            warnings.append(f"overlay item {item.get('id')!r} has no frames inside {first}-{last}; skipped")
            continue
        font = float(track.get("font_px") or keys[0]["h_px"] / 1.2)
        strips.append(_text_strip(f"label_{item.get('id', len(strips))}", item.get("text", ""), keys, font, channel))
        channel += 1
    title = track.get("title")
    if isinstance(title, dict) and title.get("text"):
        frames = title.get("frames")
        if frames is None:
            try:
                t_in = int(title["in"])
                t_out = int(title["out"]) if title.get("out") is not None else t_in + int(round(float(title["hold_s"]) * fps))
            except (KeyError, TypeError, ValueError):
                raise rc.CannotRun("overlay title needs 'in' and either 'out' or 'hold_s'")
            x = float(title.get("x", tsize[0] * 0.1))
            y = float(title.get("y", tsize[1] * 0.45))
            h = float(track.get("font_px", 48)) * 1.2
            frames = [{"frame": f, "x": x, "y": y, "w": tsize[0] * 0.8, "h": h, "opacity": 1.0}
                      for f in range(t_in, t_out + 1)]
        keys = _keys_from_frames(frames, first, last, tsize, "title")
        if keys:
            strips.append(_text_strip("title", title["text"], keys, float(track.get("font_px") or keys[0]["h_px"] / 1.2), channel))
        else:
            warnings.append(f"overlay title has no frames inside {first}-{last}; skipped")
    return strips, warnings


def plan_encode(args) -> dict:
    """Pure: validate the inputs and build the plan dict that apply_plan executes. Raises CannotRun."""
    frames_dir = rc.require_abs(args.frames, "--frames")
    rc.require_abs(args.out, "--out")
    if args.first < 0 or args.last < args.first:
        raise rc.CannotRun(f"bad frame range --first {args.first} --last {args.last}")
    if not args.fps or args.fps <= 0:
        raise rc.CannotRun("--fps must be > 0")
    if not str(args.out).lower().endswith(".mp4"):
        raise rc.CannotRun(f"--out must end in .mp4, got {args.out}")
    if not os.path.isdir(frames_dir):
        raise rc.CannotRun(f"frames folder not found: {frames_dir}")
    if args.quality not in QUALITY:
        raise rc.CannotRun(f"--quality must be one of {', '.join(QUALITY)}")
    if not (args.view_transform or "").strip():
        raise rc.CannotRun("--view-transform must not be empty")
    warnings = list(rc.check_output_path(args.out, "--out", getattr(args, "allow_in_repo", False)))
    nums = list(range(args.first, args.last + 1))
    paths = {n: rc.frame_path(frames_dir, args.pattern, n) for n in nums}
    missing = [n for n in nums if not os.path.isfile(paths[n])]
    if missing:
        raise rc.CannotRun(f"{len(missing)} frame(s) missing in {frames_dir} matching {args.pattern}: "
                           f"{rc.format_ranges(missing)}")
    src_size = png_size(paths[args.first]) if args.size is None or args.pattern.lower().endswith(".png") else None
    size = tuple(args.size) if args.size else src_size
    if args.size and (args.size[0] < 1 or args.size[1] < 1):
        raise rc.CannotRun("--size must be positive")
    fit = "FIT" if src_size is not None and tuple(size) != tuple(src_size) else "ORIGINAL"
    strips = [{"kind": "image", "name": "frames", "channel": 1, "frame_start": 1,
               "first_file": os.path.basename(paths[args.first]),
               "files": [os.path.basename(paths[n]) for n in nums], "fit_method": fit}]
    if args.overlay:
        extra, more = overlay_strips(load_track(args.overlay), args.first, args.last, args.fps, size)
        strips += extra
        warnings += more
    return {"frames_dir": frames_dir, "pattern": args.pattern, "first": args.first, "last": args.last,
            "count": len(nums), "fps": args.fps, "out": args.out, "size": [int(size[0]), int(size[1])],
            "view_transform": args.view_transform, "quality": args.quality, "crf": QUALITY[args.quality],
            "strips": strips, "warnings": warnings}


def apply_plan(plan) -> None:
    """Blender side: build a scene with the strips and render the animation to plan['out']."""
    import bpy
    import blender_compat as compat
    sc = bpy.data.scenes.new("encode")
    compat.activate_scene(bpy.context, sc)  # best effort: 5.x still renders of a non-window scene stay on frame 1
    r = sc.render
    r.resolution_x, r.resolution_y, r.resolution_percentage = plan["size"][0], plan["size"][1], 100
    r.fps = int(math.ceil(plan["fps"] - 1e-9))
    r.fps_base = r.fps / plan["fps"]
    sc.frame_start, sc.frame_end = 1, plan["count"]
    sc.view_settings.view_transform = plan["view_transform"]
    sc.view_settings.look = "None"
    sc.view_settings.exposure, sc.view_settings.gamma = 0.0, 1.0
    sc.display_settings.display_device = "sRGB"
    if hasattr(r, "use_sequencer"):
        r.use_sequencer = True
    strips = compat.vse_strips(sc)
    for s in plan["strips"]:
        if s["kind"] == "image":
            path = os.path.join(plan["frames_dir"], s["first_file"])
            strip = strips.new_image(s["name"], path, channel=s["channel"], frame_start=s["frame_start"],
                                     fit_method=s["fit_method"])
            for f in s["files"][1:]:
                strip.elements.append(f)
            continue
        strip = strips.new_effect(s["name"], "TEXT", s["channel"], s["frame_start"], length=s["length"])
        strip.text = s["text"]
        strip.font_size = s["font_size"]
        strip.color = (1.0, 1.0, 1.0, 1.0)
        if hasattr(strip, "anchor_x"):
            strip.anchor_x, strip.anchor_y = "LEFT", "TOP"
        strip.use_shadow = True
        for k in s["keys"]:
            strip.location = (k["x"], k["y"])
            strip.blend_alpha = k["opacity"]
            strip.keyframe_insert("location", frame=k["frame"])
            strip.keyframe_insert("blend_alpha", frame=k["frame"])
    compat.set_video_output(r.image_settings, r.ffmpeg, "MPEG4", "H264", plan["crf"], preset="BEST")
    r.ffmpeg.audio_codec = "NONE"
    r.filepath = plan["out"]
    os.makedirs(os.path.dirname(plan["out"]), exist_ok=True)
    bpy.ops.render.render(animation=True, scene=sc.name)
    if not os.path.isfile(plan["out"]):
        raise RuntimeError(f"render finished but {plan['out']} was not written")
    print(f"ENCODED {plan['out']} {plan['count']} frames", flush=True)


def make_parser() -> argparse.ArgumentParser:
    ap = argparse.ArgumentParser(
        prog="render_encode.py",
        description="Run inside Blender (blender -b --factory-startup --python-exit-code 1 -P render_encode.py "
                    "-- ARGS, normally through blender_run): encode a numbered image sequence to an H.264 MP4 "
                    "with Blender's FFmpeg, optionally with the render_overlay text track. "
                    "--view-transform defaults to Standard because input PNGs are display-referred (the render "
                    "already applied AgX or Filmic), so encoding must not apply a transform again (the "
                    "double-transform trap); EXR scene-linear input needs the render's transform, passed "
                    "explicitly.")
    ap.add_argument("--frames", required=True, help="absolute folder holding the frames")
    ap.add_argument("--pattern", required=True, help="frame file name with one run of # (frame_####.png)")
    ap.add_argument("--first", type=int, required=True)
    ap.add_argument("--last", type=int, required=True)
    ap.add_argument("--fps", type=float, required=True)
    ap.add_argument("--out", required=True, help="absolute path of the .mp4 to write")
    ap.add_argument("--view-transform", default=DEFAULT_VIEW_TRANSFORM, dest="view_transform",
                    help="view transform of the encode scene (default Standard, see above)")
    ap.add_argument("--quality", default="HIGH", choices=list(QUALITY), help="HIGH (default), MEDIUM or LOSSLESS")
    ap.add_argument("--overlay", help="overlay track JSON from render_overlay")
    ap.add_argument("--size", type=int, nargs=2, metavar=("W", "H"), help="video size (default: first frame)")
    ap.add_argument("--allow-in-repo", action="store_true", dest="allow_in_repo",
                    help="allow --out inside a git work tree")
    ap.add_argument("--dry-run", action="store_true", dest="dry_run", help="print the plan as JSON, do not encode")
    return ap


def main(argv=None) -> int:
    argv = list(sys.argv if argv is None else argv)
    args = make_parser().parse_args(argv[argv.index("--") + 1:] if "--" in argv else argv[1:])
    try:
        plan = plan_encode(args)
        for w in plan["warnings"]:
            print(f"{TOOL}: warning: {w}", file=sys.stderr)
        if args.dry_run:
            print(json.dumps(plan, indent=2))
            return rc.PASS
        try:
            import bpy  # noqa: F401
        except ImportError:
            raise rc.CannotRun("bpy is not available: run this script inside Blender (see blender_run)")
        apply_plan(plan)
    except rc.CannotRun as e:
        rc.error(TOOL, str(e))
        return rc.CANNOT
    return rc.PASS


if __name__ == "__main__":
    sys.exit(main())
