import copy
import json
import tempfile
import unittest
from pathlib import Path

from support import TOOLS_DIR, TempDirTestCase, load_tool, run_main

cpb = load_tool("check_power_branch")

EXAMPLE = TOOLS_DIR / "examples" / "power_branch_example.json"


def example() -> dict:
    return json.loads(EXAMPLE.read_text(encoding="utf-8"))


def statuses(findings, check: str) -> list[str]:
    return [finding.status for finding in findings if finding.check == check]


# The example branch (examples/power_branch_example.json), by hand:
#   rail 12.6 V max, 0.8 V overshoot -> start-up peak 13.4 V
#   capacitor 1000 uF, 25 V, ESR 0.04 ohm; series R = 0.015 + 0.025 + 0.02 + 0.04 = 0.100 ohm
#   charge Q = C V = 0.001 x 12.6 = 0.0126 C
#   resistive pulse: peak 12.6 / 0.1 = 126 A, I2t = C V^2 / (2 R) = 0.001 x 158.76 / 0.2 = 0.7938 A2s,
#     duration 3 R C = 0.3 ms
#   source limit 15 A is the smaller peak, so it governs: I2t = 15 x 0.0126 = 0.189 A2s over 0.84 ms
#   fuse 4 A, melting I2t 30 x pulse derating 0.4 = usable 12.0 A2s -> the pulse uses 1.6 percent
#   continuous allowance = 4 x 0.7 x 0.85 = 2.38 A (load 1.5 A; warn above 0.9 x 2.38 = 2.142 A)
#   peak 6 A for 0.1 s = 36 x 0.1 = 3.6 A2s against 12.0 A2s
#   fault clearing needs 3 x 4 = 12 A; the source gives 15 A
#   regeneration 0.02 J into 1000 uF: sqrt(13.4^2 + 2 x 0.02 / 0.001) = sqrt(179.56 + 40) = 14.82 V
#   window 18 V / 12.6 V = 1.43, above the 1.3 passive-clamp threshold

# A branch with only what was published when its fuse was chosen: the source's
# current limit, output resistance and overshoot are unknown, and the load's
# current limit was later raised. Made-up numbers.
UNBOUNDED_AS_SELECTED = {
    "name": "actuator branch as selected (made-up)",
    "rail": {"nominal_v": 12.0, "max_v": 12.0, "overshoot_v": None},
    "source": {"rating_a": 6.0, "current_limit_a": None, "can_sink": False},
    "series_resistance_ohm": {"source_output": None, "wiring": None, "fuse_cold": None},
    "capacitor": {"capacitance_f": 0.0033, "voltage_rating_v": 25.0, "esr_ohm": 0.05},
    "fuse": {"rating_a": 3.0, "type": "fast", "melting_i2t_a2s": None, "voltage_rating_v": 24.0},
    "holder": {"rating_a": 10.0},
    "wires": [{"name": "W1 20 AWG", "ampacity_a": None}],
    "loads": [{"name": "actuator", "continuous_supply_a": None, "peak_supply_a": None, "max_supply_v": 14.4}],
    "sizing_basis": [{"name": "actuator current limit mA", "assumed": 1500, "current": 2500,
                      "current_source": "setting changed after selection",
                      "sizes": "the branch fuse"}],
}
# By hand: window 14.4 V / 12.0 V = 1.20, under 1.3, so a passive clamp is ruled out;
# sizing basis 1500 against 2500 differs; overshoot is null, so UNKNOWN.


class ChargePulseTests(unittest.TestCase):
    # Hand calculation: C = 3.3 mF, V = 12 V, R = 0.04 ohm.
    # I2t = C V^2 / (2 R) = 0.0033 x 144 / 0.08 = 0.4752 / 0.08 = 5.94 A2s, peak V / R = 300 A.
    def test_resistive_pulse_is_half_c_v_squared_over_r(self):
        pulse = cpb.charge_pulse(0.0033, 12.0, 0.04, None)
        self.assertAlmostEqual(pulse["i2t"], 5.94, places=3)
        self.assertAlmostEqual(pulse["peak_a"], 300.0)

    # Constant current 6 A: I2t = I C V = 6 x 0.0033 x 12 = 0.2376 A2s over C V / I = 0.0396 / 6 = 6.6 ms.
    def test_current_limited_pulse_is_i_times_charge(self):
        pulse = cpb.charge_pulse(0.0033, 12.0, None, 6.0)
        self.assertAlmostEqual(pulse["i2t"], 0.2376, places=4)
        self.assertAlmostEqual(pulse["duration_s"], 0.0066, places=5)

    # Resistive peak 300 A against a 6 A limit: the 6 A limit is the smaller peak.
    def test_smaller_peak_governs_when_both_known(self):
        self.assertEqual(cpb.charge_pulse(0.0033, 12.0, 0.04, 6.0)["peak_a"], 6.0)

    def test_doubling_capacitance_doubles_the_pulse(self):
        small = cpb.charge_pulse(0.001, 12.0, 0.04, None)
        large = cpb.charge_pulse(0.002, 12.0, 0.04, None)
        self.assertAlmostEqual(large["i2t"], 2 * small["i2t"])

    def test_nothing_known_gives_no_pulse(self):
        self.assertIsNone(cpb.charge_pulse(0.0033, 12.0, None, None))


class BranchTests(unittest.TestCase):
    def test_example_branch_passes_clean(self):
        findings = cpb.evaluate(example())
        self.assertFalse([f for f in findings if f.status in (cpb.FAIL, cpb.UNKNOWN, cpb.WARN)])

    def test_short_inrush_beyond_usable_i2t_fails(self):
        branch = example()
        # No source limit, so the resistive pulse governs: 0.7938 A2s over 0.3 ms (under 10 ms).
        # Melting 1.0 x derating 0.4 = usable 0.4 A2s, below 0.7938.
        branch["source"]["current_limit_a"] = None
        branch["fuse"]["melting_i2t_a2s"] = 1.0
        self.assertIn(cpb.FAIL, statuses(cpb.evaluate(branch), "capacitor inrush"))

    def test_long_inrush_beyond_i2t_is_a_warning_not_a_fail(self):
        branch = example()
        # 1 A charges 1000 uF to 12.6 V in 0.0126 / 1 = 12.6 ms, past the adiabatic range.
        # I2t = 1 x 0.0126 = 0.0126 A2s; melting 0.02 x derating 0.4 = usable 0.008 A2s, so over it.
        branch["source"]["current_limit_a"] = 1.0
        branch["fuse"]["melting_i2t_a2s"] = 0.02
        self.assertEqual(statuses(cpb.evaluate(branch), "capacitor inrush"), [cpb.WARN])

    def test_unbounded_inrush_is_unknown_and_flags_a_fast_fuse(self):
        branch = example()
        branch["source"]["current_limit_a"] = None
        branch["series_resistance_ohm"]["source_output"] = None
        branch["fuse"]["type"] = "fast"
        findings = cpb.evaluate(branch)
        self.assertEqual(statuses(findings, "capacitor inrush"), [cpb.UNKNOWN])
        self.assertEqual(statuses(findings, "fuse type"), [cpb.WARN])

    def test_a_time_delay_fuse_with_unbounded_inrush_is_unknown_without_the_fuse_type_warning(self):
        branch = example()
        branch["source"]["current_limit_a"] = None
        branch["series_resistance_ohm"]["source_output"] = None
        findings = cpb.evaluate(branch)
        self.assertEqual(statuses(findings, "capacitor inrush"), [cpb.UNKNOWN])
        self.assertEqual(statuses(findings, "fuse type"), [])

    def test_continuous_current_above_derated_rating_fails(self):
        branch = example()
        # Allowance 4 x 0.7 x 0.85 = 2.38 A; 3.0 A is above it.
        branch["loads"][0]["continuous_supply_a"] = 3.0
        self.assertEqual(statuses(cpb.evaluate(branch), "fuse continuous"), [cpb.FAIL])

    def test_fuse_larger_than_wire_ampacity_fails(self):
        branch = example()
        branch["fuse"]["rating_a"] = 8.0       # against a 6 A wire
        self.assertEqual(statuses(cpb.evaluate(branch), "wire branch 20 AWG"), [cpb.FAIL])

    def test_weak_source_cannot_clear_the_fuse(self):
        branch = example()
        branch["source"]["current_limit_a"] = 9.0      # under 3 x 4 = 12 A
        self.assertEqual(statuses(cpb.evaluate(branch), "fault clearing"), [cpb.WARN])

    def test_regeneration_into_a_non_sinking_source_can_exceed_the_load_limit(self):
        branch = example()
        # sqrt(13.4^2 + 2 x 0.3 / 0.001) = sqrt(179.56 + 600) = 27.92 V: above the 16 V load
        # limit and above the 24 V fuse rating.
        branch["loads"][0]["regeneration_j"] = 0.3
        branch["loads"][0]["max_supply_v"] = 16.0
        findings = cpb.evaluate(branch)
        self.assertEqual(statuses(findings, "actuator supply limit"), [cpb.FAIL])
        self.assertEqual(statuses(findings, "fuse voltage"), [cpb.FAIL])

    def test_sizing_basis_read_from_a_file_detects_a_changed_limit(self):
        with tempfile.TemporaryDirectory() as folder:
            Path(folder, "Settings.h").write_text("const int ACTUATOR_LIMIT_MA = 2500;\n", encoding="utf-8")
            branch = example()
            branch["sizing_basis"] = [{"name": "max current", "assumed": 1500, "file": "Settings.h",
                                       "pattern": r"ACTUATOR_LIMIT_MA\s*=\s*(\d+)"}]
            findings = cpb.evaluate(branch, Path(folder))
        self.assertEqual(statuses(findings, "sizing basis max current"), [cpb.FAIL])

    def test_peak_within_rating_is_reported_not_skipped(self):
        branch = example()
        branch["loads"][0]["peak_supply_a"] = 3.5      # within the 4 A rating
        self.assertEqual(statuses(cpb.evaluate(branch), "actuator peak"), [cpb.PASS])

    def test_peak_above_rating_uses_i2t_when_no_time_current_table(self):
        branch = example()
        # 6 A for 0.1 s = 36 x 0.1 = 3.6 A2s against usable 30 x 0.4 = 12 A2s.
        self.assertEqual(statuses(cpb.evaluate(branch), "actuator peak"), [cpb.PASS])
        # 6 A for 0.5 s = 18 A2s against 12, longer than 10 ms: a warning.
        branch["loads"][0]["peak_duration_s"] = 0.5
        self.assertEqual(statuses(cpb.evaluate(branch), "actuator peak"), [cpb.WARN])
        # 60 A for 5 ms = 3600 x 0.005 = 18 A2s against 12, inside the adiabatic range: a fail.
        branch["loads"][0]["peak_duration_s"] = 0.005
        branch["loads"][0]["peak_supply_a"] = 60.0
        self.assertEqual(statuses(cpb.evaluate(branch), "actuator peak"), [cpb.FAIL])

    def test_narrow_window_rules_out_a_passive_clamp(self):
        branch = example()
        branch["rail"]["max_v"] = 12.0
        branch["loads"][0]["max_supply_v"] = 14.4     # window 14.4 / 12.0 = 1.20, under 1.3
        self.assertEqual(statuses(cpb.evaluate(branch), "clamp window"), [cpb.WARN])

    def test_wide_window_reports_nothing(self):
        self.assertEqual(statuses(cpb.evaluate(example()), "clamp window"), [])

    def test_given_clamp_is_checked_both_ways(self):
        branch = example()
        # Standoff 12.0 V is under the 12.6 V rail maximum; 20.5 V clamp is over the 18 V load limit.
        branch["clamp"] = {"standoff_v": 12.0, "clamp_v": 20.5, "clamp_current_a": 8.0}
        findings = cpb.evaluate(branch)
        self.assertEqual(statuses(findings, "clamp standoff"), [cpb.FAIL])
        self.assertEqual(statuses(findings, "clamp voltage"), [cpb.FAIL])
        # Standoff 14.0 V clears the rail; 17.0 V clamp is under the 18 V load limit.
        branch["clamp"] = {"standoff_v": 14.0, "clamp_v": 17.0}
        findings = cpb.evaluate(branch)
        self.assertEqual(statuses(findings, "clamp standoff"), [])
        self.assertEqual(statuses(findings, "clamp voltage"), [cpb.PASS])

    def test_active_clamp_is_credited_only_with_enough_energy(self):
        branch = example()
        # Regeneration 0.3 J lifts the rail to 27.92 V (see above); the load limit is 16 V.
        # An active clamp at 15.5 V with 25 J holds the peak at 15.5 V, under 16.
        branch["loads"][0]["regeneration_j"] = 0.3
        branch["loads"][0]["max_supply_v"] = 16.0
        branch["clamp"] = {"active": True, "standoff_v": 13.5, "clamp_v": 15.5, "energy_j": 25.0}
        self.assertEqual(statuses(cpb.evaluate(branch), "actuator supply limit"), [cpb.PASS])
        branch["clamp"]["energy_j"] = 0.1      # less than the 0.3 J regenerated: not credited
        self.assertEqual(statuses(cpb.evaluate(branch), "actuator supply limit"), [cpb.FAIL])
        branch["clamp"]["energy_j"] = None
        findings = cpb.evaluate(branch)
        self.assertEqual(statuses(findings, "regeneration clamp"), [cpb.UNKNOWN])
        self.assertEqual(statuses(findings, "actuator supply limit"), [cpb.FAIL])

    def test_unfused_branch_is_judged_not_crashed(self):
        branch = example()
        del branch["fuse"]
        # Smallest wire 6 A; a source that can deliver 20 A is a FAIL, not a KeyError.
        branch["source"] = {"rating_a": 16.0, "current_limit_a": 20.0}
        self.assertEqual(statuses(cpb.evaluate(branch), "no fuse"), [cpb.FAIL])
        branch["source"] = {"rating_a": 3.0, "current_limit_a": 5.0}
        self.assertEqual(statuses(cpb.evaluate(branch), "no fuse"), [cpb.PASS])
        branch["wires"] = []
        self.assertEqual(statuses(cpb.evaluate(branch), "no fuse"), [cpb.UNKNOWN])

    def test_unknown_regeneration_is_reported_not_silent(self):
        # A null regeneration_j once summed as zero and showed the rail peak at the
        # bare rail voltage with no finding at all.
        branch = example()
        branch["loads"][0]["regeneration_j"] = None
        findings = cpb.evaluate(branch)
        self.assertEqual(statuses(findings, "regeneration"), [cpb.UNKNOWN])
        message = next(f.message for f in findings if f.check == "regeneration")
        self.assertIn("actuator", message)

    def test_a_load_that_omits_regeneration_is_not_reported(self):
        branch = example()
        del branch["loads"][0]["regeneration_j"]
        self.assertEqual(statuses(cpb.evaluate(branch), "regeneration"), [])

    def test_holder_derating_applies(self):
        branch = example()
        branch["holder"] = {"rating_a": 5.0, "derating": 0.6}      # 3.0 A, under the 4 A fuse
        self.assertEqual(statuses(cpb.evaluate(branch), "holder"), [cpb.FAIL])

    def test_sustained_current_against_the_time_current_table(self):
        # Made-up maker points: [multiple of rating, minimum opening time s].
        table = [[1.2, 7200], [1.5, 1.0], [1.8, 0.3], [2.5, 0.1], [4.0, 0.05]]
        fuse = {"rating_a": 4.0, "time_current": table}
        # 5.6 A is 140 percent: between the 120 and 150 percent points, 3 s is past the 1 s of the next.
        self.assertEqual(cpb.opening_band(fuse, 5.6, 3.0)[0], cpb.WARN)
        # Same current for 0.5 s is shorter than the 1 s minimum of the next point.
        self.assertEqual(cpb.opening_band(fuse, 5.6, 0.5)[0], cpb.PASS)
        # 8 A is 200 percent: the 180 percent point opens in 0.3 s, so 3 s fails.
        self.assertEqual(cpb.opening_band(fuse, 8.0, 3.0)[0], cpb.FAIL)
        # On a 6 A fuse, 5.6 A is 93 percent, below every published point.
        self.assertEqual(cpb.opening_band({"rating_a": 6.0, "time_current": table}, 5.6, 3.0)[0], cpb.PASS)
        self.assertIsNone(cpb.opening_band({"rating_a": 4.0}, 5.6, 3.0))

    def test_missing_basis_file_is_unknown(self):
        branch = example()
        branch["sizing_basis"] = [{"name": "gone", "assumed": 1, "file": "nope.h", "pattern": "(1)"}]
        self.assertEqual(statuses(cpb.evaluate(branch), "sizing basis gone"), [cpb.UNKNOWN])

    def test_branch_without_a_rail_is_an_error(self):
        branch = example()
        del branch["rail"]
        with self.assertRaises(cpb.ToolError):
            cpb.evaluate(branch)


class UnboundedInrushRegressionTests(unittest.TestCase):
    """The failure mode the tool exists for: a branch chosen on what was known, then a limit moved."""

    def setUp(self):
        self.findings = cpb.evaluate(copy.deepcopy(UNBOUNDED_AS_SELECTED))

    def test_inrush_is_reported_unknown_not_assumed_safe(self):
        self.assertEqual(statuses(self.findings, "capacitor inrush"), [cpb.UNKNOWN])
        message = next(f.message for f in self.findings if f.check == "capacitor inrush")
        self.assertIn("soft start", message)

    def test_fast_fuse_in_front_of_bulk_capacitance_is_flagged(self):
        self.assertEqual(statuses(self.findings, "fuse type"), [cpb.WARN])

    def test_raised_current_limit_fails_the_sizing_basis(self):
        self.assertEqual(statuses(self.findings, "sizing basis actuator current limit mA"), [cpb.FAIL])

    def test_passive_clamp_is_ruled_out_for_the_narrow_window(self):
        self.assertEqual(statuses(self.findings, "clamp window"), [cpb.WARN])

    def test_unmeasured_overshoot_is_unknown(self):
        self.assertEqual(statuses(self.findings, "rail overshoot"), [cpb.UNKNOWN])


class CommandLineTests(TempDirTestCase):
    def test_exit_codes_and_strict(self):
        path = self.write("branch.json", json.dumps(UNBOUNDED_AS_SELECTED))
        self.assertEqual(run_main(cpb, [str(path)])[0], 1)
        unknown_only = copy.deepcopy(UNBOUNDED_AS_SELECTED)
        unknown_only["sizing_basis"][0]["current"] = 1500
        path.write_text(json.dumps(unknown_only), encoding="utf-8")
        self.assertEqual(run_main(cpb, [str(path)])[0], 0)
        self.assertEqual(run_main(cpb, [str(path), "--strict"])[0], 1)

    def test_unknown_regeneration_alone_fails_only_under_strict(self):
        branch = example()
        branch["loads"][0]["regeneration_j"] = None
        path = self.write("branch.json", json.dumps(branch))
        code, out = run_main(cpb, [str(path)])
        self.assertEqual(code, 0, out)
        self.assertIn("UNKNOWN", out)
        self.assertIn("regeneration energy not given for actuator", out)
        self.assertIn("Summary: 0 FAIL, 1 UNKNOWN, 0 WARN", out)
        self.assertEqual(run_main(cpb, [str(path), "--strict"])[0], 1)

    def test_example_runs_clean_from_the_command_line(self):
        code, out = run_main(cpb, [str(EXAMPLE)])
        self.assertEqual(code, 0, out)
        self.assertIn("Summary: 0 FAIL, 0 UNKNOWN, 0 WARN", out)
        self.assertEqual(run_main(cpb, [str(EXAMPLE), "--strict"])[0], 0)

    def test_unreadable_or_invalid_branch_is_could_not_run(self):
        self.assertEqual(run_main(cpb, [str(self.root / "none.json")])[0], 2)
        self.write("bad.json", "{not json")
        self.assertEqual(run_main(cpb, [str(self.root / "bad.json")])[0], 2)
        self.write("list.json", "[1]")
        self.assertEqual(run_main(cpb, [str(self.root / "list.json")])[0], 2)
        self.write("norail.json", "{}")
        self.assertEqual(run_main(cpb, [str(self.root / "norail.json")])[0], 2)

    def test_sizing_basis_files_resolve_against_the_branch_folder(self):
        self.write("Settings.h", "LIMIT = 2500;\n")
        branch = example()
        branch["sizing_basis"] = [{"name": "limit", "assumed": 1500, "file": "Settings.h", "pattern": r"LIMIT = (\d+)"}]
        path = self.write("branch.json", json.dumps(branch))
        code, out = run_main(cpb, [str(path)])
        self.assertEqual(code, 1)
        self.assertIn("sized from 1500, now 2500", out)

    def test_json_output(self):
        code, out = run_main(cpb, [str(EXAMPLE), "--json"])
        self.assertEqual(code, 0)
        self.assertEqual(json.loads(out)["counts"], {"FAIL": 0, "UNKNOWN": 0, "WARN": 0})


if __name__ == "__main__":
    unittest.main()
