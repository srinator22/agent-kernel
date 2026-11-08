"""Tests for flicker_metric.py on tiny synthetic gray PNG sequences (no Blender, no GPU).

Run: python -I -B -m unittest discover -s docs/library/tools/tests -t docs/library/tools/tests -p "test_*.py"
Set RENDER_TOOLS_PURE=1 to force the stdlib path; both paths are compared when numpy is importable.
"""
import contextlib
import io
import json
import os
import random
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import flicker_metric as fm  # noqa: E402
import render_common as rc  # noqa: E402

KEY = "RENDER_TOOLS_PURE"
TOOL = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "flicker_metric.py")
W, H = 16, 12


def have(name):
    try:
        __import__(name)
        return True
    except Exception:
        return False


@contextlib.contextmanager
def mode(pure):
    old = os.environ.get(KEY)
    if pure:
        os.environ[KEY] = "1"
    else:
        os.environ.pop(KEY, None)
    try:
        yield
    finally:
        if old is None:
            os.environ.pop(KEY, None)
        else:
            os.environ[KEY] = old


def gray(rows, w=W, h=H):
    return [bytes(r) for r in rows]


def flat(v, w=W, h=H):
    return [[v] * w for _ in range(h)]


def noisy(seed, amp, base=128, w=W, h=H):
    rng = random.Random(seed)
    return [[base + rng.randint(-amp, amp) for _ in range(w)] for _ in range(h)]


class FlickerCase(unittest.TestCase):
    def setUp(self):
        self._td = tempfile.TemporaryDirectory()
        self.addCleanup(self._td.cleanup)
        self.root = os.path.realpath(self._td.name)

    def folder(self, name, frames, first=1, w=W, h=H):
        d = os.path.join(self.root, name)
        os.makedirs(d, exist_ok=True)
        for i, rows in enumerate(frames):
            rc.write_png(os.path.join(d, f"frame_{first + i:04d}.png"), w, h, 1, gray(rows))
        return d

    def run_tool(self, *argv):
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = fm.main([str(a) for a in argv])
        return code, out.getvalue(), err.getvalue()

    def report(self, *argv):
        j = os.path.join(self.root, "rep.json")
        code, out, err = self.run_tool(*argv, "--json", j)
        with open(j, encoding="utf-8") as f:
            return code, json.load(f), out


class Metric(FlickerCase):
    def test_noise_amplitudes_are_ordered_and_proportional(self):
        lo = self.folder("lo", [noisy(n, 3) for n in range(12)])
        hi = self.folder("hi", [noisy(100 + n, 9) for n in range(12)])
        vals = {}
        for name, d in (("lo", lo), ("hi", hi)):
            code, rep, _ = self.report(d, "--first", 1, "--last", 12, "--stride", 1, "--threshold", 1.0)
            self.assertEqual(code, 0)
            vals[name] = rep["results"][0]["mean"]
        print(f"\n[flicker] noise amp 3 -> T {vals['lo']:.5f}; amp 9 -> T {vals['hi']:.5f}; "
              f"ratio {vals['hi'] / vals['lo']:.3f}", file=sys.stderr)
        self.assertLess(vals["lo"], vals["hi"])
        self.assertGreater(vals["hi"] / vals["lo"], 2.5)
        self.assertLess(vals["hi"] / vals["lo"], 3.5)

    def test_linear_brightness_ramp_reads_zero(self):
        frames = [[[min(255, 20 + 2 * n + x * 3) for x in range(W)] for _ in range(H)] for n in range(12)]
        d = self.folder("ramp", frames)
        code, rep, out = self.report(d, "--first", 1, "--last", 12, "--stride", 1, "--threshold", 0.0001)
        print(f"[flicker] linear ramp -> T {rep['results'][0]['mean']:.3e}", file=sys.stderr)
        self.assertEqual(code, 0, out)
        self.assertLess(rep["results"][0]["mean"], 1e-12)
        self.assertEqual(rep["results"][0]["worst"], [])

    def test_static_sequence_passes(self):
        d = self.folder("still", [flat(90)] * 6)
        code, out, _ = self.run_tool(d, "--first", 1, "--last", 6)
        self.assertEqual(code, 0)
        self.assertTrue(out.strip().splitlines()[-1].startswith("flicker_metric: PASS"))

    def test_single_flashing_region_is_flagged_with_its_frames(self):
        frames = []
        for n in range(1, 11):
            rows = flat(100)
            if n == 6:
                for y in range(6):
                    for x in range(8):
                        rows[y][x] = 160
            frames.append(rows)
        d = self.folder("flash", frames)
        code, rep, out = self.report(d, "--first", 1, "--last", 10, "--stride", 1, "--grid", "2x2",
                                     "--threshold", 0.01)
        self.assertEqual(code, 1, out)
        by = {r["region"]: r for r in rep["results"]}
        self.assertEqual([f["region"] for f in rep["findings"]], ["r0c0"])
        worst = [(w["frame"], round(w["value"], 4)) for w in by["r0c0"]["worst"]]
        self.assertEqual(worst[0], (6, round(60 / 255, 4)))
        self.assertEqual(sorted(f for f, _ in worst), [5, 6, 7])
        self.assertAlmostEqual(worst[1][1], 30 / 255, places=4)
        for other in ("r0c1", "r1c0", "r1c1"):
            self.assertEqual(by[other]["mean"], 0.0)
        self.assertIn("r0c0", out)
        self.assertIn("flicker_metric: FAIL 1 finding(s)", out)

    def test_window_restricts_measurement(self):
        frames = [noisy(n, 20) for n in range(8)] + [flat(128)] * 6
        d = self.folder("win", frames)
        code, out, _ = self.run_tool(d, "--first", 1, "--last", 14, "--stride", 1, "--window", "10-14",
                                     "--threshold", 0.001)
        self.assertEqual(code, 0, out)
        code, out, _ = self.run_tool(d, "--first", 1, "--last", 14, "--stride", 1, "--window", "1-8",
                                     "--threshold", 0.001)
        self.assertEqual(code, 1, out)

    def test_region_option_measures_only_that_region(self):
        rng = random.Random(5)
        frames = []
        for _ in range(8):
            rows = flat(128)
            for y in range(H):
                for x in range(8, W):
                    rows[y][x] = 128 + rng.randint(-20, 20)
            frames.append(rows)
        d = self.folder("reg", frames)
        _, rep, _ = self.report(d, "--first", 1, "--last", 8, "--stride", 1, "--region", "0,0,8,12",
                                "--region", "8,0,8,12", "--threshold", 1.0)
        self.assertEqual(rep["results"][0]["mean"], 0.0)
        self.assertGreater(rep["results"][1]["mean"], 0.02)

    def test_reference_and_compare(self):
        a = self.folder("a", [noisy(n, 3) for n in range(10)])
        b = self.folder("b", [noisy(50 + n, 9) for n in range(10)])
        ref = self.folder("ref", [flat(128)] * 10)
        code, rep, out = self.report(a, "--first", 1, "--last", 10, "--stride", 1, "--threshold", 1.0,
                                     "--compare", b, "--reference", ref)
        self.assertEqual(code, 0, out)
        r = rep["results"][0]
        self.assertGreater(r["compare"]["mean"], r["mean"])
        self.assertAlmostEqual(r["compare"]["ratio_a_over_b"], r["mean"] / r["compare"]["mean"])
        self.assertGreater(r["compare"]["ratio_a_over_b"], 0.2)
        self.assertLess(r["compare"]["ratio_a_over_b"], 0.5)
        self.assertAlmostEqual(r["reference"]["mean"], 1.5 / 255, delta=0.0015)
        self.assertIn("ratio A/B", out)
        code, _, _ = self.run_tool(a, "--first", 1, "--last", 10, "--stride", 1, "--threshold", 0.0001,
                                   "--compare", b)
        self.assertEqual(code, 1)

    def test_pure_and_numpy_paths_agree(self):
        if not have("numpy"):
            self.skipTest("numpy not importable")
        d = self.folder("agree", [noisy(n, 12) for n in range(9)])
        res = []
        for pure in (True, False):
            with mode(pure):
                res.append(self.report(d, "--first", 1, "--last", 9, "--grid", "2x2", "--stride", 1,
                                       "--threshold", 1.0)[1]["results"])
        for p, n in zip(*res):
            self.assertAlmostEqual(p["mean"], n["mean"], places=10)
            self.assertAlmostEqual(p["p95"], n["p95"], places=10)


class CannotRun(FlickerCase):
    def test_missing_frame_exits_2(self):
        d = self.folder("gap", [flat(10)] * 6)
        os.remove(os.path.join(d, "frame_0003.png"))
        code, out, err = self.run_tool(d, "--first", 1, "--last", 6)
        self.assertEqual((code, out), (2, ""))
        self.assertIn("flicker_metric: ERROR", err)
        self.assertIn("frame 3 is missing", err)

    def test_window_with_fewer_than_three_frames_exits_2(self):
        d = self.folder("w2", [flat(10)] * 6)
        for win in ("2-3", "4-4"):
            code, _, err = self.run_tool(d, "--first", 1, "--last", 6, "--window", win)
            self.assertEqual(code, 2, win)
            self.assertIn("at least 3", err)
        self.assertEqual(self.run_tool(d, "--first", 1, "--last", 2)[0], 2)

    def test_bad_arguments_exit_2(self):
        d = self.folder("args", [flat(10)] * 6)
        cases = [["--window", "5-2"], ["--window", "x"], ["--window", "1-9"], ["--grid", "4"],
                 ["--grid", "0x3"], ["--grid", "40x2"], ["--region", "1,2,3"], ["--region", "10,0,10,4"],
                 ["--stride", "0"], ["--pattern", "frame.png"], ["--threshold", "-1"]]
        for extra in cases:
            code, _, err = self.run_tool(d, "--first", 1, "--last", 6, *extra)
            self.assertEqual(code, 2, extra)
            self.assertIn("ERROR", err)
        self.assertEqual(self.run_tool(d, "--first", 6, "--last", 1)[0], 2)

    def test_missing_folder_empty_folder_and_bad_png_exit_2(self):
        self.assertEqual(self.run_tool(os.path.join(self.root, "nope"), "--first", 1, "--last", 5)[0], 2)
        empty = os.path.join(self.root, "empty")
        os.makedirs(empty)
        self.assertEqual(self.run_tool(empty, "--first", 1, "--last", 5)[0], 2)
        d = self.folder("bad", [flat(10)] * 5)
        with open(os.path.join(d, "frame_0003.png"), "wb") as f:
            f.write(b"not a png")
        code, _, err = self.run_tool(d, "--first", 1, "--last", 5)
        self.assertEqual(code, 2)
        self.assertIn("unreadable PNG", err)

    def test_mixed_resolution_and_bad_reference_exit_2(self):
        d = self.folder("mix", [flat(10)] * 5)
        rc.write_png(os.path.join(d, "frame_0004.png"), 8, 6, 1, gray(flat(10, 8, 6)))
        self.assertEqual(self.run_tool(d, "--first", 1, "--last", 5)[0], 2)
        ok = self.folder("ok", [flat(10)] * 5)
        small = self.folder("small", [flat(10, 8, 6)] * 5, w=8, h=6)
        self.assertEqual(self.run_tool(ok, "--first", 1, "--last", 5, "--reference", small)[0], 2)
        self.assertEqual(self.run_tool(ok, "--first", 1, "--last", 5, "--compare", small)[0], 2)
        shortref = self.folder("shortref", [flat(10)] * 3)
        self.assertEqual(self.run_tool(ok, "--first", 1, "--last", 5, "--reference", shortref)[0], 2)


class Cli(unittest.TestCase):
    def test_help_exits_0_and_labels_the_threshold(self):
        p = subprocess.run([sys.executable, "-I", "-B", TOOL, "--help"], capture_output=True, text=True,
                           stdin=subprocess.DEVNULL, timeout=60)
        self.assertEqual(p.returncode, 0)
        self.assertIn("E7, uncalibrated: calibrate per project", p.stdout.replace("\n", " ").replace("  ", " "))

    def test_missing_required_arguments_exit_2(self):
        p = subprocess.run([sys.executable, "-I", "-B", TOOL], capture_output=True, text=True,
                           stdin=subprocess.DEVNULL, timeout=60)
        self.assertEqual(p.returncode, 2)


if __name__ == "__main__":
    unittest.main()
