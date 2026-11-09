#!/usr/bin/env python3
"""Regression tests for tools/import_raw.py.

Everything runs in a temporary folder with inline fixtures; no network, no clock.
"""

from __future__ import annotations

import contextlib
import hashlib
import io
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import import_raw as ir  # noqa: E402

META = ["--date", "2026-01-02", "--condition", "cold", "--version", "v1.2", "--load", "none"]


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


class ImportRawTests(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.root = Path(self._tmp.name)
        self.session = self.root / "session"
        self.src = self.root / "src"
        self.src.mkdir()

    def source(self, name: str, data: bytes = b"a,b\r\n1,2\r\n") -> Path:
        path = self.src / name
        path.write_bytes(data)
        return path

    def run_tool(self, *sources: Path, meta=META):
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            try:
                code = ir.main(["--session", str(self.session), *meta, *map(str, sources)])
            except SystemExit as stop:  # argparse reports a usage error this way
                code = stop.code
        return code, out.getvalue() + err.getvalue()

    def test_imports_unchanged_and_records_a_readme_row(self):
        data = b"a,b\r\n1,2\r\n\x00\xff"
        code, out = self.run_tool(self.source("run1.csv", data), self.source("run2.csv", b"x"))
        self.assertEqual(code, 0, out)
        self.assertEqual((self.session / "raw" / "run1.csv").read_bytes(), data)
        readme = (self.session / "README.md").read_text(encoding="utf-8")
        self.assertIn(f"| raw/run1.csv | {sha(data)} | {len(data)} | 2026-01-02 | cold | v1.2 | none |", readme)
        self.assertIn(f"| raw/run2.csv | {sha(b'x')} | 1 |", readme)

    def test_unknown_metadata_is_written_as_unknown(self):
        code, out = self.run_tool(self.source("a.csv"), meta=["--date", "2026-01-02"])
        self.assertEqual(code, 0, out)
        row = next(line for line in (self.session / "README.md").read_text(encoding="utf-8").splitlines() if "raw/a.csv" in line)
        self.assertEqual(row.count("Unknown"), 3)

    def test_existing_destination_is_refused_and_nothing_is_imported(self):
        first = self.source("a.csv", b"one")
        self.assertEqual(self.run_tool(first)[0], 0)
        other = self.source("b.csv", b"two")
        replacement = self.src / "sub"
        replacement.mkdir()
        clash = replacement / "a.csv"
        clash.write_bytes(b"different")
        code, out = self.run_tool(other, clash)
        self.assertEqual(code, 2, out)
        self.assertIn("already exists", out)
        self.assertEqual((self.session / "raw" / "a.csv").read_bytes(), b"one")
        self.assertFalse((self.session / "raw" / "b.csv").exists())

    def test_two_sources_with_one_name_are_refused(self):
        sub = self.src / "sub"
        sub.mkdir()
        (sub / "a.csv").write_bytes(b"2")
        code, out = self.run_tool(self.source("a.csv"), sub / "a.csv")
        self.assertEqual(code, 2, out)
        self.assertFalse((self.session / "raw").exists())

    def test_missing_source_is_a_read_error(self):
        code, out = self.run_tool(self.src / "nope.csv")
        self.assertEqual(code, 1, out)
        self.assertIn("nope.csv", out)
        self.assertFalse((self.session / "raw").exists())

    def test_hash_mismatch_removes_the_bad_copy_and_records_no_row(self):
        src = self.source("a.csv", b"payload")
        real = ir.sha256_file
        calls = []

        def flaky(path):
            calls.append(path)
            return real(path) if len(calls) == 1 else "0" * 64

        with mock.patch.object(ir, "sha256_file", flaky):
            code, out = self.run_tool(src)
        self.assertEqual(code, 1, out)
        self.assertIn("hash mismatch", out)
        self.assertFalse((self.session / "raw" / "a.csv").exists())
        self.assertFalse((self.session / "README.md").exists())
        self.assertEqual(src.read_bytes(), b"payload")

    def test_rows_are_added_under_an_existing_table_and_notes_are_kept(self):
        self.session.mkdir()
        (self.session / "README.md").write_text(
            "# Session\n\nnotes\n\n" + ir.HEADER + "\n" + ir.SEPARATOR + "\n| raw/old.csv | " + "ab" * 32
            + " | 3 | d | c | v | l |\n\n## Limitations\n\nnone\n", encoding="utf-8")
        self.assertEqual(self.run_tool(self.source("new.csv"))[0], 0)
        lines = (self.session / "README.md").read_text(encoding="utf-8").splitlines()
        old, new = (next(i for i, line in enumerate(lines) if f"raw/{n}.csv" in line) for n in ("old", "new"))
        self.assertEqual(new, old + 1)
        self.assertIn("## Limitations", lines)

    def test_empty_source_list_and_bad_date_are_usage_errors(self):
        self.assertEqual(self.run_tool()[0], 2)
        self.assertEqual(self.run_tool(self.source("a.csv"), meta=["--date", "02/01/2026"])[0], 2)


if __name__ == "__main__":
    unittest.main()
