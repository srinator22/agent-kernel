"""Tests for render_estimate.py (typed and STATE-based estimates, dated price rows).

Run: python -I -B -m unittest discover -s docs/library/tools/tests -t docs/library/tools/tests -p "test_*.py"
No network is used; the price rows in these tests are invented test data, not real prices.
"""
import contextlib
import io
import json
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import render_estimate as re_  # noqa: E402

TODAY = "2026-10-29"
ROW = {"name": "test-gpu-a", "currency": "USD", "price_per_hour": 1.5, "unit": "gpu-hour", "speed_ratio": 2.0,
       "date": "2026-10-20", "source": "https://example.invalid/prices"}


def run_main(argv):
    out, err = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        try:
            code = re_.main(argv)
        except SystemExit as exc:
            code = exc.code
    return code, out.getvalue(), err.getvalue()


class RenderEstimateTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.dir = os.path.realpath(self.tmp.name)
        self.n = 0

    def write_json(self, data, name=None):
        self.n += 1
        path = os.path.join(self.dir, name or f"f{self.n}.json")
        with open(path, "w", encoding="utf-8") as fh:
            if isinstance(data, str):
                fh.write(data)
            else:
                json.dump(data, fh)
        return path

    def prices(self, *rows):
        return self.write_json(list(rows))

    def typed(self, *extra, spf="2", frames="3600"):
        return run_main(["--sec-per-frame", spf, "--frames", frames, "--today", TODAY, *extra])

    def make_state(self, present=(), done=((1, 5, 20.0, 5),), first=1, last=10, tool="render_chunks"):
        out = os.path.join(self.dir, "frames")
        os.makedirs(out, exist_ok=True)
        for n in present:
            with open(os.path.join(out, "frame_%04d.png" % n), "wb") as fh:
                fh.write(b"x")
        chunks = [{"index": i + 1, "first": a, "last": b, "status": "done", "seconds": s, "frames_rendered": n}
                  for i, (a, b, s, n) in enumerate(done)]
        chunks.append({"index": 99, "first": last, "last": last, "status": "todo", "seconds": None,
                       "frames_rendered": None})
        return self.write_json({"tool": tool, "first": first, "last": last, "out": out,
                                "pattern": "frame_####.png", "chunks": chunks}, name="state.json")

    # ---- typed estimates --------------------------------------------------------------------------------
    def test_local_hours_one_and_two_processes(self):
        code, out, err = self.typed()
        self.assertEqual(code, 0, out + err)
        self.assertIn("total 2.00 h (2:00:00), remaining 2.00 h", out)
        self.assertIn("supplied 2 s/frame", out)
        self.assertIn("render_estimate: PASS", out)
        code, out, _ = self.typed("--processes", "2")
        self.assertIn("total 1.00 h", out)
        self.assertNotIn("WARNING", out)

    def test_processes_per_gpu_warns_and_uses_gpu_count(self):
        code, out, _ = self.typed("--processes", "2", "--processes-per-gpu", "2")
        self.assertEqual(code, 0)
        self.assertIn("WARNING", out)
        self.assertIn("no speed-up", out)
        self.assertIn("total 2.00 h", out)
        code, out, _ = self.typed("--processes", "4", "--processes-per-gpu", "2")
        self.assertIn("total 1.00 h", out)
        code, out, _ = self.typed("--processes", "3", "--processes-per-gpu", "2")
        self.assertIn("on 2 GPU(s)", out)

    def test_small_and_large_values(self):
        code, out, _ = self.typed(spf="0.001", frames="1")
        self.assertEqual(code, 0)
        self.assertIn("0.00 h", out)
        code, out, _ = self.typed(spf="86400", frames="1000")
        self.assertIn("24000.00 h", out)

    # ---- prices -----------------------------------------------------------------------------------------
    def test_price_table_cost_and_columns(self):
        report = os.path.join(self.dir, "est.json")
        code, out, err = self.typed("--prices", self.prices(ROW), "--json", report)
        self.assertEqual(code, 0, out + err)
        self.assertIn("name", out)
        self.assertIn("test-gpu-a", out)
        self.assertIn("1.00", out)  # 2 GPU-hours of work / speed_ratio 2.0
        self.assertIn("1.50 USD", out)
        self.assertIn("https://example.invalid/prices", out)
        self.assertIn("2026-10-20", out)
        with open(report, encoding="utf-8") as fh:
            data = json.load(fh)
        self.assertEqual(data["status"], "pass")
        self.assertAlmostEqual(data["prices"][0]["cost"], 1.5)
        self.assertAlmostEqual(data["prices"][0]["gpu_hours"], 1.0)
        self.assertEqual(data["frames_remaining"], 3600)

    def test_cost_does_not_depend_on_process_count(self):
        _, one, _ = self.typed("--prices", self.prices(ROW))
        _, two, _ = self.typed("--prices", self.prices(ROW), "--processes", "2")
        self.assertIn("1.50 USD", one)
        self.assertIn("1.50 USD", two)

    def test_prices_object_form_and_multiple_rows(self):
        other = dict(ROW, name="test-gpu-b", currency="EUR", price_per_hour=0.5, speed_ratio=1.0)
        path = self.write_json({"prices": [ROW, other]})
        code, out, _ = self.typed("--prices", path)
        self.assertEqual(code, 0)
        self.assertIn("1.00 EUR", out)  # 2 gpu-hours x 0.5
        self.assertIn("1.50 USD", out)

    def test_stale_row_is_a_verify_finding_exit_1(self):
        stale = dict(ROW, name="old-row", date="2026-08-01")
        code, out, _ = self.typed("--prices", self.prices(ROW, stale))
        self.assertEqual(code, 1)
        self.assertIn("VERIFY: price row old-row dated 2026-08-01 is older than 30 days", out)
        self.assertNotIn("VERIFY: price row test-gpu-a", out)
        self.assertIn("render_estimate: FAIL 1 finding(s)", out)
        self.assertIn("old-row", out.split("finding:")[0])  # the table is still printed

    def test_age_boundary_and_custom_limit(self):
        edge = dict(ROW, date="2026-09-29")  # exactly 30 days before TODAY
        self.assertEqual(self.typed("--prices", self.prices(edge))[0], 0)
        over = dict(ROW, date="2026-09-28")  # 31 days
        self.assertEqual(self.typed("--prices", self.prices(over))[0], 1)
        self.assertEqual(self.typed("--prices", self.prices(over), "--max-price-age-days", "31")[0], 0)
        self.assertEqual(self.typed("--prices", self.prices(ROW), "--max-price-age-days", "5")[0], 1)

    def test_price_rows_missing_required_fields_exit_2(self):
        for key in ("name", "currency", "date", "source", "unit"):
            with self.subTest(missing=key):
                row = {k: v for k, v in ROW.items() if k != key}
                code, _, err = self.typed("--prices", self.prices(row))
                self.assertEqual(code, 2)
                self.assertIn("render_estimate: ERROR", err)
        for key in ("price_per_hour", "speed_ratio"):
            row = {k: v for k, v in ROW.items() if k != key}
            self.assertEqual(self.typed("--prices", self.prices(row))[0], 2)

    def test_bad_price_values_exit_2(self):
        bad_rows = [dict(ROW, date=""), dict(ROW, source="  "), dict(ROW, currency=5),
                    dict(ROW, date="2026-13-40"), dict(ROW, date="29/10/2026"), dict(ROW, date="2026-11-30"),
                    dict(ROW, speed_ratio=0), dict(ROW, speed_ratio=-1), dict(ROW, price_per_hour=-0.1),
                    dict(ROW, price_per_hour=True), dict(ROW, price_per_hour="1.5"), dict(ROW, unit="hour"),
                    "not a row", None]
        for row in bad_rows:
            with self.subTest(row=row):
                self.assertEqual(self.typed("--prices", self.prices(row))[0], 2)

    def test_bad_price_files_exit_2(self):
        for data in ("{ nope", "[]", "{}", '"x"', '{"prices": []}', "3"):
            with self.subTest(data=data):
                self.assertEqual(self.typed("--prices", self.write_json(data))[0], 2)
        self.assertEqual(self.typed("--prices", os.path.join(self.dir, "none.json"))[0], 2)

    def test_free_price_is_allowed(self):
        code, out, _ = self.typed("--prices", self.prices(dict(ROW, price_per_hour=0)))
        self.assertEqual(code, 0)
        self.assertIn("0.00 USD", out)

    # ---- STATE basis ------------------------------------------------------------------------------------
    def test_state_measured_rate_total_and_remaining(self):
        path = self.make_state(present=(1, 2, 3, 4, 5))
        code, out, err = run_main(["--state", path, "--today", TODAY])
        self.assertEqual(code, 0, out + err)
        self.assertIn("measured 4.000 s/frame over 5 frame(s) in 1 done chunk(s)", out)
        self.assertIn("frames: total 10, remaining 5", out)
        self.assertIn("remaining 0.01 h (0:00:20)", out)

    def test_state_remaining_ignores_zero_size_frames(self):
        path = self.make_state(present=(1, 2))
        out_dir = os.path.join(self.dir, "frames")
        with open(os.path.join(out_dir, "frame_0003.png"), "wb"):
            pass
        _, out, _ = run_main(["--state", path, "--today", TODAY])
        self.assertIn("remaining 8", out)

    def test_state_cost_uses_remaining_frames(self):
        path = self.make_state(present=(1, 2, 3, 4, 5, 6, 7, 8, 9, 10))
        code, out, _ = run_main(["--state", path, "--today", TODAY, "--prices", self.prices(ROW)])
        self.assertEqual(code, 0)
        self.assertIn("remaining 0", out)
        self.assertIn("0.00 USD", out)

    def test_state_sums_several_chunks(self):
        path = self.make_state(done=((1, 5, 10.0, 5), (6, 8, 30.0, 3)))
        _, out, _ = run_main(["--state", path, "--today", TODAY])
        self.assertIn("measured 5.000 s/frame over 8 frame(s) in 2 done chunk(s)", out)

    def test_state_without_measurement_exits_2(self):
        for done in ((), ((1, 5, 0.0, 0),)):
            with self.subTest(done=done):
                path = self.make_state(done=done)
                code, _, err = run_main(["--state", path])
                self.assertEqual(code, 2)
                self.assertIn("no measurement", err)

    def test_bad_state_exits_2(self):
        with open(self.make_state(), encoding="utf-8") as fh:
            good = json.load(fh)
        cases = {"wrong tool": dict(good, tool="x"), "no chunks key": {k: v for k, v in good.items() if k != "chunks"},
                 "bad range": dict(good, first=5, last=1), "no hash": dict(good, pattern="frame.png"),
                 "list": [1], "chunk not dict": dict(good, chunks=[1])}
        for name, data in cases.items():
            with self.subTest(name=name):
                self.assertEqual(run_main(["--state", self.write_json(data)])[0], 2)
        self.assertEqual(run_main(["--state", "relative.json"])[0], 2)
        self.assertEqual(run_main(["--state", os.path.join(self.dir, "none.json")])[0], 2)
        self.assertEqual(run_main(["--state", self.write_json("{ nope")])[0], 2)

    # ---- arguments --------------------------------------------------------------------------------------
    def test_bad_arguments_exit_2(self):
        state = self.make_state()
        cases = [[], ["--frames", "10"], ["--sec-per-frame", "2"], ["--state", state, "--frames", "10"],
                 ["--state", state, "--sec-per-frame", "2"], ["--sec-per-frame", "0", "--frames", "10"],
                 ["--sec-per-frame", "-1", "--frames", "10"], ["--sec-per-frame", "nan", "--frames", "10"],
                 ["--sec-per-frame", "inf", "--frames", "10"], ["--sec-per-frame", "x", "--frames", "10"],
                 ["--sec-per-frame", "2", "--frames", "0"], ["--sec-per-frame", "2", "--frames", "-5"],
                 ["--sec-per-frame", "2", "--frames", "10", "--processes", "0"],
                 ["--sec-per-frame", "2", "--frames", "10", "--processes-per-gpu", "0"],
                 ["--sec-per-frame", "2", "--frames", "10", "--today", "yesterday"],
                 ["--sec-per-frame", "2", "--frames", "10", "--today", "2026-02-30"],
                 ["--sec-per-frame", "2", "--frames", "10", "--max-price-age-days", "-1"]]
        for argv in cases:
            with self.subTest(argv=argv):
                self.assertEqual(run_main(argv)[0], 2)

    def test_default_today_is_used(self):
        fresh = dict(ROW, date=re_._dt.date.today().isoformat())
        code, out, _ = run_main(["--sec-per-frame", "1", "--frames", "10", "--prices", self.prices(fresh)])
        self.assertEqual(code, 0, out)

if __name__ == "__main__":
    unittest.main()
