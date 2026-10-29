"""Tests for render_overlay.py with synthetic extracts (anchors moving across the frame). No Blender.

Run: python -I -B -m unittest discover -s docs/library/tools/tests -t docs/library/tools/tests -p "test_*.py"
"""
import contextlib
import io
import json
import os
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import render_overlay as ro  # noqa: E402

TOOL = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "render_overlay.py")
W, H, FONT = 1920, 1080, 40


def extract(anchor_fn, last=100, fps=24.0, res=(W, H)):
    frames = [{"frame": f, "anchors": {k: v for k, v in anchor_fn(f).items()}} for f in range(1, last + 1)]
    return {"schema": "render-extract/1", "scene": {"fps": fps, "resolution": list(res)}, "frames": frames}


def moving(f):  # left to right across the middle of the frame
    u = 0.2 + 0.4 * (f - 1) / 99
    return {"Lid": [u, 0.5, 2.0], "Base": [u, 0.3, 2.0]}


def label(i="lid", subject="Lid", side="right", a=10, b=60, **kw):
    return {"id": i, "text": "Lid", "subject": subject, "side": side, "in": a, "out": b, "fade": 6,
            "offset_px": 120, **kw}


def spec(labels, title=None):
    s = {"fps": 24, "resolution": [W, H], "font_px": FONT, "labels": labels}
    if title:
        s["title"] = title
    return s


class OverlayCase(unittest.TestCase):
    def setUp(self):
        self._td = tempfile.TemporaryDirectory()
        self.addCleanup(self._td.cleanup)
        self.root = os.path.realpath(self._td.name)
        self.out_path = os.path.join(self.root, "out", "track.json")

    def put(self, name, doc):
        p = os.path.join(self.root, name)
        with open(p, "w", encoding="utf-8") as f:
            json.dump(doc, f)
        return p

    def run_tool(self, sp, ex, *extra, out=None):
        sp = sp if isinstance(sp, str) else self.put("spec.json", sp)
        ex = ex if isinstance(ex, str) else self.put("ex.json", ex)
        o, e = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(o), contextlib.redirect_stderr(e):
            code = ro.main(["--spec", sp, "--extract", ex, "--out", out or self.out_path, *extra])
        return code, o.getvalue(), e.getvalue()

    def track(self):
        with open(self.out_path, encoding="utf-8") as f:
            return json.load(f)


class Plan(OverlayCase):
    def test_clean_track_keeps_one_side_and_ramps_opacity(self):
        code, out, err = self.run_tool(spec([label()]), extract(moving))
        self.assertEqual((code, err), (0, ""), out)
        self.assertTrue(out.strip().splitlines()[-1].startswith("render_overlay: PASS"))
        t = self.track()
        self.assertEqual((t["fps"], t["resolution"]), (24, [W, H]))
        fr = t["items"][0]["frames"]
        self.assertEqual([x["frame"] for x in fr], list(range(10, 61)))
        anchors = {f: moving(f)["Lid"] for f in range(10, 61)}
        for x in fr:
            u, v, _ = anchors[x["frame"]]
            self.assertAlmostEqual(x["x"], u * W + 120)  # always right of the anchor
            self.assertAlmostEqual(x["y"] + x["h"] / 2, (1 - v) * H)
            self.assertAlmostEqual(x["w"], 3 * 0.55 * FONT)
            self.assertAlmostEqual(x["h"], 1.2 * FONT)
        ops = [x["opacity"] for x in fr]
        self.assertEqual((ops[0], ops[-1]), (0.0, 0.0))
        self.assertEqual(ops[6], 1.0)
        self.assertEqual(max(ops), 1.0)
        self.assertTrue(all(a <= b for a, b in zip(ops[:7], ops[1:7])))
        self.assertTrue(all(a >= b for a, b in zip(ops[-7:], ops[-6:])))

    def test_all_four_sides_place_the_box_on_that_side(self):
        for side in ro.SIDES:
            code, out, _ = self.run_tool(spec([label(side=side, a=40, b=50)]), extract(moving))
            self.assertEqual(code, 0, out)
            x = self.track()["items"][0]["frames"][5]
            u, v, _ = moving(45)["Lid"]
            px, py = u * W, (1 - v) * H
            if side == "left":
                self.assertAlmostEqual(x["x"] + x["w"], px - 120)
            elif side == "above":
                self.assertAlmostEqual(x["y"] + x["h"], py - 120)
            elif side == "below":
                self.assertAlmostEqual(x["y"], py + 120)

    def test_label_crossing_to_the_other_side_is_detected_and_track_is_clamped(self):
        def drift(f):
            return {"Lid": [0.2 - 0.18 * (f - 1) / 99, 0.5, 2.0]}  # 0.2 -> 0.02, toward the left edge
        code, out, _ = self.run_tool(spec([label(side="left", a=10, b=99)]), extract(drift))
        self.assertEqual(code, 1)
        self.assertIn("side: label 'lid': crosses to the other side of its subject (declared left)", out)
        self.assertIn("safe: label 'lid'", out)
        self.assertIn("-99", [l for l in out.splitlines() if l.startswith("side:")][0])
        last = self.track()["items"][0]["frames"][-1]
        self.assertAlmostEqual(last["x"], 0.05 * W)  # clamped into the safe area in the track

    def test_crossing_during_a_fade_counts(self):
        def late(f):
            return {"Lid": [0.02 if 10 <= f <= 13 else 0.5, 0.5, 2.0]}
        code, out, _ = self.run_tool(spec([label(side="left", a=10, b=60)]), extract(late))
        self.assertEqual(code, 1)
        self.assertIn("(declared left) at frames 10-13", out)

    def test_safe_area_exit_without_crossing(self):
        def edge(f):
            return {"Lid": [0.97, 0.5, 2.0]}
        code, out, _ = self.run_tool(spec([label(side="above", a=10, b=20)]), extract(edge))
        self.assertEqual(code, 1)
        self.assertIn("safe: label 'lid': box leaves the safe area (5% margin) at frames 10-20", out)
        self.assertNotIn("side:", out)
        code, out, _ = self.run_tool(spec([label(side="above", a=10, b=20)]), extract(edge), "--safe", "0")
        self.assertEqual(code, 0, out)

    def test_overlapping_labels(self):
        two = [label("a", "Lid", "right"), label("b", "Base", "right", a=30, b=50)]
        code, out, _ = self.run_tool(spec(two), extract(moving))
        self.assertEqual(code, 0, out)  # Lid at v=0.5, Base at v=0.3: well apart

        def same(f):
            return {"Lid": [0.5, 0.5, 2.0], "Base": [0.5, 0.5, 2.0]}
        code, out, _ = self.run_tool(spec(two), extract(same))
        self.assertEqual(code, 1)
        self.assertIn("overlap: labels 'a' and 'b' overlap at frames 31-49", out)  # 30 and 50 are fully faded out

    def test_missing_and_behind_camera_anchor(self):
        def gappy(f):
            a = moving(f)
            if 20 <= f <= 25:
                a.pop("Lid")
            if f == 30:
                a["Lid"] = [0.4, 0.5, -1.0]
            if f == 31:
                a["Lid"] = None
            return a
        code, out, _ = self.run_tool(spec([label()]), extract(gappy))
        self.assertEqual(code, 1)
        self.assertIn("anchor: label 'lid': anchor 'Lid' missing at frames 20-25, 31", out)
        self.assertIn("behind the camera (depth <= 0) at frames 30", out)
        frames = [x["frame"] for x in self.track()["items"][0]["frames"]]
        self.assertNotIn(22, frames)
        self.assertNotIn(30, frames)

    def test_label_outside_the_extract_frames(self):
        code, out, _ = self.run_tool(spec([label(a=90, b=120)]), extract(moving))
        self.assertEqual(code, 1)
        self.assertIn("range: label 'lid': frames 101-120 are not in the extract", out)

    def test_title_must_be_readable_twice(self):
        text = "Fits two rolls in one"  # 5 words -> 3.33 s at 3 words/s
        code, out, _ = self.run_tool(spec([label()], {"text": text, "in": 80, "hold_s": 3.0}), extract(moving))
        self.assertEqual(code, 1)
        self.assertIn("title: title hold 3s is shorter than the 3.33s needed to read 5 word(s) twice", out)
        code, out, _ = self.run_tool(spec([label()], {"text": text, "in": 80, "hold_s": 3.4}), extract(moving))
        self.assertEqual(code, 0, out)
        t = self.track()["title"]
        # out is the last frame shown (inclusive): in + hold_frames - 1, so exactly hold_frames frames show.
        # Regression: out was in + hold_frames, one frame more than the stated hold (video-direction review).
        self.assertEqual((t["in"], t["out"], t["words"], t["hold_frames"]), (80, 80 + 82 - 1, 5, 82))
        self.assertEqual(t["out"] - t["in"] + 1, t["hold_frames"])
        self.assertAlmostEqual(t["x"] + t["w"] / 2, W / 2)
        code, _, _ = self.run_tool(spec([label()], {"text": text, "in": 80, "hold_s": 3.0}), extract(moving), "--wps", "2")
        self.assertEqual(code, 1)

    def test_title_lower_third_and_cover_advisory(self):
        # A centred title over a subject is reported (advisory, exit unchanged); lower_third moves it down.
        still = lambda f: {"Pin": [0.5, 0.5, 2.0]}
        code, out, _ = self.run_tool(spec([], {"text": "End", "in": 5, "hold_s": 2.0}), extract(still))
        self.assertEqual(code, 0, out)
        self.assertIn("advisory: title box covers 'Pin' (anchor) at frames 5-", out)
        code, out, _ = self.run_tool(spec([], {"text": "End", "in": 5, "hold_s": 2.0, "position": "lower_third"}),
                                     extract(still))
        self.assertEqual(code, 0, out)
        self.assertNotIn("covers anchor", out)
        t = self.track()["title"]
        self.assertGreater(t["y"], H * 2 / 3)
        self.assertLessEqual(t["y"] + t["h"], H * 0.95)
        bad = spec([], {"text": "End", "in": 5, "hold_s": 2.0, "position": "top"})
        self.assertEqual(self.run_tool(bad, extract(still))[0], 2)

    def test_title_cover_uses_screen_boxes(self):
        # Regression (art-director finding): a ball whose centre is just below the frame still shows its top
        # under a lower-third title; the anchor point alone missed it, its screen box does not.
        ex = extract(lambda f: {"Ball": [0.5, -0.02, 0.4]})
        for fr in ex["frames"]:
            fr["screen_boxes"] = {"Ball": [0.4, -0.2, 0.6, 0.2]}
        t = {"text": "End", "in": 5, "hold_s": 2.0, "position": "lower_third"}
        code, out, _ = self.run_tool(spec([], t), ex)
        self.assertEqual(code, 0, out)
        self.assertIn("advisory: title box covers 'Ball' (screen box) at frames 5-", out)
        for fr in ex["frames"]:
            fr["screen_boxes"] = {"Ball": [0.4, 0.5, 0.6, 0.6, 0.7]}
        self.assertEqual(self.run_tool(spec([], t), ex)[0], 2)

    def test_title_alone_and_overlong_title(self):
        code, out, _ = self.run_tool(spec([], {"text": "End", "in": 5, "hold_s": 2.0}), extract(moving))
        self.assertEqual(code, 0, out)
        long_title = {"text": "x" * 120, "in": 5, "hold_s": 20.0}
        code, out, _ = self.run_tool(spec([], long_title), extract(moving))
        self.assertEqual(code, 1)
        self.assertIn("safe: title box", out)

    def test_extract_fps_or_aspect_mismatch(self):
        code, out, _ = self.run_tool(spec([label()]), extract(moving, fps=30.0))
        self.assertEqual(code, 1)
        self.assertIn("extract fps 30.0 differs from spec fps 24", out)
        code, out, _ = self.run_tool(spec([label()]), extract(moving, res=(1080, 1080)))
        self.assertEqual(code, 1)
        self.assertIn("different aspect", out)

    def test_track_and_report_are_written_on_findings(self):
        j = os.path.join(self.root, "rep.json")
        code, out, _ = self.run_tool(spec([label(a=90, b=120)]), extract(moving), "--json", j)
        self.assertEqual(code, 1)
        self.assertTrue(os.path.isfile(self.out_path))
        with open(j, encoding="utf-8") as f:
            rep = json.load(f)
        self.assertEqual((rep["tool"], rep["status"], rep["findings"][0]["kind"]), ("render_overlay", "fail", "range"))


class CannotRun(OverlayCase):
    def test_malformed_spec_exits_2_and_writes_nothing(self):
        base = spec([label()])
        cases = []
        for mutate in (lambda s: s.pop("fps"), lambda s: s.update(resolution=[1920]), lambda s: s.update(font_px=0),
                       lambda s: s.update(labels="x"), lambda s: s["labels"][0].update(side="middle"),
                       lambda s: s["labels"][0].update(out=5), lambda s: s["labels"][0].update(text=""),
                       lambda s: s["labels"][0].update({"in": 1.5}), lambda s: s["labels"][0].update(fade=-1),
                       lambda s: s["labels"].append(label()), lambda s: s.update(labels=[]),
                       lambda s: s.update(title={"text": "x", "in": 1}),
                       lambda s: s.update(title={"text": " ", "in": 1, "hold_s": 2})):
            s = json.loads(json.dumps(base))
            mutate(s)
            cases.append(s)
        for s in cases:
            code, out, err = self.run_tool(s, extract(moving))
            self.assertEqual((code, out), (2, ""), s)
            self.assertIn("render_overlay: ERROR", err)
        self.assertFalse(os.path.exists(self.out_path))

    def test_bad_extract_exits_2(self):
        bad_frames = extract(moving)
        bad_frames["frames"][3]["anchors"]["Lid"] = [0.1, 0.2]
        no_anchors = extract(moving)
        del no_anchors["frames"][0]["anchors"]
        for ex in ({"schema": "render-extract/2", "frames": []}, {"schema": "render-extract/1", "frames": []},
                   [], bad_frames, no_anchors):
            self.assertEqual(self.run_tool(spec([label()]), ex)[0], 2)

    def test_unreadable_inputs_and_relative_out_exit_2(self):
        ex = self.put("ex.json", extract(moving))
        self.assertEqual(self.run_tool(os.path.join(self.root, "none.json"), ex)[0], 2)
        broken = os.path.join(self.root, "broken.json")
        with open(broken, "w") as f:
            f.write("{")
        self.assertEqual(self.run_tool(broken, ex)[0], 2)
        self.assertEqual(self.run_tool(spec([label()]), os.path.join(self.root, "none.json"))[0], 2)
        code, _, err = self.run_tool(spec([label()]), ex, out="track.json")
        self.assertEqual(code, 2)
        self.assertIn("must be an absolute path", err)
        self.assertEqual(self.run_tool(spec([label()]), ex, "--safe", "0.6")[0], 2)
        self.assertEqual(self.run_tool(spec([label()]), ex, "--wps", "0")[0], 2)


class Cli(unittest.TestCase):
    def test_help_exits_0_and_labels_the_safe_default(self):
        p = subprocess.run([sys.executable, "-I", "-B", TOOL, "--help"], capture_output=True, text=True,
                           stdin=subprocess.DEVNULL, timeout=60)
        self.assertEqual(p.returncode, 0)
        self.assertIn("standard margin values unverified", " ".join(p.stdout.split()))

    def test_missing_arguments_exit_2(self):
        p = subprocess.run([sys.executable, "-I", "-B", TOOL], capture_output=True, text=True,
                           stdin=subprocess.DEVNULL, timeout=60)
        self.assertEqual(p.returncode, 2)


if __name__ == "__main__":
    unittest.main()
