import unittest

from support import TempDirTestCase, joined, load_tool, of_level, run_main

cd = load_tool("check_decisions")


def section(number: int, status: str = "Accepted", extra: str = "") -> str:
    return (f"## D-{number:03d} Choose widget {number}\n\n"
            f"**Date:** 2030-01-0{number % 9 + 1}\n**Status:** {status}\n"
            f"**Decision:** Use widget {number}.\n**Rationale:** It fits. {extra}\n\n")


def table(rows: list[tuple[int, str]]) -> str:
    lines = ["| ID | Title | Status |", "|---|---|---|"]
    lines += [f"| D-{n:03d} | Choose widget {n} | {status} |" for n, status in rows]
    return "\n".join(lines) + "\n\n"


GOOD = table([(1, "Accepted"), (2, "Accepted")]) + section(1) + section(2)


class DecisionTextTests(unittest.TestCase):
    def fails(self, text):
        return of_level(cd.check_decisions_text(text), "FAIL")

    def test_consistent_log_passes(self):
        findings = cd.check_decisions_text(GOOD)
        self.assertEqual([f.level for f in findings], ["PASS"])

    def test_gap_in_section_ids_fails(self):
        text = table([(1, "Accepted"), (3, "Accepted")]) + section(1) + section(3)
        self.assertIn("expected D-002 but found D-003", joined(self.fails(text)))

    def test_duplicate_section_fails(self):
        text = table([(1, "Accepted")]) + section(1) + section(1)
        self.assertIn("appears more than once", joined(self.fails(text)))

    def test_missing_field_label_fails(self):
        text = table([(1, "Accepted")]) + section(1).replace("**Rationale:**", "Why:")
        self.assertIn("missing **Rationale:**", joined(self.fails(text)))

    def test_section_without_table_row_and_row_without_section_fail(self):
        text = table([(1, "Accepted"), (2, "Accepted")]) + section(1)
        self.assertIn("D-002 is in the summary table but has no section", joined(self.fails(text)))
        text = table([(1, "Accepted")]) + section(1) + section(2)
        self.assertIn("D-002 has a section but no row", joined(self.fails(text)))

    def test_invalid_status_fails(self):
        text = table([(1, "Maybe")]) + section(1, "Maybe")
        self.assertIn("is not Accepted, Proposed or Superseded", joined(self.fails(text)))

    def test_table_status_must_equal_section_status(self):
        text = table([(1, "Proposed")]) + section(1, "Accepted")
        self.assertIn("disagrees", joined(self.fails(text)))

    def test_superseded_by_a_missing_decision_fails(self):
        text = table([(1, "Superseded by D-009")]) + section(1, "Superseded by D-009")
        self.assertIn("D-009, which does not exist", joined(self.fails(text)))

    def test_supersession_pair_passes_and_target_must_be_marked(self):
        good = (table([(1, "Superseded by D-002"), (2, "Accepted")]) + section(1, "Superseded by D-002") +
                section(2, extra="Supersedes D-001."))
        self.assertEqual(self.fails(good), [])
        unmarked = (table([(1, "Accepted"), (2, "Accepted")]) + section(1) + section(2, extra="Supersedes D-001."))
        self.assertIn("D-001 is not marked 'Superseded by D-002'", joined(self.fails(unmarked)))

    def test_supersedes_a_decision_that_does_not_exist_fails(self):
        text = table([(1, "Accepted")]) + section(1, extra="Supersedes D-007.")
        self.assertIn("D-007, which does not exist", joined(self.fails(text)))

    def test_status_text_with_a_date_suffix_is_accepted(self):
        text = table([(1, "Accepted 2030-01-02")]) + section(1, "Accepted 2030-01-02")
        self.assertEqual(self.fails(text), [])

    def test_placeholders_fail(self):
        text = GOOD + "\nTBD later\n"
        self.assertIn("contains TBD", joined(self.fails(text)))


class QuestionTextTests(unittest.TestCase):
    def test_sequential_questions_pass(self):
        text = "| Q-01 | a | open |\n| Q-02 | b | closed |\n"
        self.assertEqual([f.level for f in cd.check_questions_text(text)], ["PASS"])

    def test_gap_and_duplicate_fail(self):
        gap = of_level(cd.check_questions_text("| Q-01 | a |\n| Q-03 | b |\n"), "FAIL")
        self.assertIn("expected Q-02", joined(gap))
        dup = of_level(cd.check_questions_text("| Q-01 | a |\n| Q-01 | b |\n"), "FAIL")
        self.assertIn("more than once", joined(dup))

    def test_ids_helpers(self):
        self.assertEqual(cd.decision_ids(GOOD), {"D-001", "D-002"})
        self.assertEqual(cd.question_ids("| Q-01 | a |\n| Q-12 | b |\n"), {"Q-01", "Q-12"})


class FileTests(TempDirTestCase):
    def test_run_and_exit_codes(self):
        self.write("DECISIONS.md", GOOD)
        self.write("OPEN_QUESTIONS.md", "| Q-01 | a | open |\n")
        code, out = run_main(cd, ["--root", str(self.root)])
        self.assertEqual(code, 0, out)
        self.write("OPEN_QUESTIONS.md", "| Q-02 | a | open |\n")
        self.assertEqual(run_main(cd, ["--root", str(self.root)])[0], 1)
        self.assertEqual(run_main(cd, ["--root", str(self.root), "--no-questions"])[0], 0)

    def test_missing_file_is_could_not_run(self):
        self.write("DECISIONS.md", GOOD)
        code, out = run_main(cd, ["--root", str(self.root)])
        self.assertEqual(code, 2)
        self.assertIn("could not run", out)


if __name__ == "__main__":
    unittest.main()
