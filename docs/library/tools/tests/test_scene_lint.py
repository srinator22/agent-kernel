"""Tests for scene_lint.py on synthetic render-extract/1 documents and presets (no Blender)."""
import contextlib
import io
import json
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import blender_extract as bx  # noqa: E402
import scene_lint as sl  # noqa: E402


def make_doc():
    d = bx.skeleton("5.2.3")
    d["scene"].update(name="Scene", fps=24.0, frame_start=1, frame_end=96, resolution=[1920, 1080],
                      resolution_percentage=100, engine="CYCLES", unit_system="METRIC", scale_length=1.0,
                      view_transform="AgX", look="None", exposure=0.0, gamma=1.0, motion_blur=True,
                      film_transparent=False)
    d["scene"]["cycles"].update(device="GPU", samples=1024, use_adaptive_sampling=True, use_denoising=True,
                                denoiser="OPENIMAGEDENOISE", denoising_input_passes="RGB_ALBEDO_NORMAL",
                                denoising_prefilter="ACCURATE", seed=0, use_animated_seed=False, filter_width=1.75,
                                max_bounces=12, transmission_bounces=12)
    d["lights"] = [{"name": "Key", "type": "AREA", "energy": 300.0, "color": [1, 1, 1], "size": 1.0, "spread": 0.9,
                    "visible_camera": False, "visible_glossy": True, "visible_transmission": True},
                   {"name": "Fill", "type": "AREA", "energy": 100.0, "color": [1, 1, 1], "size": 1.0, "spread": 0.9,
                    "visible_camera": False, "visible_glossy": True, "visible_transmission": True}]
    d["materials"] = [{"name": "Shell", "images": [{"path": "//t.png", "abs": "/x/t.png", "exists": True}],
                       "transmission": 1.0, "sheen": 0.0, "roughness": 0.05}]
    d["objects"] = [{"name": "Lid", "type": "MESH", "hide_render": False, "hide_viewport": False, "animated": True,
                     "dimensions": [0.1, 0.1, 0.1], "label": "Lid"}]
    return d


PRESET = {"name": "final", "settings": {"scene.cycles.samples": 1024, "scene.cycles.use_animated_seed": False,
                                        "scene.view_transform": "AgX", "scene.motion_blur": True,
                                        "scene.resolution": [1920, 1080], "scene.cycles.filter_width": 1.75},
          "transparent_min_samples": 1024, "allow_units": ["METRIC"], "max_light_ratio": 1000}


def run(argv):
    out, err = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        try:
            code = sl.main(argv)
        except SystemExit as e:
            code = e.code
    return code, out.getvalue(), err.getvalue()


class LintCase(unittest.TestCase):
    def setUp(self):
        self._td = tempfile.TemporaryDirectory()
        self.addCleanup(self._td.cleanup)
        self.d = os.path.realpath(self._td.name)

    def put(self, data, name):
        p = os.path.join(self.d, name)
        with open(p, "w") as fh:
            json.dump(data, fh)
        return p

    def lint(self, doc=None, preset=None, extra=()):
        return run([self.put(doc or make_doc(), "e.json"), "--preset", self.put(preset or PRESET, "p.json")] + list(extra))

    def mutated(self, fn):
        d = make_doc()
        fn(d)
        return d


class FindingTests(LintCase):
    def test_clean_scene_passes(self):
        code, out, _ = self.lint()
        self.assertEqual(code, 0, out)
        self.assertIn("scene_lint: PASS preset 'final'", out.splitlines()[-1])

    def test_setting_mismatch_shows_both_values(self):
        d = self.mutated(lambda d: d["scene"]["cycles"].update(samples=256, use_animated_seed=True))
        code, out, _ = self.lint(d)
        self.assertEqual(code, 1)
        self.assertIn("scene.cycles.samples is 256, preset wants 1024", out)
        self.assertIn("scene.cycles.use_animated_seed is true, preset wants false", out)

    def test_view_transform_resolution_and_float_tolerance(self):
        d = self.mutated(lambda d: d["scene"].update(view_transform="Standard", resolution=[1280, 720]))
        d["scene"]["cycles"]["filter_width"] = 1.75 + 1e-9
        code, out, _ = self.lint(d)
        self.assertEqual(code, 1)
        self.assertIn('scene.view_transform is "Standard"', out)
        self.assertIn("scene.resolution is [1280, 720]", out)
        self.assertNotIn("filter_width", out)

    def test_bool_is_not_equal_to_number(self):
        self.assertFalse(sl.same(True, 1))
        self.assertFalse(sl.same(0, False))
        self.assertTrue(sl.same([1, 2.0], [1.0, 2]))
        self.assertFalse(sl.same([1], [1, 2]))

    def test_null_and_absent_are_unreadable(self):
        d = self.mutated(lambda d: d["scene"]["cycles"].update(samples=None))
        pre = dict(PRESET, settings={"scene.cycles.samples": 1024, "scene.nothing": 1})
        code, out, _ = self.lint(d, pre)
        self.assertEqual(code, 1)
        self.assertIn("unreadable: scene.cycles.samples is null", out)
        self.assertIn("unreadable: scene.nothing is absent", out)

    def test_units(self):
        code, out, _ = self.lint(self.mutated(lambda d: d["scene"].update(unit_system="IMPERIAL")))
        self.assertEqual(code, 1)
        self.assertIn("unit system is IMPERIAL", out)
        code, out, _ = self.lint(self.mutated(lambda d: d["scene"].update(scale_length=0.001)))
        self.assertIn("scale_length is 0.001", out)
        self.assertEqual(self.lint(self.mutated(lambda d: d["scene"].update(unit_system="IMPERIAL")),
                                   dict(PRESET, allow_units=["METRIC", "IMPERIAL"]))[0], 0)
        code, out, _ = self.lint(self.mutated(lambda d: d["scene"].update(unit_system=None, scale_length=None)))
        self.assertEqual(out.count("unreadable"), 2)

    def test_missing_texture(self):
        d = self.mutated(lambda d: d["materials"][0]["images"][0].update(exists=False))
        code, out, _ = self.lint(d)
        self.assertEqual(code, 1)
        self.assertIn("texture: material Shell: image file missing: /x/t.png", out)
        d = self.mutated(lambda d: d["materials"][0]["images"][0].update(exists=None))
        self.assertIn("cannot tell whether image", self.lint(d)[1])

    def test_glass_needs_samples(self):
        pre = dict(PRESET, settings={})
        d = self.mutated(lambda d: d["scene"]["cycles"].update(samples=256))
        code, out, _ = self.lint(d, pre)
        self.assertEqual(code, 1)
        self.assertIn("samples: transmissive material(s) Shell with 256 samples", out)
        d2 = self.mutated(lambda d: d["materials"][0].update(transmission=0.2))
        d2["scene"]["cycles"]["samples"] = 256
        self.assertEqual(self.lint(d2, pre)[0], 0)
        d3 = self.mutated(lambda d: d["scene"].update(engine="BLENDER_WORKBENCH"))
        d3["scene"]["cycles"]["samples"] = 4
        self.assertEqual(self.lint(d3, pre)[0], 0)

    def test_lights(self):
        d = self.mutated(lambda d: d["lights"][1].update(energy=0.0))
        code, out, _ = self.lint(d)
        self.assertEqual(code, 1)
        self.assertIn("light: light Fill has energy 0", out)
        d = self.mutated(lambda d: d["lights"][1].update(energy=0.1))
        code, out, _ = self.lint(d)
        self.assertEqual(code, 1)
        self.assertIn("warning:light-ratio: brightest light Key (300) is 3000 x the dimmest Fill (0.1)", out)
        d = self.mutated(lambda d: d["lights"][0].update(energy=None))
        self.assertIn("unreadable: light Key", self.lint(d)[1])

    def test_hidden_but_keyed(self):
        d = self.mutated(lambda d: d["objects"][0].update(hide_render=True))
        code, out, _ = self.lint(d)
        self.assertEqual(code, 1)
        self.assertIn("hidden-keyed: object Lid", out)
        d = self.mutated(lambda d: d["objects"][0].update(hide_render=True, animated=False))
        self.assertEqual(self.lint(d)[0], 0)

    def test_denoiser_rule_only_when_preset_asks(self):
        d = self.mutated(lambda d: d["scene"]["cycles"].update(denoiser="OPTIX", denoising_input_passes="RGB"))
        self.assertEqual(self.lint(d)[0], 0)
        code, out, _ = self.lint(d, dict(PRESET, require_oidn_albedo_normal=True))
        self.assertEqual(code, 1)
        self.assertIn("denoiser: denoiser is OPTIX with passes RGB", out)
        d = self.mutated(lambda d: d["scene"]["cycles"].update(use_denoising=False, denoiser="OPTIX"))
        self.assertEqual(self.lint(d, dict(PRESET, require_oidn_albedo_normal=True))[0], 0)


class AdvisoryTests(LintCase):
    def test_rim_light_advisory_does_not_fail(self):
        d = self.mutated(lambda d: d["lights"][0].update(visible_camera=True, visible_glossy=True))
        code, out, _ = self.lint(d)
        self.assertEqual(code, 0, out)
        self.assertIn("advisory: light Key: check rim light in glossy/transmission", out)

    def test_no_advisory_without_glass(self):
        d = self.mutated(lambda d: d["lights"][0].update(visible_camera=True))
        d["materials"][0]["transmission"] = 0.0
        code, out, _ = self.lint(d)
        self.assertNotIn("advisory", out)

    def test_film_grain_is_advisory(self):
        code, out, _ = self.lint(preset=dict(PRESET, film_grain=False))
        self.assertEqual(code, 0)
        self.assertIn("film_grain=False in the preset cannot be checked", out)


class ErrorTests(LintCase):
    def test_json_report(self):
        rep = os.path.join(self.d, "r.json")
        d = self.mutated(lambda d: d["scene"]["cycles"].update(samples=1))
        code, out, _ = self.lint(d, extra=["--json", rep])
        self.assertEqual(code, 1)
        with open(rep, "r", encoding="utf-8") as fh:
            data = json.load(fh)
        self.assertEqual((data["tool"], data["status"]), ("scene_lint", "fail"))
        self.assertTrue(data["findings"])

    def test_exit_2_cases(self):
        good_e = self.put(make_doc(), "e.json")
        good_p = self.put(PRESET, "p.json")
        bad_e = self.put({"schema": "other"}, "be.json")
        junk = os.path.join(self.d, "junk.json")
        with open(junk, "w") as fh:
            fh.write("[")
        cases = [
            [bad_e, "--preset", good_p],
            [os.path.join(self.d, "none.json"), "--preset", good_p],
            [good_e, "--preset", os.path.join(self.d, "none.json")],
            [good_e, "--preset", junk],
            [good_e, "--preset", self.put({"setings": {}}, "typo.json")],
            [good_e, "--preset", self.put({"settings": []}, "s.json")],
            [good_e, "--preset", self.put({"max_light_ratio": -1}, "m.json")],
            [good_e, "--preset", self.put({"allow_units": "METRIC"}, "u.json")],
            [good_e, "--preset", self.put([], "l.json")],
            [good_e],
            [],
        ]
        for argv in cases:
            code, _, err = run(argv)
            self.assertEqual(code, 2, argv)
        self.assertIn("scene_lint: ERROR", run(cases[0])[2])
        self.assertEqual(run(["--help"])[0], 0)


if __name__ == "__main__":
    unittest.main()
