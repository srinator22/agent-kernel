"""Tests for kb_index.py on a tiny synthetic tree (Markdown and text only, so no optional library is needed).

Run: python -I -m unittest discover -s docs/library/tools/tests
"""
import io
import sqlite3
import subprocess
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from unittest import mock

TOOLS = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(TOOLS))
import kb_index  # noqa: E402


def fts5_available():
    connection = sqlite3.connect(":memory:")
    try:
        connection.execute("CREATE VIRTUAL TABLE t USING fts5(x)")
        return True
    except sqlite3.OperationalError:
        return False
    finally:
        connection.close()


def cli(*argv):
    out, err = io.StringIO(), io.StringIO()
    with redirect_stdout(out), redirect_stderr(err):
        code = kb_index.main(list(argv))
    return code, out.getvalue(), err.getvalue()


class SplitAndQuery(unittest.TestCase):
    def test_split_markdown_sections_and_fences(self):
        text = "# Title\nintro\n## One\nbody one\n```\n## not a heading\n```\n## Two\n\n## Three\nlast\n"
        rows = kb_index.split_markdown(text, "fallback")
        self.assertEqual([r[1] for r in rows], ["Title", "One", "Three"])
        self.assertEqual([r[0] for r in rows], [1, 2, 3])
        self.assertIn("## not a heading", rows[1][2])

    def test_match_expression(self):
        f = kb_index.build_match_expression
        self.assertEqual(f("fuse rating"), '"fuse" AND "rating"')
        self.assertEqual(f('"4.2 A" OR pin*'), '"4 2 A" OR "pin"*')
        self.assertEqual(f("SOME_SETTING"), '"SOME SETTING"')
        self.assertEqual(f("OR OR"), "")
        self.assertEqual(f("!!! ???"), "")

    def test_phrase_expression_only_for_plain_multiword(self):
        self.assertEqual(kb_index.build_phrase_expression("fuse rating"), '"fuse rating"')
        self.assertIsNone(kb_index.build_phrase_expression("fuse"))
        self.assertIsNone(kb_index.build_phrase_expression('"fuse rating"'))
        self.assertIsNone(kb_index.build_phrase_expression("a OR b"))


@unittest.skipUnless(fts5_available(), "this Python's sqlite3 has no FTS5")
class BuildAndSearch(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.write("README.md", "# Project\nOverview text.\n## Power\nThe input fuse is rated 7.5 A slow blow.\n")
        self.write("notes/other.md", "# Other\n## Cooling\nFan curve notes and airflow.\n")
        self.write("knowledge/memo.txt", "Plain memo about connector keying.\n")
        self.write("node_modules/skip.md", "# Skip\nshould never be indexed fuse\n")
        self.write(".hidden/skip.md", "# Skip\nhidden fuse\n")
        self.write("datasheets/sheet.pdf", "not really a pdf")

    def write(self, rel, text):
        p = self.root / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(text, encoding="utf-8")

    def build(self, *extra):
        return cli("build", "--root", str(self.root), *extra)

    def test_help(self):
        done = subprocess.run([sys.executable, "-I", str(TOOLS / "kb_index.py"), "--help"], text=True,
                              capture_output=True)
        self.assertEqual(done.returncode, 0)
        self.assertIn("build", done.stdout)

    def test_build_then_search_finds_section_with_path(self):
        with mock.patch.object(kb_index, "pymupdf_available", return_value=False):
            code, out, err = self.build()
        self.assertEqual(code, 0, out + err)
        self.assertIn("datasheets/sheet.pdf: pymupdf is not installed", out)
        code, out, err = cli("search", "--root", str(self.root), "fuse rated")
        self.assertEqual(code, 0, err)
        self.assertIn("README.md  sec 2  [doc]", out)
        self.assertNotIn("node_modules", out)
        self.assertNotIn(".hidden", out)

    def test_kind_and_file_filters(self):
        with mock.patch.object(kb_index, "pymupdf_available", return_value=False):
            self.build()
        _, out, _ = cli("search", "--root", str(self.root), "connector", "--kind", "knowledge")
        self.assertIn("knowledge/memo.txt", out)
        _, out, _ = cli("search", "--root", str(self.root), "connector", "--kind", "doc")
        self.assertIn("no matches", out)
        _, out, _ = cli("search", "--root", str(self.root), "fan", "--file", "notes/")
        self.assertIn("notes/other.md", out)

    def test_incremental_build_and_removal(self):
        with mock.patch.object(kb_index, "pymupdf_available", return_value=False):
            self.build()
            code, out, _ = self.build()
            self.assertIn("Indexed 0 file(s)", out)
            self.assertIn("Unchanged (skipped): 3", out)
            (self.root / "notes" / "other.md").unlink()
            self.write("README.md", "# Project\n## Power\nNow a ten amp fuse.\n")
            code, out, _ = self.build()
        self.assertIn("removed: notes/other.md", out)
        self.assertIn("Indexed 1 file(s)", out)
        _, out, _ = cli("search", "--root", str(self.root), "airflow")
        self.assertIn("no matches", out)
        _, out, _ = cli("search", "--root", str(self.root), "ten amp")
        self.assertIn("README.md", out)

    def test_require_pdf_without_library_exits_2(self):
        with mock.patch.object(kb_index, "pymupdf_available", return_value=False):
            code, out, err = self.build("--require-pdf")
        self.assertEqual(code, 2)
        self.assertIn("--require-pdf", err)

    def test_corrupt_pdf_with_library_reports_error_and_exits_1(self):
        class Boom:
            @staticmethod
            def open(*_):
                raise ValueError("bad pdf")
        with mock.patch.object(kb_index, "pymupdf_available", return_value=True), \
                mock.patch.dict(sys.modules, {"pymupdf": Boom}):
            code, out, _ = self.build()
        self.assertEqual(code, 1)
        self.assertIn("ERROR: datasheets/sheet.pdf: ValueError: bad pdf", out)

    def build_with_fake_pdf(self, available, *extra, extractor=None):
        """Build with a stub PDF extractor (the file's text is its single page) instead of pymupdf."""
        def fake_pdf(source):
            return kb_index.Extracted([(1, source.path.stem, source.path.read_text(encoding="utf-8"))], 1)
        with mock.patch.object(kb_index, "pymupdf_available", return_value=available), \
                mock.patch.dict(kb_index.EXTRACTORS, {"pdf": extractor or fake_pdf}):
            return self.build(*extra)

    def search_text(self, query):
        _, out, _ = cli("search", "--root", str(self.root), query)
        return out

    def index_old_pdf_then_change_it(self):
        self.write("datasheets/sheet.pdf", "Old limit obsoletevalue forty volts.\n")
        code, out, err = self.build_with_fake_pdf(True)
        self.assertEqual(code, 0, out + err)
        self.assertIn("datasheets/sheet.pdf", self.search_text("obsoletevalue"))
        self.write("datasheets/sheet.pdf", "New limit currentvalue sixty volts.\n")

    def test_changed_pdf_without_library_drops_stale_rows(self):
        self.index_old_pdf_then_change_it()
        code, out, err = self.build_with_fake_pdf(False)
        self.assertEqual(code, 0, out + err)
        self.assertIn("no matches", self.search_text("obsoletevalue"))
        self.assertIn("STALE DROPPED: datasheets/sheet.pdf: changed since it was indexed and pymupdf is not installed",
                      out)
        # The digest went too, so the next build with the library indexes the new text.
        code, out, err = self.build_with_fake_pdf(True)
        self.assertEqual(code, 0, out + err)
        self.assertIn("datasheets/sheet.pdf", self.search_text("currentvalue"))

    def test_changed_pdf_with_require_pdf_exits_2_and_drops_stale_rows(self):
        self.index_old_pdf_then_change_it()
        code, out, err = self.build_with_fake_pdf(False, "--require-pdf")
        self.assertEqual(code, 2, out + err)
        self.assertIn("no matches", self.search_text("obsoletevalue"))
        self.assertIn("--require-pdf", err)
        self.assertIn("1 stale indexed PDF(s) were removed", err)

    def test_changed_pdf_that_fails_extraction_drops_stale_rows(self):
        self.index_old_pdf_then_change_it()

        def broken(_source):
            raise ValueError("bad pdf")
        code, out, err = self.build_with_fake_pdf(True, extractor=broken)
        self.assertEqual(code, 1, out + err)
        self.assertIn("ERROR: datasheets/sheet.pdf: ValueError: bad pdf", out)
        self.assertIn("no matches", self.search_text("obsoletevalue"))

    def test_deleted_pdf_is_removed_without_library(self):
        self.index_old_pdf_then_change_it()
        (self.root / "datasheets" / "sheet.pdf").unlink()
        code, out, err = self.build_with_fake_pdf(False)
        self.assertEqual(code, 0, out + err)
        self.assertIn("removed: datasheets/sheet.pdf", out)
        self.assertIn("no matches", self.search_text("obsoletevalue"))

    def test_search_without_index_exits_2(self):
        code, _, err = cli("search", "--root", str(self.root), "fuse")
        self.assertEqual(code, 2)
        self.assertIn("no index", err)

    def test_query_without_words_exits_2(self):
        with mock.patch.object(kb_index, "pymupdf_available", return_value=False):
            self.build()
        code, _, err = cli("search", "--root", str(self.root), "!!!")
        self.assertEqual(code, 2)
        self.assertIn("no searchable words", err)

    def test_rebuild_and_custom_doc_dir(self):
        self.write("manuals/guide.txt", "Torque values for the terminal block.\n")
        with mock.patch.object(kb_index, "pymupdf_available", return_value=False):
            self.build("--rebuild", "--doc-dir", "manuals")
        _, out, _ = cli("search", "--root", str(self.root), "terminal block", "--kind", "manuals")
        self.assertIn("manuals/guide.txt", out)
        _, out, _ = cli("search", "--root", str(self.root), "connector keying")
        self.assertIn("no matches", out)  # knowledge/ is no longer a doc-dir

    def test_exclude_prefix(self):
        with mock.patch.object(kb_index, "pymupdf_available", return_value=False):
            self.build("--exclude", "notes/")
        _, out, _ = cli("search", "--root", str(self.root), "airflow")
        self.assertIn("no matches", out)


if __name__ == "__main__":
    unittest.main()
