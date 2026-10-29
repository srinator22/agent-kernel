"""Tests for motion_check.py on synthetic render-extract/1 documents (no Blender)."""
import contextlib
import io
import json
import math
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import blender_extract as bx  # noqa: E402
import motion_check as mc  # noqa: E402

FPS = 24.0


def make_doc(n=60, pos=None, fwd=None, objects=None, anchors=None, fps=FPS):
    d = bx.skeleton("5.2.3")
    d["scene"]["fps"] = fps
    d["frames"] = []
    for i in range(n):
        f = i + 1
        p = pos(i) if pos else [0.02 * i, -1.0, 0.3]
        v = fwd(i) if fwd else [0.0, 1.0, 0.0]
        d["frames"].append({
            "frame": f,
            "camera": {"location": p, "forward": v, "lens": 50.0, "focus_distance": 1.0, "fstop": 4.0},
            "objects": objects(i) if objects else {},
            "anchors": anchors(i) if anchors else {}, "volumes": {}})
    return d


def run(argv):
    out, err = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        try:
            code = mc.main(argv)
        except SystemExit as e:
            code = e.code
    return code, out.getvalue(), err.getvalue()


class Base(unittest.TestCase):
    def setUp(self):
        self._td = tempfile.TemporaryDirectory()
        self.addCleanup(self._td.cleanup)
        self.d = os.path.realpath(self._td.name)

    def put(self, data, name="x.json"):
        p = os.path.join(self.d, name)
        with open(p, "w") as fh:
            json.dump(data, fh)
        return p

    def check(self, doc, *extra):
        return run([self.put(doc)] + list(extra))


class StopTests(Base):
    def test_steady_camera_passes(self):
        code, out, _ = self.check(make_doc())
        self.assertEqual(code, 0, out)
        self.assertIn("motion_check: PASS", out.splitlines()[-1])
        self.assertIn("labels: no track given", out)

    def test_stop_found_with_frame_range(self):
        # move, stand still on frames 21-30, move again
        pos = lambda i: [0.02 * (i if i < 20 else (20 if i < 30 else i - 10)), -1.0, 0.3]
        code, out, _ = self.check(make_doc(pos=pos), "--accel-floor", "1e6")
        self.assertEqual(code, 1)
        self.assertIn("stop: camera stops", out)
        self.assertRegex(out, r"frames 2\d-3\d")

    def test_declared_hold_is_not_a_finding(self):
        pos = lambda i: [0.02 * (i if i < 20 else (20 if i < 30 else i - 10)), -1.0, 0.3]
        code, out, _ = self.check(make_doc(pos=pos), "--holds", "19-32", "--accel-floor", "1e6")
        self.assertEqual(code, 0, out)

    def test_static_camera_is_a_note_not_a_finding(self):
        code, out, _ = self.check(make_doc(pos=lambda i: [0, -1, 0.3]))
        self.assertEqual(code, 0, out)
        self.assertIn("does not move", out)

    def test_pure_rotation_is_not_a_stop(self):
        pos = lambda i: [0, -1, 0.3]
        fwd = lambda i: [math.sin(0.02 * i), math.cos(0.02 * i), 0.0]
        code, out, _ = self.check(make_doc(pos=pos, fwd=fwd))
        self.assertEqual(code, 0, out)

    def test_stepped_frames_use_real_spacing(self):
        doc = make_doc(n=30)
        for fr in doc["frames"]:
            fr["frame"] *= 2  # every other frame: same path, twice the time per sample
            fr["camera"]["location"] = [fr["camera"]["location"][0] * 2, -1.0, 0.3]
        code, out, _ = self.check(doc)
        self.assertEqual(code, 0, out)


class SpikeTests(Base):
    def test_camera_spike_found(self):
        pos = lambda i: [0.02 * i + (0.05 if i == 30 else 0.0), -1.0, 0.3]
        code, out, _ = self.check(make_doc(pos=pos))
        self.assertEqual(code, 1)
        self.assertRegex(out, r"spike: camera acceleration spike .* at frames 30-32")

    def test_smooth_ease_has_no_spike(self):
        pos = lambda i: [1.0 * (0.5 - 0.5 * math.cos(math.pi * i / 59)) + 0.0, -1.0, 0.3]
        pos2 = lambda i: [pos(i)[0] + 0.01 * i, -1.0, 0.3]
        self.assertEqual(self.check(make_doc(pos=pos2))[0], 0)

    def test_object_spike_found_by_name(self):
        obj = lambda i: {"Lid": {"location": [0.0, 0.0, 0.01 * i + (0.08 if i == 20 else 0)],
                                 "aabb_min": None, "aabb_max": None, "samples": []}}
        code, out, _ = self.check(make_doc(objects=obj))
        self.assertEqual(code, 1)
        self.assertIn("object Lid acceleration spike", out)

    def test_object_at_rest_with_one_eased_move_has_no_spike(self):
        # Regression: a lid still for most of the shot and opened with an ease in and out was flagged,
        # because the median acceleration over the whole shot was 0.
        def z(i):
            if i < 30:
                return 0.0
            if i >= 60:
                return 0.05
            s = (i - 30) / 30
            return 0.05 * (3 * s * s - 2 * s * s * s)  # smoothstep: zero speed at both ends
        obj = lambda i: {"Lid": {"location": [0.0, 0.0, z(i)], "aabb_min": None, "aabb_max": None,
                                 "samples": []}}
        code, out, _ = self.check(make_doc(n=120, objects=obj))
        self.assertEqual(code, 0, out)

    def test_empty_objects_are_skipped_with_a_note(self):
        # Regression: an invisible focus-target empty with a short eased move was reported as a spike;
        # empties are never seen, and visible children are tracked by their own world positions.
        obj = lambda i: {"Focus": {"location": [0.0, 0.0, 0.03 if i >= 50 else 0.0], "aabb_min": None,
                                   "aabb_max": None, "samples": []}}
        doc = make_doc(n=120, objects=obj)
        doc["objects"] = [{"name": "Focus", "type": "EMPTY", "hide_render": False, "hide_viewport": False,
                           "animated": True, "dimensions": None, "label": None}]
        code, out, _ = self.check(doc)
        self.assertEqual(code, 0, out)
        self.assertIn("object Focus (EMPTY) not checked", out)

    def test_object_at_rest_with_a_pop_is_a_spike(self):
        obj = lambda i: {"Lid": {"location": [0.0, 0.0, 0.03 if i >= 50 else 0.0], "aabb_min": None,
                                 "aabb_max": None, "samples": []}}
        code, out, _ = self.check(make_doc(n=120, objects=obj))
        self.assertEqual(code, 1, out)
        self.assertIn("object Lid acceleration spike", out)

    def test_object_with_few_frames_is_noted(self):
        obj = lambda i: {"Lid": {"location": [0, 0, 0], "aabb_min": None, "aabb_max": None, "samples": []}} \
            if i < 2 else {}
        code, out, _ = self.check(make_doc(objects=obj))
        self.assertEqual(code, 0, out)
        self.assertIn("fewer than 3 frames", out)

    def test_accel_floor_suppresses_tiny_noise(self):
        pos = lambda i: [0.02 * i + (1e-7 if i % 2 else 0.0), -1.0, 0.3]
        self.assertEqual(self.check(make_doc(pos=pos))[0], 0)


class OvershootTests(Base):
    def wp_file(self, xs):
        return self.put([{"frame": f, "pos": [x, -1.0, 0.3], "target": [0, 0, 0], "lens": 50} for f, x in xs], "wp.json")

    def test_overshoot_found(self):
        # path overshoots waypoint 2 at x=1.0 by 5 cm between frames 20 and 40
        def x_of(i):
            return 0.05 * i if i <= 20 else 1.0 + 0.05 * math.sin(math.pi * (i - 20) / 20)
        pos = lambda i: [x_of(i), -1.0, 0.3]
        wp = self.wp_file([(1, 0.0), (21, 1.0), (41, 1.0)])
        code, out, _ = self.check(make_doc(pos=pos), "--waypoints", wp)
        self.assertEqual(code, 1)
        self.assertIn("overshoot: camera x leaves", out)

    def test_within_tolerance_passes(self):
        wp = self.wp_file([(1, 0.0), (60, 1.18)])
        pos = lambda i: [0.02 * i, -1.0, 0.3]
        self.assertEqual(self.check(make_doc(pos=pos), "--waypoints", wp)[0], 0)

    def test_bad_waypoints_exit_2(self):
        wp = self.put([{"frame": 5, "pos": [0, 0, 0], "target": [0, 0, 0]}, {"frame": 2, "pos": [0, 0, 0], "target": [0, 0, 0]}], "bad.json")
        self.assertEqual(self.check(make_doc(), "--waypoints", wp)[0], 2)


class LabelTests(Base):
    W, H = 1920, 1080

    def doc(self, u_of):
        return make_doc(n=20, anchors=lambda i: {"Lid": [u_of(i), 0.5, 1.0]})

    def track(self, side, box_x, frames=range(1, 21), **kw):
        item = {"id": "lid", "text": "Lid", "subject": "Lid", "side": side,
                "frames": [{"frame": f, "x": box_x(f), "y": 500, "w": 100, "h": 48, "opacity": 1.0} for f in frames]}
        item.update(kw)
        return self.put({"fps": 24, "resolution": [self.W, self.H], "items": [item]}, "track.json")

    def test_left_label_stays_left(self):
        doc = self.doc(lambda i: 0.4 + 0.01 * i)  # anchor x from 768 to 960 px
        code, out, _ = self.check(doc, "--track", self.track("left", lambda f: 500))
        self.assertEqual(code, 0, out)
        self.assertNotIn("labels: no track given", out)

    def test_flip_detected_with_frames(self):
        doc = self.doc(lambda i: 0.2 + 0.03 * i)  # anchor starts left of the box centre (550 px) and passes it
        code, out, _ = self.check(doc, "--track", self.track("left", lambda f: 500))
        self.assertEqual(code, 1)
        self.assertRegex(out, r"label: label 'lid' \(Lid, left\) is on the wrong side .* frames 1-3")

    def test_right_above_below(self):
        doc = self.doc(lambda i: 0.5)  # anchor (960, 540)
        self.assertEqual(self.check(doc, "--track", self.track("right", lambda f: 1100))[0], 0)
        self.assertEqual(self.check(doc, "--track", self.track("right", lambda f: 100))[0], 1)
        above = self.put({"resolution": [self.W, self.H], "items": [{"id": "a", "subject": "Lid", "side": "above", "frames": [
            {"frame": 1, "x": 900, "y": 300, "w": 100, "h": 48}]}]}, "above.json")
        below = self.put({"resolution": [self.W, self.H], "items": [{"id": "b", "subject": "Lid", "side": "below", "frames": [
            {"frame": 1, "x": 900, "y": 300, "w": 100, "h": 48}]}]}, "below.json")
        self.assertEqual(self.check(doc, "--track", above)[0], 0)
        self.assertEqual(self.check(doc, "--track", below)[0], 1)

    def test_fade_frames_are_part_of_the_life(self):
        doc = self.doc(lambda i: 0.4 if i < 3 else 0.2)  # subject jumps left of the box late: flips from frame 4
        code, out, _ = self.check(doc, "--track", self.track("left", lambda f: 500, frames=range(1, 8)))
        self.assertEqual(code, 1)
        self.assertIn("4-7", out)

    def test_missing_anchor_frames_noted_or_found(self):
        doc = self.doc(lambda i: 0.8)
        code, out, _ = self.check(doc, "--track", self.track("left", lambda f: 100, frames=[1, 2, 99]))
        self.assertEqual(code, 0, out)
        self.assertIn("no anchor in frames 99", out)
        code, out, _ = self.check(doc, "--track", self.track("left", lambda f: 100, frames=[98, 99]))
        self.assertEqual(code, 1)
        self.assertIn("no anchor for the subject", out)

    def test_behind_camera_is_a_finding(self):
        doc = make_doc(n=20, anchors=lambda i: {"Lid": [0.5, 0.5, -1.0]})
        code, out, _ = self.check(doc, "--track", self.track("left", lambda f: 100, frames=[1, 2]))
        self.assertEqual(code, 1)
        self.assertIn("behind the camera", out)

    def test_bad_track_exit_2(self):
        doc = self.doc(lambda i: 0.5)
        for bad in ({"items": []}, {"resolution": [1, 1], "items": [{"subject": "Lid", "side": "middle", "frames": []}]},
                    {"resolution": [1, 1], "items": [{"subject": "Lid", "side": "left", "frames": [{"frame": 1}]}]}):
            self.assertEqual(self.check(doc, "--track", self.put(bad, "t.json"))[0], 2)

    def test_labels_flag_is_accepted(self):
        self.assertEqual(self.check(make_doc(), "--labels")[0], 0)


class ExitCodeTests(Base):
    def test_too_few_frames_exit_2(self):
        code, _, err = self.check(make_doc(n=2))
        self.assertEqual(code, 2)
        self.assertIn("motion_check: ERROR", err)

    def test_camera_null_exit_2(self):
        doc = make_doc()
        doc["frames"][5]["camera"] = None
        code, _, err = self.check(doc)
        self.assertEqual(code, 2)
        self.assertIn("frame 6", err)

    def test_bad_document_exit_2(self):
        for bad in ({"schema": "nope"}, [], {"schema": bx.SCHEMA}):
            self.assertEqual(run([self.put(bad)])[0], 2)
        p = os.path.join(self.d, "junk.json")
        with open(p, "w") as fh:
            fh.write("{")
        self.assertEqual(run([p])[0], 2)
        self.assertEqual(run([os.path.join(self.d, "missing.json")])[0], 2)

    def test_null_fps_and_bad_holds_exit_2(self):
        self.assertEqual(self.check(make_doc(fps=None))[0], 2)
        self.assertEqual(self.check(make_doc(), "--holds", "9-1")[0], 2)
        self.assertEqual(self.check(make_doc(), "--holds", "x")[0], 2)
        self.assertEqual(self.check(make_doc(), "--spike", "-1")[0], 2)

    def test_json_report_and_help(self):
        rep = os.path.join(self.d, "r.json")
        code, out, _ = self.check(make_doc(), "--json", rep)
        self.assertEqual(code, 0)
        with open(rep, "r", encoding="utf-8") as fh:
            data = json.load(fh)
        self.assertEqual((data["tool"], data["status"], data["frames"]), ("motion_check", "pass", 60))
        self.assertEqual(run(["--help"])[0], 0)
        self.assertEqual(run([])[0], 2)

    def test_accelerations_helper_uniform(self):
        accs = mc.accelerations([1, 2, 3, 4], [[0, 0, 0], [1, 0, 0], [3, 0, 0], [3, 0, 0]], 1.0)
        self.assertEqual([round(a, 9) for _, a in accs], [1.0, 2.0])
        self.assertEqual([f for f, _ in accs], [2, 3])


if __name__ == "__main__":
    unittest.main()
