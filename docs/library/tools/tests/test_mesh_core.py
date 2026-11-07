"""Tests for mesh_core.py (stdlib only): run with
python -I -m unittest discover -s docs/library/tools/tests"""

from __future__ import annotations

import json
import math
import os
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, ".."))
import mesh_core as mc  # noqa: E402
import mesh_fixtures as fx  # noqa: E402


class StlIo(unittest.TestCase):
    def test_binary_roundtrip_keeps_float32_values(self):
        tris = fx.box((0, 0, 0), (1.25, 2.5, 0.1))
        back = fx.roundtrip(tris)
        self.assertEqual(len(back), len(tris))
        self.assertAlmostEqual(back[0][0][0], tris[0][0][0], places=6)

    def test_ascii(self):
        fd, path = tempfile.mkstemp(suffix=".stl")
        os.close(fd)
        try:
            with open(path, "w") as fh:
                fh.write("solid t\nfacet normal 0 0 1\nouter loop\nvertex 0 0 0\nvertex 1 0 0\nvertex 0 1 0\nendloop\nendfacet\nendsolid t\n")
            self.assertEqual(mc.read_stl(path), [((0.0, 0.0, 0.0), (1.0, 0.0, 0.0), (0.0, 1.0, 0.0))])
        finally:
            os.remove(path)

    def test_garbage_cannot_run(self):
        fd, path = tempfile.mkstemp(suffix=".stl")
        os.write(fd, b"\x00\x01not an stl")
        os.close(fd)
        try:
            with self.assertRaises(mc.CannotRun):
                mc.read_stl(path)
        finally:
            os.remove(path)

    def test_missing_file_cannot_run(self):
        with self.assertRaises(mc.CannotRun):
            mc.read_stl(os.path.join(HERE, "no_such_file.stl"))


class Bodies(unittest.TestCase):
    def test_touching_boxes_stay_separate(self):
        a = fx.box((0, 0, 0), (1, 1, 1))
        b = fx.box((1, 0, 0), (2, 1, 1))  # shares the x = 1 face
        groups = mc.segment_bodies(fx.roundtrip(a + b))
        self.assertEqual([len(g) for g in groups], [len(a), len(b)])

    def test_body_split_across_runs_is_joined(self):
        a = fx.box((0, 0, 0), (1, 1, 1))
        top = [t for t in a if all(abs(p[2] - 1) < 1e-9 for p in t)]
        rest = [t for t in a if t not in top]
        other = fx.box((5, 5, 5), (6, 6, 6))
        groups = mc.segment_bodies(top + other + rest)
        self.assertEqual(sorted(len(g) for g in groups), sorted([len(a), len(other)]))

    def test_connectivity_mode_for_interleaved_bodies(self):
        a = fx.box((0, 0, 0), (1, 1, 1))
        b = fx.box((3, 0, 0), (4, 1, 1))
        mixed = [t for pair in zip(a, b) for t in pair]
        for mode in ("order", "connectivity"):
            groups = mc.segment_bodies(mixed, mode=mode)
            self.assertEqual(sorted(len(g) for g in groups), [12, 12], mode)
        with self.assertRaises(mc.CannotRun):
            mc.segment_bodies(mixed, mode="nonsense")

    def test_twin_sheet_is_not_a_solid(self):
        solids, sheets = mc.split_parts(fx.sheet((0, 0), (1, 1), 0.5))
        self.assertEqual((len(solids), len(sheets)), (0, 2))

    def test_solid_with_patch(self):
        tris = fx.box((0, 0, 0), (1, 1, 1)) + fx.sheet((0.2, 0.2), (0.4, 0.4), 1.0)
        solids, sheets = mc.split_parts(tris)
        self.assertEqual(len(solids), 1)
        self.assertEqual(len(sheets), 2)

    def test_inventory_rows(self):
        tris = fx.box((0, 0, 0), (2, 1, 0.5)) + fx.sheet((5, 5), (6, 6), 0.0)
        rows = mc.inventory(tris)
        self.assertEqual([r["kind"] for r in rows], ["solid", "sheet"])
        self.assertAlmostEqual(rows[0]["volume"], 1.0, places=9)
        self.assertEqual(rows[0]["axes"], "xyz")

    def test_empty(self):
        self.assertEqual(mc.segment_bodies([]), [])
        self.assertEqual(mc.inventory([]), [])


class Distances(unittest.TestCase):
    def test_index_matches_brute_force(self):
        import random

        rng = random.Random(3)
        tris = fx.revolve(fx.cup_profile(), n=24) + fx.box((5, 5, 0), (6, 7, 1))
        idx = mc.TriIndex(tris)
        for _ in range(200):
            p = (rng.uniform(-3, 8), rng.uniform(-3, 8), rng.uniform(-1, 3))
            brute = min(mc.norm(mc.sub(p, mc.closest_on_triangle(p, *t))) for t in tris)
            self.assertAlmostEqual(idx.distance(p), brute, places=12)

    def test_point_on_surface_is_zero(self):
        idx = mc.TriIndex(fx.box((0, 0, 0), (1, 1, 1)))
        self.assertEqual(idx.distance((0.5, 0.5, 1.0)), 0.0)

    def test_empty_index_refused(self):
        with self.assertRaises(ValueError):
            mc.TriIndex([])


class Holes(unittest.TestCase):
    def _cracked_box(self):
        tris = fx.box((0, 0, 0), (1, 1, 1))
        top = [t for t in tris if all(abs(p[2] - 1) < 1e-9 for p in t)]
        return [t for t in tris if t not in top]

    def test_fill_restores_a_closed_body(self):
        tris, n = mc.fill_planar_holes(self._cracked_box(), max_area=2.0)
        m = mc.Mesh(tris)
        self.assertEqual(n, 1)
        self.assertTrue(m.is_watertight())
        self.assertAlmostEqual(m.volume(), 1.0, places=9)

    def test_zip_t_junction_crack(self):
        # top face carries a vertex M on its back edge; the back wall does not: a zero-area crack
        box = fx.box((0, 0, 0), (1, 1, 1))
        tris = [t for t in box if not all(abs(p[2] - 1) < 1e-12 for p in t)]
        A, B, C, D, M = (0, 0, 1), (1, 0, 1), (1, 1, 1), (0, 1, 1), (0.5, 1, 1)
        tris += [(A, B, C), (A, C, M), (A, M, D)]
        self.assertFalse(mc.Mesh(tris).is_watertight())
        zipped, n = mc.zip_cracks(tris)
        m = mc.Mesh(zipped)
        self.assertEqual(n, 1)
        self.assertTrue(m.is_watertight())
        self.assertAlmostEqual(m.volume(), 1.0, places=12)

    def test_zip_leaves_a_real_hole(self):
        tris, n = mc.zip_cracks(self._cracked_box())
        self.assertEqual(n, 0)
        self.assertFalse(mc.Mesh(tris).is_watertight())

    def test_large_hole_left_open(self):
        tris, n = mc.fill_planar_holes(self._cracked_box(), max_area=0.5)
        self.assertEqual(n, 0)
        self.assertFalse(mc.Mesh(tris).is_watertight())


class Triangulate(unittest.TestCase):
    def _area(self, pts, tris):
        return sum(mc._orient(pts[a], pts[b], pts[c]) / 2 for a, b, c in tris)

    def _check(self, outer, holes, expect):
        tris = mc.triangulate(outer, holes)
        pts = list(outer) + [p for h in holes for p in h]
        for a, b, c in tris:
            self.assertGreater(mc._orient(pts[a], pts[b], pts[c]), 0)
        self.assertAlmostEqual(self._area(pts, tris), expect, places=9)

    def test_concave(self):
        self._check([(0, 0), (2, 0), (2, 1), (1, 1), (1, 2), (0, 2)], [], 3.0)

    def test_hole(self):
        self._check([(0, 0), (10, 0), (10, 10), (0, 10)], [[(4, 4), (6, 4), (6, 6), (4, 6)]], 96.0)

    def test_two_holes_cw_input(self):
        holes = [[(1, 1), (1, 2), (2, 2), (2, 1)], [(5, 5), (5, 7), (7, 7), (7, 5)]]
        self._check([(0, 0), (10, 0), (10, 10), (0, 10)], holes, 95.0)

    def test_hole_touching_outer_vertex(self):
        # the hole shares the outer vertex (10, 5): the face is valid only as one weakly simple ring
        outer = [(0, 0), (10, 0), (10, 5), (10, 10), (0, 10)]
        self._check(outer, [[(10, 5), (8, 6), (8, 4)]], 100.0 - 2.0)

    def test_hole_touching_at_a_vertex_that_is_not_its_rightmost(self):
        # regression: only the rightmost hole vertex was checked for contact, so this hole was
        # bridged as a free hole and the triangles overlapped (area too large)
        # (the old code returned 115.6 for this wedge instead of 99.2)
        outer = [(0, 0), (3, 0), (10, 0), (10, 10), (0, 10)]
        self._check(outer, [[(3, 0), (5, 4), (5.2, 3.6)]], 100.0 - 0.8)

    def test_touching_hole_with_a_slit_and_free_holes(self):
        outer = [(0, 0), (3, 0), (10, 0), (10, 10), (0, 10)]
        holes = [[(3, 0), (5, 4), (5.2, 3.6)], [(1, 6), (2, 6)], [(6, 6), (8, 6), (8, 8), (6, 8)]]
        self._check(outer, holes, 100.0 - 0.8 - 4.0)

    def test_slit_hole(self):
        self._check([(0, 0), (4, 0), (4, 4), (0, 4)], [[(1, 2), (3, 2)]], 16.0)


class LoopFit(unittest.TestCase):
    def test_circle(self):
        segs = mc.fit_loop(fx.circle(1.0, 2.0, 0.3257, n=40))
        self.assertEqual(segs[0][0], "C")
        self.assertAlmostEqual(segs[0][2], 0.3257, places=6)
        self.assertAlmostEqual(segs[0][1][0], 1.0, places=6)

    def test_rectangle_lines_only(self):
        segs = mc.fit_loop([(0, 0), (2, 0), (2, 0.5), (2, 1), (0, 1)])
        self.assertEqual([s[0] for s in segs], ["L"] * 4)

    def test_rounded_rectangle(self):
        segs = mc.fit_loop(fx.rounded_rect(3.0, 2.0, 0.4, n_arc=8))
        kinds = [s[0] for s in segs]
        self.assertEqual(kinds.count("A"), 4)
        self.assertEqual(kinds.count("L"), 4)
        for s in segs:
            if s[0] == "A":
                self.assertAlmostEqual(s[5], 0.4, places=6)
        self.assertAlmostEqual(mc.loop_area(segs), 6.0 - (4 - math.pi) * 0.16, places=6)

    def test_degenerate(self):
        self.assertIsNone(mc.fit_loop([(0, 0), (1, 0)]))


class Plans(unittest.TestCase):
    def test_box_is_one_slab(self):
        tris = fx.roundtrip(fx.box((0, 0, 1.14), (0.5, 0.99, 1.47)))
        rec = mc.plan_body(tris)
        self.assertEqual(rec["kind"], "prism")
        self.assertEqual(len(rec["slabs"]), 1)
        self.assertAlmostEqual(mc.prism_volume(rec), 0.5 * 0.99 * 0.33, places=6)

    def test_plate_with_fillets_and_hole(self):
        outer = fx.rounded_rect(22.0, 22.0, 1.0, n_arc=8)
        hole = fx.circle(2.0, 2.0, 1.0, n=48)
        tris = fx.roundtrip(fx.extrude(outer, [hole], 0.0, 1.14))
        rec = mc.plan_body(tris)
        self.assertEqual(rec["kind"], "prism")
        s = rec["slabs"][0]
        self.assertEqual(len(s["inner"]), 1)
        self.assertEqual(s["inner"][0][0][0], "C")
        self.assertAlmostEqual(s["inner"][0][0][2], 1.0, places=5)
        radii = [x[5] for x in s["outer"] if x[0] == "A"]
        self.assertEqual(len(radii), 4)
        for r in radii:
            self.assertAlmostEqual(r, 1.0, places=5)

    def test_stepped_prism_two_slabs(self):
        big = [(0, 0), (2, 0), (2, 2), (0, 2)]
        small = [(0.5, 0.5), (1.5, 0.5), (1.5, 1.5), (0.5, 1.5)]
        body = fx.roundtrip(fx.stepped(big, small, 0.0, 1.0, 1.5))
        self.assertTrue(mc.Mesh(body).is_watertight())
        rec = mc.plan_body(body)
        self.assertEqual(rec["axis"], "z")
        self.assertEqual(len(rec["slabs"]), 2)
        self.assertAlmostEqual(mc.prism_volume(rec), 4.5, places=5)

    def test_revolved_cup_with_fillet(self):
        tris = fx.roundtrip(fx.revolve(fx.cup_profile(), n=64, cx=3.0, cy=4.0))
        m = mc.Mesh(tris)
        self.assertTrue(m.is_watertight())
        rec = mc.plan_body(tris)
        self.assertEqual(rec["kind"], "revolve")
        self.assertAlmostEqual(rec["centre"][0], 3.0, places=5)
        self.assertAlmostEqual(rec["centre"][1], 4.0, places=5)
        radii = [s[5] for s in rec["profile"] if s[0] == "A"]
        self.assertEqual(len(radii), 1)
        self.assertAlmostEqual(radii[0], 0.05, places=5)
        self.assertLess(rec["max_vertex_offset"], 1e-5)

    def test_non_revolved_body_rejected(self):
        tris = fx.frustum(1.0, 0.6, 0.7)
        m = mc.Mesh(tris)
        self.assertTrue(m.is_watertight())
        self.assertEqual(mc.revolve_candidates(m), ["z"])
        with self.assertRaises(ValueError):
            mc.plan_revolve(tris, "z")
        self.assertIsNone(mc.plan_body(tris))


class Cli(unittest.TestCase):
    def test_inventory_and_plan(self):
        d = tempfile.mkdtemp()
        stl = os.path.join(d, "in.stl")
        mc.write_stl(stl, fx.box((0, 0, 0), (1, 1, 1)) + fx.sheet((3, 3), (4, 4), 0))
        self.assertEqual(mc.main(["inventory", stl, "--out", os.path.join(d, "inv.json")]), mc.PASS)
        with open(os.path.join(d, "inv.json")) as fh:
            self.assertEqual(len(json.load(fh)), 2)
        self.assertEqual(mc.main(["plan", stl, "--out", os.path.join(d, "plan.json")]), mc.PASS)
        with open(os.path.join(d, "plan.json")) as fh:
            plans = json.load(fh)
        self.assertEqual(plans[0]["plan"]["kind"], "prism")
        self.assertIsNone(plans[1]["plan"])
        self.assertEqual(mc.main(["inventory", os.path.join(d, "missing.stl"), "--out", os.path.join(d, "x.json")]), mc.CANNOT)


if __name__ == "__main__":
    unittest.main()
