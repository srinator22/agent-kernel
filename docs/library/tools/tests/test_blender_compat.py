"""Tests for blender_compat.py (fake old and new API shapes) and the pure helpers of blender_extract.py.

No Blender needed: the shims use hasattr, so small fake classes stand in for each API generation.
Run: python -I -B -m unittest discover -s docs/library/tools/tests -t docs/library/tools/tests -p "test_*.py"
"""
import contextlib
import copy
import io
import json
import os
import subprocess
import sys
import tempfile
import types
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import blender_compat as bc  # noqa: E402
import blender_extract as bx  # noqa: E402
import render_common as rc  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
S = types.SimpleNamespace


class FCurves(list):
    def find(self, data_path, index=0):
        for f in self:
            if (f.data_path, f.array_index) == (data_path, index):
                return f
        return None

    def new(self, data_path, index=0):
        f = S(data_path=data_path, array_index=index)
        self.append(f)
        return f


class OldAction:
    def __init__(self, n=2):
        self.fcurves = FCurves(S(data_path=f"p{i}", array_index=0) for i in range(n))


class Bag:
    def __init__(self, slot, curves):
        self.slot, self.fcurves = slot, curves


class NewStripChannelbags:
    """5.x shape with a `channelbags` collection and a `channelbag(slot)` method."""
    def __init__(self, bags):
        self.channelbags = bags

    def channelbag(self, slot, ensure=False):
        return next((b for b in self.channelbags if b.slot is slot), None)


class NewStripOnlyMethod:
    def __init__(self, bags):
        self._bags = bags

    def channelbag(self, slot, ensure=False):
        return next((b for b in self._bags if b.slot is slot), None)


class NewAction:
    """Layered action: no `fcurves` attribute, like 5.x."""
    def __init__(self, strip_cls=NewStripChannelbags):
        self.s1, self.s2 = S(name="S1"), S(name="S2")
        self.slots = [self.s1, self.s2]
        self.bag1 = Bag(self.s1, [S(data_path="a", array_index=0), S(data_path="b", array_index=0)])
        self.bag2 = Bag(self.s2, [S(data_path="c", array_index=0)])
        self.layers = [S(strips=[strip_cls([self.bag1, self.bag2])])]
        self.ensured = []

    def fcurve_ensure_for_datablock(self, datablock, data_path, index=0):
        self.ensured.append((datablock, data_path, index))
        return S(data_path=data_path, array_index=index, ensured=True)


class ActionTests(unittest.TestCase):
    def test_old_shape_returns_legacy_fcurves(self):
        self.assertEqual([f.data_path for f in bc.action_fcurves(OldAction(3))], ["p0", "p1", "p2"])

    def test_new_shape_all_slots(self):
        self.assertEqual([f.data_path for f in bc.action_fcurves(NewAction())], ["a", "b", "c"])

    def test_new_shape_one_slot(self):
        a = NewAction()
        self.assertEqual([f.data_path for f in bc.action_fcurves(a, a.s2)], ["c"])
        self.assertEqual([f.data_path for f in bc.action_fcurves(a, a.s1)], ["a", "b"])

    def test_new_shape_method_only_strip(self):
        a = NewAction(NewStripOnlyMethod)
        self.assertEqual([f.data_path for f in bc.action_fcurves(a)], ["a", "b", "c"])
        self.assertEqual([f.data_path for f in bc.action_fcurves(a, a.s1)], ["a", "b"])

    def test_unknown_slot_and_empty_shapes(self):
        a = NewAction()
        self.assertEqual(bc.action_fcurves(a, S(name="other")), [])
        self.assertEqual(bc.action_fcurves(None), [])
        self.assertEqual(bc.action_fcurves(S(layers=[])), [])
        self.assertEqual(bc.action_fcurves(S(layers=[], fcurves=[1, 2])), [1, 2])  # 4.4 legacy-with-layers

    def test_ensure_old_creates_once(self):
        a = OldAction(0)
        f1 = bc.ensure_fcurve(a, object(), "location", 1)
        f2 = bc.ensure_fcurve(a, object(), "location", 1)
        self.assertIs(f1, f2)
        self.assertEqual(len(a.fcurves), 1)
        self.assertIsNot(bc.ensure_fcurve(a, object(), "location", 2), f1)

    def test_ensure_new_uses_datablock_api(self):
        a, blk = NewAction(), object()
        f = bc.ensure_fcurve(a, blk, "rotation_euler", 2)
        self.assertTrue(f.ensured)
        self.assertEqual(a.ensured, [(blk, "rotation_euler", 2)])

    def test_assign_old_has_no_slot(self):
        ad, act = S(action=None), OldAction()
        self.assertIsNone(bc.assign_action(ad, act))
        self.assertIs(ad.action, act)

    def test_assign_new_picks_first_slot_or_keeps_existing(self):
        act = NewAction()
        ad = S(action=None, action_slot=None)
        self.assertIs(bc.assign_action(ad, act), act.s1)
        self.assertIs(ad.action_slot, act.s1)
        ad2 = S(action=None, action_slot=act.s2)
        self.assertIs(bc.assign_action(ad2, act), act.s2)

    def test_assign_new_prefers_suitable_slots(self):
        act = NewAction()
        ad = S(action=None, action_slot=None, action_suitable_slots=[act.s2])
        self.assertIs(bc.assign_action(ad, act), act.s2)

    def test_assign_new_without_slots(self):
        ad = S(action=None, action_slot=None)
        self.assertIsNone(bc.assign_action(ad, S(slots=[])))
        self.assertIsNone(bc.assign_action(ad, None))


class SceneTests(unittest.TestCase):
    def test_compositor_old(self):
        sc = S(use_nodes=False, node_tree="TREE")
        self.assertEqual(bc.compositor_tree(sc), "TREE")
        self.assertTrue(sc.use_nodes)

    def test_compositor_new_existing_and_created(self):
        self.assertEqual(bc.compositor_tree(S(compositing_node_group="G")), "G")
        made = []

        class Groups:
            def new(self, name, kind):
                made.append((name, kind))
                return "NEW"
        bpy = S(data=S(node_groups=Groups()))
        sc = S(compositing_node_group=None)
        self.assertEqual(bc.compositor_tree(sc, bpy), "NEW")
        self.assertEqual(sc.compositing_node_group, "NEW")
        self.assertEqual(made, [("Compositing", "CompositorNodeTree")])
        self.assertIsNone(bc.compositor_tree(S(compositing_node_group=None)))

    def test_vse_old_and_new(self):
        old = S(sequence_editor=S(sequences="OLD"))
        new = S(sequence_editor=S(strips="NEW", sequences="OLD"))
        self.assertEqual(bc.vse_strips(old), "OLD")
        self.assertEqual(bc.vse_strips(new), "NEW")

    def test_vse_creates_editor(self):
        sc = S(sequence_editor=None)
        sc.sequence_editor_create = lambda: setattr(sc, "sequence_editor", S(strips="X"))
        self.assertEqual(bc.vse_strips(sc), "X")

    def test_sequencer_scene(self):
        sc = object()
        self.assertIs(bc.sequencer_scene(S(), sc), sc)
        self.assertIs(bc.sequencer_scene(S(sequencer_scene=None), sc), sc)
        other = object()
        self.assertIs(bc.sequencer_scene(S(sequencer_scene=other), sc), other)

    def test_activate_scene_window_wm_window_or_none(self):
        sc = object()
        ctx = S(window=S(scene=None))
        self.assertTrue(bc.activate_scene(ctx, sc))
        self.assertIs(ctx.window.scene, sc)
        w = S(scene=None)
        ctx2 = S(window=None, window_manager=S(windows=[w]))
        self.assertTrue(bc.activate_scene(ctx2, sc))
        self.assertIs(w.scene, sc)
        self.assertFalse(bc.activate_scene(S(window=None, window_manager=S(windows=[])), sc))
        self.assertFalse(bc.activate_scene(S(), sc))

    def test_eevee_id(self):
        self.assertEqual(bc.eevee_id(["BLENDER_WORKBENCH", "BLENDER_EEVEE_NEXT", "CYCLES"]), "BLENDER_EEVEE_NEXT")
        self.assertEqual(bc.eevee_id([S(identifier="BLENDER_EEVEE"), S(identifier="CYCLES")]), "BLENDER_EEVEE")
        self.assertEqual(bc.eevee_id(["BLENDER_EEVEE", "BLENDER_EEVEE_NEXT"]), "BLENDER_EEVEE")
        with self.assertRaises(RuntimeError):
            bc.eevee_id(["CYCLES"])

    def test_video_output_order_new_and_old(self):
        class Strict:
            """media_type must be set before file_format, as in 5.x."""
            def __init__(self):
                self.log = []

            def __setattr__(self, k, v):
                if k != "log":
                    self.log.append(k)
                object.__setattr__(self, k, v)
        new, ff = Strict(), S()
        new.media_type = "IMAGE"
        new.log.clear()
        bc.set_video_output(new, ff, crf="MEDIUM", preset="BEST")
        self.assertEqual(new.log, ["media_type", "file_format"])
        self.assertEqual((new.media_type, new.file_format), ("VIDEO", "FFMPEG"))
        self.assertEqual((ff.format, ff.codec, ff.constant_rate_factor, ff.ffmpeg_preset),
                         ("MPEG4", "H264", "MEDIUM", "BEST"))
        old, ff2 = S(), S()
        bc.set_video_output(old, ff2)
        self.assertFalse(hasattr(old, "media_type"))
        self.assertEqual(old.file_format, "FFMPEG")
        self.assertFalse(hasattr(ff2, "ffmpeg_preset"))

    def test_cycles(self):
        cy = object()
        self.assertIs(bc.cycles(S(cycles=cy)), cy)
        with self.assertRaises(AttributeError):
            bc.cycles(S())

    def test_auto_smooth_both_shapes(self):
        polys = [S(use_smooth=False) for _ in range(3)]
        old = S(polygons=polys)
        bc.auto_smooth(old, 30)
        self.assertTrue(old.use_auto_smooth and all(p.use_smooth for p in polys))
        self.assertAlmostEqual(old.auto_smooth_angle, 0.5235987756, places=6)
        calls = []
        new = S(shade_smooth=lambda: calls.append("smooth"), set_sharp_from_angle=lambda angle: calls.append(angle))
        bc.auto_smooth(new, 180)
        self.assertEqual(calls[0], "smooth")
        self.assertAlmostEqual(calls[1], 3.14159265, places=6)


class Prefs:
    def __init__(self, devices, new_api=True):
        self.devices = devices
        self.compute_device_type = None
        self.calls = []
        if new_api:
            self.refresh_devices = lambda: self.calls.append("refresh")
        else:
            self.get_devices = lambda: self.calls.append("get")


def dev(id_, type_, use=True):
    return S(id=id_, type=type_, name=id_, use=use)


class PinGpuTests(unittest.TestCase):
    def setUp(self):
        self.devs = [dev("cpu0", "CPU"), dev("g0", "OPTIX"), dev("g1", "OPTIX"), dev("c0", "CUDA")]

    def test_pins_named_device_and_turns_cpu_off(self):
        p = Prefs(self.devs)
        self.assertEqual(bc.pin_gpu(p, "OPTIX", "g1"), ["g1"])
        self.assertEqual([d.use for d in self.devs], [False, False, True, False])
        self.assertEqual(p.compute_device_type, "OPTIX")
        self.assertEqual(p.calls, ["refresh"])

    def test_first_device_when_no_id(self):
        self.assertEqual(bc.pin_gpu(Prefs(self.devs), "OPTIX"), ["g0"])
        self.assertEqual([d.use for d in self.devs], [False, True, False, False])

    def test_old_get_devices_shape(self):
        p = Prefs(self.devs, new_api=False)
        self.assertEqual(bc.pin_gpu(p, "CUDA"), ["c0"])
        self.assertEqual(p.calls, ["get"])

    def test_no_match_raises_and_leaves_devices_alone(self):
        before = [d.use for d in self.devs]
        for kind, ident in (("HIP", None), ("OPTIX", "missing")):
            with self.assertRaises(RuntimeError) as cm:
                bc.pin_gpu(Prefs(self.devs), kind, ident)
            self.assertIn("CPU", str(cm.exception))
        self.assertEqual([d.use for d in self.devs], before)

    def test_type_not_offered_by_build_raises_runtime_error(self):
        class Strict(Prefs):
            """compute_device_type rejects values the build does not offer, as the real enum does."""
            def __setattr__(self, k, v):
                if k == "compute_device_type" and v not in (None, "NONE", "CUDA", "OPTIX"):
                    raise TypeError('enum "%s" not found in (NONE, CUDA, OPTIX)' % v)
                object.__setattr__(self, k, v)
        devs = [dev("cpu0", "CPU"), dev("g0", "OPTIX")]
        with self.assertRaises(RuntimeError) as cm:
            bc.pin_gpu(Strict(devs), "METAL")
        self.assertIn("not offered", str(cm.exception))
        self.assertTrue(all(d.use for d in devs))  # nothing was switched off

    def test_only_cpu_present_raises(self):
        with self.assertRaises(RuntimeError):
            bc.pin_gpu(Prefs([dev("cpu0", "CPU")]), "OPTIX")


class BreaksTests(unittest.TestCase):
    def test_every_row_complete_and_sourced(self):
        self.assertGreaterEqual(len(bc.BREAKS), 40)
        for b in bc.BREAKS:
            self.assertEqual(set(b), {"since", "area", "old", "new", "shim", "source"})
            self.assertTrue(all(b.values()))
            self.assertIn("VERIFY 2026-10-29", b["source"])

    def test_named_shims_exist(self):
        for b in bc.BREAKS:
            if b["shim"] != "-":
                self.assertTrue(callable(getattr(bc, b["shim"])), b["shim"])

    def test_ascii_only(self):
        for line in bc.break_lines():
            line.encode("ascii")

    def test_cli_list_and_help(self):
        for flag in ("--list", "--help"):
            r = subprocess.run([sys.executable, "-I", "-B", os.path.join(HERE, "..", "blender_compat.py"), flag],
                               capture_output=True, text=True, stdin=subprocess.DEVNULL, timeout=60)
            self.assertEqual(r.returncode, 0, r.stderr)
            self.assertIn("slotted actions", r.stdout.lower())
            self.assertIn("5.0", r.stdout)

    def test_cli_without_args_exits_2(self):
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            self.assertEqual(bc.main([]), 2)


# ------------------------------------------------------------------ blender_extract pure helpers
def good_doc():
    d = bx.skeleton("5.2.3")
    d["scene"].update(fps=24.0, frame_start=1, frame_end=3, resolution=[160, 90])
    d["frames"] = [{"frame": 1, "camera": {"location": [0, -1, 0], "forward": [0, 1, 0], "lens": 50.0,
                                           "focus_distance": 1.0, "fstop": 4.0},
                    "objects": {"Lid": {"location": [0, 0, 0], "aabb_min": [-1, -1, -1], "aabb_max": [1, 1, 1],
                                        "samples": []}},
                    "anchors": {"Lid": [0.5, 0.5, 1.0]}, "volumes": {}}]
    return d


class ExtractHelperTests(unittest.TestCase):
    def test_parse_frames(self):
        self.assertEqual(bx.parse_frames(None, 1, 5), [1, 2, 3, 4, 5])
        self.assertEqual(bx.parse_frames("1-96", 1, 5, 24), [1, 25, 49, 73])
        self.assertEqual(bx.parse_frames("48,1,24,24", 1, 96), [1, 24, 48])
        self.assertEqual(bx.parse_frames("", 3, 4), [3, 4])
        for bad in ("a", "5-1", "1,,2", "-3"):
            with self.assertRaises(rc.CannotRun):
                bx.parse_frames(bad, 1, 5)
        with self.assertRaises(rc.CannotRun):
            bx.parse_frames("1-3", 1, 5, 0)

    def test_skeleton_is_valid_with_no_frames(self):
        self.assertEqual(bx.validate_extract(bx.skeleton("5.2.3")), [])

    def test_good_document_validates_and_round_trips(self):
        d = good_doc()
        self.assertEqual(bx.validate_extract(d), [])
        with tempfile.TemporaryDirectory() as td:
            p = os.path.join(td, "x.json")
            bx.write_extract(p, d)
            self.assertEqual(bx.load_extract(p), d)
            self.assertEqual([n for n in os.listdir(td)], ["x.json"])  # no temp file left behind

    def test_null_values_are_valid(self):
        d = good_doc()
        d["frames"][0]["camera"] = None
        d["frames"][0]["objects"]["Lid"]["aabb_min"] = None
        d["scene"]["fps"] = None
        self.assertEqual(bx.validate_extract(d), [])

    def test_screen_boxes_are_optional_and_checked(self):
        d = good_doc()
        d["frames"][0]["screen_boxes"] = {"Lid": [0.1, 0.2, 0.4, 0.5], "Pin": None}
        self.assertEqual(bx.validate_extract(d), [])
        for bad in ([0.1, 0.2, 0.4], [0.4, 0.2, 0.1, 0.5], "box"):
            d["frames"][0]["screen_boxes"] = {"Lid": bad}
            self.assertIn("screen_boxes", " ".join(bx.validate_extract(d)), bad)

    def test_screen_box_projects_corners_and_drops_boxes_behind(self):
        # A fake projection: u = x, v = z, depth = y (camera looking along +y).
        proj = lambda p: (p[0], p[2], p[1])
        self.assertEqual(bx.screen_box([0.1, 1.0, 0.2], [0.3, 2.0, 0.6], proj), [0.1, 0.2, 0.3, 0.6])
        self.assertIsNone(bx.screen_box([0.1, -1.0, 0.2], [0.3, 2.0, 0.6], proj))

    def test_problems(self):
        cases = []
        d = good_doc(); d["schema"] = "render-extract/2"; cases.append(("schema", d))
        d = good_doc(); del d["frames"]; cases.append(("frames", d))
        d = good_doc(); del d["scene"]["gamma"]; cases.append(("gamma", d))
        d = good_doc(); del d["scene"]["cycles"]["seed"]; cases.append(("seed", d))
        d = good_doc(); d["frames"][0]["camera"]["location"] = [1, 2]; cases.append(("location", d))
        d = good_doc(); d["frames"][0]["frame"] = "1"; cases.append(("integer", d))
        d = good_doc(); d["frames"].append(copy.deepcopy(d["frames"][0])); cases.append(("duplicate", d))
        d = good_doc(); d["frames"][0]["anchors"]["Lid"] = [0.5, float("nan"), 1]; cases.append(("anchors", d))
        d = good_doc(); d["frames"][0]["objects"]["Lid"].pop("samples"); cases.append(("samples", d))
        d = good_doc(); d["lights"] = [{"name": "k"}]; cases.append(("lights", d))
        d = good_doc(); d["scene"]["resolution"] = [1, 2, 3]; cases.append(("resolution", d))
        d = good_doc(); d["scene"]["fps"] = 0; cases.append(("fps", d))
        for word, doc in cases:
            problems = bx.validate_extract(doc)
            self.assertTrue(problems, word)
            self.assertIn(word, " ".join(problems), word)
        for junk in (None, [], "x", 3):
            self.assertTrue(bx.validate_extract(junk))

    def test_load_extract_errors(self):
        with tempfile.TemporaryDirectory() as td:
            with self.assertRaises(rc.CannotRun):
                bx.load_extract(os.path.join(td, "missing.json"))
            p = os.path.join(td, "bad.json")
            with open(p, "w") as fh:
                fh.write("{not json")
            with self.assertRaises(rc.CannotRun):
                bx.load_extract(p)
            with open(p, "w") as fh:
                json.dump({"schema": "other"}, fh)
            with self.assertRaises(rc.CannotRun) as cm:
                bx.load_extract(p)
            self.assertIn("render-extract/1", str(cm.exception))

    def test_write_refuses_relative_and_invalid(self):
        with self.assertRaises(rc.CannotRun):
            bx.write_extract("rel.json", good_doc())
        with tempfile.TemporaryDirectory() as td:
            with self.assertRaises(rc.CannotRun):
                bx.write_extract(os.path.join(td, "a.json"), {"schema": bx.SCHEMA})
            self.assertEqual(os.listdir(td), [])

    def test_script_args_and_parser(self):
        self.assertEqual(bx.script_args(["blender", "-b", "--", "--out", "/x"]), ["--out", "/x"])
        self.assertEqual(bx.script_args(["blender_extract.py", "--out", "/x"]), ["--out", "/x"])
        a = bx.make_parser().parse_args(["--out", "/x", "--step", "3", "--volume-objects", "A,B"])
        self.assertEqual((a.step, a.samples_every, a.volume_objects), (3, 0, "A,B"))

    def test_main_outside_blender_exits_2_and_help_0(self):
        tool = os.path.join(HERE, "..", "blender_extract.py")
        out = os.path.join(tempfile.gettempdir(), "never_written_extract.json")
        r = subprocess.run([sys.executable, "-I", "-B", tool, "--out", out], capture_output=True, text=True,
                           stdin=subprocess.DEVNULL, timeout=60)
        self.assertEqual(r.returncode, 2)
        self.assertIn("blender_extract: ERROR", r.stderr)
        self.assertFalse(os.path.exists(out))
        r = subprocess.run([sys.executable, "-I", "-B", tool, "--help"], capture_output=True, text=True,
                           stdin=subprocess.DEVNULL, timeout=60)
        self.assertEqual(r.returncode, 0)
        r = subprocess.run([sys.executable, "-I", "-B", tool, "--out", "relative.json"], capture_output=True,
                           text=True, stdin=subprocess.DEVNULL, timeout=60)
        self.assertEqual(r.returncode, 2)
        r = subprocess.run([sys.executable, "-I", "-B", tool], capture_output=True, text=True,
                           stdin=subprocess.DEVNULL, timeout=60)
        self.assertEqual(r.returncode, 2)  # argparse: --out is required


if __name__ == "__main__":
    unittest.main()
