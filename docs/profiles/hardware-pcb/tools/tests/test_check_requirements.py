import unittest

from support import TempDirTestCase, joined, load_tool, of_level, run_main

cr = load_tool("check_requirements")

REQ_HEAD = "| ID | Requirement | Source | Verification |\n|---|---|---|---|\n"
GOOD_REQ = (REQ_HEAD +
            "| PWR-01 | Input up to 20 A (D-001) | D-001 | measure at bench |\n"
            "| PWR-02 | Hold-up time | Q-01 | simulation |\n"
            "| SAF-01 | Stop chain | D-002 | fault model |\n")
DECISIONS = "## D-001 One\n\n## D-002 Two\n"
QUESTIONS = "| Q-01 | question | open |\n"


class RequirementTextTests(unittest.TestCase):
    def fails(self, text):
        return of_level(cr.check_requirements_text(text), "FAIL")

    def test_good_table_passes(self):
        findings = cr.check_requirements_text(GOOD_REQ)
        self.assertEqual([f.level for f in findings], ["PASS"])
        self.assertIn("3 requirements in 2 groups", findings[0].message)

    def test_duplicate_and_gap_fail(self):
        text = REQ_HEAD + "| PWR-01 | a | s | v |\n| PWR-01 | b | s | v |\n"
        self.assertIn("PWR-01 appears more than once", joined(self.fails(text)))
        text = REQ_HEAD + "| PWR-01 | a | s | v |\n| PWR-03 | b | s | v |\n"
        self.assertIn("not sequential", joined(self.fails(text)))

    def test_empty_source_or_verification_fails(self):
        text = REQ_HEAD + "| PWR-01 | a |  | v |\n| PWR-02 | b | s |  |\n"
        out = joined(self.fails(text))
        self.assertIn("PWR-01: Source cell is empty", out)
        self.assertIn("PWR-02: Verification cell is empty", out)

    def test_extra_pipe_in_text_does_not_shift_the_last_cells(self):
        text = REQ_HEAD + "| PWR-01 | a | b | s | v |\n"
        self.assertEqual(self.fails(text), [])

    def test_row_with_too_few_cells_fails(self):
        self.assertIn("fewer than four cells", joined(self.fails("| PWR-01 | only |\n")))

    def test_no_rows_fails(self):
        self.assertIn("no requirement rows", joined(self.fails("prose only\n")))


class ReferenceTests(unittest.TestCase):
    def test_unresolved_references_fail_and_name_the_document(self):
        texts = {"REQUIREMENTS.md": "see D-001 and Q-01", "ARCHITECTURE.md": "uses D-009 and Q-77"}
        findings = cr.check_references(texts, {"D-001"}, {"Q-01"})
        out = joined(of_level(findings, "FAIL"))
        self.assertIn("D-009 is referenced in ARCHITECTURE.md", out)
        self.assertIn("Q-77 is referenced in ARCHITECTURE.md", out)
        self.assertNotIn("D-001", out)

    def test_all_resolved_passes(self):
        findings = cr.check_references({"a.md": "D-001, Q-01"}, {"D-001"}, {"Q-01"})
        self.assertEqual([f.level for f in findings], ["PASS"])

    def test_embedded_ids_are_not_references(self):
        # "AD-001" and "D-0012" are other schemes, not decision references.
        findings = cr.check_references({"a.md": "AD-001 and D-0012 and TQ-05"}, set(), set())
        self.assertEqual([f.level for f in findings], ["PASS"])


class FileTests(TempDirTestCase):
    def setUp(self):
        super().setUp()
        self.write("REQUIREMENTS.md", GOOD_REQ)
        self.write("DECISIONS.md", DECISIONS)
        self.write("OPEN_QUESTIONS.md", QUESTIONS)

    def test_passes_without_the_optional_architecture_document(self):
        code, out = run_main(cr, ["--root", str(self.root)])
        self.assertEqual(code, 0, out)
        self.assertIn("not scanned: ARCHITECTURE.md", out)

    def test_dangling_reference_in_architecture_fails(self):
        self.write("ARCHITECTURE.md", "relies on D-005\n")
        code, out = run_main(cr, ["--root", str(self.root)])
        self.assertEqual(code, 1)
        self.assertIn("D-005", out)

    def test_named_document_must_exist(self):
        code, out = run_main(cr, ["--root", str(self.root), "--doc", str(self.root / "missing.md")])
        self.assertEqual(code, 2)
        self.assertIn("could not run", out)

    def test_extra_documents_are_scanned(self):
        extra = self.write("NOTES.md", "Q-50 unresolved\n")
        code, out = run_main(cr, ["--root", str(self.root), "--doc", str(extra)])
        self.assertEqual(code, 1)
        self.assertIn("Q-50", out)


if __name__ == "__main__":
    unittest.main()
