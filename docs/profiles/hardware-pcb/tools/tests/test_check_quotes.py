import importlib.util
import json
import sys
import unittest
from pathlib import Path
from unittest import mock

from support import TempDirTestCase, joined, load_tool, of_level, run_main

cq = load_tool("check_quotes")

PAGES = [
    "Page one text.\nThe regulator input range is 4.5 V to 28 V.",
    "Page two text.\nOutput current is limited to 3.5 A.",
    "Page three text.\nThe switching frequency is 570 kHz.",
]


def parse(text: str):
    return cq.parse_citations(text, Path("note.md"))


def fake_pages(pages=PAGES):
    return mock.patch.object(cq, "extract_pdf_pages", lambda path: list(pages))


class ParseTests(unittest.TestCase):
    def test_page_forms(self):
        text = ('"alpha one" [datasheets/a.pdf p.12]\n'
                '"beta two" [datasheets/a.pdf, p. 13]\n'
                '"gamma three" [datasheets/a.pdf page 14]\n'
                '"delta four" [notes/source.txt]\n')
        got = [(c.quote, c.source, c.page, c.line) for c in parse(text)]
        self.assertEqual(got, [
            ("alpha one", "datasheets/a.pdf", 12, 1),
            ("beta two", "datasheets/a.pdf", 13, 2),
            ("gamma three", "datasheets/a.pdf", 14, 3),
            ("delta four", "notes/source.txt", None, 4),
        ])

    def test_fenced_code_is_ignored(self):
        text = '```\n"in a fence" [a.pdf p.1]\n```\n"outside" [b.pdf p.2]\n'
        self.assertEqual([c.quote for c in parse(text)], ["outside"])

    def test_tilde_fence_and_longer_fence_are_ignored(self):
        text = '~~~\n"tilde" [a.pdf]\n~~~\n````\n"four" [a.pdf]\n```\n"still inside" [a.pdf]\n````\n"after" [a.pdf]\n'
        self.assertEqual([c.quote for c in parse(text)], ["after"])

    def test_inline_code_is_ignored(self):
        text = 'Use `"in code" [a.pdf p.1]` but "in prose" [b.pdf p.2].\n'
        self.assertEqual([c.quote for c in parse(text)], ["in prose"])

    def test_unquoted_brackets_are_ignored(self):
        self.assertEqual(parse("See [datasheets/a.pdf p.3] for details.\n"), [])

    def test_quote_without_citation_is_ignored(self):
        self.assertEqual(parse('He wrote "just a phrase" and moved on. [see below]\n'), [])

    def test_bracket_without_file_suffix_is_ignored(self):
        self.assertEqual(parse('"a phrase" [TODO]\n'), [])

    def test_two_citations_on_one_line(self):
        text = '"first quote" [a.pdf p.1] and also "second quote" [b.pdf page 2]\n'
        got = [(c.quote, c.source, c.page) for c in parse(text)]
        self.assertEqual(got, [("first quote", "a.pdf", 1), ("second quote", "b.pdf", 2)])

    def test_stray_quote_before_a_citation(self):
        got = [c.quote for c in parse('He said "foo" and "bar baz" [a.txt]\n')]
        self.assertEqual(got, ["bar baz"])

    def test_curly_quotes_are_not_citations(self):
        self.assertEqual(parse("\u201cfancy quote\u201d [a.pdf p.1]\n"), [])


class NormaliseTests(unittest.TestCase):
    def test_case_space_punctuation_and_hyphenation(self):
        self.assertEqual(cq.normalise("Regu-\nlator,  INPUT"), cq.normalise("regulator input"))

    def test_nfkc_folds_ligatures_and_wide_forms(self):
        self.assertEqual(cq.normalise("\ufb01lter \uff13.\uff15 A"), "filter35a")


class TextSourceTests(TempDirTestCase):
    def findings(self, note: str):
        self.write("note.md", note)
        return cq.run([self.root / "note.md"], self.root)

    def test_match_ignoring_whitespace_case_and_punctuation(self):
        self.write("notes/source.txt", "The  OUTPUT\tcurrent\u00a0is limited -- to 3.5 A,\nmaximum.\n")
        found = self.findings('"output current is limited to 3.5 A" [notes/source.txt]\n')
        self.assertEqual([f.level for f in found], ["PASS"])
        self.assertEqual(found[0].location, "note.md:1")

    def test_hyphenated_line_break_in_source(self):
        self.write("notes/source.txt", "The internal regu-\nlator supplies the core.\n")
        found = self.findings('"internal regulator supplies" [notes/source.txt]\n')
        self.assertEqual([f.level for f in found], ["PASS"])

    def test_curly_punctuation_in_source(self):
        self.write("notes/source.txt", "\u201cOutput current\u201d is limited to 3.5\u00a0A.\n")
        found = self.findings('"Output current is limited to 3.5 A" [notes/source.txt]\n')
        self.assertEqual([f.level for f in found], ["PASS"])

    def test_mismatch_fails(self):
        self.write("notes/source.txt", "Output current is limited to 3.5 A.\n")
        found = self.findings('"Output current is limited to 5 A" [notes/source.txt]\n')
        self.assertEqual([f.level for f in found], ["FAIL"])
        self.assertIn("not found", found[0].message)

    def test_long_quote_is_shortened_in_messages(self):
        self.write("notes/source.txt", "nothing relevant\n")
        found = self.findings('"' + "word " * 40 + '" [notes/source.txt]\n')
        self.assertLess(len(found[0].message), 140)

    def test_missing_source_fails(self):
        found = self.findings('"anything here" [notes/absent.txt]\n')
        self.assertEqual([f.level for f in found], ["FAIL"])
        self.assertIn("cited source does not exist", found[0].message)

    def test_resolution_relative_to_citing_file_first(self):
        self.write("sub/source.txt", "sub folder version says alpha\n")
        self.write("source.txt", "root version says beta\n")
        self.write("sub/note.md", '"sub folder version says alpha" [source.txt]\n')
        found = cq.run([self.root / "sub" / "note.md"], self.root)
        self.assertEqual([f.level for f in found], ["PASS"])

    def test_resolution_falls_back_to_root(self):
        self.write("datasheets/source.txt", "only in the root datasheets folder\n")
        self.write("sub/note.md", '"only in the root datasheets folder" [datasheets/source.txt]\n')
        found = cq.run([self.root / "sub" / "note.md"], self.root)
        self.assertEqual([f.level for f in found], ["PASS"])
        self.assertEqual(found[0].location, "sub/note.md:1")

    def test_text_source_with_page_gives_info(self):
        self.write("notes/source.txt", "Output current is limited to 3.5 A.\n")
        found = self.findings('"Output current is limited" [notes/source.txt p.4]\n')
        self.assertEqual([f.level for f in found], ["PASS", "INFO"])
        self.assertIn("not checked", found[1].message)

    def test_unknown_binary_is_unchecked(self):
        self.write("datasheets/limits.xlsx", b"PK\x03\x04binary")
        found = self.findings('"some quoted cell" [datasheets/limits.xlsx]\n')
        self.assertEqual([f.level for f in found], ["UNCHECKED"])
        self.assertIn("cannot extract text from .xlsx", found[0].message)

    def test_nul_bytes_mark_an_unknown_suffix_binary(self):
        self.write("datasheets/blob.dat", b"abc\x00def")
        found = self.findings('"abc def" [datasheets/blob.dat]\n')
        self.assertEqual([f.level for f in found], ["UNCHECKED"])

    def test_quote_without_letters_or_digits_is_unchecked(self):
        self.write("notes/source.txt", "anything\n")
        found = self.findings('"---" [notes/source.txt]\n')
        self.assertEqual([f.level for f in found], ["UNCHECKED"])


class PdfTests(TempDirTestCase):
    def setUp(self):
        super().setUp()
        self.write("datasheets/part.pdf", b"%PDF-1.4 placeholder")

    def findings(self, note: str, pages=PAGES):
        self.write("note.md", note)
        with fake_pages(pages):
            return cq.run([self.root / "note.md"], self.root)

    def test_cited_page_match_passes(self):
        found = self.findings('"Output current is limited to 3.5 A" [datasheets/part.pdf p.2]\n')
        self.assertEqual([f.level for f in found], ["PASS"])
        self.assertIn("page 2", found[0].message)

    def test_wrong_page_fails_naming_both_pages(self):
        found = self.findings('"Output current is limited to 3.5 A" [datasheets/part.pdf p.3]\n')
        self.assertEqual([f.level for f in found], ["FAIL"])
        self.assertIn("found on page 2, cited page 3", found[0].message)

    def test_not_on_any_page_fails(self):
        found = self.findings('"Output current is limited to 9 A" [datasheets/part.pdf p.2]\n')
        self.assertEqual([f.level for f in found], ["FAIL"])
        self.assertIn("not found", found[0].message)

    def test_page_beyond_count_fails(self):
        found = self.findings('"Output current is limited to 3.5 A" [datasheets/part.pdf p.40]\n')
        self.assertEqual([f.level for f in found], ["FAIL"])
        self.assertIn("40", found[0].message)
        self.assertIn("3 pages", found[0].message)

    def test_page_zero_fails(self):
        found = self.findings('"Output current is limited to 3.5 A" [datasheets/part.pdf p.0]\n')
        self.assertEqual([f.level for f in found], ["FAIL"])

    def test_no_page_cited_passes_with_warn(self):
        found = self.findings('"switching frequency is 570 kHz" [datasheets/part.pdf]\n')
        self.assertEqual([f.level for f in found], ["PASS", "WARN"])
        self.assertIn("cite the page", found[1].message)
        self.assertIn("page 3", found[1].message)

    def test_no_page_cited_and_not_found_fails(self):
        found = self.findings('"switching frequency is 999 kHz" [datasheets/part.pdf]\n')
        self.assertEqual([f.level for f in found], ["FAIL"])

    def test_hyphenation_across_pdf_line_break(self):
        found = self.findings('"regulator input range" [datasheets/part.pdf p.1]\n',
                              pages=["The regu-\nlator input range is wide.", "two"])
        self.assertEqual([f.level for f in found], ["PASS"])

    def test_pdf_without_text_layer_is_unchecked(self):
        found = self.findings('"anything at all" [datasheets/part.pdf p.1]\n', pages=["", "  \n"])
        self.assertEqual([f.level for f in found], ["UNCHECKED"])

    def test_pages_are_extracted_once_per_file(self):
        self.write("note.md", '"page one text" [datasheets/part.pdf p.1]\n"page two text" [datasheets/part.pdf p.2]\n')
        calls = []

        def counting(path):
            calls.append(path)
            return list(PAGES)

        with mock.patch.object(cq, "extract_pdf_pages", counting):
            found = cq.run([self.root / "note.md"], self.root)
        self.assertEqual([f.level for f in found], ["PASS", "PASS"])
        self.assertEqual(len(calls), 1)

    def test_pymupdf_missing_is_unchecked(self):
        self.write("note.md", '"Output current is limited" [datasheets/part.pdf p.2]\n')
        with mock.patch.dict(sys.modules, {"pymupdf": None, "fitz": None}):
            found = cq.run([self.root / "note.md"], self.root)
        self.assertEqual([f.level for f in found], ["UNCHECKED"])
        self.assertIn("pymupdf is not installed", found[0].message)

    def test_pymupdf_missing_gives_exit_2(self):
        self.write("note.md", '"Output current is limited" [datasheets/part.pdf p.2]\n')
        with mock.patch.dict(sys.modules, {"pymupdf": None, "fitz": None}):
            code, out = run_main(cq, [str(self.root / "note.md"), "--root", str(self.root)])
        self.assertEqual(code, 2)
        self.assertIn("UNCHECKED", out)


@unittest.skipUnless(importlib.util.find_spec("pymupdf"), "pymupdf not installed")
class RealPdfTests(TempDirTestCase):
    def setUp(self):
        super().setUp()
        import pymupdf
        document = pymupdf.open()
        document.new_page().insert_text((72, 100), "Output current is limited to 3.5 A")
        document.new_page().insert_text((72, 100), "Switching frequency is 570 kHz")
        path = self.root / "datasheets" / "part.pdf"
        path.parent.mkdir()
        document.save(str(path))
        document.close()

    def run_note(self, note: str):
        self.write("note.md", note)
        return cq.run([self.root / "note.md"], self.root)

    def test_extracts_pages(self):
        pages = cq.extract_pdf_pages(self.root / "datasheets" / "part.pdf")
        self.assertEqual(len(pages), 2)
        self.assertIn("570 kHz", pages[1])

    def test_right_and_wrong_page(self):
        good = self.run_note('"limited to 3.5 A" [datasheets/part.pdf p.1]\n')
        self.assertEqual([f.level for f in good], ["PASS"])
        bad = self.run_note('"limited to 3.5 A" [datasheets/part.pdf p.2]\n')
        self.assertEqual([f.level for f in bad], ["FAIL"])
        self.assertIn("found on page 1, cited page 2", bad[0].message)

    def test_damaged_pdf_is_unchecked(self):
        self.write("datasheets/broken.pdf", b"this is not a pdf")
        found = self.run_note('"anything here" [datasheets/broken.pdf p.1]\n')
        self.assertEqual([f.level for f in found], ["UNCHECKED"])


class MainTests(TempDirTestCase):
    def main(self, *args):
        return run_main(cq, [*args, "--root", str(self.root)])

    def test_no_citations_exits_0(self):
        self.write("note.md", 'Plain prose with "a phrase" but no citation.\n')
        code, out = self.main(str(self.root / "note.md"))
        self.assertEqual(code, 0)
        self.assertIn("no cited quotes found", out)

    def test_default_path_is_root(self):
        self.write("a/note.md", '"known text" [src.txt]\n')
        self.write("a/src.txt", "this is known text\n")
        code, out = self.main()
        self.assertEqual(code, 0)
        self.assertIn("PASS", out)

    def test_fail_exits_1(self):
        self.write("note.md", '"made up" [src.txt]\n')
        self.write("src.txt", "real content\n")
        code, out = self.main(str(self.root / "note.md"))
        self.assertEqual(code, 1)
        self.assertIn("FAIL", out)
        self.assertIn("note.md:1", out)

    def test_unchecked_exits_2(self):
        self.write("note.md", '"cell text" [limits.xlsx]\n')
        self.write("limits.xlsx", b"PK\x03\x04")
        code, out = self.main(str(self.root / "note.md"))
        self.assertEqual(code, 2)
        self.assertIn("UNCHECKED", out)

    def test_fail_beats_unchecked(self):
        self.write("note.md", '"cell text" [limits.xlsx]\n"made up" [src.txt]\n')
        self.write("limits.xlsx", b"PK\x03\x04")
        self.write("src.txt", "real content\n")
        code, out = self.main(str(self.root / "note.md"))
        self.assertEqual(code, 1)
        self.assertIn("PASS: 0  WARN: 0  FAIL: 1  INFO: 0  UNCHECKED: 1", out)

    def test_json_output_parses(self):
        self.write("note.md", '"known text" [src.txt]\n"made up" [src.txt]\n')
        self.write("src.txt", "this is known text\n")
        code, out = self.main(str(self.root / "note.md"), "--json")
        data = json.loads(out)
        self.assertEqual(code, 1)
        self.assertEqual(data["counts"]["PASS"], 1)
        self.assertEqual(data["counts"]["FAIL"], 1)
        self.assertEqual({f["level"] for f in data["findings"]}, {"PASS", "FAIL"})
        self.assertEqual(data["findings"][0]["location"], "note.md:1")

    def test_unreadable_input_path_exits_2(self):
        code, out = self.main(str(self.root / "missing.md"))
        self.assertEqual(code, 2)
        self.assertIn("could not run", out)

    def test_root_that_is_not_a_folder_exits_2(self):
        code, out = run_main(cq, ["--root", str(self.root / "nope")])
        self.assertEqual(code, 2)
        self.assertIn("could not run", out)

    def test_folder_scan_is_recursive_and_skips_noise(self):
        self.write("src.txt", "real content here\n")
        self.write("docs/deep/note.md", '"real content here" [src.txt]\n')
        self.write(".git/note.md", '"fabricated in git" [src.txt]\n')
        self.write("node_modules/pkg/note.md", '"fabricated in modules" [src.txt]\n')
        self.write(".venv/note.md", '"fabricated in venv" [src.txt]\n')
        self.write("docs/ignored.txt", '"fabricated in txt" [src.txt]\n')
        found = cq.run([self.root], self.root)
        self.assertEqual([f.level for f in found], ["PASS"])
        self.assertNotIn("fabricated", joined(found))
        self.assertEqual(found[0].location, "docs/deep/note.md:1")

    def test_help_exits_cleanly(self):
        with self.assertRaises(SystemExit) as raised:
            run_main(cq, ["--help"])
        self.assertEqual(raised.exception.code, 0)

    def test_counts_helper_agrees_with_levels(self):
        self.write("note.md", '"known text" [src.txt p.3]\n')
        self.write("src.txt", "this is known text\n")
        found = cq.run([self.root / "note.md"], self.root)
        self.assertEqual(len(of_level(found, "INFO")), 1)


if __name__ == "__main__":
    unittest.main()
