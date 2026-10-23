import unittest

from support import TempDirTestCase, joined, load_tool, of_level, run_main

ds = load_tool("check_doc_sync")

SYNC = """
[doc_sync]
docs = ["ARCH.md", "NOTES.md"]
hole_words = ["mounting hole"]
known_keys = ["tooling_holes_mm"]

[[doc_sync.superseded]]
term = "widget-A"
by = "D-001"
note = "widget-B replaced it"

[[doc_sync.superseded]]
term = "legacy bus"
by = "D-002"
note = "use the main bus"
allow = "kept as a fallback"
"""

PARAMS = {"floorplan": {
    "mechanism_holes_mm": [[10, 20], [10, 90.5]],
    "tooling_holes_mm": [[3, 3]],
    "connector_wall_edge": "bottom",
}}


class DocSyncTests(TempDirTestCase):
    def setUp(self):
        super().setUp()
        self.write("doc_sync.toml", SYNC)
        self.write("ARCH.md", "# Architecture\nThe board uses widget-B.\n")
        self.write("NOTES.md", "Notes.\n")

    def run_check(self, params=PARAMS, **kwargs):
        return ds.run(self.root, params=params, **kwargs)

    def test_clean_documents_pass(self):
        findings = self.run_check()
        self.assertEqual(of_level(findings, "FAIL"), [])
        self.assertEqual(len(of_level(findings, "PASS")), 2)

    def test_stale_term_fails_with_file_line_and_superseding_decision(self):
        self.write("ARCH.md", "ok\nThe board uses widget-A today.\n")
        out = joined(of_level(self.run_check(), "FAIL"))
        self.assertIn("ARCH.md:2", out)
        self.assertIn("superseded by D-001", out)

    def test_history_word_excuses_the_line(self):
        self.write("ARCH.md", "widget-A was rejected in favour of widget-B.\nformerly widget-A.\n")
        self.assertEqual(of_level(self.run_check(), "FAIL"), [])

    def test_term_allow_pattern_excuses_only_that_term(self):
        self.write("ARCH.md", "legacy bus kept as a fallback.\nwidget-A kept as a fallback.\n")
        fails = of_level(self.run_check(), "FAIL")
        self.assertEqual(len(fails), 1)
        self.assertIn("widget-A", fails[0].message)

    def test_hole_coordinates_must_match_the_parameters(self):
        self.write("ARCH.md", "mounting hole at (10, 20)\nmounting hole at (10, 90.5) and (3, 3)\n")
        self.assertEqual(of_level(self.run_check(), "FAIL"), [])
        self.write("ARCH.md", "mounting hole at (11, 20)\nunrelated point (99, 99)\n")
        fails = of_level(self.run_check(), "FAIL")
        self.assertEqual(len(fails), 1)
        self.assertIn("(11, 20)", fails[0].message)

    def test_hole_line_with_history_word_is_ignored(self):
        self.write("ARCH.md", "mounting hole formerly at (11, 20)\n")
        self.assertEqual(of_level(self.run_check(), "FAIL"), [])

    def test_connector_edge_stale_statement_fails(self):
        self.write("ARCH.md", "The connector wall is on the top edge.\n")
        self.assertIn("described on the top edge", joined(of_level(self.run_check(), "FAIL")))
        self.write("ARCH.md", "The connector wall is on the bottom edge.\n")
        self.assertEqual(of_level(self.run_check(), "FAIL"), [])

    def test_edge_patterns_can_be_overridden(self):
        self.write("doc_sync.toml", SYNC + '\n[doc_sync.edge_patterns]\ntop = "north side"\n')
        self.write("ARCH.md", "The connector wall is on the north side.\n")
        self.assertTrue(of_level(self.run_check(), "FAIL"))

    def test_missing_listed_document_warns(self):
        self.write("doc_sync.toml", SYNC.replace('"NOTES.md"', '"GONE.md"'))
        findings = self.run_check()
        self.assertIn("GONE.md", joined(of_level(findings, "WARN")))
        self.assertEqual(of_level(findings, "FAIL"), [])

    def test_without_parameters_hole_and_edge_checks_are_skipped_with_info(self):
        self.write("ARCH.md", "mounting hole at (1, 2)\nconnector wall on the top edge\n")
        findings = self.run_check(params={})
        self.assertEqual(of_level(findings, "FAIL"), [])
        self.assertIn("skipped", joined(of_level(findings, "INFO")))

    def test_dash_typography_fails_and_can_be_disabled(self):
        self.write("NOTES.md", "a " + chr(0x2014) + " b\n")
        self.assertIn("NOTES.md (1)", joined(of_level(self.run_check(), "FAIL")))
        self.assertEqual(of_level(self.run_check(typography=False), "FAIL"), [])

    def test_dash_in_a_skipped_folder_is_ignored(self):
        self.write("third_party/x.md", "a " + chr(0x2013) + " b\n")
        self.write("doc_sync.toml", SYNC + '\n')
        self.write("vendor/y.md", "a " + chr(0x2013) + " b\n")
        self.assertTrue(of_level(self.run_check(), "FAIL"))
        self.write("doc_sync.toml", SYNC.replace("[doc_sync]\n", '[doc_sync]\ntypography_skip = ["third_party", "vendor"]\n'))
        self.assertEqual(of_level(self.run_check(), "FAIL"), [])

    def test_long_failure_lists_are_capped(self):
        self.write("ARCH.md", "\n".join("widget-A line" for _ in range(20)) + "\n")
        fails = of_level(self.run_check(), "FAIL")
        self.assertEqual(len(fails), ds.SHOW_MAX + 1)
        self.assertIn("8 more stale statements", fails[-1].message)

    def test_bad_sync_file_is_an_error(self):
        self.write("doc_sync.toml", "[doc_sync]\n")
        with self.assertRaises(ds.ToolError):
            self.run_check()
        self.write("doc_sync.toml", "not toml [[")
        with self.assertRaises(ds.ToolError):
            self.run_check()
        self.write("doc_sync.toml", '[doc_sync]\ndocs=["ARCH.md"]\n[[doc_sync.superseded]]\nterm="("\n')
        with self.assertRaises(ds.ToolError):
            self.run_check()


class CommandLineTests(TempDirTestCase):
    def test_exit_codes(self):
        self.write("doc_sync.toml", SYNC)
        self.write("ARCH.md", "fine\n")
        self.write("NOTES.md", "fine\n")
        self.write("parameters.toml", '[floorplan]\nmechanism_holes_mm = [[1, 2]]\nconnector_wall_edge = "left"\n')
        self.assertEqual(run_main(ds, ["--root", str(self.root)])[0], 0)
        self.write("NOTES.md", "widget-A again\n")
        code, out = run_main(ds, ["--root", str(self.root)])
        self.assertEqual(code, 1)
        self.assertIn("NOTES.md:1", out)
        self.assertEqual(run_main(ds, ["--root", str(self.root), "--sync", str(self.root / "none.toml")])[0], 2)

    def test_parameters_file_is_found_by_default_name(self):
        self.write("doc_sync.toml", SYNC)
        self.write("ARCH.md", "mounting hole (5, 5)\n")
        self.write("NOTES.md", "x\n")
        self.write("parameters.toml", '[floorplan]\nmechanism_holes_mm = [[1, 2]]\n')
        code, out = run_main(ds, ["--root", str(self.root)])
        self.assertEqual(code, 1)
        self.assertIn("(5, 5)", out)


if __name__ == "__main__":
    unittest.main()
