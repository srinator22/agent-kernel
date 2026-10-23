import unittest

from support import TempDirTestCase, joined, load_tool, of_level, run_main

cp = load_tool("check_parameters")

GOOD = """
[power.input_current]
value = 18.0
unit = "A"
min = 0.0
max = 20.0
source = "datasheets/psu.pdf#p3"
status = "datasheet"

[power.margin]
value = 1.25
unit = "x"
min = 1.0
max = 2.0
source = "D-002"
status = "decision"

[mechanical.edge]
value = "bottom"
allowed = ["top", "bottom"]
source = "D-002"
status = "decision"

[[rails.items]]
name = "logic"
value = 5.0
unit = "V"
min = 4.5
max = 5.5
source = "D-001"
status = "decision"
"""


class ParameterTests(TempDirTestCase):
    def setUp(self):
        super().setUp()
        self.write("datasheets/psu.pdf", b"x")

    def check(self, text=GOOD, **kwargs):
        import tomllib
        return cp.run(tomllib.loads(text), self.root, **kwargs)

    def test_good_file_passes_with_one_pass_per_parameter(self):
        findings = self.check()
        self.assertEqual(of_level(findings, "FAIL"), [])
        self.assertEqual(of_level(findings, "WARN"), [])
        self.assertEqual(len(of_level(findings, "PASS")), 4)
        self.assertIn("datasheet 1, decision 3", joined(of_level(findings, "INFO")))

    def test_names_come_from_the_path_and_array_row_names(self):
        names = [n for n, _ in cp.collect(__import__("tomllib").loads(GOOD))]
        self.assertEqual(sorted(names), ["mechanical.edge", "power.input_current", "power.margin", "rails.items[logic]"])

    def test_value_outside_bounds_fails_and_on_the_bound_passes(self):
        self.assertIn("outside [0, 20]", joined(of_level(self.check(GOOD.replace("18.0", "20.5")), "FAIL")))
        self.assertEqual(of_level(self.check(GOOD.replace("18.0", "20.0")), "FAIL"), [])

    def test_inverted_bounds_fail(self):
        self.assertIn("min 0 is above max", joined(of_level(self.check(GOOD.replace("max = 20.0", "max = -1.0")), "FAIL")))

    def test_missing_bounds_warn(self):
        text = GOOD.replace("min = 0.0\nmax = 20.0\n", "")
        findings = self.check(text)
        self.assertEqual(of_level(findings, "FAIL"), [])
        self.assertIn("min and max are not both recorded", joined(of_level(findings, "WARN")))

    def test_missing_unit_warns(self):
        findings = self.check(GOOD.replace('unit = "A"\n', ""))
        self.assertIn("no unit recorded", joined(of_level(findings, "WARN")))

    def test_invalid_status_fails(self):
        self.assertIn("status 'maybe'", joined(of_level(self.check(GOOD.replace('"datasheet"', '"maybe"')), "FAIL")))

    def test_datasheet_source_must_exist(self):
        text = GOOD.replace("datasheets/psu.pdf#p3", "datasheets/none.pdf")
        self.assertIn("does not exist", joined(of_level(self.check(text), "FAIL")))

    def test_datasheet_status_with_a_decision_source_fails(self):
        text = GOOD.replace("datasheets/psu.pdf#p3", "D-001")
        self.assertIn("is a decision", joined(of_level(self.check(text), "FAIL")))

    def test_decision_status_needs_a_decision_id_that_exists_when_a_log_is_given(self):
        self.assertIn("needs a D-NNN source", joined(of_level(self.check(GOOD.replace('source = "D-002"', 'source = "notes"', 1)), "FAIL")))
        findings = self.check(decisions={"D-001"})
        self.assertIn("D-002 is not in the decision log", joined(of_level(findings, "FAIL")))
        self.assertEqual(of_level(self.check(decisions={"D-001", "D-002"}), "FAIL"), [])

    def test_missing_source_fails(self):
        text = GOOD.replace('source = "D-001"\n', "")
        self.assertIn("no source recorded", joined(of_level(self.check(text), "FAIL")))

    def test_estimate_and_pending_status_never_give_a_plain_pass(self):
        findings = self.check(GOOD.replace('"datasheet"', '"estimate"'))
        self.assertEqual(of_level(findings, "FAIL"), [])
        self.assertIn("basis status: estimate", joined(of_level(findings, "WARN")))
        self.assertEqual(len(of_level(findings, "PASS")), 3)

    def test_pending_value_warns_and_needs_pending_status(self):
        text = '[a.x]\nvalue = "pending"\nstatus = "pending"\nsource = "to be chosen"\n'
        findings = self.check(text)
        self.assertEqual(of_level(findings, "FAIL"), [])
        self.assertIn("a.x: value is pending", joined(of_level(findings, "WARN")))
        bad = text.replace('status = "pending"', 'status = "decision"')
        self.assertIn("status is 'decision'", joined(of_level(self.check(bad), "FAIL")))

    def test_pending_value_without_source_is_only_a_warning_for_the_source(self):
        findings = self.check('[a.x]\nvalue = "pending"\nstatus = "pending"\n')
        self.assertEqual(of_level(findings, "FAIL"), [])

    def test_non_number_without_allowed_and_value_not_allowed_fail(self):
        self.assertIn("must be a number", joined(of_level(self.check('[a.x]\nvalue = "fast"\nstatus = "estimate"\nsource = "s"\n'), "FAIL")))
        self.assertIn("not in allowed", joined(of_level(self.check(GOOD.replace('value = "bottom"', 'value = "left"')), "FAIL")))
        self.assertIn("must be a number", joined(of_level(self.check('[a.x]\nvalue = true\nstatus = "estimate"\nsource = "s"\n'), "FAIL")))

    def test_duplicate_array_row_names_fail(self):
        row = '[[rails.items]]\nname = "logic"\nvalue = 5.0\nunit = "V"\nmin = 4\nmax = 6\nsource = "D-001"\nstatus = "decision"\n'
        self.assertIn("defined 2 times", joined(of_level(self.check(GOOD + row), "FAIL")))

    def test_required_table_and_empty_file(self):
        self.assertIn("[thermal] is missing", joined(of_level(self.check(require=["thermal"]), "FAIL")))
        self.assertIn("no parameter", joined(of_level(self.check("[a]\nb = 1\n"), "FAIL")))


class CommandLineTests(TempDirTestCase):
    def test_exit_codes(self):
        self.write("datasheets/psu.pdf", b"x")
        self.write("parameters.toml", GOOD)
        code, out = run_main(cp, ["--root", str(self.root)])
        self.assertEqual(code, 0, out)
        self.write("parameters.toml", GOOD.replace("18.0", "99"))
        code, out = run_main(cp, ["--root", str(self.root)])
        self.assertEqual(code, 1)
        self.assertIn("outside", out)
        self.assertEqual(run_main(cp, ["--root", str(self.root / "nope")])[0], 2)
        self.write("parameters.toml", "bad [[ toml")
        self.assertEqual(run_main(cp, ["--root", str(self.root)])[0], 2)

    def test_decision_log_option(self):
        self.write("datasheets/psu.pdf", b"x")
        self.write("parameters.toml", GOOD)
        self.write("DECISIONS.md", "## D-001 a\n\n## D-002 b\n")
        self.assertEqual(run_main(cp, ["--root", str(self.root), "--decisions", str(self.root / "DECISIONS.md")])[0], 0)
        self.assertEqual(run_main(cp, ["--root", str(self.root), "--decisions", str(self.root / "missing.md")])[0], 2)


if __name__ == "__main__":
    unittest.main()
