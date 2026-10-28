"""Tests for render_common.py: PNG codec, frame names, path guards, helpers.

Run: python -I -B -m unittest discover -s docs/library/tools/tests -t docs/library/tools/tests -p "test_*.py"
Set RENDER_TOOLS_PURE=1 to run the whole suite on the stdlib path only (CI has no Pillow or numpy).
"""
import contextlib
import io
import os
import struct
import subprocess
import sys
import tempfile
import unittest
import zlib

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import render_common as rc  # noqa: E402

KEY = "RENDER_TOOLS_PURE"
GLOBAL_PURE = os.environ.get(KEY, "") not in ("", "0")
TOOL = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "render_common.py")


def have(name):
    try:
        __import__(name)
        return True
    except Exception:
        return False


HAVE_PIL, HAVE_NP = have("PIL"), have("numpy")


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


def modes():
    return [True] if GLOBAL_PURE else [True, False]


def pixels(w, h, c, maxval, seed=1):
    out, s = [], seed
    for _ in range(h):
        row = []
        for _ in range(w * c):
            s = (s * 1103515245 + 12345) & 0x7FFFFFFF
            row.append((s >> 8) % (maxval + 1))
        out.append(row)
    return out


def build_png(w, h, depth, ct, raw, extra=(), interlace=0, filt_raw=True):
    body = b"".join(rc.png_chunk(k, v) for k, v in extra)
    return rc.PNG_SIG + rc.png_chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, depth, ct, 0, 0, interlace)) \
        + body + rc.png_chunk(b"IDAT", zlib.compress(raw)) + rc.png_chunk(b"IEND", b"")


class TmpCase(unittest.TestCase):
    def setUp(self):
        self._td = tempfile.TemporaryDirectory()
        self.d = os.path.realpath(self._td.name)
        self.addCleanup(self._td.cleanup)

    def path(self, *parts):
        return os.path.join(self.d, *parts)

    def save(self, name, data):
        with open(self.path(name), "wb") as f:
            f.write(data)
        return self.path(name)


class PngCodec(TmpCase):
    def test_round_trip_all_layouts_and_filters(self):
        for c in (1, 2, 3, 4):
            for depth in (8, 16):
                for ft in range(5):
                    rows = pixels(7, 5, c, (1 << depth) - 1, seed=c + depth + ft)
                    p = self.path(f"a_{c}_{depth}_{ft}.png")
                    rc.write_png(p, 7, 5, c, rows, depth, ft)
                    for pure in modes():
                        with mode(pure):
                            img = rc.read_png(p)
                        self.assertEqual((img.width, img.height, img.channels, img.bitdepth),
                                         (7, 5, c, depth), (c, depth, ft, pure))
                        self.assertEqual(img.maxval, (1 << depth) - 1)
                        self.assertEqual([list(r) for r in img.rows], rows, (c, depth, ft, pure))

    @unittest.skipIf(GLOBAL_PURE or not HAVE_PIL, "Pillow not in use")
    def test_pillow_and_pure_agree(self):
        for c, depth in ((1, 8), (2, 8), (3, 8), (4, 8), (1, 16), (3, 16)):
            p = self.path(f"g_{c}_{depth}.png")
            rc.write_png(p, 9, 6, c, pixels(9, 6, c, (1 << depth) - 1, 5), depth, 4)
            with mode(True):
                a = rc.read_png(p)
            with mode(False):
                b = rc.read_png(p)
            self.assertEqual([list(r) for r in a.rows], [list(r) for r in b.rows])
            self.assertEqual((a.channels, a.bitdepth), (b.channels, b.bitdepth))

    def test_palette_with_and_without_trns(self):
        plte = bytes([255, 0, 0, 0, 255, 0, 0, 0, 255])
        raw = b"".join(b"\x00" + bytes(r) for r in ([0, 1, 2, 1], [2, 2, 0, 1]))
        want = [[255, 0, 0, 0, 255, 0, 0, 0, 255, 0, 255, 0], [0, 0, 255, 0, 0, 255, 255, 0, 0, 0, 255, 0]]
        plain = self.save("p.png", build_png(4, 2, 8, 3, raw, [(b"PLTE", plte)]))
        alpha = self.save("pa.png", build_png(4, 2, 8, 3, raw, [(b"PLTE", plte), (b"tRNS", bytes([0, 128]))]))
        for pure in modes():
            with mode(pure):
                a, b = rc.read_png(plain), rc.read_png(alpha)
            self.assertEqual((a.channels, [list(r) for r in a.rows]), (3, want), pure)
            self.assertEqual(b.channels, 4, pure)
            self.assertEqual(b.pixel(0, 0), (255, 0, 0, 0), pure)
            self.assertEqual(b.pixel(1, 0), (0, 255, 0, 128), pure)
            self.assertEqual(b.pixel(2, 0), (0, 0, 255, 255), pure)

    def test_gray_trns_is_ignored(self):
        raw = b"\x00" + bytes([1, 2, 3])
        p = self.save("t.png", build_png(3, 1, 8, 0, raw, [(b"tRNS", b"\x00\x02")]))
        for pure in modes():
            with mode(pure):
                img = rc.read_png(p)
            self.assertEqual((img.channels, list(img.rows[0])), (1, [1, 2, 3]))

    def expect_error(self, data, text):
        p = self.save("bad.png", data)
        for pure in modes():
            with mode(pure):
                with self.assertRaises(rc.CannotRun) as cm:
                    rc.read_png(p)
            self.assertIn("unreadable PNG", str(cm.exception))
            self.assertIn(text, str(cm.exception), pure)

    def test_corrupt_and_truncated_files(self):
        good = build_png(2, 2, 8, 0, b"\x00\x01\x02\x00\x03\x04")
        self.expect_error(b"", "signature")
        self.expect_error(b"GIF89a" + b"\x00" * 20, "signature")
        self.expect_error(good[:8], "truncated")
        self.expect_error(good[:20], "truncated")
        self.expect_error(good[:-5], "truncated")
        self.expect_error(good[:-12], "no IEND")
        flipped = bytearray(good)
        flipped[20] ^= 0xFF
        self.expect_error(bytes(flipped), "CRC")

    def test_header_and_data_problems(self):
        self.expect_error(build_png(2, 2, 8, 0, b"\x00\x01\x02\x00\x03\x04", interlace=1), "interlaced")
        self.expect_error(build_png(2, 2, 4, 0, b"\x00\x11\x00\x22"), "bit depth")
        self.expect_error(build_png(2, 2, 16, 3, b""), "bit depth")
        self.expect_error(build_png(0, 2, 8, 0, b""), "IHDR")
        self.expect_error(build_png(2, 2, 8, 3, b"\x00\x00\x01\x00\x00\x01"), "PLTE")
        self.expect_error(build_png(2, 2, 8, 0, b"\x00\x01"), "truncated image data")
        self.expect_error(build_png(2, 2, 8, 0, b"\x00" * 20), "longer")
        self.expect_error(build_png(2, 2, 8, 0, b"\x09\x01\x02\x00\x03\x04"), "filter type")
        self.expect_error(build_png(2, 2, 8, 3, b"\x00\x00\x07\x00\x00\x01", [(b"PLTE", b"\x00" * 6)]), "palette")
        no_data = rc.PNG_SIG + rc.png_chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, 8, 0, 0, 0, 0)) \
            + rc.png_chunk(b"IEND", b"")
        self.expect_error(no_data, "image data")
        bad_zlib = rc.PNG_SIG + rc.png_chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, 8, 0, 0, 0, 0)) \
            + rc.png_chunk(b"IDAT", b"not zlib data") + rc.png_chunk(b"IEND", b"")
        self.expect_error(bad_zlib, "corrupt image data")
        huge = build_png(2 ** 30, 2 ** 30, 8, 0, b"")
        self.expect_error(huge, "implausibly large")

    def test_missing_file(self):
        with self.assertRaises(rc.CannotRun):
            rc.read_png(self.path("nope.png"))

    def test_write_png_rejects_bad_input(self):
        p = self.path("w.png")
        for args in ((0, 1, 1, []), (2, 1, 1, [[1]]), (2, 1, 5, [[1, 2]]), (2, 2, 1, [[1, 2]]),
                     (2, 1, 1, [[1, 300]])):
            with self.assertRaises(rc.CannotRun, msg=args):
                rc.write_png(p, *args)
        with self.assertRaises(rc.CannotRun):
            rc.write_png(p, 1, 1, 1, [[70000]], 16)
        with self.assertRaises(rc.CannotRun):
            rc.write_png(self.path("missing", "w.png"), 1, 1, 1, [[1]])
        self.assertFalse(os.path.exists(p))
        self.assertEqual([n for n in os.listdir(self.d) if n.endswith(".tmp")], [])

    def test_extreme_values_survive(self):
        rc.write_png(self.path("e.png"), 2, 1, 1, [[0, 65535]], 16)
        for pure in modes():
            with mode(pure):
                self.assertEqual(list(rc.read_png(self.path("e.png")).rows[0]), [0, 65535])


class LumaTests(TmpCase):
    def test_values(self):
        img = rc.Image(2, 1, 3, 8, [bytes([255, 255, 255, 0, 0, 0])])
        self.assertAlmostEqual(rc.luma(img)[0][0], 1.0)
        self.assertEqual(rc.luma(img)[0][1], 0.0)
        red = rc.Image(1, 1, 3, 8, [bytes([255, 0, 0])])
        self.assertAlmostEqual(rc.luma(red)[0][0], 0.2126)
        gray = rc.Image(2, 1, 1, 16, [[0, 65535]])
        self.assertEqual(rc.luma(gray), [[0.0, 1.0]])
        ga = rc.Image(2, 1, 2, 8, [bytes([51, 255, 255, 0])])
        self.assertEqual(rc.luma(ga), [[51 / 255.0, 1.0]])

    def test_stride_and_errors(self):
        img = rc.Image(5, 5, 1, 8, [bytes(range(i * 5, i * 5 + 5)) for i in range(5)])
        out = rc.luma(img, 2)
        self.assertEqual((len(out), len(out[0])), (3, 3))
        self.assertAlmostEqual(out[1][1], 12 / 255.0)
        with self.assertRaises(rc.CannotRun):
            rc.luma(img, 0)

    def test_paths_agree(self):
        for c, depth in ((1, 8), (3, 8), (4, 8), (2, 16), (3, 16)):
            rows = pixels(11, 9, c, (1 << depth) - 1, 3)
            img = rc.Image(11, 9, c, depth, [bytes(r) if depth == 8 else r for r in rows])
            for stride in (1, 3):
                results = []
                for pure in modes() + ([False] if not GLOBAL_PURE else []):
                    with mode(pure):
                        results.append(rc.luma(img, stride))
                for r in results[1:]:
                    for ra, rb in zip(results[0], r):
                        for a, b in zip(ra, rb):
                            self.assertAlmostEqual(a, b, places=12)
                self.assertTrue(all(0.0 <= v <= 1.0 for row in results[0] for v in row))

    def test_rgb8_rows(self):
        gray16 = rc.Image(2, 1, 1, 16, [[0, 65535]])
        self.assertEqual(rc.rgb8_rows(gray16), [bytes([0, 0, 0, 255, 255, 255])])
        self.assertEqual(rc.rgb8_rows(rc.Image(1, 1, 1, 16, [[32768]])), [bytes([128, 128, 128])])
        rgba = rc.Image(2, 1, 4, 8, [bytes([1, 2, 3, 9, 4, 5, 6, 9])])
        self.assertEqual(rc.rgb8_rows(rgba), [bytes([1, 2, 3, 4, 5, 6])])
        ga = rc.Image(1, 1, 2, 8, [bytes([7, 200])])
        self.assertEqual(rc.rgb8_rows(ga), [bytes([7, 7, 7])])


class FrameNames(TmpCase):
    def test_frame_path(self):
        self.assertEqual(os.path.basename(rc.frame_path("x", "frame_####.png", 7)), "frame_0007.png")
        self.assertEqual(os.path.basename(rc.frame_path("x", "f#.exr", 12)), "f12.exr")
        self.assertEqual(os.path.basename(rc.frame_path("x", "frame_####.png", 12345)), "frame_12345.png")
        for bad in ("frame.png", "a#b#.png", "../x_##.png", "d/x_##.png", ""):
            with self.assertRaises(rc.CannotRun, msg=bad):
                rc.frame_path("x", bad, 1)
        with self.assertRaises(rc.CannotRun):
            rc.frame_path("x", "f_##.png", -1)

    def test_scan_frames(self):
        for name in ("frame_0001.png", "frame_0002.png", "frame_10000.png", "frame_00003.png", "frame_3.png",
                     "frame_0004.jpg", "other_0005.png", "frame_0006.png.tmp"):
            self.save(name, b"x")
        os.mkdir(self.path("frame_0009.png"))
        found = rc.scan_frames(self.d, "frame_####.png")
        self.assertEqual(sorted(found), [1, 2, 10000])
        self.assertEqual(found[2], self.path("frame_0002.png"))
        self.assertEqual(rc.scan_frames(self.d, "other_####.png"), {5: self.path("other_0005.png")})
        with self.assertRaises(rc.CannotRun):
            rc.scan_frames(self.path("missing"), "f_####.png")
        with self.assertRaises(rc.CannotRun):
            rc.scan_frames(self.d, "nohash.png")

    def test_ranges(self):
        self.assertEqual(rc.parse_frame_list("1, 24,48"), [1, 24, 48])
        self.assertEqual(rc.parse_frame_list("3-5,9"), [3, 4, 5, 9])
        self.assertEqual(rc.parse_ranges("2-4"), [(2, 4)])
        for bad in ("", "a", "5-3", "1,,2", "-1", "1-", "1.5", "0-9999999"):
            with self.assertRaises(rc.CannotRun, msg=bad):
                rc.parse_frame_list(bad)
        self.assertEqual(rc.format_ranges([5, 1, 2, 3, 9, 9]), "1-3, 5, 9")
        self.assertEqual(rc.format_ranges([]), "")
        self.assertEqual(rc.group_ranges([2, 3, 7]), [(2, 3), (7, 7)])


class PathsAndFiles(TmpCase):
    def test_require_abs(self):
        self.assertEqual(rc.require_abs(self.d, "x"), self.d)
        for bad in ("rel/path", "", None, "."):
            with self.assertRaises(rc.CannotRun, msg=bad):
                rc.require_abs(bad, "--out")

    def test_git_worktree_and_cloud(self):
        self.assertFalse(rc.in_git_worktree(self.path("a", "b.png")))
        os.mkdir(self.path(".git"))
        self.assertTrue(rc.in_git_worktree(self.path("a", "b.png")))
        self.assertTrue(rc.in_git_worktree(self.d))
        os.makedirs(self.path("linked"))
        self.save(os.path.join("linked", ".git"), b"gitdir: x")
        self.assertTrue(rc.in_git_worktree(self.path("linked", "out.png")))
        for p in ("C:/Users/a/OneDrive/x.png", "C:/Users/a/OneDrive - Corp/x.png", "/home/a/Dropbox/x",
                  "/Users/a/iCloud/x", "/Users/a/iCloudDrive/x", "C:/Users/a/Google Drive/x",
                  "C:/Users/a/GoogleDrive/x", "C:\\Users\\a\\onedrive\\x"):
            self.assertTrue(rc.cloud_synced(p), p)
        for p in ("C:/Users/a/Documents/x", "/data/render", "C:/Users/a/OneDriveTools/x",
                  "/tmp/dropboxish/x", "C:/Users/a/Work-OneDrive/x"):
            self.assertFalse(rc.cloud_synced(p), p)

    def test_check_output_path(self):
        self.assertEqual(rc.check_output_path(self.path("o.png"), "--out"), [])
        warn = rc.check_output_path(self.path("OneDrive", "o.png"), "--out")
        self.assertEqual(len(warn), 1)
        os.mkdir(self.path(".git"))
        with self.assertRaises(rc.CannotRun) as cm:
            rc.check_output_path(self.path("o.png"), "--out")
        self.assertIn("--allow-in-repo", str(cm.exception))
        self.assertEqual(rc.check_output_path(self.path("o.png"), "--out", allow_in_repo=True), [])
        with self.assertRaises(rc.CannotRun):
            rc.check_output_path("rel.png", "--out")

    def test_sha_and_json(self):
        p = self.save("a.bin", b"abc")
        self.assertEqual(rc.sha256_file(p),
                         "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        self.save("empty.bin", b"")
        self.assertEqual(rc.sha256_file(self.path("empty.bin"))[:8], "e3b0c442")
        with self.assertRaises(rc.CannotRun):
            rc.sha256_file(self.path("none"))
        j = self.path("sub", "r.json")
        rc.write_json_atomic(j, {"b": 1, "a": [1, 2]})
        rc.write_json_atomic(j, {"b": 2})
        with open(j, encoding="utf-8") as f:
            self.assertEqual(f.read(), '{\n  "b": 2\n}\n')
        self.assertEqual(os.listdir(self.path("sub")), ["r.json"])

    def test_finish(self):
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            self.assertEqual(rc.finish("t", [], "(ok)"), rc.PASS)
            self.assertEqual(rc.finish("t", [{"kind": "k", "message": "m"}], "(x)", self.path("f.json")), rc.FAIL)
        lines = buf.getvalue().splitlines()
        self.assertEqual(lines, ["t: PASS (ok)", "k: m", "t: FAIL 1 finding(s) (x)"])
        self.assertTrue(os.path.exists(self.path("f.json")))


class Cli(unittest.TestCase):
    def test_main(self):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            self.assertEqual(rc.main(["--self-test"]), 0)
        self.assertIn("PASS", out.getvalue())
        err = io.StringIO()
        with contextlib.redirect_stderr(err):
            self.assertEqual(rc.main([]), 2)
            with self.assertRaises(SystemExit) as cm:
                rc.main(["--bogus"])
        self.assertEqual(cm.exception.code, 2)
        self.assertIn("render_common: ERROR", err.getvalue())

    def test_subprocess_help_and_self_test(self):
        for args, code in (([ "--help"], 0), (["--self-test"], 0), ([], 2)):
            done = subprocess.run([sys.executable, "-I", TOOL, *args], capture_output=True, text=True,
                                  stdin=subprocess.DEVNULL, check=False)
            self.assertEqual(done.returncode, code, done.stderr)


if __name__ == "__main__":
    unittest.main()
