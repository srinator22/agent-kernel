"""Tests for fit_check.py on synthetic render-extract/1 documents (no Blender).

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
import fit_check as fc  # noqa: E402

TOOL = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "fit_check.py")


def box(x0, x1, y=(0.0, 0.1), z=(0.0, 0.1), samples=None):
    o = {"aabb_min": [x0, y[0], z[0]], "aabb_max": [x1, y[1], z[1]], "location": [0, 0, 0]}
    if samples is not None:
        o["samples"] = samples
    return o


def doc(states, dims=None):
    """states: {frame: {name: box dict or None}}"""
    names = sorted({n for s in states.values() for n in s})
    dims = dims or {}
    return {"schema": "render-extract/1", "blender": "5.2.3", "scene": {"name": "S"},
            "objects": [{"name": n, "type": "MESH", "dimensions": dims.get(n)} for n in names],
            "frames": [{"frame": f, "objects": {n: b for n, b in s.items() if b is not None}, "anchors": {},
                        "volumes": {}} for f, s in sorted(states.items())]}


class FitCase(unittest.TestCase):
    def setUp(self):
        self._td = tempfile.TemporaryDirectory()
        self.addCleanup(self._td.cleanup)
        self.root = os.path.realpath(self._td.name)

    def put(self, name, obj):
        p = os.path.join(self.root, name)
        with open(p, "w", encoding="utf-8") as f:
            json.dump(obj, f)
        return p

    def run_tool(self, extract, spec, *extra):
        ex = extract if isinstance(extract, str) else self.put("ex.json", extract)
        sp = spec if isinstance(spec, str) else self.put("fit.json", spec)
        o, e = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(o), contextlib.redirect_stderr(e):
            code = fc.main([ex, "--spec", sp, *extra])
        return code, o.getvalue(), e.getvalue()


class Pairs(FitCase):
    def two(self, gap, lid_x=0.0):
        """Lid box [lid_x, lid_x+0.1]; Base box starts `gap` after the lid's far edge."""
        return doc({1: {"Lid": box(lid_x, lid_x + 0.1), "Base": box(lid_x + 0.1 + gap, lid_x + 0.3 + gap)}})

    def test_separated_passes_and_reports_smallest_gap(self):
        code, out, err = self.run_tool(self.two(0.01), {"pairs": [["Lid", "Base"]], "clearance_m": 0.0005})
        self.assertEqual((code, err), (0, ""), out)
        last = out.strip().splitlines()[-1]
        self.assertTrue(last.startswith("fit_check: PASS"))
        self.assertIn("smallest gap 0.01 m", last)
        self.assertIn("box level only", last)

    def test_touching_is_below_clearance(self):
        code, out, _ = self.run_tool(self.two(0.0), {"pairs": [["Lid", "Base"]], "clearance_m": 0.0005})
        self.assertEqual(code, 1)
        self.assertIn("clearance: 'Lid' and 'Base' gap 0 m is below clearance 0.0005 m", out)
        self.assertEqual(self.run_tool(self.two(0.0), {"pairs": [["Lid", "Base"]], "clearance_m": 0})[0], 0)

    def test_gap_just_under_and_over_clearance(self):
        spec = {"pairs": [["Lid", "Base"]], "clearance_m": 0.001}
        self.assertEqual(self.run_tool(self.two(0.0009), spec)[0], 1)
        self.assertEqual(self.run_tool(self.two(0.0011), spec)[0], 0)

    def test_overlap_is_a_collision(self):
        code, out, _ = self.run_tool(self.two(-0.02), {"pairs": [["Lid", "Base"]], "clearance_m": 0.0005})
        self.assertEqual(code, 1)
        self.assertIn("collision: 'Lid' and 'Base' overlap at state(s) 1", out)
        self.assertIn("0.0002 m3", out)  # 0.02 x 0.1 x 0.1
        self.assertNotIn("clearance:", out)

    def test_allowed_contact_suppresses_collision_and_clearance(self):
        spec = {"pairs": [["Lid", "Base"]], "clearance_m": 0.0005, "allowed_contacts": [["Base", "Lid"]]}
        self.assertEqual(self.run_tool(self.two(-0.02), spec)[0], 0)
        self.assertEqual(self.run_tool(self.two(0.0), spec)[0], 0)

    def test_states_all_pairs_all_over_an_animation(self):
        states = {f: {"Lid": box(0.0, 0.1), "Base": box(0.12 - 0.01 * f, 0.4), "Pin": box(0.9, 1.0)}
                  for f in range(1, 6)}
        code, out, _ = self.run_tool(doc(states), {"states": "all", "pairs": "all", "clearance_m": 0.0005})
        self.assertEqual(code, 1)
        self.assertIn("'Base' and 'Lid' overlap at state(s) 3-5", out)  # base x0 = 0.09, 0.08, 0.07 from f=3
        self.assertNotIn("Pin", out)
        code, out, _ = self.run_tool(doc(states), {"states": [1], "pairs": [["Lid", "Base"]],
                                                   "clearance_m": 0.0005})
        self.assertEqual(code, 0, out)
        self.assertIn("states 1", out)

    def test_samples_give_a_tighter_gap_estimate(self):
        # boxes nearly touch at a corner, but the vertices that exist are far from the other box
        a = box(0.0, 0.1, samples=[[0.0, 0.0, 0.0], [0.0, 0.1, 0.1]])
        b = box(0.1001, 0.3, samples=[[0.3, 0.0, 0.0], [0.3, 0.1, 0.1]])
        d = doc({1: {"A": a, "B": b}})
        spec = {"pairs": [["A", "B"]], "clearance_m": 0.01}
        code, out, _ = self.run_tool(d, spec)
        self.assertEqual(code, 0, out)
        d2 = doc({1: {"A": box(0.0, 0.1), "B": box(0.1001, 0.3)}})
        code, out, _ = self.run_tool(d2, spec)
        self.assertEqual(code, 1)
        self.assertIn("gap 0.0001 m", out)

    def test_sample_estimate_is_reported_with_box_gap(self):
        a = box(0.0, 0.1, samples=[[0.0, 0.0, 0.0]])
        b = box(0.105, 0.3, samples=[[0.2, 0.0, 0.0]])
        code, out, _ = self.run_tool(doc({1: {"A": a, "B": b}}), {"pairs": [["A", "B"]], "clearance_m": 0.2})
        self.assertEqual(code, 1)
        self.assertIn("(box gap 0.005 m)", out)

    def test_json_report(self):
        j = os.path.join(self.root, "o", "rep.json")
        code, _, _ = self.run_tool(self.two(0.01), {"pairs": [["Lid", "Base"]], "clearance_m": 0.0005}, "--json", j)
        with open(j, encoding="utf-8") as f:
            rep = json.load(f)
        self.assertEqual((code, rep["status"], rep["states"]), (0, "pass", [1]))
        self.assertAlmostEqual(rep["measurements"][0]["box_gap_m"], 0.01)
        self.assertAlmostEqual(rep["smallest_gap_m"], 0.01)


class PartsAndScale(FitCase):
    def test_scale_error_is_found_and_axis_order_is_ignored(self):
        dims = {"Base": [0.12, 0.08, 0.03]}
        spec = {"pairs": [], "dimensions": {"Base": {"expected_m": [0.12, 0.08, 0.03], "tol": 0.02}}}
        states = {1: {"Base": box(0, 0.12)}}
        self.assertEqual(self.run_tool(doc(states, dims), spec)[0], 0)
        shuffled = {"Base": [0.03, 0.12, 0.08]}
        self.assertEqual(self.run_tool(doc(states, shuffled), spec)[0], 0)
        code, out, _ = self.run_tool(doc(states, {"Base": [120.0, 80.0, 30.0]}), spec)  # millimetres as metres
        self.assertEqual(code, 1)
        self.assertIn("scale: part 'Base' dimensions", out)
        self.assertIn("wrong scale or units", out)
        code, out, _ = self.run_tool(doc(states, {"Base": [0.12 * 1.03, 0.08, 0.03]}), spec)
        self.assertEqual(code, 1)
        self.assertEqual(self.run_tool(doc(states, {"Base": [0.12 * 1.015, 0.08, 0.03]}), spec)[0], 0)

    def test_dimension_part_missing_or_unreadable(self):
        spec = {"pairs": [], "dimensions": {"Ghost": {"expected_m": [1, 1, 1]}, "Base": {"expected_m": [1, 1, 1]}}}
        code, out, _ = self.run_tool(doc({1: {"Base": box(0, 1)}}), spec)  # Base dimensions null
        self.assertEqual(code, 1)
        self.assertIn("missing: part 'Ghost' is not in the extract's object list", out)
        self.assertIn("missing: part 'Base' has no readable dimensions", out)

    def test_part_missing_from_a_state(self):
        states = {1: {"Lid": box(0, 0.1), "Base": box(0.5, 0.6)}, 2: {"Lid": box(0, 0.1)},
                  3: {"Lid": box(0, 0.1), "Base": None}, 4: {"Lid": box(0, 0.1), "Base": box(0.5, 0.6)}}
        code, out, _ = self.run_tool(doc(states), {"pairs": [["Lid", "Base"]], "clearance_m": 0.001})
        self.assertEqual(code, 1)
        self.assertIn("missing: part 'Base' is absent or has no readable bounds at state(s) 2-3", out)

    def test_null_bounds_in_extract_count_as_missing(self):
        d = doc({1: {"Lid": box(0, 0.1), "Base": box(0.5, 0.6)}})
        d["frames"][0]["objects"]["Base"]["aabb_min"] = None
        code, out, _ = self.run_tool(d, {"pairs": [["Lid", "Base"]]})
        self.assertEqual(code, 1)
        self.assertIn("'Base'", out)


class CannotRun(FitCase):
    def test_bad_extract_exits_2(self):
        good = doc({1: {"Lid": box(0, 1)}})
        spec = {"pairs": "all"}
        wrong_schema = dict(good, schema="render-extract/0")
        no_frames = dict(good, frames=[])
        no_objects = {k: v for k, v in good.items() if k != "objects"}
        inverted = doc({1: {"Lid": box(1, 0)}})
        bad_vec = doc({1: {"Lid": box(0, 1)}})
        bad_vec["frames"][0]["objects"]["Lid"]["aabb_max"] = [1, 1]
        bad_sample = doc({1: {"Lid": box(0, 1, samples=[[1, 2]])}})
        for bad in (wrong_schema, no_frames, no_objects, inverted, bad_vec, bad_sample, [], "x"):
            code, out, err = self.run_tool(bad, spec)
            self.assertEqual((code, out), (2, ""), bad)
            self.assertIn("fit_check: ERROR", err)

    def test_bad_spec_exits_2(self):
        d = doc({1: {"Lid": box(0, 1), "Base": box(2, 3)}})
        for bad in ({"states": [9]}, {"states": []}, {"states": ["x"]}, {"pairs": [["Lid"]]},
                    {"pairs": [["Lid", "Lid"]]}, {"pairs": []}, {"clearance_m": -1}, {"clearance_m": "a"},
                    {"allowed_contacts": [["Lid"]]}, {"dimensions": {"Lid": {"expected_m": [1, 1]}}},
                    {"dimensions": {"Lid": {"expected_m": [1, 1, 0]}}},
                    {"dimensions": {"Lid": {"expected_m": [1, 1, 1], "tol": -1}}}, []):
            code, out, err = self.run_tool(d, bad)
            self.assertEqual((code, out), (2, ""), bad)
            self.assertIn("ERROR", err)

    def test_missing_and_malformed_files_exit_2(self):
        d = self.put("ok.json", doc({1: {"Lid": box(0, 1)}}))
        self.assertEqual(self.run_tool(os.path.join(self.root, "none.json"), {"pairs": "all"})[0], 2)
        self.assertEqual(self.run_tool(d, os.path.join(self.root, "none.json"))[0], 2)
        broken = os.path.join(self.root, "broken.json")
        with open(broken, "w") as f:
            f.write("{")
        self.assertEqual(self.run_tool(broken, {"pairs": "all"})[0], 2)
        self.assertEqual(self.run_tool(d, broken)[0], 2)


class Cli(unittest.TestCase):
    def test_help_exits_0_and_states_the_v1_limit(self):
        p = subprocess.run([sys.executable, "-I", "-B", TOOL, "--help"], capture_output=True, text=True,
                           stdin=subprocess.DEVNULL, timeout=60)
        self.assertEqual(p.returncode, 0)
        flat = " ".join(p.stdout.split())
        self.assertIn("axis-aligned boxes plus vertex samples, not exact mesh distance", flat)
        self.assertIn("not proof of clearance", flat)

    def test_missing_arguments_exit_2(self):
        p = subprocess.run([sys.executable, "-I", "-B", TOOL], capture_output=True, text=True,
                           stdin=subprocess.DEVNULL, timeout=60)
        self.assertEqual(p.returncode, 2)


if __name__ == "__main__":
    unittest.main()
