import hashlib
import unittest

from support import TempDirTestCase, joined, load_tool, of_level, run_main

cm = load_tool("check_manifest")

HEADER = ("| Subsystem | Part | Document | File | Revision | Source | SHA-256 | Status |\n"
          "|---|---|---|---|---|---|---|---|\n")


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def row(file_cell: str, digest: str, status: str = "Accepted") -> str:
    return f"| power | Widget | Datasheet | {file_cell} | v1 | example | {digest} | {status} |\n"


class ParseTests(unittest.TestCase):
    def test_plain_paths_and_columns(self):
        found, rows = cm.parse_manifest("# Title\n\n" + HEADER + row("power/A.pdf", "ab" * 32))
        self.assertTrue(found)
        self.assertEqual(len(rows), 1)
        self.assertEqual((rows[0].path, rows[0].sha256, rows[0].status), ("power/A.pdf", "ab" * 32, "Accepted"))

    def test_markdown_link_and_backticks(self):
        _, rows = cm.parse_manifest(HEADER + row("[Datasheet](power/A.pdf)", "ab" * 32) + row("`power/B.pdf`", "cd" * 32))
        self.assertEqual([r.path for r in rows], ["power/A.pdf", "power/B.pdf"])

    def test_dash_means_no_path(self):
        _, rows = cm.parse_manifest(HEADER + row("-", "-", "NOT RETRIEVED - timeout"))
        self.assertIsNone(rows[0].path)

    def test_second_table_with_bare_names(self):
        text = (HEADER + row("motor/", "see below") +
                "\n| File | Pages | SHA-256 |\n|---|---|---|\n| Top.pdf | 1 | " + "cd" * 32 + " |\n")
        _, rows = cm.parse_manifest(text)
        self.assertEqual([r.path for r in rows], ["motor/", "Top.pdf"])

    def test_text_without_a_manifest_table(self):
        found, rows = cm.parse_manifest("prose\n| a | b |\n|---|---|\n| 1 | 2 |\n")
        self.assertFalse(found)
        self.assertEqual(rows, [])


class VerificationTests(TempDirTestCase):
    def setUp(self):
        super().setUp()
        (self.root / "datasheets").mkdir()

    def manifest(self, text):
        self.write("datasheets/MANIFEST.md", text)

    def findings(self, params=None, **kwargs):
        return cm.run(params or {}, self.root, **kwargs)

    def test_consistent_manifest_passes(self):
        self.write("datasheets/power/A.pdf", b"hello")
        self.manifest(HEADER + row("power/A.pdf", sha(b"hello")))
        findings = self.findings()
        self.assertEqual(of_level(findings, "FAIL"), [])
        self.assertEqual(len(of_level(findings, "PASS")), 1)

    def test_unlisted_pdf_and_xlsx_fail(self):
        self.write("datasheets/power/A.pdf", b"x")
        self.write("datasheets/bom/B.xlsx", b"x")
        self.manifest(HEADER)
        text = joined(of_level(self.findings(), "FAIL"))
        self.assertIn("unlisted file: power/A.pdf", text)
        self.assertIn("unlisted file: bom/B.xlsx", text)

    def test_other_suffixes_need_no_row_unless_asked(self):
        self.write("datasheets/notes.txt", b"x")
        self.manifest(HEADER)
        self.assertEqual(of_level(self.findings(), "FAIL"), [])
        self.assertTrue(of_level(self.findings(suffixes=(".txt",)), "FAIL"))

    def test_listed_but_missing_file_fails(self):
        self.manifest(HEADER + row("power/GONE.pdf", "ab" * 32))
        self.assertIn("GONE.pdf", joined(of_level(self.findings(), "FAIL")))

    def test_not_retrieved_row_only_warns(self):
        self.manifest(HEADER + row("-", "-", "NOT RETRIEVED - timeout"))
        findings = self.findings()
        self.assertEqual(of_level(findings, "FAIL"), [])
        self.assertTrue(of_level(findings, "WARN"))

    def test_row_without_path_and_status_fails(self):
        self.manifest(HEADER + row("-", "-", "Accepted"))
        self.assertTrue(of_level(self.findings(), "FAIL"))

    def test_hash_mismatch_fails_and_is_case_insensitive_when_equal(self):
        self.write("datasheets/A.pdf", b"data")
        self.manifest(HEADER + row("A.pdf", "0" * 64))
        self.assertIn("does not match", joined(of_level(self.findings(), "FAIL")))
        self.manifest(HEADER + row("A.pdf", sha(b"data").upper()))
        self.assertEqual(of_level(self.findings(), "FAIL"), [])

    def test_missing_hash_warns(self):
        self.write("datasheets/B.xlsx", b"data")
        self.manifest(HEADER + row("B.xlsx", "-"))
        findings = self.findings()
        self.assertEqual(of_level(findings, "FAIL"), [])
        self.assertIn("no SHA-256", joined(of_level(findings, "WARN")))

    def test_directory_row_covers_files_below_and_second_table_hashes_them(self):
        self.write("datasheets/motor/Top.pdf", b"layer")
        self.write("datasheets/motor/Bottom.pdf", b"layer2")
        manifest = (HEADER + row("motor/", "see per-file table") +
                    f"\n| File | SHA-256 |\n|---|---|\n| Top.pdf | {sha(b'layer')} |\n")
        self.manifest(manifest)
        self.assertEqual(of_level(self.findings(), "FAIL"), [])

    def test_ambiguous_bare_name_fails(self):
        self.write("datasheets/a/Top.pdf", b"1")
        self.write("datasheets/b/Top.pdf", b"2")
        self.manifest(HEADER + row("Top.pdf", "ab" * 32))
        self.assertIn("ambiguous", joined(of_level(self.findings(), "FAIL")))

    def test_missing_directory_row_fails(self):
        self.manifest(HEADER + row("nothere/", "-"))
        self.assertIn("does not exist", joined(of_level(self.findings(), "FAIL")))

    def test_no_manifest_table_fails_and_missing_manifest_is_an_error(self):
        self.manifest("# nothing here\n")
        self.assertIn("no manifest table", joined(of_level(self.findings(), "FAIL")))
        (self.root / "datasheets" / "MANIFEST.md").unlink()
        with self.assertRaises(cm.ToolError):
            self.findings()

    def test_part_datasheet_cross_check(self):
        self.write("datasheets/A.pdf", b"data")
        self.write("datasheets/C.pdf", b"other")
        self.manifest(HEADER + row("A.pdf", sha(b"data")) + row("C.pdf", sha(b"other")))
        params = {"parts": [
            {"ref": "U1", "datasheet": "datasheets/A.pdf"},
            {"ref": "U2", "datasheet": "datasheets/none.pdf"},
            {"ref": "U3", "datasheet": "pending"},
            {"ref": "U4", "datasheet": "NOT RETRIEVED"},
        ]}
        findings = self.findings(params)
        self.assertEqual(len(of_level(findings, "FAIL")), 1)
        self.assertIn("U2", joined(of_level(findings, "FAIL")))

    def test_part_datasheet_present_but_unlisted_warns(self):
        self.write("datasheets/A.pdf", b"data")
        self.write("datasheets/notes.txt", b"data")
        self.manifest(HEADER + row("A.pdf", sha(b"data")))
        params = {"parts": [{"ref": "U1", "datasheet": "datasheets/notes.txt"}]}
        self.assertIn("not listed", joined(of_level(self.findings(params), "WARN")))

    def test_capture_scan_is_opt_in_and_honours_the_allow_list(self):
        self.write("datasheets/page.html", b"<html></html>")
        self.write("knowledge/saved.html", b"<html></html>")
        self.manifest(HEADER)
        self.assertEqual(of_level(self.findings(), "WARN"), [])
        warned = of_level(self.findings(check_captures=True, capture_allow=[("datasheets/ok/", False)]), "WARN")
        self.assertIn("datasheets/page.html", joined(warned))
        allowed = self.findings(check_captures=True, capture_allow=[("datasheets/", True)])
        self.assertEqual(of_level(allowed, "WARN"), [])


class CommandLineTests(TempDirTestCase):
    def test_exit_codes(self):
        (self.root / "datasheets").mkdir()
        self.write("datasheets/A.pdf", b"data")
        self.write("datasheets/MANIFEST.md", HEADER + row("A.pdf", sha(b"data")))
        code, out = run_main(cm, ["--root", str(self.root)])
        self.assertEqual(code, 0)
        self.assertIn("PASS", out)
        self.write("datasheets/MANIFEST.md", HEADER)
        self.assertEqual(run_main(cm, ["--root", str(self.root)])[0], 1)
        self.assertEqual(run_main(cm, ["--root", str(self.root / "nowhere")])[0], 2)

    def test_json_output_and_help(self):
        (self.root / "datasheets").mkdir()
        self.write("datasheets/MANIFEST.md", HEADER)
        code, out = run_main(cm, ["--root", str(self.root), "--json"])
        self.assertEqual(code, 0)
        self.assertIn('"counts"', out)
        with self.assertRaises(SystemExit) as raised:
            run_main(cm, ["--help"])
        self.assertEqual(raised.exception.code, 0)


if __name__ == "__main__":
    unittest.main()
