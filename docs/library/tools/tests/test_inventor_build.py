"""Tests for the pure planning part of inventor_build.py (no Inventor, any OS)."""

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
import inventor_build as ib  # noqa: E402
import mesh_core as mc  # noqa: E402
import mesh_fixtures as fx  # noqa: E402


class Pure(unittest.TestCase):
    def test_safe_name(self):
        self.assertEqual(ib.safe_name("012_U3 ToF-sensor"), "B012_U3_ToF_sensor")
        self.assertEqual(ib.safe_name("PCB"), "PCB")

    def test_arc_end_order(self):
        self.assertEqual(ib.arc_end_order((0, 0), (1, 0), (0.01, 0)), ((1, 0), (0, 0)))
        self.assertEqual(ib.arc_end_order((0, 0), (1, 0), (0.99, 0)), ((0, 0), (1, 0)))

    def test_group_slabs(self):
        rec = dict(slabs=[dict(z0=1, z1=2, i=0), dict(z0=0, z1=1, i=1), dict(z0=1, z1=2, i=2)])
        g = ib.group_slabs(rec)
        self.assertEqual([(a, b, len(s)) for a, b, s in g], [(0, 1, 1), (1, 2, 2)])


class Plan(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp()
        os.makedirs(os.path.join(self.dir, "each"))
        box = mc.plan_body(fx.box((0, 0, 0), (1, 1, 1)))
        cup = mc.plan_body(fx.revolve(fx.cup_profile(), n=64))
        feats = [dict(box, id=0, part=0, name="chip", colour="#111111"), dict(cup, id=1, part=0, name="cup", colour="#222222")]
        rows = [
            dict(id=0, part=0, name="chip", kind="prism"),
            dict(id=1, part=0, name="cup", kind="revolve"),
            dict(id=2, part=0, name="chip", kind="faceted"),
            dict(id=3, part=None, name="empty", kind="empty"),
        ]
        with open(os.path.join(self.dir, "features.json"), "w") as fh:
            json.dump(feats, fh, default=list)
        with open(os.path.join(self.dir, "report.json"), "w") as fh:
            json.dump(dict(summary={}, bodies=rows), fh)
        open(os.path.join(self.dir, "each", "004_mark_surf.step"), "w").close()

    def tearDown(self):
        shutil.rmtree(self.dir, ignore_errors=True)

    def test_operations_and_unique_names(self):
        ops = ib.plan(self.dir, {"4": {"colour": "#E6E6DC"}})
        self.assertEqual([o["op"] for o in ops], ["prism", "revolve", "import", "surface"])
        self.assertTrue(ops[2]["file"].endswith(os.path.join("each", "002_p0.step")))
        self.assertEqual(ops[3]["colour"], "#E6E6DC")
        names = []
        for o in ops:
            for g in o.get("groups", []):
                names += [g["sketch"], g["feature"], g["param"]]
            names += [o[k] for k in ("sketch", "feature", "plane") if k in o]
        self.assertEqual(len(names), len(set(names)))
        self.assertTrue(all(not g["param"][0].isdigit() for o in ops for g in o.get("groups", [])))

    def test_cli_dry_run_and_missing_dir(self):
        self.assertEqual(ib.main(["--build-dir", self.dir, "--dry-run"]), ib.PASS)
        self.assertEqual(ib.main(["--build-dir", os.path.join(self.dir, "nope"), "--dry-run"]), ib.CANNOT)


if __name__ == "__main__":
    unittest.main()
