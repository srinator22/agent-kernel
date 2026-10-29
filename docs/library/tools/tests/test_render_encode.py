"""Tests for render_encode.py: the pure plan only (no Blender). The Blender side is exercised by the procedure."""
import contextlib
import io
import json
import os
import subprocess
import sys
import tempfile
import types
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import render_common as rc  # noqa: E402
import render_encode as re_  # noqa: E402

TOOL = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "render_encode.py")
W, H = 32, 18


def ns(**kw):
    base = dict(frames=None, pattern="frame_####.png", first=1, last=6, fps=24.0, out=None,
                view_transform="Standard", quality="HIGH", overlay=None, size=None, allow_in_repo=False,
                dry_run=False)
    base.update(kw)
    return types.SimpleNamespace(**base)


class PlanCase(unittest.TestCase):
    def setUp(self):
        self._td = tempfile.TemporaryDirectory()
        self.addCleanup(self._td.cleanup)
        self.d = os.path.realpath(self._td.name)
        self.frames = os.path.join(self.d, "frames")
        os.makedirs(self.frames)
        self.out = os.path.join(self.d, "out", "film.mp4")
        for i in range(1, 7):
            rc.write_png(os.path.join(self.frames, f"frame_{i:04d}.png"), W, H, 3,
                         [bytes([i * 10] * (W * 3)) for _ in range(H)])

    def args(self, **kw):
        base = dict(frames=self.frames, out=self.out)
        base.update(kw)
        return ns(**base)

    def track(self, data, name="track.json"):
        p = os.path.join(self.d, name)
        with open(p, "w") as fh:
            json.dump(data, fh)
        return p


class BasicPlanTests(PlanCase):
    def test_plan_basics(self):
        p = re_.plan_encode(self.args())
        self.assertEqual((p["count"], p["size"], p["fps"], p["out"]), (6, [W, H], 24.0, self.out))
        self.assertEqual((p["view_transform"], p["quality"], p["crf"]), ("Standard", "HIGH", "HIGH"))
        self.assertEqual(len(p["strips"]), 1)
        s = p["strips"][0]
        self.assertEqual((s["kind"], s["channel"], s["frame_start"], s["fit_method"]), ("image", 1, 1, "ORIGINAL"))
        self.assertEqual(s["files"], [f"frame_{i:04d}.png" for i in range(1, 7)])
        self.assertEqual(s["first_file"], "frame_0001.png")
        self.assertEqual(p["warnings"], [])

    def test_default_view_transform_is_standard_and_documented(self):
        self.assertEqual(re_.DEFAULT_VIEW_TRANSFORM, "Standard")
        self.assertEqual(re_.make_parser().get_default("view_transform"), "Standard")
        self.assertIn("double-transform", re_.make_parser().description)
        self.assertEqual(re_.plan_encode(self.args(view_transform="AgX"))["view_transform"], "AgX")

    def test_subrange_is_renumbered_from_one(self):
        p = re_.plan_encode(self.args(first=3, last=5))
        self.assertEqual((p["count"], p["strips"][0]["files"][0], p["strips"][0]["first_file"]),
                         (3, "frame_0003.png", "frame_0003.png"))

    def test_quality_mapping(self):
        self.assertEqual(re_.plan_encode(self.args(quality="MEDIUM"))["crf"], "MEDIUM")
        self.assertEqual(re_.plan_encode(self.args(quality="LOSSLESS"))["crf"], "PERC_LOSSLESS")
        with self.assertRaises(rc.CannotRun):
            re_.plan_encode(self.args(quality="ULTRA"))

    def test_size_override_uses_fit(self):
        p = re_.plan_encode(self.args(size=[64, 36]))
        self.assertEqual((p["size"], p["strips"][0]["fit_method"]), ([64, 36], "FIT"))
        self.assertEqual(re_.plan_encode(self.args(size=[W, H]))["strips"][0]["fit_method"], "ORIGINAL")

    def test_non_png_needs_size(self):
        for i in range(1, 7):
            with open(os.path.join(self.frames, f"x_{i:04d}.exr"), "wb") as fh:
                fh.write(b"EXR")
        with self.assertRaises(rc.CannotRun):
            re_.plan_encode(self.args(pattern="x_####.exr"))
        p = re_.plan_encode(self.args(pattern="x_####.exr", size=[W, H], view_transform="AgX"))
        self.assertEqual(p["size"], [W, H])

    def test_fractional_fps_kept(self):
        self.assertAlmostEqual(re_.plan_encode(self.args(fps=23.976))["fps"], 23.976)


class RefusalTests(PlanCase):
    def test_missing_frames_listed(self):
        os.remove(os.path.join(self.frames, "frame_0003.png"))
        os.remove(os.path.join(self.frames, "frame_0004.png"))
        os.remove(os.path.join(self.frames, "frame_0006.png"))
        with self.assertRaises(rc.CannotRun) as cm:
            re_.plan_encode(self.args())
        self.assertIn("3 frame(s) missing", str(cm.exception))
        self.assertIn("3-4, 6", str(cm.exception))

    def test_relative_paths_refused(self):
        with self.assertRaises(rc.CannotRun):
            re_.plan_encode(ns(frames=self.frames, out="film.mp4"))
        with self.assertRaises(rc.CannotRun):
            re_.plan_encode(ns(frames="frames", out=self.out))

    def test_output_inside_git_worktree_refused_unless_allowed(self):
        os.makedirs(os.path.join(self.d, "repo", ".git"))
        out = os.path.join(self.d, "repo", "film.mp4")
        with self.assertRaises(rc.CannotRun) as cm:
            re_.plan_encode(ns(frames=self.frames, out=out))
        self.assertIn("git work tree", str(cm.exception))
        self.assertEqual(re_.plan_encode(ns(frames=self.frames, out=out, allow_in_repo=True))["out"], out)

    def test_cloud_synced_output_warns(self):
        out = os.path.join(self.d, "OneDrive", "film.mp4")
        p = re_.plan_encode(ns(frames=self.frames, out=out))
        self.assertTrue(any("cloud-synced" in w for w in p["warnings"]))

    def test_bad_arguments(self):
        for kw in (dict(first=5, last=2), dict(fps=0), dict(fps=-1), dict(first=-1), dict(view_transform=" "),
                   dict(out=os.path.join(self.d, "film.avi")), dict(pattern="frame_.png"),
                   dict(pattern="frame_##_##.png"), dict(frames=os.path.join(self.d, "nope")),
                   dict(size=[0, 10])):
            with self.assertRaises(rc.CannotRun, msg=str(kw)):
                re_.plan_encode(self.args(**kw))

    def test_corrupt_first_frame(self):
        with open(os.path.join(self.frames, "frame_0001.png"), "wb") as fh:
            fh.write(b"junk")
        with self.assertRaises(rc.CannotRun):
            re_.plan_encode(self.args())


class OverlayPlanTests(PlanCase):
    def item(self, frames, **kw):
        d = {"id": "lid", "text": "Lid", "subject": "Lid", "side": "left", "frames": frames}
        d.update(kw)
        return d

    def frames_list(self, start, end, x=8, y=4, op=None):
        return [{"frame": f, "x": x + f, "y": y, "w": 10, "h": 4.8,
                 "opacity": op(f) if op else 1.0} for f in range(start, end + 1)]

    def test_item_becomes_text_strip_with_keys(self):
        t = self.track({"fps": 24, "resolution": [W, H], "items": [self.item(self.frames_list(2, 5))]})
        p = re_.plan_encode(self.args(overlay=t))
        self.assertEqual(len(p["strips"]), 2)
        s = p["strips"][1]
        self.assertEqual((s["kind"], s["text"], s["channel"], s["frame_start"], s["length"]), ("text", "Lid", 2, 2, 4))
        self.assertEqual([k["frame"] for k in s["keys"]], [2, 3, 4, 5])
        k = s["keys"][0]
        self.assertEqual(s["anchor_x"], "RIGHT")  # a left-side label anchors at its right edge
        self.assertAlmostEqual(k["x"], (8 + 2 + 10) / W)
        self.assertAlmostEqual(k["y"], 1 - 4 / H)
        self.assertEqual(s["font_size"], 4)  # h 4.8 / 1.2

    def test_opacity_keys_and_clamp(self):
        fr = self.frames_list(1, 4, op=lambda f: {1: 0.0, 2: 0.5, 3: 1.0, 4: 1.7}[f])
        t = self.track({"resolution": [W, H], "items": [self.item(fr)]})
        keys = re_.plan_encode(self.args(overlay=t))["strips"][1]["keys"]
        self.assertEqual([k["opacity"] for k in keys], [0.0, 0.5, 1.0, 1.0])

    def test_frames_outside_range_are_dropped_and_renumbered(self):
        t = self.track({"resolution": [W, H], "items": [self.item(self.frames_list(3, 9))]})
        p = re_.plan_encode(self.args(first=2, last=5, overlay=t))
        keys = p["strips"][1]["keys"]
        self.assertEqual([k["frame"] for k in keys], [2, 3, 4])  # render frames 3-5 -> video frames 2-4

    def test_item_wholly_outside_is_skipped_with_warning(self):
        t = self.track({"resolution": [W, H], "items": [self.item(self.frames_list(20, 30))]})
        p = re_.plan_encode(self.args(overlay=t))
        self.assertEqual(len(p["strips"]), 1)
        self.assertTrue(any("no frames inside" in w for w in p["warnings"]))

    def test_title_from_hold(self):
        t = self.track({"fps": 24, "resolution": [W, H], "font_px": 5, "items": [],
                        "title": {"text": "The End", "in": 2, "hold_s": 0.1}})
        p = re_.plan_encode(self.args(overlay=t))
        s = p["strips"][1]
        self.assertEqual((s["name"], s["text"], s["frame_start"]), ("title", "The End", 2))
        self.assertEqual(s["keys"][-1]["frame"], 2 + 2)  # round(0.1 * 24) = 2 frames after in
        self.assertEqual(s["font_size"], 5)

    def test_title_clipped_to_range(self):
        t = self.track({"resolution": [W, H], "items": [], "title": {"text": "T", "in": 5, "hold_s": 4.0}})
        s = re_.plan_encode(self.args(overlay=t))["strips"][1]
        self.assertEqual((s["frame_start"], s["keys"][-1]["frame"]), (5, 6))

    def test_title_with_explicit_frames(self):
        t = self.track({"resolution": [W, H], "items": [], "title": {"text": "T", "frames": self.frames_list(1, 3)}})
        self.assertEqual(len(re_.plan_encode(self.args(overlay=t))["strips"][1]["keys"]), 3)

    def test_fps_and_resolution_mismatch_warn(self):
        t = self.track({"fps": 30, "resolution": [W * 2, H * 2], "items": [self.item(self.frames_list(1, 3))]})
        w = " ".join(re_.plan_encode(self.args(overlay=t))["warnings"])
        self.assertIn("fps", w)
        self.assertIn("resolution", w)

    def test_resolution_mismatch_scales_by_track_resolution(self):
        t = self.track({"resolution": [W * 2, H * 2], "items": [self.item(self.frames_list(1, 1, x=0, y=0))]})
        k = re_.plan_encode(self.args(overlay=t))["strips"][1]["keys"][0]
        self.assertAlmostEqual(k["x"], (1 + 10) / (W * 2))  # right edge of a left-side label, track pixels

    def test_font_size_scales_with_the_video_height(self):
        # Regression: positions scaled to the video but the font stayed in track pixels, so a 2x track
        # encoded at 1x drew text at twice its relative size (found on the sample-scene preview).
        t = self.track({"resolution": [W * 2, H * 2], "font_px": 10,
                        "items": [self.item(self.frames_list(1, 2))],
                        "title": {"text": "T", "in": 1, "hold_s": 0.05}})
        strips = re_.plan_encode(self.args(overlay=t))["strips"]
        self.assertEqual([s["font_size"] for s in strips[1:]], [5, 5])

    def test_title_uses_its_own_font_and_centre_anchor(self):
        # Regression (sample-scene preview): the title ignored title.font_px (fell back to 48) and was
        # anchored at its box's left edge, so a wider-than-estimated title drifted right of centre.
        t = self.track({"resolution": [W, H], "items": [],
                        "title": {"text": "T", "in": 1, "hold_s": 0.05, "font_px": 7, "x": 10, "w": 20, "y": 4}})
        s = re_.plan_encode(self.args(overlay=t))["strips"][1]
        self.assertEqual((s["font_size"], s["anchor_x"]), (7, "CENTER"))
        self.assertAlmostEqual(s["keys"][0]["x"], (10 + 20 / 2) / W)

    def test_label_anchor_is_the_side_away_from_the_subject(self):
        # A wider-than-estimated label grows away from its subject, never across it.
        for side, anchor, x in (("right", "LEFT", 8 + 1), ("left", "RIGHT", 8 + 1 + 10), ("above", "CENTER", 8 + 1 + 5)):
            t = self.track({"resolution": [W, H], "items": [self.item(self.frames_list(1, 1), side=side)]})
            s = re_.plan_encode(self.args(overlay=t))["strips"][1]
            self.assertEqual(s["anchor_x"], anchor, side)
            self.assertAlmostEqual(s["keys"][0]["x"], x / W, msg=side)

    def test_several_items_get_separate_channels(self):
        items = [self.item(self.frames_list(1, 3), id="a"), self.item(self.frames_list(2, 4), id="b")]
        p = re_.plan_encode(self.args(overlay=self.track({"resolution": [W, H], "items": items})))
        self.assertEqual([s["channel"] for s in p["strips"]], [1, 2, 3])
        self.assertEqual([s["name"] for s in p["strips"][1:]], ["label_a", "label_b"])

    def test_bad_overlays_refused(self):
        bad = [{"items": "x"}, [], {"resolution": [W, H], "items": [self.item([{"frame": 1}])]},
               {"resolution": [W, H], "items": [], "title": {"text": "T"}}]
        for i, data in enumerate(bad):
            with self.assertRaises(rc.CannotRun, msg=str(data)):
                re_.plan_encode(self.args(overlay=self.track(data, f"b{i}.json")))
        with self.assertRaises(rc.CannotRun):
            re_.plan_encode(self.args(overlay=os.path.join(self.d, "none.json")))
        junk = os.path.join(self.d, "junk.json")
        with open(junk, "w") as fh:
            fh.write("{")
        with self.assertRaises(rc.CannotRun):
            re_.plan_encode(self.args(overlay=junk))


class CliTests(PlanCase):
    def run_cli(self, *argv):
        return subprocess.run([sys.executable, "-I", "-B", TOOL] + list(argv), capture_output=True, text=True,
                              stdin=subprocess.DEVNULL, timeout=60)

    def base(self):
        return ["--frames", self.frames, "--pattern", "frame_####.png", "--first", "1", "--last", "6",
                "--fps", "24", "--out", self.out]

    def test_dry_run_prints_plan_json(self):
        r = self.run_cli(*self.base(), "--dry-run")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(json.loads(r.stdout)["count"], 6)
        self.assertFalse(os.path.exists(self.out))

    def test_outside_blender_exit_2(self):
        r = self.run_cli(*self.base())
        self.assertEqual(r.returncode, 2)
        self.assertIn("render_encode: ERROR", r.stderr)

    def test_missing_frames_exit_2_and_help_0(self):
        os.remove(os.path.join(self.frames, "frame_0002.png"))
        r = self.run_cli(*self.base(), "--dry-run")
        self.assertEqual(r.returncode, 2)
        self.assertIn("missing", r.stderr)
        self.assertEqual(self.run_cli("--help").returncode, 0)
        self.assertEqual(self.run_cli().returncode, 2)

    def test_args_after_blender_separator(self):
        r = self.run_cli("--python-exit-code", "1", "--", *self.base(), "--dry-run")
        self.assertEqual(r.returncode, 0, r.stderr)


if __name__ == "__main__":
    unittest.main()
