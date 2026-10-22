import tomllib
import unittest

from support import TempDirTestCase, joined, load_tool, of_level, run_main

cb = load_tool("check_bom")

MANIFEST = ("| Part | File | SHA-256 | Status |\n|---|---|---|---|\n"
            "| Regulator | power/REG100.pdf | " + "ab" * 32 + " | Accepted |\n"
            "| Connectors | conn/ | see below | Accepted |\n"
            "| Header | [sheet](conn/HDR.pdf) | " + "cd" * 32 + " | Accepted |\n")

PARAMS = """
[derating]
passive_size_min = "0603"
temperature_grade_min_c = 105

[[rails]]
name = "3V3"

[[parts]]
mpn = "REG100ABC"
alt = "REG100XYZ (second source)"
datasheet = "datasheets/power/REG100.pdf"
temp_grade_c = 125

[[parts]]
mpn = "OSC200"
datasheet = "datasheets/power/REG100.pdf"
temp_grade_c = 85

[[parts]]
mpn = "OSC300"
datasheet = "datasheets/power/REG100.pdf"
temp_grade_c = 85
temp_grade_exception = "indoor only"
"""

HEADER = "ref,value,footprint,mpn,datasheet,description,rating_note,fit\n"


def parse(rows: str):
    return cb.parse_bom(HEADER + rows)


def row(ref, value, footprint, mpn="", datasheet="", description="", note="", fit="") -> str:
    return f"{ref},{value},{footprint},{mpn},{datasheet},{description},{note},{fit}\n"


def params(extra: str = ""):
    return tomllib.loads(PARAMS + extra)


class ParserTests(unittest.TestCase):
    def test_size_codes(self):
        self.assertEqual(cb.size_of("C_0603_1608Metric"), "0603")
        self.assertEqual(cb.size_of("R_0402"), "0402")
        self.assertEqual(cb.size_of("C_1005Metric"), "0402")
        self.assertIsNone(cb.size_of("SOT-23"))
        self.assertIsNone(cb.size_of("QFN-48"))

    def test_capacitance_values(self):
        self.assertAlmostEqual(cb.capacitance_farads("100n 50V"), 1e-7)
        self.assertAlmostEqual(cb.capacitance_farads("4.7uF"), 4.7e-6)
        self.assertAlmostEqual(cb.capacitance_farads("4u7"), 4.7e-6)
        self.assertIsNone(cb.capacitance_farads("REG100"))

    def test_mpn_placeholders_and_value_fallback(self):
        comp = lambda ref, value, mpn="": {"ref": ref, "value": value, "footprint": "", "fields": {"MPN": mpn}}
        self.assertEqual(cb.component_mpn(comp("U1", "x", "REG100ABC")), "REG100ABC")
        self.assertIsNone(cb.component_mpn(comp("U1", "x", "pending")))
        self.assertEqual(cb.component_mpn(comp("U1", "REG100ABC")), "REG100ABC")
        self.assertIsNone(cb.component_mpn(comp("R1", "10k")))
        self.assertIsNone(cb.component_mpn(comp("C1", "100n 50V")))

    def test_bom_columns_are_case_insensitive_and_canonicalised(self):
        parts = cb.parse_bom("Ref,Value,Footprint,MPN,Datasheet\nU1,x,SOT-23,REG100ABC,a.pdf\n,skipped,x,,\n")
        self.assertEqual(len(parts), 1)
        self.assertEqual(parts[0]["fields"], {"MPN": "REG100ABC", "Datasheet": "a.pdf"})

    def test_bad_bom_is_an_error(self):
        with self.assertRaises(cb.ToolError):
            cb.parse_bom("ref,value\nU1,x\n")
        with self.assertRaises(cb.ToolError):
            cb.parse_bom("")
        with self.assertRaises(cb.ToolError):
            cb.parse_bom("ref,value,footprint\n")

    def test_manifest_keys_cover_paths_links_and_directories(self):
        keys = cb.manifest_keys(MANIFEST, "datasheets")
        self.assertEqual(keys, {"power/reg100.pdf", "conn/", "conn/hdr.pdf"})
        self.assertTrue(cb.datasheet_is_stored("datasheets/conn/ANY.pdf", keys, "datasheets"))
        self.assertTrue(cb.datasheet_is_stored("C:\\work\\datasheets\\power\\REG100.pdf", keys, "datasheets"))
        self.assertFalse(cb.datasheet_is_stored("datasheets/other/X.pdf", keys, "datasheets"))
        self.assertFalse(cb.datasheet_is_stored("pending", keys, "datasheets"))


class SizeTests(unittest.TestCase):
    def test_small_passives_fail_with_the_reference(self):
        comps = parse(row("R1", "10k", "R_0402_1005Metric") + row("C1", "100n", "C_0201_0603Metric") + row("R2", "1k", "R_0603_1608Metric"))
        findings = cb.check_passive_size(comps, {})
        self.assertEqual(len(of_level(findings, "FAIL")), 2)
        self.assertIn("R1", joined(of_level(findings, "FAIL")))
        self.assertNotIn("R2", joined(of_level(findings, "FAIL")))

    def test_large_unsized_and_diode_packages_pass(self):
        comps = parse(row("C1", "10u", "C_1206_3216Metric") + row("U1", "x", "SOT-23") + row("D1", "tvs", "D_SMA_0402"))
        self.assertEqual([f.level for f in cb.check_passive_size(comps, {})], ["PASS"])

    def test_minimum_is_a_parameter_and_validated(self):
        comps = parse(row("R1", "10k", "R_0603_1608Metric"))
        self.assertEqual(of_level(cb.check_passive_size(comps, {"passive_size_min": "0805"}), "FAIL")[0].check, "bom.passive_size")
        with self.assertRaises(cb.ToolError):
            cb.check_passive_size(comps, {"passive_size_min": "0099"})


class PowerCapTests(unittest.TestCase):
    def test_bulk_capacitor_below_the_power_size_warns(self):
        findings = cb.check_power_rail_capacitors(parse(row("C1", "10u 25V", "C_0603_1608Metric")), {}, {})
        self.assertIn("C1", joined(of_level(findings, "WARN")))

    def test_small_decoupling_with_a_rail_note_is_info_only(self):
        comps = parse(row("C1", "100n", "C_0603_1608Metric", note="3V3 decoupling") + row("C2", "100n", "C_0603_1608Metric"))
        findings = cb.check_power_rail_capacitors(comps, {}, params())
        self.assertEqual(of_level(findings, "WARN"), [])
        self.assertIn("1 rail-decoupling", joined(of_level(findings, "INFO")))

    def test_larger_sizes_and_polarised_parts_are_skipped_and_thresholds_are_parameters(self):
        comps = parse(row("C1", "10u", "C_0805_2012Metric") + row("C2", "47u", "CP_Elec_6.3x5.4"))
        self.assertEqual(cb.check_power_rail_capacitors(comps, {}, {}), [])
        two = parse(row("C1", "2.2u", "C_0603_1608Metric"))
        self.assertTrue(of_level(cb.check_power_rail_capacitors(two, {"bulk_capacitance_f": 1e-6}, {}), "WARN"))


class CapacitorTypeTests(unittest.TestCase):
    def fails(self, rows):
        return of_level(cb.check_capacitor_type(parse(rows)), "FAIL")

    def test_forbidden_dielectrics_and_chemistries_fail(self):
        for description in ("Y5V", "Z5U", "tantalum"):
            self.assertTrue(self.fails(row("C1", "1u", "C_0805", description=description)), description)

    def test_x5r_fails_only_in_power_paths(self):
        self.assertEqual(self.fails(row("C1", "100n", "C_0603", description="X5R")), [])
        self.assertTrue(self.fails(row("C1", "22u", "C_1206", description="X5R")))
        self.assertTrue(self.fails(row("C1", "10u", "C_0805", description="X5R")))

    def test_electrolytic_needs_polymer_or_hybrid(self):
        self.assertTrue(self.fails(row("C1", "100u", "CP_Elec_8x10", description="electrolytic")))
        self.assertEqual(self.fails(row("C1", "100u", "CP_Elec_8x10", description="polymer electrolytic")), [])

    def test_polarised_without_a_type_warns_and_missing_dielectric_is_counted(self):
        findings = cb.check_capacitor_type(parse(row("C1", "100u", "CP_Elec_8x10") + row("C2", "100n", "C_0603") + row("C3", "1u", "C_0603", description="X7R")))
        self.assertIn("C1", joined(of_level(findings, "WARN")))
        self.assertIn("1 capacitors without a stated dielectric", joined(of_level(findings, "INFO")))

    def test_unpolarised_description_is_not_polarised(self):
        findings = cb.check_capacitor_type(parse(row("C1", "100n", "C_0603", description="Unpolarized capacitor X7R")))
        self.assertEqual(of_level(findings, "WARN"), [])


class DatasheetTests(unittest.TestCase):
    stored = cb.manifest_keys(MANIFEST, "datasheets")

    def check(self, rows, extra=""):
        return cb.check_datasheets(parse(rows), params(extra), self.stored, "datasheets")

    def test_active_with_a_stored_datasheet_via_field_or_parts_list_passes(self):
        findings = self.check(row("U1", "x", "QFN", mpn="REG100ABC") + row("U2", "x", "QFN", mpn="XYZ9000", datasheet="datasheets/conn/XYZ.pdf"))
        self.assertEqual(of_level(findings, "FAIL"), [])
        self.assertIn("2 of 2 parts", joined(of_level(findings, "PASS")))

    def test_alt_part_number_in_the_parts_list_is_recognised(self):
        self.assertEqual(of_level(self.check(row("U1", "x", "QFN", mpn="REG100XYZ")), "FAIL"), [])

    def test_active_or_connector_without_a_datasheet_fails_others_warn(self):
        findings = self.check(row("U1", "x", "QFN", mpn="NOPE1234") + row("J1", "x", "THT", mpn="CONN5555") + row("D1", "x", "SOD", mpn="DIODE123"))
        self.assertEqual({f.message.split()[-2] for f in of_level(findings, "FAIL")}, {"U1", "J1"})
        self.assertIn("D1", joined(of_level(findings, "WARN")))

    def test_exempt_prefixes_generic_passives_and_pending_parts_are_summarised(self):
        findings = self.check(row("TP1", "tp", "TP") + row("H1", "hole", "MH") + row("R1", "10k", "R_0603") + row("C1", "100n 50V", "C_0603")
                              + row("U9", "pending", "QFN", mpn="pending"))
        self.assertEqual(of_level(findings, "FAIL"), [])
        info = joined(of_level(findings, "INFO"))
        self.assertIn("2 plain passives", info)
        self.assertIn("1 other components have no part number yet (U 1)", info)

    def test_value_field_can_carry_the_part_number(self):
        self.assertEqual(of_level(self.check(row("U1", "REG100ABC", "QFN")), "FAIL"), [])


class GradeTests(unittest.TestCase):
    def check(self, rows):
        return cb.check_temperature_grade(parse(rows), params(), {"temperature_grade_min_c": 105})

    def test_below_minimum_fails_unless_the_parts_row_has_an_exception(self):
        self.assertIn("OSC200", joined(of_level(self.check(row("Y1", "x", "XTAL", mpn="OSC200")), "FAIL")))
        excepted = self.check(row("Y1", "x", "XTAL", mpn="OSC300"))
        self.assertEqual(of_level(excepted, "FAIL"), [])
        self.assertIn("indoor only", joined(of_level(excepted, "WARN")))

    def test_meeting_the_minimum_passes_and_missing_grades_are_aggregated(self):
        findings = self.check(row("U1", "x", "QFN", mpn="REG100ABC") + row("U2", "x", "QFN", mpn="UNKNOWN99"))
        self.assertIn("all 1 graded", joined(of_level(findings, "PASS")))
        self.assertIn("1 U/Q/Y/L components have no temperature grade", joined(of_level(findings, "INFO")))

    def test_only_u_q_y_l_are_graded(self):
        self.assertEqual(of_level(self.check(row("D1", "x", "SOD", mpn="OSC200")), "FAIL"), [])

    def test_minimum_comes_from_the_parameters(self):
        comps = parse(row("U1", "x", "QFN", mpn="REG100ABC"))
        self.assertTrue(of_level(cb.check_temperature_grade(comps, params(), {"temperature_grade_min_c": 150}), "FAIL"))
        with self.assertRaises(cb.ToolError):
            cb.check_temperature_grade(comps, params(), {"temperature_grade_min_c": "hot"})


class DnpTests(unittest.TestCase):
    def test_dnp_markers_are_listed_as_info(self):
        comps = parse(row("R1", "10k DNP", "R_0603") + row("R2", "1k", "R_0603", fit="no") + row("R3", "1k", "R_0603", fit="yes")
                      + row("R4", "1k", "R_0603", note="fit optional"))
        refs = joined(cb.check_dnp(comps))
        for ref in ("R1", "R2", "R4"):
            self.assertIn(ref, refs)
        self.assertNotIn("R3", refs)

    def test_summary_counts_by_prefix(self):
        findings = cb.check_summary(parse(row("R1", "1k", "R") + row("R2", "1k", "R") + row("U1", "x", "Q")))
        self.assertIn("3 components: R 2, U 1", findings[0].message)


class CommandLineTests(TempDirTestCase):
    def setUp(self):
        super().setUp()
        self.write("datasheets/MANIFEST.md", MANIFEST)
        self.write("parameters.toml", PARAMS)
        self.args = ["--params", str(self.root / "parameters.toml"), "--manifest", str(self.root / "datasheets" / "MANIFEST.md")]

    def test_clean_bom_exits_0_and_a_failing_one_exits_1(self):
        good = self.write("good.csv", HEADER + row("U1", "x", "QFN", mpn="REG100ABC") + row("R1", "10k", "R_0603_1608Metric"))
        code, out = run_main(cb, ["--bom", str(good), *self.args])
        self.assertEqual(code, 0, out)
        bad = self.write("bad.csv", HEADER + row("R1", "10k", "R_0402_1005Metric"))
        self.assertEqual(run_main(cb, ["--bom", str(bad), *self.args])[0], 1)

    def test_unreadable_inputs_exit_2(self):
        good = self.write("good.csv", HEADER + row("R1", "10k", "R_0603_1608Metric"))
        self.assertEqual(run_main(cb, ["--bom", str(self.root / "none.csv"), *self.args])[0], 2)
        self.assertEqual(run_main(cb, ["--bom", str(good), "--params", str(self.root / "none.toml"),
                                       "--manifest", str(self.root / "datasheets" / "MANIFEST.md")])[0], 2)
        self.assertEqual(run_main(cb, ["--bom", str(good), "--params", str(self.root / "parameters.toml"),
                                       "--manifest", str(self.root / "nomanifest.md")])[0], 2)


if __name__ == "__main__":
    unittest.main()
