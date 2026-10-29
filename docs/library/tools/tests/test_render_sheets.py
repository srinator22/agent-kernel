"""Tests for render_sheets.py on tiny synthetic frames (no Blender, no GPU).

Run: python -I -B -m unittest discover -s docs/library/tools/tests -t docs/library/tools/tests -p "test_*.py"
Set RENDER_TOOLS_PURE=1 to force the stdlib path; both paths are compared when Pillow and numpy exist.
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
import render_common as rc  # noqa: E402
import render_sheets as rs  # noqa: E402

KEY = "RENDER_TOOLS_PURE"
GLOBAL_PURE = os.environ.get(KEY, "") not in ("", "0")
TOOL = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "render_sheets.py")
W, H = 32, 16
BG, FG = (40, 40, 40), (235, 235, 235)
LH = 7 * 2 + 8  # caption band
COLORS = {1: (200, 30, 30), 2: (30, 200, 30), 3: (30, 30, 200), 4: (200, 200, 30)}


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


class SheetCase(unittest.TestCase):
    def setUp(self):
        self._td = tempfile.TemporaryDirectory()
        self.addCleanup(self._td.cleanup)
        self.d = os.path.realpath(self._td.name)
        self.a = os.path.join(self.d, "a")
        self.b = os.path.join(self.d, "b")
        os.makedirs(self.a)
        os.makedirs(self.b)
        for n, color in COLORS.items():
            self.frame(self.a, n, color)
            self.frame(self.b, n, color)

    def frame(self, folder, n, color, w=W, h=H):
        rc.write_png(os.path.join(folder, f"frame_{n:04d}.png"), w, h, 3, [bytes(color) * w] * h)

    def out(self, name="sheet.png"):
        return os.path.join(self.d, name)

    def run_tool(self, *argv):
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = rs.main(list(argv))
        return code, out.getvalue(), err.getvalue()

    def read(self, path):
        img = rc.read_png(path)
        return img, (lambda x, y: img.pixel(x, y))


class Contact(SheetCase):
    def test_layout_colours_and_captions(self):
        o = self.out()
        code, out, err = self.run_tool("contact", self.a, "--frames", "1,2,3", "--cols", "2",
                                       "--thumb-width", "64", "--out", o)
        self.assertEqual((code, err), (0, ""), out)
        self.assertTrue(out.startswith("render_sheets: PASS wrote"))
        img, px = self.read(o)
        th = 32
        self.assertEqual((img.width, img.height), (8 + 2 * 72, 8 + 2 * (th + LH + 8)))
        self.assertEqual(px(0, 0), BG)
        self.assertEqual(px(8 + 10, 8 + 10), COLORS[1])
        self.assertEqual(px(8 + 72 + 10, 8 + 10), COLORS[2])
        self.assertEqual(px(8 + 10, 8 + 62 + 10), COLORS[3])
        self.assertEqual(px(8 + 72 + 10, 8 + 62 + 10), BG)  # empty fourth cell stays gutter
        band = [px(x, y) for y in range(8 + th, 8 + th + LH) for x in range(8, 8 + 64)]
        self.assertIn(FG, band)

    def test_label_banner_adds_height(self):
        a, b = self.out("a.png"), self.out("b.png")
        self.run_tool("contact", self.a, "--frames", "1", "--thumb-width", "32", "--out", a)
        code, _, _ = self.run_tool("contact", self.a, "--frames", "1", "--thumb-width", "32", "--label",
                                   "PREVIEW 24 - CHECK", "--out", b)
        self.assertEqual(code, 0)
        ia, ib = rc.read_png(a), rc.read_png(b)
        self.assertEqual(ib.height - ia.height, 30)
        self.assertIn(FG, [ib.pixel(x, y) for y in range(8, 22) for x in range(8, 120)])
        self.assertNotIn(FG, [ia.pixel(x, y) for y in range(0, 8) for x in range(ia.width)])

    def test_every_first_last_and_ranges(self):
        for spec in (["--every", "2", "--first", "1", "--last", "4"], ["--frames", "1-4"],
                     ["--frames", "2,2,4"]):
            code, out, err = self.run_tool("contact", self.a, *spec, "--thumb-width", "16", "--out", self.out())
            self.assertEqual(code, 0, out + err + str(spec))
        img = rc.read_png(self.out())
        self.assertEqual(img.width, 8 + 3 * 24)  # 2,2,4 -> three cells

    def test_sixteen_bit_frames_scale_to_eight(self):
        rc.write_png(os.path.join(self.a, "frame_0007.png"), 4, 4, 1, [[65535] * 4] * 4, 16)
        self.assertEqual(self.run_tool("contact", self.a, "--frames", "7", "--thumb-width", "8",
                                       "--out", self.out())[0], 0)
        self.assertEqual(self.read(self.out())[1](8 + 2, 8 + 2), (255, 255, 255))

    def test_mixed_frame_sizes_are_scaled_to_the_first(self):
        self.frame(self.a, 9, (10, 20, 30), 50, 40)
        code, out, _ = self.run_tool("contact", self.a, "--frames", "1,9", "--thumb-width", "32",
                                     "--out", self.out())
        self.assertEqual(code, 0, out)
        self.assertEqual(self.read(self.out())[1](8 + 40 + 5, 8 + 5), (10, 20, 30))

    def test_json_report(self):
        j = os.path.join(self.d, "r.json")
        self.run_tool("contact", self.a, "--frames", "1,2", "--out", self.out(), "--json", j)
        with open(j, encoding="utf-8") as f:
            rep = json.load(f)
        self.assertEqual((rep["tool"], rep["status"], rep["items"]), ("render_sheets", "pass", [1, 2]))

    def test_errors_exit_2(self):
        o = self.out()
        cases = [
            (["contact", self.a, "--frames", "9", "--out", o], "frame 9 not found"),
            (["contact", self.a, "--out", o], "--frames LIST"),
            (["contact", self.a, "--frames", "1", "--every", "2", "--out", o], "not both"),
            (["contact", self.a, "--every", "2", "--out", o], "--first"),
            (["contact", self.a, "--every", "2", "--first", "5", "--last", "1", "--out", o], "--first"),
            (["contact", self.a, "--frames", "1", "--label", "lower", "--out", o], "--label"),
            (["contact", self.a, "--frames", "1", "--label", "A;B", "--out", o], "--label"),
            (["contact", self.a, "--frames", "1", "--label", "", "--out", o], "--label"),
            (["contact", self.a, "--frames", "x", "--out", o], "bad --frames"),
            (["contact", self.a, "--frames", "", "--out", o], "--frames LIST"),
            (["contact", self.a, "--frames", "1", "--cols", "0", "--out", o], "--cols"),
            (["contact", self.a, "--frames", "1", "--thumb-width", "2", "--out", o], "--thumb-width"),
            (["contact", self.a, "--frames", "1", "--pattern", "frame.png", "--out", o], "'#'"),
            (["contact", self.a, "--frames", "1", "--out", "relative.png"], "absolute"),
            (["contact", self.a, "--frames", "1", "--out", os.path.join(self.d, "x.jpg")], ".png"),
            (["contact", self.a, "--frames", "1", "--out", os.path.join(self.d, "no", "x.png")], "folder"),
            (["contact", os.path.join(self.d, "nodir"), "--frames", "1", "--out", o], "not found"),
            (["contact", self.a, "--frames", "1", "--thumb-width", "100000", "--out", o], "reduce"),
        ]
        for argv, text in cases:
            code, out, err = self.run_tool(*argv)
            self.assertEqual(code, 2, (argv, out, err))
            self.assertIn("render_sheets: ERROR", err, argv)
            self.assertIn(text, err, argv)
        self.assertFalse(os.path.exists(o))

    def test_corrupt_frame_exits_2(self):
        with open(os.path.join(self.a, "frame_0005.png"), "wb") as f:
            f.write(b"junk")
        code, _, err = self.run_tool("contact", self.a, "--frames", "5", "--out", self.out())
        self.assertEqual(code, 2)
        self.assertIn("unreadable PNG", err)

    def test_output_guards(self):
        os.makedirs(os.path.join(self.d, "repo", ".git"))
        o = os.path.join(self.d, "repo", "s.png")
        code, _, err = self.run_tool("contact", self.a, "--frames", "1", "--out", o)
        self.assertEqual(code, 2)
        self.assertIn("--allow-in-repo", err)
        self.assertEqual(self.run_tool("contact", self.a, "--frames", "1", "--out", o, "--allow-in-repo")[0], 0)
        cloud = os.path.join(self.d, "OneDrive")
        os.makedirs(cloud)
        code, out, err = self.run_tool("contact", self.a, "--frames", "1", "--out", os.path.join(cloud, "s.png"))
        self.assertEqual(code, 0, err)
        self.assertIn("WARNING", err)
        self.assertIn("cloud-synced", err)


class Crops(SheetCase):
    def quadrants(self):
        rows = []
        for y in range(16):
            row = b""
            for x in range(32):
                row += bytes((200, 0, 0) if x < 16 and y < 8 else (0, 200, 0) if x >= 16 and y < 8 else (0, 0, 200))
            rows.append(row)
        p = os.path.join(self.d, "quad.png")
        rc.write_png(p, 32, 16, 3, rows)
        return p

    def test_two_boxes_side_by_side(self):
        p = self.quadrants()
        o = self.out()
        code, out, err = self.run_tool("crops", p, "--box", "0,0,8,4;16,0,8,4", "--scale", "3", "--out", o)
        self.assertEqual((code, err), (0, ""), out)
        img, px = self.read(o)
        self.assertEqual((img.width, img.height), (8 + 2 * (24 + 8), 8 + 12 + LH))
        self.assertEqual(px(8 + 5, 8 + 5), (200, 0, 0))
        self.assertEqual(px(8 + 32 + 5, 8 + 5), (0, 200, 0))
        self.assertEqual(px(8 + 24 + 2, 8 + 5), BG)  # gutter between crops
        self.assertIn(FG, [px(x, y) for y in range(8 + 12, img.height) for x in range(8, 40)])

    def test_scale_one_and_edge_box(self):
        p = self.quadrants()
        self.assertEqual(self.run_tool("crops", p, "--box", "24,12,8,4", "--scale", "1", "--out", self.out())[0], 0)
        self.assertEqual(self.read(self.out())[1](9, 9), (0, 0, 200))

    def test_bad_boxes_exit_2(self):
        p = self.quadrants()
        for box in ("0,0,33,4", "30,0,4,4", "0,15,4,2", "-1,0,4,4", "0,0,0,4", "1,2,3", "a,b,c,d", "0,0,4,4;", ""):
            code, out, err = self.run_tool("crops", p, f"--box={box}", "--out", self.out())
            self.assertEqual(code, 2, (box, out))
            self.assertIn("--box", err)
        for scale in ("0", "17"):
            self.assertEqual(self.run_tool("crops", p, "--box", "0,0,4,4", "--scale", scale, "--out", self.out())[0], 2)
        self.assertEqual(self.run_tool("crops", os.path.join(self.d, "none.png"), "--box", "0,0,4,4",
                                       "--out", self.out())[0], 2)
        self.assertFalse(os.path.exists(self.out()))


class Compare(SheetCase):
    def test_rows_labels_and_difference(self):
        self.frame(self.b, 2, (COLORS[2][0] + 10, COLORS[2][1], COLORS[2][2]))
        o = self.out()
        code, out, err = self.run_tool("compare", self.a, self.b, "--frames", "1,2", "--thumb-width", "64",
                                       "--out", o)
        self.assertEqual((code, err), (0, ""), out)
        img, px = self.read(o)
        th, ch = 32, 32 + LH + 8
        self.assertEqual((img.width, img.height), (8 + 2 * 72, 8 + 3 * ch))
        self.assertEqual(px(8 + 5, 8 + 5), COLORS[1])
        self.assertEqual(px(8 + 5, 8 + ch + 5), COLORS[1])
        self.assertEqual(px(8 + 5, 8 + 2 * ch + 5), (0, 0, 0))
        self.assertEqual(px(8 + 72 + 5, 8 + 2 * ch + 5), (40, 0, 0))
        for row in range(3):
            self.assertIn(FG, [px(x, 8 + row * ch + th + y) for y in range(LH) for x in range(8, 70)])

    def test_wraps_into_groups_and_clips(self):
        self.frame(self.b, 3, (0, 0, 0))
        self.frame(self.a, 3, (255, 255, 255))
        code, out, err = self.run_tool("compare", self.a, self.b, "--frames", "1-4", "--cols", "2",
                                       "--thumb-width", "32", "--out", self.out())
        self.assertEqual(code, 0, err)
        img, px = self.read(self.out())
        ch = 16 + LH + 8
        self.assertEqual((img.width, img.height), (8 + 2 * 40, 8 + 6 * ch))
        self.assertEqual(px(8 + 5, 8 + 5 * ch + 5), (255, 255, 255))  # frame 3 diff, clipped

    def test_errors(self):
        o = self.out()
        os.remove(os.path.join(self.b, "frame_0002.png"))
        code, _, err = self.run_tool("compare", self.a, self.b, "--frames", "1,2", "--out", o)
        self.assertEqual(code, 2)
        self.assertIn("frame 2 not found", err)
        self.assertEqual(self.run_tool("compare", self.a, os.path.join(self.d, "zz"), "--frames", "1", "--out", o)[0], 2)
        with contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit) as cm:
                rs.main(["compare", self.a, self.b, "--out", o])
        self.assertEqual(cm.exception.code, 2)
        self.assertFalse(os.path.exists(o))


class Helpers(unittest.TestCase):
    def test_font_covers_label_alphabet(self):
        for ch in "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789- ":
            glyph = rs.FONT[ch]
            self.assertEqual(len(glyph), 7, ch)
            self.assertTrue(all(0 <= v < 32 for v in glyph), ch)
        self.assertEqual(len({tuple(g) for g in rs.FONT.values()}), len(rs.FONT))

    def test_resize_nearest(self):
        rows = [bytes([10, 10, 10, 20, 20, 20]), bytes([30, 30, 30, 40, 40, 40])]
        self.assertEqual(rs.resize_nn(rows, 2, 2, 4, 4)[0], bytes([10] * 6 + [20] * 6))
        self.assertEqual(rs.resize_nn(rows, 2, 2, 1, 1), [bytes([10, 10, 10])])

    def test_absdiff4_clips_and_paths_agree(self):
        a, b = bytes([0, 100, 255, 7]), bytes([0, 0, 250, 9])
        self.assertEqual(rs.absdiff4(a, b), bytes([0, 255, 20, 8]))
        if not GLOBAL_PURE and have("numpy"):
            with mode(True):
                pure = rs.absdiff4(a, b)
            with mode(False):
                self.assertEqual(rs.absdiff4(a, b), pure)

    def test_help_exit_codes(self):
        for args in ([], ["contact"], ["bogus"]):
            with contextlib.redirect_stderr(io.StringIO()):
                with self.assertRaises(SystemExit) as cm:
                    rs.main(args)
            self.assertEqual(cm.exception.code, 2)
        for args in (["--help"], ["contact", "--help"], ["crops", "--help"], ["compare", "--help"]):
            done = subprocess.run([sys.executable, "-I", TOOL, *args], capture_output=True, text=True,
                                  stdin=subprocess.DEVNULL, check=False)
            self.assertEqual(done.returncode, 0, args)


@unittest.skipIf(GLOBAL_PURE or not (have("PIL") and have("numpy")), "needs Pillow and numpy")
class PathsAgree(SheetCase):
    def test_sheets_are_identical(self):
        self.frame(self.b, 2, (COLORS[2][0] + 10, 200, 3))
        rc.write_png(os.path.join(self.a, "frame_0008.png"), 9, 6, 1, [[i * 7 % 65536 for i in range(9)]] * 6, 16)
        rc.write_png(os.path.join(self.b, "frame_0008.png"), 9, 6, 1, [[i * 9 % 65536 for i in range(9)]] * 6, 16)
        jobs = [("contact", self.a, "--frames", "1,2,3,4,8", "--cols", "3", "--thumb-width", "40", "--label", "FINAL 1"),
                ("compare", self.a, self.b, "--frames", "1,2,8", "--thumb-width", "40")]
        for job in jobs:
            sheets = []
            for pure in (True, False):
                o = self.out(f"{job[0]}_{pure}.png")
                with mode(pure):
                    self.assertEqual(self.run_tool(*job, "--out", o)[0], 0)
                img = rc.read_png(o)
                sheets.append((img.width, img.height, [bytes(r) for r in img.rows]))
            self.assertEqual(sheets[0], sheets[1], job[0])


if __name__ == "__main__":
    unittest.main()
