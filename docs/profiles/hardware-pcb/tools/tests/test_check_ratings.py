import tomllib
import unittest

from support import TempDirTestCase, joined, load_tool, of_level, run_main

cr = load_tool("check_ratings")

BASE = """
[derating]
voltage_steady_state_factor = 1.5
voltage_transient_margin = 1.1
current_continuous_factor = 0.7
inductor_saturation_factor = 1.3
temperature_grade_min_c = 105

[domains.12V]
v_steady_max = 12.6
clamp_max_v = 30.0
min_part_voltage_rating = 40.0

[domains.5V]
v_steady_max = 5.25
clamp_max_v = 8.0
min_part_voltage_rating = 16.0

[[loads]]
name = "fan"
i_a = 3.0

[[parts]]
ref = "U1"
domain = "12V"
v_abs_max = 60.0
status = "datasheet"
datasheet = "datasheets/u1.pdf"
i_cont_a = 6.0
demand = "item:loads:fan:i_a"
temp_grade_c = 125
"""


def run(extra: str = "", base: str = BASE):
    return cr.run(tomllib.loads(base + extra))


def part(ref="U2", **fields) -> str:
    body = "".join(f"{k} = {v if not isinstance(v, str) else repr(v).replace(chr(39), chr(34))}\n" for k, v in fields.items())
    return f'\n[[parts]]\nref = "{ref}"\n{body}'


class VoltageTests(unittest.TestCase):
    def test_good_part_passes_every_check(self):
        findings = run()
        self.assertEqual(of_level(findings, "FAIL"), [])
        self.assertEqual(of_level(findings, "WARN"), [])
        checks = {f.check for f in of_level(findings, "PASS")}
        self.assertTrue({"ratings.rating", "ratings.derate_steady", "ratings.derate_transient",
                         "ratings.derate_current", "ratings.temp_grade"} <= checks)

    def test_rating_below_domain_minimum_fails(self):
        findings = run(part(domain="12V", v_abs_max=35.0, status="datasheet"))
        self.assertIn("U2: v_abs_max 35 V vs 12V domain minimum 40 V: too low", joined(of_level(findings, "FAIL")))

    def test_steady_state_derating_uses_the_policy_factor(self):
        # 1.5 x 5.25 = 7.875 V steady, 1.1 x 8 = 8.8 V transient, minimum 16 V: 16 V passes, 15 V fails the minimum only.
        self.assertEqual(of_level(run(part(domain="5V", v_abs_max=16.0, status="datasheet")), "FAIL"), [])
        findings = run(part(domain="5V", v_abs_max=15.0, status="datasheet"))
        self.assertEqual([f.check for f in of_level(findings, "FAIL")], ["ratings.rating"])

    def test_derating_fails_when_the_domain_minimum_is_looser_than_the_policy(self):
        text = BASE.replace("min_part_voltage_rating = 16.0", "min_part_voltage_rating = 6.0")
        findings = run(part(domain="5V", v_abs_max=7.0, status="datasheet"), text)
        checks = [f.check for f in of_level(findings, "FAIL")]
        self.assertIn("ratings.derate_steady", checks)
        self.assertIn("ratings.derate_transient", checks)

    def test_domain_override_replaces_the_policy_factor(self):
        text = BASE.replace("min_part_voltage_rating = 16.0", "min_part_voltage_rating = 16.0\nvoltage_steady_state_factor = 4.0")
        findings = run(part(domain="5V", v_abs_max=20.0, status="datasheet"), text)
        self.assertIn("4 x 5V steady 5.25 V = 21 V (domain override)", joined(of_level(findings, "FAIL")))

    def test_documented_exception_turns_a_rating_fail_into_a_warn(self):
        findings = run(part(domain="12V", v_abs_max=35.0, status="datasheet", rating_exception="series resistor and clamp protect the pins"))
        self.assertEqual(of_level(findings, "FAIL"), [])
        self.assertIn("excepted: series resistor and clamp protect the pins", joined(of_level(findings, "WARN")))

    def test_pending_rating_and_pending_requirement(self):
        findings = run(part(domain="12V", v_abs_max="pending", datasheet="datasheets/x.pdf"))
        self.assertIn("v_abs_max is pending", joined(of_level(findings, "WARN")))
        self.assertEqual(of_level(findings, "FAIL"), [])
        low = run(part(domain="12V", v_abs_max_min_required=30.0))
        self.assertIn("requirement is too low", joined(of_level(low, "FAIL")))
        ok = run(part(domain="12V", v_abs_max_min_required=45.0))
        self.assertIn("requirement is adequate", joined(of_level(ok, "WARN")))

    def test_estimate_status_never_passes_plainly(self):
        findings = run(part(domain="12V", v_abs_max=60.0, status="estimate"))
        self.assertIn("basis status: estimate", joined(of_level(findings, "WARN")))

    def test_unknown_domain_fails_and_missing_datasheets_warn(self):
        self.assertIn("domain '48V' is not in [domains]", joined(of_level(run(part(domain="48V")), "FAIL")))
        findings = run(part(domain="12V", v_abs_max=60.0, datasheet="NOT RETRIEVED - timeout"))
        self.assertIn("datasheet missing", joined(of_level(findings, "WARN")))

    def test_reverse_only_and_unrated_parts_are_info(self):
        findings = run(part(domain="12V", v_reverse_max=40.0) + part("U3", domain="12V"))
        self.assertEqual(len([f for f in findings if f.level == "INFO" and f.check == "ratings.rating"]), 2)


class TvsTests(unittest.TestCase):
    def tvs(self, **fields):
        return run(part("D1", domain="12V", status="datasheet", **fields))

    def test_good_tvs_passes(self):
        findings = self.tvs(v_standoff=13.0, v_clamp_max=21.0)
        self.assertEqual(of_level(findings, "FAIL"), [])
        self.assertIn("stands off 13 V (needs 12.6 V), clamps at 21 V", joined(of_level(findings, "PASS")))

    def test_low_standoff_and_high_clamp_fail(self):
        findings = self.tvs(v_standoff=12.0, v_clamp_max=33.0)
        out = joined(of_level(findings, "FAIL"))
        self.assertIn("v_standoff 12 V is below", out)
        self.assertIn("v_clamp_max 33 V exceeds domain clamp_max_v 30 V", out)

    def test_clamp_exception_downgrades_only_the_clamp(self):
        findings = self.tvs(v_standoff=13.0, v_clamp_max=33.0, clamp_rule_exception="load rated 45 V")
        self.assertEqual(of_level(findings, "FAIL"), [])
        self.assertIn("recorded exception: load rated 45 V", joined(of_level(findings, "WARN")))
        findings = self.tvs(v_standoff=12.0, v_clamp_max=33.0, clamp_rule_exception="load rated 45 V")
        self.assertTrue(of_level(findings, "FAIL"))

    def test_pending_clamp_warns(self):
        findings = self.tvs(v_standoff=13.0, v_clamp_max="pending")
        self.assertIn("v_clamp_max is pending", joined(of_level(findings, "WARN")))


class CurrentAndInductorTests(unittest.TestCase):
    def test_demand_over_derated_current_fails_at_the_limit_passes(self):
        # 0.7 x 6 A = 4.2 A against a 3 A load.
        over = BASE.replace("i_a = 3.0", "i_a = 4.3")
        self.assertIn("over the continuous-current derating", joined(of_level(run(base=over), "FAIL")))
        at = BASE.replace("i_a = 3.0", "i_a = 4.2")
        self.assertEqual(of_level(run(base=at), "FAIL"), [])

    def test_parallel_devices_share_the_demand(self):
        findings = run(part("Q1", domain="12V", v_abs_max=60.0, status="datasheet", i_cont_a=3.0, parallel_devices=2,
                            demand="const:4.0"))
        self.assertIn("Q1: demand 2 A shared by 2 parallel devices", joined(of_level(findings, "PASS")))

    def test_per_channel_rating_is_used(self):
        findings = run(part("U5", domain="12V", i_cont_a_per_ch=1.0, demand="const:0.8"))
        self.assertIn("i_cont_a_per_ch 1 A = 0.7 A", joined(of_level(findings, "FAIL")))

    def test_parts_without_rating_or_demand_are_counted_not_skipped(self):
        findings = run(part("U6", domain="12V", demand="const:1.0") + part("U7", domain="12V", i_cont_a=2.0))
        info = joined([f for f in findings if f.check == "ratings.derate_current" and f.level == "INFO"])
        self.assertIn("no continuous current rating recorded for U6", info)
        self.assertIn("no demand source for U7", info)

    def test_bad_demand_sources_are_errors(self):
        for spec in ("rail:x", "item:loads:none:i_a", "param:missing.value", "const:abc", "item:loads:fan"):
            with self.assertRaises(cr.ToolError, msg=spec):
                run(part("U8", domain="12V", i_cont_a=2.0, demand=spec))

    def test_inductor_saturation(self):
        ok = run(part("L1", domain="12V", l_uh=4.7, i_sat_a=9.0, i_peak_a=6.0, status="datasheet"))
        self.assertIn("L1: i_sat_a 9 A vs 1.3 x peak 6 A = 7.80 A", joined(of_level(ok, "PASS")))
        bad = run(part("L1", domain="12V", l_uh=4.7, i_sat_a=7.0, i_peak_a=6.0, status="datasheet"))
        self.assertIn("saturates before the derated peak", joined(of_level(bad, "FAIL")))
        none = run(part("L1", domain="12V", l_uh=4.7, i_sat_min_a=9.0))
        self.assertIn("i_peak_a is None", joined(of_level(none, "WARN")))

    def test_temperature_grade(self):
        self.assertIn("85 C vs minimum 105 C", joined(of_level(run(part("U9", domain="12V", temp_grade_c=85)), "FAIL")))
        excepted = run(part("U9", domain="12V", temp_grade_c=85, temp_grade_exception="mounted away from heat"))
        self.assertEqual(of_level(excepted, "FAIL"), [])
        self.assertIn("mounted away from heat", joined(of_level(excepted, "WARN")))
        self.assertIn("parts have no temp_grade_c recorded", joined(of_level(run(part("U9", domain="12V")), "INFO")))


class DomainAndProtectionTests(unittest.TestCase):
    def test_domain_clamp_above_minimum_rating_fails_and_equal_warns(self):
        bad = BASE.replace("min_part_voltage_rating = 40.0", "min_part_voltage_rating = 25.0")
        self.assertIn("domain 12V: clamp_max_v 30 V vs minimum part rating 25 V", joined(of_level(run(base=bad), "FAIL")))
        equal = BASE.replace("min_part_voltage_rating = 40.0", "min_part_voltage_rating = 30.0")
        self.assertIn("zero margin", joined(of_level(run(base=equal), "WARN")))

    def test_protection_order_and_overvoltage_cutoff(self):
        extra = '\n[protection]\nfuse_rating_a = 25.0\nfuse_continuous_derating = 0.8\ntrip_a = 22.0\nov_cutoff_v = 15.0\nov_domain = "12V"\n'
        findings = run(extra)
        self.assertIn("the electronic limit acts first", joined(of_level(findings, "INFO")))
        self.assertIn("cut-off operates below the clamp", joined(of_level(findings, "INFO")))
        later = run(extra.replace("trip_a = 22.0", "trip_a = 30.0").replace("ov_cutoff_v = 15.0", "ov_cutoff_v = 31.0"))
        self.assertIn("the fuse acts first", joined(of_level(later, "INFO")))
        self.assertIn("between 20 A and 30 A the fuse carries more than its continuous rating", joined(of_level(later, "INFO")))
        self.assertIn("cut-off must be below the clamp", joined(of_level(later, "FAIL")))

    def test_policy_is_required(self):
        with self.assertRaises(cr.ToolError):
            cr.run({})
        with self.assertRaises(cr.ToolError):
            cr.run(tomllib.loads(BASE.replace("temperature_grade_min_c = 105", "")))
        with self.assertRaises(cr.ToolError):
            cr.run({"derating": tomllib.loads(BASE)["derating"], "parts": [{"domain": "12V"}]})


class CommandLineTests(TempDirTestCase):
    def test_exit_codes(self):
        path = self.write("parameters.toml", BASE)
        code, out = run_main(cr, ["--params", str(path)])
        self.assertEqual(code, 0, out)
        bad = self.write("bad.toml", BASE.replace("v_abs_max = 60.0", "v_abs_max = 20.0"))
        self.assertEqual(run_main(cr, ["--params", str(bad)])[0], 1)
        self.assertEqual(run_main(cr, ["--params", str(self.root / "none.toml")])[0], 2)
        self.write("nopolicy.toml", "[domains.x]\nclamp_max_v = 1\n")
        self.assertEqual(run_main(cr, ["--params", str(self.root / "nopolicy.toml")])[0], 2)


if __name__ == "__main__":
    unittest.main()
