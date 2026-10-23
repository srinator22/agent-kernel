"""Tests for check_defect_memory.py on inline fixtures in the template's column layout.

Run: python -I -m unittest discover -s docs/library/tools/tests
"""
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

TOOL = Path(__file__).resolve().parent.parent / "check_defect_memory.py"
REPO_TEMPLATE = Path(__file__).resolve().parents[4] / "docs" / "DEFECT_MEMORY.md"

HEAD = ("# Defect memory\n\n## Table format\n\n"
        "| ID | Symptom and discovery route | Root cause | Permanent defence | Status |\n"
        "|---|---|---|---|---|\n\n## Rows\n\nIntro.\n\n"
        "| ID | Symptom and discovery route | Root cause | Permanent defence | Status |\n"
        "|---|---|---|---|---|\n")
GOOD = ("| M-001 | s | c | `tools/x.py` test | fixed (abc1234) |\n"
        "| M-002 | s | c | d | open |\n"
        "| I-001 | s | c | d | accepted (rare, owner A) |\n"
        "| W-001 | s | c | d | fixed (0123abcd), superseded by W-002 |\n"
        "| W-002 | s | c | d | open |\n")


def run(text, *args, files=()):
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        (root / "docs").mkdir()
        for name in files:
            (root / name).parent.mkdir(parents=True, exist_ok=True)
            (root / name).write_text("x", encoding="utf-8")
        (root / "docs" / "DEFECT_MEMORY.md").write_text(text, encoding="utf-8")
        done = subprocess.run([sys.executable, "-I", str(TOOL), "--root", str(root), *args], text=True,
                              capture_output=True, check=False)
    return done.returncode, done.stdout + done.stderr


class DefectMemoryChecker(unittest.TestCase):
    def test_help(self):
        done = subprocess.run([sys.executable, "-I", str(TOOL), "--help"], text=True, capture_output=True)
        self.assertEqual(done.returncode, 0)

    def test_good_table_passes(self):
        code, out = run(HEAD + GOOD, files=["tools/x.py"])
        self.assertEqual(code, 0, out)
        self.assertIn("PASS (5 row(s)", out)

    def test_missing_file_could_not_run(self):
        with tempfile.TemporaryDirectory() as d:
            done = subprocess.run([sys.executable, "-I", str(TOOL), "--root", d], text=True,
                                  capture_output=True, check=False)
        self.assertEqual(done.returncode, 2)

    def test_no_table_could_not_run(self):
        code, out = run("# Defect memory\n\nNo table here.\n")
        self.assertEqual(code, 2, out)

    def test_format_example_in_prose_is_not_judged(self):
        code, out = run(HEAD + "| M-001 | s | c | d | open |\n")
        self.assertEqual(code, 0, out)

    def test_wrong_header(self):
        code, out = run("## Rows\n\n| ID | What | Why |\n|---|---|---|\n| M-001 | a | b |\n")
        self.assertEqual(code, 1)
        self.assertIn("header", out)

    def test_gap_in_sequence(self):
        code, out = run(HEAD + "| M-001 | s | c | d | open |\n| M-003 | s | c | d | open |\n")
        self.assertEqual(code, 1)
        self.assertIn("expected M-002", out)

    def test_duplicate_id(self):
        code, out = run(HEAD + "| M-001 | s | c | d | open |\n| M-001 | s | c | d | open |\n")
        self.assertEqual(code, 1)
        self.assertIn("used twice", out)

    def test_empty_cell_and_wrong_cell_count(self):
        code, out = run(HEAD + "| M-001 | s |  | d | open |\n| M-002 | s | c | open |\n")
        self.assertEqual(code, 1)
        self.assertIn("empty cell 'root cause'", out)
        self.assertIn("4 cells, expected 5", out)

    def test_bad_id_and_bad_status(self):
        code, out = run(HEAD + "| X-001 | s | c | d | open |\n| M-001 | s | c | d | done |\n")
        self.assertEqual(code, 1)
        self.assertIn("id must look like", out)
        self.assertIn("status 'done'", out)

    def test_fixed_without_commit_and_accepted_without_reason(self):
        code, out = run(HEAD + "| M-001 | s | c | d | fixed |\n| M-002 | s | c | d | accepted |\n")
        self.assertEqual(code, 1)
        self.assertIn("must name the commit", out)
        self.assertIn("must give the reason", out)

    def test_superseded_target_must_exist(self):
        code, out = run(HEAD + "| M-001 | s | c | d | open, superseded by M-009 |\n")
        self.assertEqual(code, 1)
        self.assertIn("M-009, which is not a row", out)

    def test_fixed_defence_path_must_exist_unless_switched_off(self):
        text = HEAD + "| M-001 | s | c | `tests/test_gone.py` | fixed (abc1234) |\n"
        code, out = run(text)
        self.assertEqual(code, 1)
        self.assertIn("tests/test_gone.py, which does not exist", out)
        self.assertEqual(run(text, "--no-path-check")[0], 0)
        self.assertEqual(run(text, files=["tests/test_gone.py"])[0], 0)

    def test_examples_skipped_but_can_be_forbidden(self):
        text = HEAD + "| M-000 EXAMPLE | s | c | d | fixed (abc1234) |\n"
        self.assertEqual(run(text)[0], 0)
        code, out = run(text, "--no-examples")
        self.assertEqual(code, 1)
        self.assertIn("placeholder row", out)

    def test_pipe_escape_in_cell(self):
        code, out = run(HEAD + "| M-001 | a \\| b | c | d | open |\n")
        self.assertEqual(code, 0, out)

    @unittest.skipUnless(REPO_TEMPLATE.is_file(), "template DEFECT_MEMORY.md not found")
    def test_shipped_template_file_passes(self):
        done = subprocess.run([sys.executable, "-I", str(TOOL), "--file", str(REPO_TEMPLATE),
                               "--root", str(REPO_TEMPLATE.parent.parent)], text=True, capture_output=True,
                              check=False)
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)


if __name__ == "__main__":
    unittest.main()
