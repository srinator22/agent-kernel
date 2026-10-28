"""Tests for camera_path.py: monotone spline vs Catmull-Rom, sampling, holds, check, exit codes."""
import contextlib
import io
import json
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import camera_path as cp  # noqa: E402
import render_common as rc  # noqa: E402


def wp(frame, pos, target=(0, 0, 0), lens=50.0, **kw):
    d = {"frame": frame, "pos": list(pos), "target": list(target), "lens": lens}
    d.update(kw)
    return d


def rc_json(path):
    with open(path, "r", encoding="utf-8") as fh:
        return json.load(fh)


def run(argv):
    out, err = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        try:
            code = cp.main(argv)
        except SystemExit as e:
            code = e.code
    return code, out.getvalue(), err.getvalue()


class SplineTests(unittest.TestCase):
    XS, YS = [0.0, 10.0, 20.0, 30.0], [0.0, 0.0, 1.0, 1.0]

    def test_golden_catmull_overshoots_pchip_does_not(self):
        pc, cr = cp.pchip(self.XS, self.YS), cp.catmull_rom(self.XS, self.YS)
        # segment 0-10 has equal data (0, 0); Catmull-Rom dips below 0, PCHIP stays exactly 0
        self.assertAlmostEqual(cr(7.0), 0.5 * (0.343 - 0.49), places=9)  # -0.0735
        self.assertLess(cr(7.0), -0.07)
        self.assertEqual(pc(7.0), 0.0)
        # segment 20-30 (1, 1): Catmull-Rom rises above 1 (peak about 1.074 at x=23.3)
        self.assertGreater(cr(23.0), 1.07)
        self.assertEqual(pc(23.0), 1.0)
        for x in range(0, 31):
            self.assertTrue(-1e-12 <= pc(float(x)) <= 1 + 1e-12, x)

    def test_passes_through_knots_and_holds_ends(self):
        for fn in (cp.pchip, cp.catmull_rom):
            f = fn(self.XS, self.YS)
            for x, y in zip(self.XS, self.YS):
                self.assertAlmostEqual(f(x), y, places=12)
            self.assertEqual(f(-5.0), 0.0)
            self.assertEqual(f(99.0), 1.0)

    def test_monotone_data_stays_monotone(self):
        f = cp.pchip([0, 5, 6, 20], [0, 1, 10, 11])
        vals = [f(x / 2) for x in range(0, 41)]
        self.assertTrue(all(b >= a - 1e-12 for a, b in zip(vals, vals[1:])))
        self.assertTrue(all(0 - 1e-12 <= v <= 11 + 1e-12 for v in vals))

    def test_local_extremum_not_exceeded(self):
        f = cp.pchip([0, 10, 20], [0, 5, 0])
        self.assertLessEqual(max(f(x / 4) for x in range(0, 81)), 5 + 1e-12)

    def test_two_knots_are_linear(self):
        f = cp.pchip([0, 10], [1.0, 3.0])
        self.assertAlmostEqual(f(5.0), 2.0)
        self.assertAlmostEqual(f(2.5), 1.5)
        g = cp.catmull_rom([0, 10], [1.0, 3.0])
        self.assertAlmostEqual(g(5.0), 2.0)

    def test_bad_knots(self):
        for xs, ys in (([0, 0], [1, 2]), ([2, 1], [1, 2]), ([0], [1]), ([0, 1, 2], [1, 2])):
            for fn in (cp.pchip, cp.catmull_rom):
                with self.assertRaises(rc.CannotRun):
                    fn(xs, ys)


class SampleTests(unittest.TestCase):
    def test_sample_counts_time_and_values(self):
        s = cp.sample_path([wp(10, (0, 0, 0)), wp(34, (2.4, 0, 1.2))], 24)
        self.assertEqual(len(s), 25)
        self.assertEqual((s[0]["frame"], s[-1]["frame"]), (10, 34))
        self.assertAlmostEqual(s[12]["t"], 0.5)
        self.assertAlmostEqual(s[12]["pos"][0], 1.2, places=9)
        self.assertAlmostEqual(s[-1]["pos"][2], 1.2, places=9)
        self.assertEqual(s[3]["lens"], 50.0)

    def test_hold_between_equal_waypoints_is_exactly_flat(self):
        wps = [wp(1, (0, 0, 1)), wp(25, (1, 0, 1)), wp(49, (1, 0, 1), hold=True), wp(73, (3, 0, 1))]
        s = cp.sample_path(wps, 24)
        for x in s[24:49]:
            self.assertAlmostEqual(x["pos"][0], 1.0, places=12)
        # eases out of and into the hold: no overshoot anywhere, hold declared
        self.assertEqual(cp.check_path(wps, s), [])
        self.assertTrue(all(0 <= x["pos"][0] <= 3 for x in s))

    def test_lens_omitted(self):
        s = cp.sample_path([wp(1, (0, 0, 0), lens=None), wp(5, (1, 0, 0), lens=None)], 24)
        self.assertIsNone(s[0]["lens"])

    def test_catmull_sampling_can_be_selected(self):
        wps = [wp(1, (0, 0, 0), hold=True), wp(11, (0, 0, 0)), wp(21, (1, 0, 0)), wp(31, (1, 0, 0), hold=True)]
        self.assertEqual(cp.check_path(wps, cp.sample_path(wps, 24, "pchip")), [])
        kinds = {f["kind"] for f in cp.check_path(wps, cp.sample_path(wps, 24, "catmull"))}
        self.assertIn("overshoot", kinds)
        with self.assertRaises(rc.CannotRun):
            cp.sample_path(wps, 24, "bezier")

    def test_waypoint_validation(self):
        good = [wp(1, (0, 0, 0)), wp(5, (1, 1, 1))]
        bad = {
            "unsorted": [wp(5, (0, 0, 0)), wp(1, (1, 1, 1))],
            "duplicate": [wp(1, (0, 0, 0)), wp(1, (1, 1, 1))],
            "one": [wp(1, (0, 0, 0))],
            "empty": [],
            "pos": [wp(1, (0, 0)), wp(5, (1, 1, 1))],
            "nan": [wp(1, (0, 0, float("nan"))), wp(5, (1, 1, 1))],
            "float frame": [wp(1.5, (0, 0, 0)), wp(5, (1, 1, 1))],
            "lens": [wp(1, (0, 0, 0), lens=-1), wp(5, (1, 1, 1))],
            "mixed lens": [wp(1, (0, 0, 0)), wp(5, (1, 1, 1), lens=None)],
            "not a list": {"a": 1},
        }
        self.assertEqual(len(cp.parse_waypoints(good)), 2)
        self.assertEqual(len(cp.parse_waypoints({"waypoints": good})), 2)
        for name, data in bad.items():
            with self.assertRaises(rc.CannotRun, msg=name):
                cp.parse_waypoints(data)

    def test_bad_fps(self):
        with self.assertRaises(rc.CannotRun):
            cp.sample_path([wp(1, (0, 0, 0)), wp(5, (1, 1, 1))], 0)


class CheckTests(unittest.TestCase):
    def test_undeclared_stop_found_and_hold_flag_accepted(self):
        wps = [wp(1, (0, 0, 0)), wp(25, (1, 0, 0)), wp(49, (1, 0, 0)), wp(73, (2, 0, 0))]
        kinds = [f["kind"] for f in cp.check_path(wps, cp.sample_path(wps, 24))]
        self.assertEqual(kinds, ["stop"])
        wps[2]["hold"] = True
        self.assertEqual(cp.check_path(wps, cp.sample_path(wps, 24)), [])

    def test_hold_flag_on_earlier_waypoint_also_counts(self):
        wps = [wp(1, (0, 0, 0)), wp(25, (1, 0, 0), hold=True), wp(49, (1, 0, 0)), wp(73, (2, 0, 0))]
        self.assertEqual(cp.check_path(wps, cp.sample_path(wps, 24)), [])

    def test_overshoot_reported_with_axis_and_frames(self):
        wps = [wp(1, (0, 0, 0)), wp(11, (0, 0, 0), hold=True), wp(21, (1, 0, 0)), wp(31, (1, 0, 0), hold=True)]
        f = cp.check_path(wps, cp.sample_path(wps, 24, "catmull"))
        over = [x for x in f if x["kind"] == "overshoot"]
        self.assertTrue(over)
        self.assertTrue(any("pos.x" in x["message"] for x in over))

    def test_target_and_lens_channels_checked(self):
        wps = [wp(1, (0, 0, 0), (0, 0, 0), 35, hold=True), wp(11, (0, 0, 1), (0, 0, 0), 35),
               wp(21, (0, 0, 2), (1, 0, 0), 90), wp(31, (0, 0, 3), (1, 0, 0), 90)]
        f = cp.check_path(wps, cp.sample_path(wps, 24, "catmull"))
        text = " ".join(x["message"] for x in f)
        self.assertTrue("target.x" in text or "lens" in text)


class CliTests(unittest.TestCase):
    def setUp(self):
        self._td = tempfile.TemporaryDirectory()
        self.addCleanup(self._td.cleanup)
        self.d = os.path.realpath(self._td.name)

    def write(self, data, name="wp.json"):
        p = os.path.join(self.d, name)
        with open(p, "w") as fh:
            json.dump(data, fh)
        return p

    def test_pass_and_out_file(self):
        p = self.write([wp(1, (0, 0, 0)), wp(25, (1, 0, 0)), wp(49, (2, 0, 0))])
        out = os.path.join(self.d, "path.json")
        code, stdout, _ = run([p, "--fps", "24", "--out", out, "--check"])
        self.assertEqual(code, 0, stdout)
        self.assertIn("camera_path: PASS", stdout.splitlines()[-1])
        doc = rc_json(out)
        self.assertEqual((doc["first_frame"], doc["last_frame"], len(doc["samples"])), (1, 49, 49))

    def test_check_findings_exit_1_and_json_report(self):
        p = self.write([wp(1, (0, 0, 0)), wp(25, (1, 0, 0)), wp(49, (1, 0, 0)), wp(73, (2, 0, 0))])
        rep = os.path.join(self.d, "r.json")
        code, stdout, _ = run([p, "--fps", "24", "--check", "--json", rep])
        self.assertEqual(code, 1)
        self.assertIn("camera_path: FAIL 1 finding(s)", stdout)
        self.assertEqual(rc_json(rep)["status"], "fail")
        code, _, _ = run([p, "--fps", "24"])  # no --check: not examined
        self.assertEqual(code, 0)

    def test_catmull_check_exits_1(self):
        p = self.write([wp(1, (0, 0, 0), hold=True), wp(11, (0, 0, 0)), wp(21, (1, 0, 0)), wp(31, (1, 0, 0), hold=True)])
        self.assertEqual(run([p, "--fps", "24", "--check"])[0], 0)
        self.assertEqual(run([p, "--fps", "24", "--check", "--spline", "catmull"])[0], 1)

    def test_exit_2_cases(self):
        unsorted = self.write([wp(9, (0, 0, 0)), wp(2, (1, 0, 0))], "u.json")
        dup = self.write([wp(2, (0, 0, 0)), wp(2, (1, 0, 0))], "d.json")
        bad = os.path.join(self.d, "bad.json")
        with open(bad, "w") as fh:
            fh.write("[")
        good = self.write([wp(1, (0, 0, 0)), wp(5, (1, 0, 0))], "g.json")
        for argv in ([unsorted, "--fps", "24"], [dup, "--fps", "24"], [bad, "--fps", "24"],
                     [os.path.join(self.d, "nope.json"), "--fps", "24"], [good, "--fps", "0"],
                     [good, "--fps", "24", "--out", "relative.json"]):
            code, _, err = run(argv)
            self.assertEqual(code, 2, argv)
            self.assertIn("camera_path: ERROR", err)
        self.assertEqual(run([good])[0], 2)  # argparse: --fps required
        self.assertEqual(run([])[0], 2)

    def test_help_exit_0(self):
        self.assertEqual(run(["--help"])[0], 0)


if __name__ == "__main__":
    unittest.main()
