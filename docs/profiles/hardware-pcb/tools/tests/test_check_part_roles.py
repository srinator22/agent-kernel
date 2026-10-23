import tomllib
import unittest

from support import TempDirTestCase, joined, load_tool, of_level, run_main

pr = load_tool("check_part_roles")

HEADER = "ref,value,footprint,mpn\n"


def bom(*rows: tuple) -> list[dict]:
    return pr.parse_bom(HEADER + "".join(f"{r},{v},FP,{m}\n" for r, v, m in rows))


def parts(text: str) -> dict:
    return tomllib.loads(text)


class NormaliserTests(unittest.TestCase):
    def test_trailing_space_case_and_punctuation_are_ignored(self):
        self.assertEqual(pr.normalise_mpn("  reg-100abc "), "REG100ABC")

    def test_comma_packaging_code_and_pbf_suffix_are_dropped(self):
        self.assertEqual(pr.normalise_mpn("PART-B200,215"), "PARTB200")
        self.assertEqual(pr.normalise_mpn("PART-A100#PBF"), "PARTA100")

    def test_reel_suffix_is_dropped_but_other_suffixes_are_kept(self):
        self.assertEqual(pr.normalise_mpn("PART-C300R"), "PARTC300")
        self.assertEqual(pr.normalise_mpn("PART-B200-Q1"), "PARTB200Q1")

    def test_parenthetical_commentary_is_not_a_token(self):
        self.assertEqual(pr.free_text_tokens("PART-A100 (second source PART-Z999)"), {"PARTA100"})

    def test_placeholders_name_no_part(self):
        for value in ("pending", "TBD", "", "n/a", "-"):
            self.assertEqual(pr.expected_tokens({"mpn": value}), [], value)


class RoleTests(unittest.TestCase):
    def test_role_with_its_mpn_on_the_bom_passes(self):
        findings = pr.check(bom(("U1", "x", "REG100ABC")), parts('[[parts]]\nref = "U_REG"\nmpn = "REG100ABC"\n'))
        self.assertEqual([f.level for f in findings], ["PASS"])

    def test_mpn_may_be_in_the_value_field_with_a_packaging_difference(self):
        findings = pr.check(bom(("U1", "REG100ABCR", "")), parts('[[parts]]\nref = "U_REG"\nmpn = "REG100ABC"\n'))
        self.assertEqual(of_level(findings, "FAIL"), [])

    def test_role_mpn_absent_fails_with_the_role_and_mpn(self):
        findings = pr.check(bom(("U1", "x", "OTHER777")), parts('[[parts]]\nref = "U_REG"\nmpn = "REG100ABC"\n'))
        self.assertIn("role U_REG names MPN REG100ABC but no component carries it", joined(of_level(findings, "FAIL")))

    def test_multi_variant_mpn_needs_only_one_variant(self):
        findings = pr.check(bom(("U1", "x", "REG100B")), parts('[[parts]]\nref = "U_REG"\nmpn = "REG100A / REG100B"\n'))
        self.assertEqual(of_level(findings, "FAIL"), [])

    def test_alt_fitted_is_a_warn_not_a_fail(self):
        findings = pr.check(bom(("U1", "x", "REG100XYZ")), parts('[[parts]]\nref = "U_REG"\nmpn = "REG100ABC"\nalt = "REG100XYZ (second source)"\n'))
        self.assertEqual(of_level(findings, "FAIL"), [])
        self.assertIn("alternative fitted on U1", joined(of_level(findings, "WARN")))

    def test_pending_row_is_info_and_not_checked(self):
        findings = pr.check(bom(("U1", "x", "REG100ABC")), parts('[[parts]]\nref = "U_NEW"\nmpn = "pending"\n[[parts]]\nref = "U_REG"\nmpn = "REG100ABC"\n'))
        self.assertIn("1 parameters roles name no MPN yet and are not checked: U_NEW", joined(of_level(findings, "INFO")))
        self.assertEqual(of_level(findings, "FAIL"), [])

    def test_repeated_row_is_reported_once(self):
        row = '[[parts]]\nref = "U_REG"\nmpn = "NOTHERE123"\n'
        findings = pr.check(bom(("U1", "x", "REG100ABC")), parts(row + row))
        self.assertEqual(len(of_level(findings, "FAIL")), 1)

    def test_bom_only_row_is_info_not_fail(self):
        findings = pr.check(bom(("U1", "x", "REG100ABC")), parts('[[parts]]\nref = "F_BLADE"\nmpn = "BLADE5A"\nnot_a_symbol = "added at assembly"\n'))
        self.assertEqual(of_level(findings, "FAIL"), [])
        self.assertIn("added at assembly", joined(of_level(findings, "INFO")))

    def test_role_names_with_digits_are_not_taken_as_designators(self):
        findings = pr.check(bom(("Q1", "x", "PART-B200")), parts('[[parts]]\nref = "Q_SW_1"\nmpn = "PART-B200"\n'))
        self.assertEqual(of_level(findings, "FAIL"), [])


class DesignatorTests(unittest.TestCase):
    ROW = '[[parts]]\nref = "J5, J6"\nmpn = "CONN5555"\nalt = "CONN5556"\n'

    def test_listed_designators_carrying_the_mpn_pass(self):
        findings = pr.check(bom(("J5", "x", "CONN5555"), ("J6", "x", "CONN5555")), parts(self.ROW))
        self.assertEqual(of_level(findings, "FAIL"), [])

    def test_different_mpn_fails_showing_both_and_missing_designator_fails(self):
        findings = pr.check(bom(("J5", "x", "WRONG999")), parts(self.ROW))
        out = joined(of_level(findings, "FAIL"))
        self.assertIn("J5 carries WRONG999", out)
        self.assertIn("the BOM has no component J6", out)

    def test_alt_on_a_designator_is_a_warn(self):
        findings = pr.check(bom(("J5", "x", "CONN5555"), ("J6", "x", "CONN5556")), parts(self.ROW))
        self.assertEqual(of_level(findings, "FAIL"), [])
        self.assertIn("J6", joined(of_level(findings, "WARN")))


class UnlistedTests(unittest.TestCase):
    def test_unknown_mpn_warns_once_with_all_designators(self):
        findings = pr.check(bom(("U1", "x", "MYSTERY42"), ("U2", "x", "MYSTERY42")), parts('[[parts]]\nref = "U_X"\nmpn = "OTHER100"\n'))
        warns = of_level(findings, "WARN")
        self.assertIn("MPN MYSTERY42 on U1, U2 (2 parts)", joined(warns))

    def test_part_named_in_mpn_or_alt_is_not_unlisted(self):
        findings = pr.check(bom(("U1", "x", "REG100XYZ")), parts('[[parts]]\nref = "U_REG"\nmpn = "REG100ABC"\nalt = "REG100XYZ"\n'))
        self.assertEqual([f for f in findings if f.check == "part_roles.unlisted"], [])

    def test_passives_are_aggregated_as_info_not_warn(self):
        findings = pr.check(bom(("R1", "10k", "RES12345"), ("C1", "1u", "CAP12345")), parts('[[parts]]\nref = "U_X"\nmpn = "pending"\n'))
        self.assertEqual(of_level(findings, "WARN"), [])
        self.assertIn("2 passives, test points and mechanical parts carry 2 MPNs", joined(of_level(findings, "INFO")))

    def test_placeholder_mpn_is_ignored(self):
        findings = pr.check(bom(("U1", "x", "pending")), parts('[[parts]]\nref = "U_X"\nmpn = "pending"\n'))
        self.assertEqual(of_level(findings, "WARN"), [])


class CommandLineTests(TempDirTestCase):
    def test_exit_codes(self):
        params = self.write("parameters.toml", '[[parts]]\nref = "U_REG"\nmpn = "REG100ABC"\n')
        good = self.write("good.csv", HEADER + "U1,x,FP,REG100ABC\n")
        bad = self.write("bad.csv", HEADER + "U1,x,FP,OTHER555\n")
        self.assertEqual(run_main(pr, ["--bom", str(good), "--params", str(params)])[0], 0)
        code, out = run_main(pr, ["--bom", str(bad), "--params", str(params)])
        self.assertEqual(code, 1)
        self.assertIn("no component carries it", out)
        self.assertEqual(run_main(pr, ["--bom", str(self.root / "none.csv"), "--params", str(params)])[0], 2)
        self.assertEqual(run_main(pr, ["--bom", str(good), "--params", str(self.root / "none.toml")])[0], 2)
        broken = self.write("broken.csv", "ref,value\nU1,x\n")
        self.assertEqual(run_main(pr, ["--bom", str(broken), "--params", str(params)])[0], 2)


if __name__ == "__main__":
    unittest.main()
