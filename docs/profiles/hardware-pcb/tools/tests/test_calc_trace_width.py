import json
import math
import tomllib
import unittest

from support import TempDirTestCase, joined, load_tool, of_level, run_main

ct = load_tool("calc_trace_width")

BASE = """
[traces]
temp_rise_c_default = 10
copper_oz_outer = 1.0
copper_oz_inner = 0.5
class_width_step_mm = 0.1

[[traces.nets]]
name = "MAIN"
i_a = 6.0
netclass = "Power"
i_source = "param:input.current_a"

[[traces.nets]]
name = "AUX"
i_a = 1.0
netclass = "Power"
i_source = "item:loads:fan:i_a"
i_source_scale = 0.5

[[traces.nets]]
name = "CORE"
i_a = 2.0
layer = "inner"
temp_rise_c = 20

[[traces.nets]]
name = "FUTURE"
i_a = "pending"

[input]
current_a = 5.0

[[loads]]
name = "fan"
i_a = 1.5
"""

STACK = """
[stackup]
stackup_name = "stack-4L"
layer_names = ["L1", "L2", "L3", "L4"]
copper_thickness_mm = [0.035, 0.0152, 0.0152, 0.035]
copper_oz = [1.0, 0.5, 0.5, 1.0]
dielectric_thickness_mm = [0.2, 0.9, 0.2]
dielectric_dk = [4.3, 4.3, 4.3]
finished_thickness_sum_mm = 1.4004
"""


def params(*extra: str) -> dict:
    return tomllib.loads(BASE + "".join(extra))


class FormulaTests(unittest.TestCase):
    # Hand calculation of IPC-2221 for 1 A, 10 C rise, 1 oz (1.378 mil): external
    # A = (1 / (0.048 * 10**0.44)) ** (1 / 0.725) = 16.30 mil^2, width 11.83 mil = 0.3003 mm;
    # internal (k 0.024) multiplies the area by 2 ** (1 / 0.725) = 2.601, width 0.781 mm.
    def test_external_golden_value(self):
        self.assertAlmostEqual(ct.width_mm(1.0, 10.0, 1.0, internal=False), 0.3003, delta=0.001)

    def test_internal_golden_value_and_ratio(self):
        internal = ct.width_mm(1.0, 10.0, 1.0, internal=True)
        self.assertAlmostEqual(internal, 0.781, delta=0.002)
        self.assertAlmostEqual(internal / ct.width_mm(1.0, 10.0, 1.0, internal=False), 2.0 ** (1.0 / 0.725), places=6)

    def test_scaling_laws(self):
        one = ct.width_mm(2.0, 10.0, 1.0, False)
        self.assertAlmostEqual(one / ct.width_mm(2.0, 10.0, 2.0, False), 2.0, places=6)
        self.assertGreater(ct.width_mm(3.0, 10.0, 1.0, False), one)
        self.assertLess(ct.width_mm(2.0, 30.0, 1.0, False), one)

    def test_explicit_thickness_replaces_nominal(self):
        nominal = ct.nominal_thickness_mm(1.0)
        self.assertAlmostEqual(nominal, 0.035, delta=0.0001)
        ratio = ct.width_mm(2.0, 10.0, 1.0, False) / ct.width_mm(2.0, 10.0, 1.0, False, thickness_mm=0.0304)
        self.assertAlmostEqual(ratio, 0.0304 / nominal, places=9)

    def test_bad_inputs_raise(self):
        for args in ((0, 10, 1), (1, 0, 1), (1, 10, 0), (-1, 10, 1)):
            with self.assertRaises(ValueError):
                ct.width_mm(*args, internal=False)
        with self.assertRaises(ValueError):
            ct.width_mm(1, 10, 1, False, thickness_mm=0)

    # Hand calculation of IPC-2141, er 4.3, h 0.2 mm, w 0.3 mm, t 0.035 mm:
    # 87 / sqrt(5.71) = 36.41; ln(5.98 * 0.2 / (0.8 * 0.3 + 0.035)) = ln(4.349) = 1.4701; Z0 = 53.5 ohm.
    def test_microstrip_golden_value(self):
        self.assertAlmostEqual(ct.z0_microstrip(0.3, 0.2, 0.035, 4.3), 53.5, delta=0.1)

    def test_pair_is_below_twice_single_and_rises_with_gap(self):
        single = ct.z0_microstrip(0.3, 0.2, 0.035, 4.3)
        close = ct.zdiff_microstrip(0.3, 0.1, 0.2, 0.035, 4.3)
        far = ct.zdiff_microstrip(0.3, 0.5, 0.2, 0.035, 4.3)
        self.assertLess(close, far)
        self.assertLess(far, 2 * single)

    def test_solving_inverts_the_formula(self):
        for target in (80.0, 90.0, 100.0):
            width = ct.solve_diff_width(target, 0.15, 0.2, 0.035, 4.3)
            self.assertAlmostEqual(ct.zdiff_microstrip(width, 0.15, 0.2, 0.035, 4.3), target, places=4)
        width = ct.solve_single_width(50.0, 0.2, 0.035, 4.3)
        self.assertAlmostEqual(ct.z0_microstrip(width, 0.2, 0.035, 4.3), 50.0, places=4)

    def test_bad_geometry_raises(self):
        with self.assertRaises(ValueError):
            ct.z0_microstrip(0, 0.2, 0.035, 4.3)
        with self.assertRaises(ValueError):
            ct.zdiff_microstrip(0.3, 0, 0.2, 0.035, 4.3)


class NetTests(unittest.TestCase):
    def test_every_sized_net_is_reported_and_pending_warns(self):
        findings = ct.run(params())
        self.assertEqual(len([f for f in findings if f.check == "trace_width.net"]), 3)
        self.assertIn("FUTURE", joined(of_level(findings, "WARN")))
        self.assertIn("IPC-2152", joined(of_level(findings, "INFO")))

    def test_inner_net_uses_inner_weight_and_its_own_rise(self):
        rows = {r.name: r for r in ct.compute_nets(params())}
        self.assertAlmostEqual(rows["CORE"].width_mm, ct.width_mm(2.0, 20.0, 0.5, True))
        self.assertEqual(rows["CORE"].thickness_from, "nominal")

    def test_stackup_finished_copper_sizes_the_width(self):
        rows = {r.name: r for r in ct.compute_nets(params(STACK))}
        self.assertAlmostEqual(rows["CORE"].thickness_mm, 0.0152)
        self.assertAlmostEqual(rows["CORE"].width_mm, ct.width_mm(2.0, 20.0, 0.5, True, thickness_mm=0.0152), places=9)
        self.assertEqual(rows["MAIN"].thickness_from, "stack-up")

    def test_design_current_below_its_source_fails_at_or_above_passes(self):
        findings = ct.run(params())
        out = joined(of_level(findings, "PASS"))
        self.assertIn("MAIN: design current 6 A against param:input.current_a = 5.00 A: margin 1.00 A", out)
        # AUX carries one phase (scale 0.5) of the 1.5 A load: 0.75 A, design 1 A.
        self.assertIn("AUX: design current 1 A against item:loads:fan:i_a = 0.75 A", out)
        low = BASE.replace("i_a = 6.0", "i_a = 4.5")
        self.assertIn("MAIN: design current 4.5 A is below", joined(of_level(ct.run(tomllib.loads(low)), "FAIL")))

    def test_unknown_or_non_number_sources_are_errors_not_passes(self):
        for spec in ("rail:x:y", "param:input.missing", "item:loads:nofan:i_a", "item:loads:fan", "const:abc"):
            bad = tomllib.loads(BASE.replace("param:input.current_a", spec))
            with self.assertRaises(ct.ToolError, msg=spec):
                ct.compute_nets(bad)
        text = tomllib.loads(BASE.replace("param:input.current_a", "param:input"))
        with self.assertRaises(ct.ToolError):
            ct.compute_nets(text)

    def test_class_width_is_the_widest_net_rounded_up_to_the_step(self):
        row = {c.netclass: c for c in ct.class_widths(params())}["Power"]
        self.assertEqual(row.widest, "MAIN")
        self.assertAlmostEqual(row.required_mm, ct.width_mm(6.0, 10.0, 1.0, False))
        self.assertAlmostEqual(row.width_mm, math.ceil(row.required_mm / 0.1) * 0.1, places=6)
        wide = tomllib.loads(BASE.replace("class_width_step_mm = 0.1", "class_width_step_mm = 0.5"))
        self.assertAlmostEqual(ct.class_widths(wide)[0].width_mm % 0.5, 0.0, places=6)

    def test_wide_net_gets_a_pour_note(self):
        wide = tomllib.loads(BASE.replace("i_a = 6.0", "i_a = 60.0").replace("param:input.current_a", "const:1"))
        self.assertIn("use a pour or plane", joined(ct.run(wide)))

    def test_project_file_class_widths(self):
        need = ct.class_widths(params())[0].width_mm
        self.assertIn("PASS", [f.level for f in ct.run(params(), {"Power": need}) if f.check.endswith("project")])
        self.assertIn("is 0.2 mm in the project file", joined(of_level(ct.run(params(), {"Power": 0.2}), "FAIL")))
        self.assertIn("has no track width", joined(of_level(ct.run(params(), {}), "FAIL")))

    def test_stackup_weight_disagreeing_with_traces_fails(self):
        text = STACK.replace("copper_oz = [1.0, 0.5, 0.5, 1.0]", "copper_oz = [2.0, 0.5, 0.5, 2.0]")
        self.assertIn("typed twice", joined(of_level(ct.run(params(text)), "FAIL")))
        self.assertEqual(of_level(ct.run(params(STACK)), "FAIL"), [])

    def test_stackup_row_count_and_sum_checks(self):
        short = STACK.replace("dielectric_dk = [4.3, 4.3, 4.3]", "dielectric_dk = [4.3, 4.3]")
        self.assertIn("dielectric_dk has 2 entries", joined(of_level(ct.run(params(short)), "FAIL")))
        wrong = STACK.replace("finished_thickness_sum_mm = 1.4004", "finished_thickness_sum_mm = 1.6")
        self.assertIn("finished_thickness_sum_mm says 1.6", joined(of_level(ct.run(params(wrong)), "FAIL")))

    def test_layer_outside_the_enum_is_an_error_not_an_outer_net(self):
        # "internal" once took the outer coefficient (k 0.048, twice the inner one) and the outer copper,
        # understating the width of an inner net; every spelling but outer and inner is refused.
        for value in ('"internal"', '"Inner"', '"outer "', '""', "1"):
            bad = tomllib.loads(BASE.replace('layer = "inner"', f"layer = {value}"))
            with self.assertRaises(ct.ToolError, msg=value) as raised:
                ct.run(bad)
            self.assertIn("net CORE: layer", str(raised.exception))
            self.assertIn("'outer' or 'inner'", str(raised.exception))

    def test_layer_is_checked_on_a_pending_net_too(self):
        bad = tomllib.loads(BASE.replace('i_a = "pending"', 'i_a = "pending"\nlayer = "internal"'))
        with self.assertRaises(ct.ToolError):
            ct.run(bad)

    def test_outer_spelt_out_and_omitted_layer_are_the_same(self):
        spelt = tomllib.loads(BASE.replace('name = "MAIN"\n', 'name = "MAIN"\nlayer = "outer"\n'))
        rows = {r.name: r for r in ct.compute_nets(spelt)}
        self.assertEqual(rows["MAIN"].layer, "outer")
        self.assertAlmostEqual(rows["MAIN"].width_mm, {r.name: r for r in ct.compute_nets(params())}["MAIN"].width_mm)

    def test_missing_traces_table_or_bad_copper_is_an_error(self):
        with self.assertRaises(ct.ToolError):
            ct.run({})
        with self.assertRaises(ct.ToolError):
            ct.run(tomllib.loads(BASE.replace("copper_oz_outer = 1.0", "copper_oz_outer = 0")))


class ImpedanceTests(unittest.TestCase):
    def impedance(self, body: str) -> list:
        return [f for f in ct.run(params(STACK, body)) if f.check == "trace_width.impedance"]

    def test_pair_that_matches_its_stack_passes(self):
        width = ct.solve_diff_width(90.0, 0.15, 0.2, 0.035, 4.3)
        body = (f'[impedance]\nstackup = "stack-4L"\n[impedance.usb]\nlayer = "L1"\nreference_layer = "L2"\n'
                f'width_mm = {width:.4f}\ngap_mm = 0.15\nzdiff_ohm = 90.0\n')
        found = self.impedance(body)
        self.assertEqual([f.level for f in found], ["PASS"])

    def test_pair_sized_for_another_stack_fails_outside_the_band(self):
        body = ('[impedance]\n[impedance.usb]\nlayer = "L1"\nreference_layer = "L2"\n'
                'width_mm = 0.9\ngap_mm = 0.15\nzdiff_ohm = 90.0\n')
        self.assertIn("outside the 8 percent model band", joined(self.impedance(body)))

    def test_band_is_a_parameter(self):
        width = ct.solve_diff_width(90.0, 0.15, 0.2, 0.035, 4.3)
        body = (f'[impedance]\nmodel_band_pct = 0.5\n[impedance.usb]\nlayer = "L1"\nreference_layer = "L2"\n'
                f'width_mm = {width * 1.05:.4f}\ngap_mm = 0.15\nzdiff_ohm = 90.0\n')
        self.assertEqual([f.level for f in self.impedance(body)], ["FAIL"])

    def test_single_ended_trace(self):
        width = ct.solve_single_width(50.0, 0.2, 0.035, 4.3)
        body = (f'[impedance]\n[impedance.clk]\nlayer = "L1"\nreference_layer = "L2"\nwidth_mm = {width:.4f}\nz0_ohm = 50.0\n')
        self.assertEqual([f.level for f in self.impedance(body)], ["PASS"])

    def test_below_legal_minimum_fails_and_uncontrolled_is_info(self):
        body = ('[impedance]\n[impedance.usb]\nlayer = "L1"\nreference_layer = "L2"\nwidth_mm = 0.05\ngap_mm = 0.15\n'
                'zdiff_ohm = 90.0\nminimum_legal = { width_mm = 0.1 }\n')
        self.assertIn("below the legal minimum (width 0.05 < 0.1)", joined(self.impedance(body)))
        body = ('[impedance]\n[impedance.can]\nlayer = "L1"\nreference_layer = "L2"\nwidth_mm = 0.3\ngap_mm = 0.15\n'
                'zdiff_ohm = 120.0\ncontrolled = false\n')
        self.assertEqual([f.level for f in self.impedance(body)], ["INFO"])

    def test_wrong_stackup_name_or_non_adjacent_reference_fails(self):
        body = '[impedance]\nstackup = "other"\n'
        self.assertIn("this design is stack-4L", joined(self.impedance(body)))
        body = ('[impedance]\n[impedance.usb]\nlayer = "L1"\nreference_layer = "L3"\nwidth_mm = 0.3\ngap_mm = 0.15\n'
                'zdiff_ohm = 90.0\n')
        self.assertIn("not adjacent", joined(self.impedance(body)))

    def test_no_impedance_table_is_silent(self):
        self.assertEqual(self.impedance(""), [])


class CommandLineTests(TempDirTestCase):
    def test_exit_codes_and_table(self):
        path = self.write("parameters.toml", BASE)
        code, out = run_main(ct, ["--params", str(path)])
        self.assertEqual(code, 0, out)
        self.assertIn("Width mm", out)
        self.assertIn("MAIN", out)
        low = self.write("low.toml", BASE.replace("i_a = 6.0", "i_a = 1.0"))
        self.assertEqual(run_main(ct, ["--params", str(low)])[0], 1)
        self.assertEqual(run_main(ct, ["--params", str(self.root / "none.toml")])[0], 2)

    def test_misspelt_layer_exits_2(self):
        path = self.write("typo.toml", BASE.replace('layer = "inner"', 'layer = "internal"'))
        code, out = run_main(ct, ["--params", str(path)])
        self.assertEqual(code, 2, out)
        self.assertIn("could not run: net CORE: layer 'internal'", out)

    def test_kicad_project_file(self):
        path = self.write("parameters.toml", BASE)
        need = ct.class_widths(params())[0].width_mm
        good = self.write("good.kicad_pro", json.dumps({"net_settings": {"classes": [{"name": "Power", "track_width": need}]}}))
        bad = self.write("bad.kicad_pro", json.dumps({"net_settings": {"classes": [{"name": "Power", "track_width": 0.1}]}}))
        self.assertEqual(run_main(ct, ["--params", str(path), "--kicad-pro", str(good)])[0], 0)
        self.assertEqual(run_main(ct, ["--params", str(path), "--kicad-pro", str(bad)])[0], 1)
        broken = self.write("broken.kicad_pro", "{}")
        self.assertEqual(run_main(ct, ["--params", str(path), "--kicad-pro", str(broken)])[0], 2)

    def test_json_output(self):
        path = self.write("parameters.toml", BASE)
        code, out = run_main(ct, ["--params", str(path), "--json"])
        self.assertEqual(code, 0)
        self.assertIn("counts", json.loads(out))


if __name__ == "__main__":
    unittest.main()
