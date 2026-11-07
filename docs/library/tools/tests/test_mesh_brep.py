"""Tests for mesh_brep.py and mesh_verify.py. They need CadQuery (OpenCascade) and are skipped
without it, so the template self-test passes on plain Python; run them where CadQuery is installed:
python -m unittest discover -s docs/library/tools/tests -p "test_mesh_brep.py" """

from __future__ import annotations

import json
import os
import shutil
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, ".."))
import mesh_core as mc  # noqa: E402
import mesh_fixtures as fx  # noqa: E402

try:
    import cadquery  # noqa: F401

    HAVE_CQ = True
except ImportError:
    HAVE_CQ = False

if HAVE_CQ:
    import mesh_brep as mb
    import mesh_verify as mv


def _quiet(*_a, **_k):
    pass


@unittest.skipUnless(HAVE_CQ, "CadQuery not installed")
class Build(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp()

    def tearDown(self):
        shutil.rmtree(self.dir, ignore_errors=True)

    def _run(self, tris, names=None):
        stl = os.path.join(self.dir, "in.stl")
        mc.write_stl(stl, tris)
        out = os.path.join(self.dir, "out")
        summary = mb.run(stl, out, names=names, log=_quiet)
        with open(os.path.join(out, "report.json")) as fh:
            return summary, json.load(fh)["bodies"], out, stl

    def test_box_is_an_exact_prism(self):
        summary, rows, out, stl = self._run(fx.box((0, 0, 1.14), (0.5, 0.99, 1.47)), {"0": {"name": "R0", "colour": "#1C1C1E"}})
        self.assertEqual(summary["failed"], [])
        self.assertEqual(rows[0]["kind"], "prism")
        self.assertTrue(rows[0]["valid"])
        self.assertEqual(rows[0]["free_edges"], 0)
        self.assertLess(rows[0]["verr"], 1e-5)
        self.assertAlmostEqual(rows[0]["volume"], 0.5 * 0.99 * 0.33, places=6)
        bodies = mv.read_bodies(os.path.join(out, "solids.step"))
        self.assertEqual([b["name"] for b in bodies], ["000_R0"])

    def test_plate_with_fillets_and_hole(self):
        tris = fx.extrude(fx.rounded_rect(22.0, 22.0, 1.0, n_arc=8), [fx.circle(2.0, 2.0, 1.0, n=48)], 0.0, 1.14)
        summary, rows, _, _ = self._run(tris)
        self.assertEqual(rows[0]["kind"], "prism")
        self.assertLess(rows[0]["verr"], 1e-4)
        self.assertEqual(summary["failed"], [])

    def test_revolved_cup(self):
        summary, rows, _, _ = self._run(fx.revolve(fx.cup_profile(), n=64, cx=3.0, cy=4.0))
        self.assertEqual(rows[0]["kind"], "revolve")
        self.assertLess(rows[0]["verr"], 1e-4)
        self.assertEqual(summary["failed"], [])

    def test_frustum_is_faceted(self):
        summary, rows, _, _ = self._run(fx.frustum(1.0, 0.6, 0.7))
        self.assertTrue(rows[0]["kind"].startswith("faceted"))
        self.assertLess(rows[0]["verr"], 1e-6)
        self.assertEqual(summary["failed"], [])

    def test_pinched_shell_is_repaired_to_a_valid_solid(self):
        summary, rows, _, _ = self._run(fx.pinched_pocket())
        self.assertEqual(summary["failed"], [], rows)
        self.assertTrue(rows[0]["valid"])
        self.assertEqual(rows[0]["free_edges"], 0)
        self.assertAlmostEqual(rows[0]["volume"], 15.0, places=9)

    def test_patch_on_a_part_is_imprinted_and_coloured(self):
        tris = fx.box((0, 0, 0), (1, 1, 1)) + fx.sheet((0.2, 0.2), (0.4, 0.4), 1.0)
        names = {"0": {"name": "chip", "colour": "#1C1C1E"}, "1": {"name": "mark", "colour": "#E6E6DC"}}
        summary, rows, out, _ = self._run(tris, names)
        self.assertEqual(summary["imprinted_patch_bodies"], 1)
        self.assertEqual(summary["surface_bodies"], 0)
        self.assertFalse(os.path.exists(os.path.join(out, "surfaces.step")))
        bodies = mv.read_bodies(os.path.join(out, "solids.step"))
        self.assertEqual(len(bodies), 1)
        self.assertEqual(bodies[0]["free_edges"], 0)
        self.assertGreaterEqual(bodies[0]["coloured_faces"], 1)

    def test_floating_patch_goes_to_surfaces(self):
        tris = fx.box((0, 0, 0), (1, 1, 1)) + fx.sheet((3, 3), (4, 4), 0.5)
        summary, _, out, stl = self._run(tris)
        self.assertEqual(summary["surface_bodies"], 1)
        self.assertTrue(os.path.exists(os.path.join(out, "surfaces.step")))
        rep = mv.verify([os.path.join(out, "solids.step")], stl, log=_quiet)
        self.assertEqual(rep["open_bodies"], [])
        both = mv.verify([os.path.join(out, "solids.step"), os.path.join(out, "surfaces.step")], stl, log=_quiet)
        self.assertLess(both["stl_to_cad_max"], 1e-4)
        self.assertGreater(rep["stl_to_cad_max"], 0.4)  # the sheet sits 0.5 above the box

    def test_open_body_is_reported_not_hidden(self):
        box = fx.box((0, 0, 0), (1, 1, 1))
        open_box = [t for t in box if not all(abs(p[2] - 1) < 1e-12 for p in t)]
        summary, _, _, _ = self._run(open_box)
        self.assertEqual(summary["open_after_repair"], [0])
        self.assertEqual(summary["solids"], 0)

    def test_t_junction_crack_is_zipped(self):
        box = fx.box((0, 0, 0), (1, 1, 1))
        tris = [t for t in box if not all(abs(p[2] - 1) < 1e-12 for p in t)]
        A, B, C, D, M = (0, 0, 1), (1, 0, 1), (1, 1, 1), (0, 1, 1), (0.5, 1, 1)
        tris += [(A, B, C), (A, C, M), (A, M, D)]
        summary, rows, _, _ = self._run(tris)
        self.assertEqual(summary["open_after_repair"], [])
        self.assertEqual(rows[0]["cracks_zipped"], 1)
        self.assertAlmostEqual(rows[0]["volume"], 1.0, places=9)

    def test_cli_exit_codes(self):
        stl = os.path.join(self.dir, "in.stl")
        mc.write_stl(stl, fx.box((0, 0, 0), (1, 1, 1)))
        out = os.path.join(self.dir, "o")
        self.assertEqual(mb.main([stl, "--out", out]), mc.PASS)
        self.assertEqual(mv.main([os.path.join(out, "solids.step"), "--stl", stl]), mc.PASS)
        self.assertEqual(mb.main([os.path.join(self.dir, "none.stl"), "--out", out]), mc.CANNOT)


if __name__ == "__main__":
    unittest.main()
