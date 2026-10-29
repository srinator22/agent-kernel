"""Tests for frame_audit.py on small synthetic PNG sequences (no Blender, no GPU).

Run: python -I -B -m unittest discover -s docs/library/tools/tests -t docs/library/tools/tests -p "test_*.py"
Set RENDER_TOOLS_PURE=1 to force the stdlib path; both paths are compared when Pillow and numpy exist.
"""
import contextlib
import io
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import frame_audit as fa  # noqa: E402
import render_common as rc  # noqa: E402

KEY = "RENDER_TOOLS_PURE"
GLOBAL_PURE = os.environ.get(KEY, "") not in ("", "0")
TOOL = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "frame_audit.py")
W, H = 24, 16


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


def noise(seed, w=W, h=H, lo=20, hi=100):
    out, s = [], seed * 7919 + 1
    for _ in range(h):
        row = []
        for _ in range(w * 3):
            s = (s * 1103515245 + 12345) & 0x7FFFFFFF
            row.append(lo + (s >> 8) % (hi - lo))
        out.append(bytes(row))
    return out


def solid(v, w=W, h=H):
    return [bytes([v] * (w * 3)) for _ in range(h)]


def gradient(w=W, h=H):
    return [bytes([20 + x * 3 for x in range(w) for _ in range(3)]) for _ in range(h)]


class AuditCase(unittest.TestCase):
    def setUp(self):
        self._td = tempfile.TemporaryDirectory()
        self.addCleanup(self._td.cleanup)
        self.d = os.path.realpath(self._td.name)

    def put(self, n, rows, w=W, h=H, name="frame_{:04d}.png"):
        rc.write_png(os.path.join(self.d, name.format(n)), w, h, 3, rows)

    def seq(self, first=1, last=12):
        for n in range(first, last + 1):
            self.put(n, noise(n))

    def run_tool(self, *args, first=1, last=12):
        out, err = io.StringIO(), io.StringIO()
        argv = [self.d, "--first", str(first), "--last", str(last), *args]
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = fa.main(argv)
        return code, out.getvalue(), err.getvalue()


class Findings(AuditCase):
    def test_clean_sequence_passes_and_writes_json(self):
        self.seq()
        j = os.path.join(self.d, "out", "r.json")
        code, out, err = self.run_tool("--json", j)
        self.assertEqual((code, err), (0, ""), out)
        self.assertTrue(out.strip().splitlines()[-1].startswith("frame_audit: PASS"))
        self.assertIn("expected 12, present 12", out)
        with open(j, encoding="utf-8") as f:
            rep = json.load(f)
        self.assertEqual((rep["tool"], rep["status"], rep["findings"], rep["present"]), ("frame_audit", "pass", [], 12))
        self.assertEqual(len(rep["frames"]), 12)
        self.assertGreater(rep["frames"]["3"]["mean_luma"], 0.05)

    def test_missing_frames_ranges_and_chunks(self):
        self.seq()
        for n in (3, 4, 9):
            os.remove(os.path.join(self.d, f"frame_{n:04d}.png"))
        code, out, _ = self.run_tool()
        self.assertEqual(code, 1)
        self.assertIn("missing: 3 frame(s) missing: 3-4, 9", out)
        self.assertIn("FAIL 1 finding(s)", out)
        code, out, _ = self.run_tool("--chunk", "4")
        self.assertEqual(code, 1)
        # Chunks count from 1, as in render_chunks (review note: they were numbered from 0 here).
        self.assertIn("chunk 1 (frames 1-4) is missing 2 frame(s): 3-4", out)
        self.assertIn("chunk 3 (frames 9-12) is missing 1 frame(s): 9", out)
        self.assertNotIn("chunk 2", out)
        self.assertIn("missing 2", out)

    def test_empty_folder_reports_everything_missing(self):
        code, out, err = self.run_tool(first=1, last=5)
        self.assertEqual(code, 1, err)
        self.assertIn("5 frame(s) missing: 1-5", out)
        self.assertIn("present 0", out)

    def test_unexpected_frames(self):
        self.seq()
        self.put(99, noise(99))
        self.put(0, noise(50))
        code, out, _ = self.run_tool()
        self.assertEqual(code, 1)
        self.assertIn("unexpected: 2 frame(s) outside 1-12: 0, 99", out)

    def test_unreadable_frames_are_findings_not_crashes(self):
        self.seq()
        p3 = os.path.join(self.d, "frame_0003.png")
        with open(p3, "rb") as f:
            data = f.read()
        with open(p3, "wb") as f:
            f.write(data[: len(data) // 2])
        with open(os.path.join(self.d, "frame_0005.png"), "wb") as f:
            f.write(b"")
        with open(os.path.join(self.d, "frame_0006.png"), "wb") as f:
            f.write(b"not a png at all")
        code, out, err = self.run_tool()
        self.assertEqual((code, err), (1, ""), out)
        for n in (3, 5, 6):
            self.assertIn(f"unreadable: frame {n}: unreadable PNG", out)
        self.assertNotIn("Traceback", out)

    def test_resolution(self):
        self.seq()
        self.put(7, noise(7, 30, 16), 30, 16)
        code, out, _ = self.run_tool()
        self.assertEqual(code, 1)
        self.assertIn("resolution: frame 7 is 30x16, expected 24x16", out)
        code, out, _ = self.run_tool("--width", "30", "--height", "16")
        self.assertEqual(out.count("resolution:"), 11)
        self.assertNotIn("frame 7 is", out)

    def test_first_frame_unreadable_still_sets_reference_from_next(self):
        self.seq()
        with open(os.path.join(self.d, "frame_0001.png"), "wb") as f:
            f.write(b"bad")
        code, out, _ = self.run_tool()
        self.assertEqual(out.count("resolution:"), 0)
        self.assertIn("unreadable: frame 1", out)

    def test_black_and_blank(self):
        self.seq()
        self.put(4, solid(0))
        self.put(8, solid(128))
        self.put(9, noise(9, lo=0, hi=2))
        code, out, _ = self.run_tool()
        self.assertEqual(code, 1)
        self.assertIn("black: frame 4 is black", out)
        self.assertNotIn("blank: frame 4", out)
        self.assertIn("blank: frame 8 is blank", out)
        self.assertIn("black: frame 9 is black", out)
        code, out, _ = self.run_tool("--black-mean", "0", "--blank-std", "0")
        self.assertNotIn("black:", out)
        self.assertNotIn("blank:", out)

    def test_fireflies(self):
        self.seq()
        rows = [bytearray(r) for r in noise(5)]
        for x in (3, 8, 15):
            rows[6][x * 3:x * 3 + 3] = b"\xff\xff\xff"
        self.put(5, [bytes(r) for r in rows])
        code, out, _ = self.run_tool()
        self.assertEqual(code, 1)
        self.assertIn("firefly: frame 5 has 3 firefly pixel(s)", out)
        self.assertEqual(out.count("firefly:"), 1)
        code, out, _ = self.run_tool("--firefly-frac", "0.5")
        self.assertEqual(code, 0, out)

    def test_firefly_edge_pixels_and_small_grids(self):
        self.assertEqual(fa.count_fireflies([]), (0, 0))
        self.assertEqual(fa.count_fireflies([[1.0, 1.0], [1.0, 1.0]]), (0, 0))
        grid = [[0.1] * 5 for _ in range(5)]
        grid[0][0] = 1.0
        self.assertEqual(fa.count_fireflies(grid), (0, 9))
        grid[2][2] = 1.0
        self.assertEqual(fa.count_fireflies(grid), (1, 9))
        self.assertEqual(fa.count_fireflies([[1.0] * 6 for _ in range(6)]), (0, 16))

    def test_size_anomaly(self):
        self.seq()
        self.put(6, gradient())
        code, out, _ = self.run_tool()
        self.assertEqual(code, 1)
        self.assertIn("size: frame 6 is", out)
        self.assertEqual(out.count("size:"), 1)
        code, out, _ = self.run_tool("--size-ratio", "0.01")
        self.assertEqual(code, 0, out)

    def test_size_check_needs_three_frames(self):
        self.put(1, noise(1))
        self.put(2, gradient())
        code, out, _ = self.run_tool(first=1, last=2)
        self.assertEqual(code, 0, out)

    def test_duplicates_and_allowed_holds(self):
        self.seq()
        shutil_copy = lambda a, b: shutil.copyfile(os.path.join(self.d, f"frame_{a:04d}.png"),
                                                   os.path.join(self.d, f"frame_{b:04d}.png"))
        shutil_copy(5, 6)
        shutil_copy(5, 7)
        code, out, _ = self.run_tool()
        self.assertEqual(code, 1)
        self.assertIn("duplicate: frame(s) 6-7 identical to the previous frame (2 frame(s))", out)
        self.assertEqual(self.run_tool("--allow-duplicates", "5-7")[0], 0)
        self.assertEqual(self.run_tool("--allow-duplicates", "1-3,5-7")[0], 0)
        code, out, _ = self.run_tool("--allow-duplicates", "5-6")
        self.assertEqual(code, 1)
        self.assertIn("frame(s) 7-7", out)

    def test_gap_between_identical_frames_is_not_consecutive(self):
        self.seq()
        shutil.copyfile(os.path.join(self.d, "frame_0005.png"), os.path.join(self.d, "frame_0007.png"))
        os.remove(os.path.join(self.d, "frame_0006.png"))
        code, out, _ = self.run_tool()
        self.assertNotIn("duplicate:", out)

    def test_sixteen_bit_gray_frames(self):
        for n in range(1, 5):
            rows = [[v * 257 for v in noise(n, 8, 8)[y][0::3]] for y in range(8)]
            rc.write_png(os.path.join(self.d, f"frame_{n:04d}.png"), 8, 8, 1, rows, 16)
        code, out, err = self.run_tool(first=1, last=4)
        self.assertEqual(code, 0, out + err)

    def test_rgba_frames(self):
        for n in range(1, 5):
            rc.write_png(os.path.join(self.d, f"frame_{n:04d}.png"), 8, 8, 4,
                         [[(x * 9 + y * n + (x * y) % 7) % 60 + 20 for x in range(32)] for y in range(8)])
        code, out, err = self.run_tool(first=1, last=4)
        self.assertEqual(code, 0, out + err)

    def test_single_frame(self):
        self.put(3, noise(3))
        self.assertEqual(self.run_tool(first=3, last=3)[0], 0)

    def test_custom_pattern(self):
        for n in range(10, 13):
            self.put(n, noise(n), name="shot_a_{:03d}.png")
        self.assertEqual(self.run_tool("--pattern", "shot_a_###.png", first=10, last=12)[0], 0)
        code, out, _ = self.run_tool("--pattern", "shot_a_####.png", first=10, last=12)
        self.assertEqual(code, 1)
        self.assertIn("3 frame(s) missing", out)


class CannotRun(AuditCase):
    def assert_cannot(self, *args, first=1, last=5, text=None):
        code, out, err = self.run_tool(*args, first=first, last=last)
        self.assertEqual(code, 2, out + err)
        self.assertTrue(err.startswith("frame_audit: ERROR"), err)
        if text:
            self.assertIn(text, err)

    def test_exr_and_other_formats(self):
        self.assert_cannot("--pattern", "f_####.exr", text="NaN and EXR checks need an EXR reader")
        self.assert_cannot("--pattern", "f_####.EXR", text="EXR reader")
        self.assert_cannot("--pattern", "f_####.jpg", text="only PNG")
        self.assert_cannot("--pattern", "f_####", text="only PNG")

    def test_bad_arguments(self):
        self.assert_cannot("--pattern", "frame.png", text="'#'")
        self.assert_cannot(first=5, last=1, text="bad range")
        self.assert_cannot("--width", "10", text="together")
        self.assert_cannot("--width", "0", "--height", "5", text="positive")
        self.assert_cannot("--size-ratio", "1.5", text="size-ratio")
        self.assert_cannot("--size-ratio", "0", text="size-ratio")
        self.assert_cannot("--stride", "0", text="stride")
        self.assert_cannot("--chunk", "-1", text="chunk")
        self.assert_cannot("--allow-duplicates", "x", text="allow-duplicates")
        self.assert_cannot("--allow-duplicates", "9-3", text="runs backwards")

    def test_missing_directory(self):
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = fa.main([os.path.join(self.d, "nope"), "--first", "1", "--last", "2"])
        self.assertEqual(code, 2)
        self.assertIn("not a directory", err.getvalue())

    def test_argparse_errors_exit_2(self):
        with contextlib.redirect_stderr(io.StringIO()):
            for argv in ([], [self.d], [self.d, "--first", "a", "--last", "2"]):
                with self.assertRaises(SystemExit) as cm:
                    fa.main(argv)
                self.assertEqual(cm.exception.code, 2)

    def test_help_exit_code(self):
        done = subprocess.run([sys.executable, "-I", TOOL, "--help"], capture_output=True, text=True,
                              stdin=subprocess.DEVNULL, check=False)
        self.assertEqual(done.returncode, 0)
        self.assertIn("--allow-duplicates", done.stdout)


@unittest.skipIf(GLOBAL_PURE or not (have("PIL") and have("numpy")), "needs Pillow and numpy")
class PathsAgree(AuditCase):
    def test_pure_and_fast_reports_match(self):
        self.seq()
        rows = [bytearray(r) for r in noise(5)]
        rows[6][9:12] = b"\xff\xff\xff"
        self.put(5, [bytes(r) for r in rows])
        self.put(4, solid(0))
        os.remove(os.path.join(self.d, "frame_0009.png"))
        reports = []
        for pure in (True, False):
            with mode(pure):
                j = os.path.join(self.d, f"r_{pure}.json")
                code, out, _ = self.run_tool("--json", j)
            with open(j, encoding="utf-8") as f:
                reports.append((code, out, json.load(f)))
        (c1, o1, r1), (c2, o2, r2) = reports
        self.assertEqual((c1, o1), (c2, o2))
        self.assertEqual(r1["counts"], r2["counts"])
        self.assertEqual([f["message"] for f in r1["findings"]], [f["message"] for f in r2["findings"]])
        for n, v in r1["frames"].items():
            self.assertAlmostEqual(v["mean_luma"], r2["frames"][n]["mean_luma"], places=9)
            self.assertAlmostEqual(v["std_luma"], r2["frames"][n]["std_luma"], places=9)
            self.assertEqual(v["fireflies"], r2["frames"][n]["fireflies"])

    def test_firefly_counters_agree(self):
        import random
        rnd = random.Random(4)
        grid = [[rnd.random() ** 3 for _ in range(30)] for _ in range(20)]
        results = []
        for pure in (True, False):
            with mode(pure):
                results.append(fa.count_fireflies(grid))
        self.assertEqual(results[0], results[1])
        self.assertGreater(results[0][1], 0)


if __name__ == "__main__":
    unittest.main()
