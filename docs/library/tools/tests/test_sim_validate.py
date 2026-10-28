"""Tests for sim_validate.py on synthetic volume series (no Blender, no sim, no GPU).

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
import sim_validate as sv  # noqa: E402

TOOL = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "sim_validate.py")
TARGET = 0.0002  # m3
F1, F2, LAST, FPS = 10, 40, 80, 24


def good(frac=1.0, post=lambda f, v: v, last=LAST):
    """Linear pour F1..F2 to frac x TARGET, then held (post may reshape the after-pour part)."""
    rows = []
    for f in range(1, last + 1):
        if f <= F1:
            v = 0.0
        elif f <= F2:
            v = TARGET * frac * (f - F1) / (F2 - F1)
        else:
            v = post(f, TARGET * frac)
        rows.append({"frame": f, "volume": v, "particles": int(v * 1e7)})
    return rows


class SimCase(unittest.TestCase):
    def setUp(self):
        self._td = tempfile.TemporaryDirectory()
        self.addCleanup(self._td.cleanup)
        self.root = os.path.realpath(self._td.name)

    def series(self, rows, name="s.json"):
        p = os.path.join(self.root, name)
        with open(p, "w", encoding="utf-8") as f:
            json.dump(rows, f)
        return p

    def run_tool(self, rows, *extra, target=TARGET):
        path = rows if isinstance(rows, str) else self.series(rows)
        out, err = io.StringIO(), io.StringIO()
        argv = ["--series", path, "--target-volume", str(target), "--pour-start", str(F1),
                "--pour-end", str(F2), *map(str, extra)]
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = sv.main(argv)
        return code, out.getvalue(), err.getvalue()


class Findings(SimCase):
    def test_good_pour_passes(self):
        code, out, err = self.run_tool(good(), "--flow-m3s", TARGET / ((F2 - F1) / FPS), "--fps", FPS)
        self.assertEqual((code, err), (0, ""), out)
        self.assertTrue(out.strip().splitlines()[-1].startswith("sim_validate: PASS"))
        self.assertIn("emitted 100.0% of target", out)

    def test_silent_under_emission_prints_the_percentage(self):
        code, out, _ = self.run_tool(good(0.03))
        self.assertEqual(code, 1)
        self.assertIn("SILENT UNDER-EMISSION", out)
        self.assertIn("only 3.0% of the target", out)
        self.assertIn("FAIL 1 finding(s)", out)

    def test_tolerance_edges(self):
        self.assertEqual(self.run_tool(good(0.91))[0], 0)
        self.assertEqual(self.run_tool(good(0.89))[0], 1)
        code, out, _ = self.run_tool(good(1.2))
        self.assertEqual(code, 1)
        self.assertIn("over-emission", out)
        self.assertEqual(self.run_tool(good(0.89), "--tol", "0.2")[0], 0)

    def test_leak_after_the_pour(self):
        rows = good(post=lambda f, v: v * (1 - 0.01 * (f - F2)))
        code, out, _ = self.run_tool(rows)
        self.assertEqual(code, 1)
        self.assertIn("leak: ", out)
        self.assertIn("leaks through a collider", out)
        self.assertNotIn("gain: ", out)

    def test_volume_gain_after_the_pour(self):
        code, out, _ = self.run_tool(good(post=lambda f, v: v * (1 + 0.01 * (f - F2))))
        self.assertEqual(code, 1)
        self.assertIn("gain: ", out)
        self.assertIn("solver artefact", out)

    def test_drain_allowed_after_drain_from(self):
        drain = lambda f, v: v if f < 60 else max(0.0, v * (1 - 0.1 * (f - 59)))  # noqa: E731
        self.assertEqual(self.run_tool(good(post=drain))[0], 1)
        code, out, _ = self.run_tool(good(post=drain), "--drain-from", "60")
        self.assertEqual(code, 0, out)

    def test_small_post_pour_wobble_within_loss_tol_passes(self):
        self.assertEqual(self.run_tool(good(post=lambda f, v: v * (1 - 0.03)))[0], 0)

    def test_flow_rate_mismatch(self):
        q = TARGET / ((F2 - F1) / FPS)
        code, out, _ = self.run_tool(good(0.5), "--flow-m3s", q, "--fps", FPS, "--tol", "0.4")
        self.assertEqual(code, 1)
        self.assertIn("flow: ", out)
        self.assertIn("50.0%", out)

    def test_particles_must_not_fall_during_the_pour(self):
        rows = good()
        rows[25]["particles"] -= 500
        code, out, _ = self.run_tool(rows)
        self.assertEqual(code, 1)
        self.assertIn("particles: ", out)
        self.assertIn("first at frame 26", out)
        rows = good()
        rows[60]["particles"] = 0  # after the pour: not checked
        self.assertEqual(self.run_tool(rows)[0], 0)

    def test_missing_and_duplicate_frames(self):
        rows = [r for r in good() if r["frame"] not in (20, 21, 55)]
        rows.append(dict(rows[3]))
        code, out, _ = self.run_tool(rows)
        self.assertEqual(code, 1)
        self.assertIn("3 frame(s) without a volume sample between 1 and 80: 20-21, 55", out)
        self.assertIn("duplicate frame(s) in the series (first sample used): 4", out)

    def test_extract_document_input_with_object(self):
        frames = [{"frame": r["frame"], "volumes": {"Liquid": r["volume"], "Other": 1.0}} for r in good(0.03)]
        doc = {"schema": "render-extract/1", "frames": frames}
        code, out, _ = self.run_tool(self.series(doc), "--object", "Liquid")
        self.assertEqual(code, 1)
        self.assertIn("3.0%", out)
        self.assertEqual(self.run_tool(self.series(doc), "--object", "Other", "--tol", "5e-1")[0], 1)

    def test_json_report(self):
        j = os.path.join(self.root, "r", "rep.json")
        code, out, _ = self.run_tool(good(0.03), "--json", j)
        with open(j, encoding="utf-8") as f:
            rep = json.load(f)
        self.assertEqual((code, rep["tool"], rep["status"]), (1, "sim_validate", "fail"))
        self.assertAlmostEqual(rep["emitted_percent"], 3.0)
        self.assertEqual(rep["findings"][0]["kind"], "under-emission")


class CacheHash(SimCase):
    def make_cache(self, **files):
        d = os.path.join(self.root, "cache")
        for rel, data in files.items():
            p = os.path.join(d, *rel.split("/"))
            os.makedirs(os.path.dirname(p), exist_ok=True)
            with open(p, "wb") as f:
                f.write(data)
        return d

    def test_hash_is_stable_and_changes_with_content_name_and_extra_files(self):
        d = self.make_cache(**{"a.bin": b"one", "sub/b.bin": b"two"})
        h1 = sv.hash_cache(d)[0]
        self.assertEqual(sv.hash_cache(d)[0], h1)
        self.assertEqual(sv.hash_cache(d)[1:], (2, 6))
        with open(os.path.join(d, "sub", "b.bin"), "wb") as f:
            f.write(b"twO")
        h2 = sv.hash_cache(d)[0]
        self.assertNotEqual(h1, h2)
        os.replace(os.path.join(d, "a.bin"), os.path.join(d, "c.bin"))
        h3 = sv.hash_cache(d)[0]
        self.assertNotEqual(h2, h3)
        with open(os.path.join(d, "z.bin"), "wb") as f:
            f.write(b"")
        self.assertNotEqual(sv.hash_cache(d)[0], h3)

    def test_expected_hash_match_and_mismatch(self):
        d = self.make_cache(**{"a.bin": b"one"})
        h = sv.hash_cache(d)[0]
        code, out, _ = self.run_tool(good(), "--cache", d, "--expect-hash", h.upper())
        self.assertEqual(code, 0, out)
        self.assertIn(h, out)
        with open(os.path.join(d, "a.bin"), "wb") as f:
            f.write(b"changed")
        code, out, _ = self.run_tool(good(), "--cache", d, "--expect-hash", h)
        self.assertEqual(code, 1)
        self.assertIn("cache: cache hash", out)
        self.assertIn("validated cache", out)

    def test_cache_problems_exit_2(self):
        empty = os.path.join(self.root, "empty")
        os.makedirs(empty)
        for extra in (["--cache", empty], ["--cache", os.path.join(self.root, "none")],
                      ["--expect-hash", "0" * 64], ["--cache", empty, "--expect-hash", "xyz"]):
            self.assertEqual(self.run_tool(good(), *extra)[0], 2, extra)


class CannotRun(SimCase):
    def test_bad_series_exit_2(self):
        bad = os.path.join(self.root, "bad.json")
        with open(bad, "w") as f:
            f.write("{nope")
        cases = [bad, os.path.join(self.root, "missing.json"), self.series([]), self.series({"a": 1}),
                 self.series([{"frame": 1}]), self.series([{"frame": 1, "volume": -1.0}]),
                 self.series([{"frame": 1, "volume": "x"}]), self.series([{"frame": 1.5, "volume": 0.1}]),
                 self.series([{"frame": 1, "volume": 0.1, "particles": -3}]),
                 self.series({"schema": "render-extract/2", "frames": []}),
                 self.series({"schema": "render-extract/1", "frames": [{"frame": 1}]})]
        for c in cases:
            code, out, err = self.run_tool(c, "--object", "Liquid")
            self.assertEqual((code, out), (2, ""), c)
            self.assertIn("sim_validate: ERROR", err)

    def test_extract_needs_object_that_exists(self):
        doc = {"schema": "render-extract/1", "frames": [{"frame": f, "volumes": {"L": 0.1}} for f in range(1, 50)]}
        self.assertEqual(self.run_tool(self.series(doc))[0], 2)
        self.assertEqual(self.run_tool(self.series(doc), "--object", "Nope")[0], 2)

    def test_no_sample_at_pour_ends_exits_2(self):
        rows = [r for r in good() if r["frame"] != F2]
        code, _, err = self.run_tool(rows)
        self.assertEqual(code, 2)
        self.assertIn("no volume sample", err)
        self.assertEqual(self.run_tool(good(last=30))[0], 2)

    def test_bad_arguments_exit_2(self):
        for extra in (["--tol", "1.5"], ["--flow-m3s", "1"], ["--fps", "24"], ["--drain-from", "30"],
                      ["--loss-tol", "-1"], ["--flow-m3s", "-1", "--fps", "24"]):
            self.assertEqual(self.run_tool(good(), *extra)[0], 2, extra)
        self.assertEqual(self.run_tool(good(), target=0)[0], 2)
        out = io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(io.StringIO()):
            code = sv.main(["--series", self.series(good()), "--target-volume", "1", "--pour-start", "40",
                            "--pour-end", "10"])
        self.assertEqual(code, 2)


class Cli(unittest.TestCase):
    def test_help_exits_0(self):
        p = subprocess.run([sys.executable, "-I", "-B", TOOL, "--help"], capture_output=True, text=True,
                           stdin=subprocess.DEVNULL, timeout=60)
        self.assertEqual(p.returncode, 0)
        self.assertIn("--expect-hash", p.stdout)

    def test_missing_arguments_exit_2(self):
        p = subprocess.run([sys.executable, "-I", "-B", TOOL], capture_output=True, text=True,
                           stdin=subprocess.DEVNULL, timeout=60)
        self.assertEqual(p.returncode, 2)


if __name__ == "__main__":
    unittest.main()
