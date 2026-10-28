"""Tests for color_check.py on small synthetic PNG sequences (no Blender, no GPU).

Set RENDER_TOOLS_PURE=1 to force the stdlib path; both paths are compared when numpy is importable.
"""
import contextlib
import io
import json
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import color_check as cc  # noqa: E402
import render_common as rc  # noqa: E402

KEY = "RENDER_TOOLS_PURE"
W, H = 20, 12


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


def flat(v, w=W, h=H, ch=3):
    return [bytes([v] * (w * ch)) for _ in range(h)]


def run(argv):
    out, err = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        try:
            code = cc.main(argv)
        except SystemExit as e:
            code = e.code
    return code, out.getvalue(), err.getvalue()


class SeqCase(unittest.TestCase):
    def setUp(self):
        self._td = tempfile.TemporaryDirectory()
        self.addCleanup(self._td.cleanup)
        self.d = os.path.realpath(self._td.name)

    def put(self, n, rows, ch=3, bitdepth=8, w=W, h=H):
        rc.write_png(os.path.join(self.d, f"frame_{n:04d}.png"), w, h, ch, rows, bitdepth)

    def seq(self, n=6, v=100, **kw):
        for i in range(1, n + 1):
            self.put(i, flat(v, ch=kw.get("ch", 3)), ch=kw.get("ch", 3))

    def check(self, first, last, *extra):
        return run([self.d, "--first", str(first), "--last", str(last), "--stride", "1"] + list(extra))


class FindingTests(SeqCase):
    def test_clean_sequence_passes(self):
        self.seq()
        code, out, _ = self.check(1, 6)
        self.assertEqual(code, 0, out)
        self.assertIn("color_check: PASS 6 frame(s) 1-6", out.splitlines()[-1])

    def test_bit_depth_mismatch_names_frames(self):
        self.seq(5)
        self.put(3, [[30000] * (W * 3) for _ in range(H)], bitdepth=16)
        code, out, _ = self.check(1, 5)
        self.assertEqual(code, 1)
        self.assertIn("bitdepth: frames 3 are not 8 bit", out)

    def test_expected_bitdepth_flag(self):
        self.seq(3)
        code, out, _ = self.check(1, 3, "--bitdepth", "16")
        self.assertEqual(code, 1)
        self.assertIn("frames 1-3 are not 16 bit", out)

    def test_sixteen_bit_sequence_passes(self):
        for i in range(1, 4):
            self.put(i, [[30000 + i] * (W * 3) for _ in range(H)], bitdepth=16)
        self.assertEqual(self.check(1, 3, "--bitdepth", "16")[0], 0)

    def test_unexpected_alpha(self):
        self.seq(4)
        self.put(2, [bytes([100, 100, 100, 255] * W) for _ in range(H)], ch=4)
        self.assertEqual(self.check(1, 4)[0], 0)  # alpha allowed unless asked
        code, out, _ = self.check(1, 4, "--no-alpha")
        self.assertEqual(code, 1)
        self.assertIn("alpha: frames 2 have an alpha channel", out)

    def test_clipped_highlights(self):
        self.seq(4)
        rows = flat(100)
        rows[0] = bytes([255] * (W * 3))  # 1 of 12 rows = 8.3 percent
        rows[1] = bytes([255] * (W * 3))
        self.put(3, rows)
        code, out, _ = self.check(1, 4, "--jump", "1")
        self.assertEqual(code, 1)
        self.assertIn("clipped: 1 frame(s)", out)
        self.assertIn("3", out)
        code, out, _ = self.check(1, 4, "--jump", "1", "--clip-frac", "0.5")
        self.assertEqual(code, 0, out)

    def test_crushed_blacks_and_opt_out(self):
        self.seq(4, v=0)
        code, out, _ = self.check(1, 4)
        self.assertEqual(code, 1)
        self.assertIn("crushed: 4 frame(s)", out)
        self.assertEqual(self.check(1, 4, "--no-crush-check")[0], 0)

    def test_one_channel_at_zero_counts(self):
        for i in range(1, 4):
            self.put(i, [bytes([0, 120, 120] * W) for _ in range(H)])
        code, out, _ = self.check(1, 3)
        self.assertIn("crushed", out)

    def test_exposure_pop(self):
        for i in range(1, 7):
            self.put(i, flat(100 if i < 4 else 140))
        code, out, _ = self.check(1, 6)
        self.assertEqual(code, 1)
        self.assertIn("exposure-pop", out)
        self.assertIn("4 (+", out)
        self.assertEqual(self.check(1, 6, "--jump", "0.5")[0], 0)

    def test_slow_drift_is_not_a_pop(self):
        for i in range(1, 7):
            self.put(i, flat(100 + 3 * i))
        self.assertEqual(self.check(1, 6)[0], 0)

    def test_gray_images(self):
        for i in range(1, 4):
            self.put(i, [bytes([100] * W) for _ in range(H)], ch=1)
        self.assertEqual(self.check(1, 3)[0], 0)


class ErrorTests(SeqCase):
    def test_missing_frame_exit_2(self):
        self.seq(5)
        os.remove(os.path.join(self.d, "frame_0003.png"))
        code, _, err = self.check(1, 5)
        self.assertEqual(code, 2)
        self.assertIn("color_check: ERROR", err)
        self.assertIn("3", err)

    def test_corrupt_frame_exit_2(self):
        self.seq(3)
        with open(os.path.join(self.d, "frame_0002.png"), "wb") as fh:
            fh.write(b"not a png")
        self.assertEqual(self.check(1, 3)[0], 2)

    def test_bad_arguments_exit_2(self):
        self.seq(3)
        self.assertEqual(self.check(3, 1)[0], 2)
        self.assertEqual(run([os.path.join(self.d, "nope"), "--first", "1", "--last", "2"])[0], 2)
        self.assertEqual(self.check(1, 3, "--clip-frac", "2")[0], 2)
        self.assertEqual(run([self.d, "--first", "1", "--last", "3", "--stride", "0"])[0], 2)
        self.assertEqual(run([self.d, "--first", "1", "--last", "3", "--pattern", "frame.png"])[0], 2)
        self.assertEqual(run([self.d])[0], 2)

    def test_json_report_and_help(self):
        self.seq(3)
        rep = os.path.join(self.d, "r.json")
        code, _, _ = self.check(1, 3, "--json", rep)
        self.assertEqual(code, 0)
        with open(rep, "r", encoding="utf-8") as fh:
            data = json.load(fh)
        self.assertEqual((data["status"], len(data["frames"])), ("pass", 3))
        self.assertEqual(run(["--help"])[0], 0)


class PathAgreementTests(SeqCase):
    def test_pure_and_fast_paths_agree(self):
        rows = [bytes(((x * 13 + y * 7 + k * 50) % 256) if (x + y) % 5 else (0 if k == 1 else 255)
                      for x in range(W) for k in range(3)) for y in range(H)]
        self.put(1, rows)
        img = rc.read_png(os.path.join(self.d, "frame_0001.png"))
        results = []
        for pure in (True, False):
            with mode(pure):
                results.append((cc.clip_fractions(img, 1), cc.clip_fractions(img, 3), cc.mean_luma(img, 2)))
        self.assertEqual(results[0][0], results[1][0])
        self.assertEqual(results[0][1], results[1][1])
        self.assertAlmostEqual(results[0][2], results[1][2], places=9)
        self.assertGreater(results[0][0][0], 0)
        self.assertGreater(results[0][0][1], 0)

    def test_sixteen_bit_agreement(self):
        rows = [[(x * 977 + y * 31 + k * 4000) % 65536 if (x + y) % 4 else 0 for x in range(W) for k in range(3)]
                for y in range(H)]
        self.put(1, rows, bitdepth=16)
        img = rc.read_png(os.path.join(self.d, "frame_0001.png"))
        with mode(True):
            a = cc.clip_fractions(img, 2)
        with mode(False):
            b = cc.clip_fractions(img, 2)
        self.assertEqual(a, b)

    def test_end_to_end_same_findings_both_modes(self):
        for i in range(1, 6):
            self.put(i, flat(100 if i < 4 else 150))
        outs = []
        for pure in (True, False):
            with mode(pure):
                outs.append(self.check(1, 5))
        self.assertEqual(outs[0][:2], outs[1][:2])

    @unittest.skipUnless(have("numpy"), "numpy not installed")
    def test_numpy_path_is_exercised(self):
        with mode(False):
            self.assertIsNotNone(rc._numpy())


if __name__ == "__main__":
    unittest.main()
