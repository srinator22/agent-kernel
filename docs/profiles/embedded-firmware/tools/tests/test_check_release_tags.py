#!/usr/bin/env python3
"""Regression tests for tools/check_release_tags.py.

Rules run against a throwaway git repository built in a temporary folder, with
the user's global and system git configuration masked out. Fixtures are inline.
"""

from __future__ import annotations

import contextlib
import hashlib
import io
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import check_release_tags as crt  # noqa: E402

PREFIX = "fw-"
VERSION_FILE = "VERSION"
CHANGELOG = "CHANGELOG.md"
CODE_FILE = "src/app.ino"
CODE_PATTERN = r'CODE_VERSION\s*=\s*"app v{version}"'
ARCHIVE_ROOT = "releases/fw"


def changelog(*versions: str) -> str:
    return "# Changelog\n\n" + "".join(f"## v{v} (2026-01-01)\n\n- change\n\n" for v in versions)


class ChangelogParserTests(unittest.TestCase):
    pattern = crt.compile_single_group(crt.DEFAULT_CHANGELOG_PATTERN, "p")

    def test_dated_headings_are_releases(self) -> None:
        text = "# C\n\n## v1.1.0 (2026-02-01)\n\n### Notes\n\n## v1.0.0 (2026-01-01)\n"
        self.assertEqual(crt.parse_changelog(text, self.pattern, "C"), ["1.1.0", "1.0.0"])

    def test_fenced_examples_are_not_headings(self) -> None:
        text = "# C\n\n## v1.0.0 (2026-01-01)\n\n```text\n## v9.9.9\n```\n"
        self.assertEqual(crt.parse_changelog(text, self.pattern, "C"), ["1.0.0"])

    def test_unrecognised_or_duplicate_headings_fail_loudly(self) -> None:
        bad = {
            "no versions": "# C\n\n## Unreleased\n",
            "duplicate": "# C\n\n## v1.0.0 (d)\n\n## v1.0.0 (e)\n",
        }
        for label, text in bad.items():
            with self.subTest(label), self.assertRaises(crt.RunError):
                crt.parse_changelog(text, self.pattern, "C")
        # A release-looking heading the pattern does not match is an error.
        strict = crt.compile_single_group(r"^## v(\d+\.\d+\.\d+) \(\d{4}-\d{2}-\d{2}\)$", "p")
        with self.assertRaises(crt.RunError):
            crt.parse_changelog("# C\n\n## v1.0.0\n", strict, "C")

    def test_pattern_must_have_one_group(self) -> None:
        with self.assertRaises(crt.RunError):
            crt.compile_single_group(r"^## v\d+", "p")

    def test_exceptions_file_is_exact_pairs(self) -> None:
        good = ("# comment\n- 1.0.0 no-tag: before the repository\n"
                "1.1.0 legacy-tag v1.1.0: old naming\n1.2.0 no-archive: pre-archive\n")
        parsed = crt.parse_exceptions(good, "E")
        self.assertEqual(parsed[("1.1.0", "legacy-tag")], "v1.1.0")
        self.assertIn(("1.0.0", "no-tag"), parsed)
        for text in ("1.0.x no-tag: pattern\n", "1.0.0 legacy-tag: no name\n",
                     "1.0.0 no-tag: a\n1.0.0 no-tag: b\n", "1.0.0 no-tag v1.0.0: has name\n"):
            with self.subTest(text), self.assertRaises(crt.RunError):
                crt.parse_exceptions(text, "E")


class TempRepository:
    def __init__(self, root: Path) -> None:
        self.root = root
        self.git("init", "-q", "-b", "main")

    def write(self, relative: str, text: str) -> None:
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8", newline="\n")

    def git(self, *args: str) -> str:
        return subprocess.run(["git", *args], cwd=self.root, check=True,
                              capture_output=True, text=True).stdout

    def commit_version(self, version: str, log: str, code_version: str | None = None) -> str:
        self.write(VERSION_FILE, version + "\n")
        self.write(CHANGELOG, log)
        # CRLF, as a Windows checkout would hold the in-code version file.
        (self.root / CODE_FILE).parent.mkdir(parents=True, exist_ok=True)
        (self.root / CODE_FILE).write_bytes(
            f'const char* CODE_VERSION = "app v{code_version or version}";\r\n'.encode())
        self.git("add", "-A")
        self.git("commit", "-q", "-m", f"version {version}")
        return self.git("rev-parse", "HEAD").strip()

    def tag(self, name: str, commit: str = "HEAD", annotated: bool = True) -> None:
        if annotated:
            self.git("tag", "-a", name, commit, "-m", name)
        else:
            self.git("tag", name, commit)

    def archive(self, version: str, tree: str = "clean") -> Path:
        folder = self.root / ARCHIVE_ROOT / f"v{version}"
        folder.mkdir(parents=True, exist_ok=True)
        image = folder / "app.hex"
        image.write_bytes(b":00000001FF\r\n")
        digest = hashlib.sha256(image.read_bytes()).hexdigest()
        (folder / "SHA256SUMS.txt").write_text(f"{digest}  app.hex\n", encoding="utf-8")
        (folder / "BUILD_INFO.md").write_text(f"Tree state: {tree}\n", encoding="utf-8")
        return folder


class RuleTests(unittest.TestCase):
    def setUp(self) -> None:
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        base = Path(self.directory.name)
        config = base / "gitconfig"
        config.write_text("[user]\n\tname = Test\n\temail = test@example.invalid\n"
                          "[tag]\n\tgpgSign = false\n[commit]\n\tgpgSign = false\n",
                          encoding="utf-8")
        patcher = mock.patch.dict(os.environ, {
            "GIT_CONFIG_GLOBAL": str(config), "GIT_CONFIG_NOSYSTEM": "1"})
        patcher.start()
        self.addCleanup(patcher.stop)
        self.base = base / "repo"
        self.base.mkdir()
        self.repo = TempRepository(self.base)

    def run_checker(self, *extra: str) -> tuple[int, str]:
        buffer = io.StringIO()
        with contextlib.redirect_stdout(buffer):
            code = crt.main([
                "--version-file", VERSION_FILE, "--changelog", CHANGELOG,
                "--tag-prefix", PREFIX, "--archive-root", ARCHIVE_ROOT,
                "--root", str(self.base), *extra])
        return code, buffer.getvalue()

    def test_pending_current_version_passes_by_default_and_fails_with_require_current(self) -> None:
        self.repo.commit_version("1.0.0", changelog("1.0.0"))
        self.repo.tag("fw-v1.0.0")
        self.repo.archive("1.0.0")
        self.repo.commit_version("1.0.1", changelog("1.0.1", "1.0.0"))

        code, output = self.run_checker()
        self.assertEqual(code, 0, output)
        self.assertIn("pending release: tag before upload", output)
        self.assertRegex(output, r"WARN\s+1\.0\.1")

        code, output = self.run_checker("--require-current")
        self.assertEqual(code, 1, output)
        self.assertRegex(output, r"FAIL\s+1\.0\.1: pending release")

        self.repo.tag("fw-v1.0.1")
        self.repo.archive("1.0.1")
        code, output = self.run_checker("--require-current")
        self.assertEqual(code, 0, output)
        self.assertIn("current version is tagged (fw-v1.0.1)", output)

    def test_current_version_that_is_not_newest_entry_fails(self) -> None:
        self.repo.commit_version("1.0.0", changelog("1.0.1", "1.0.0"))
        code, output = self.run_checker()
        self.assertEqual(code, 1, output)
        self.assertIn("neither tagged nor the newest changelog entry", output)

    def test_missing_tag_for_a_changelog_release_fails(self) -> None:
        self.repo.commit_version("1.0.0", changelog("1.0.0"))
        self.repo.tag("fw-v1.0.0")
        self.repo.archive("1.0.0")
        self.repo.commit_version("1.1.0", changelog("1.1.0", "1.0.5", "1.0.0"))
        self.repo.tag("fw-v1.1.0")
        self.repo.archive("1.1.0")
        code, output = self.run_checker()
        self.assertEqual(code, 1, output)
        self.assertRegex(output, r"FAIL\s+1\.0\.5: no tag fw-v1\.0\.5")

    def test_history_option_requires_a_tag_for_every_value_the_version_file_held(self) -> None:
        # A version that reached a machine while the changelog still omitted it.
        self.repo.commit_version("1.0.1", changelog("1.0.0"))
        self.repo.commit_version("1.1.0", changelog("1.1.0", "1.0.0"))
        self.repo.tag("fw-v1.1.0")
        self.repo.archive("1.1.0")
        code, output = self.run_checker()
        self.assertNotRegex(output, r"FAIL\s+1\.0\.1")
        code, output = self.run_checker("--check-history")
        self.assertEqual(code, 1, output)
        self.assertRegex(output, r"FAIL\s+1\.0\.1: no tag fw-v1\.0\.1 \(version file first read it at")

    def test_exceptions_are_exact_and_legacy_tag_names_are_accepted(self) -> None:
        first = self.repo.commit_version("1.0.0", changelog("1.0.0"))
        self.repo.tag("v1.0.0", first)  # old naming scheme
        self.repo.archive("1.0.0")
        self.repo.commit_version("1.1.0", changelog("1.1.0", "1.0.0"))
        self.repo.tag("fw-v1.1.0")
        self.repo.archive("1.1.0")

        code, output = self.run_checker()
        self.assertEqual(code, 1, output)
        self.assertRegex(output, r"FAIL\s+1\.0\.0: no tag fw-v1\.0\.0")

        self.repo.write("EXCEPTIONS.md", "1.0.0 legacy-tag v1.0.0: old naming scheme\n")
        code, output = self.run_checker("--exceptions", "EXCEPTIONS.md")
        self.assertEqual(code, 0, output)
        self.assertRegex(output, r"PASS\s+1\.0\.0: tag v1\.0\.0")

        # An exception for another version does not excuse this one.
        self.repo.write("EXCEPTIONS.md", "0.9.0 no-tag: other\n")
        code, _ = self.run_checker("--exceptions", "EXCEPTIONS.md")
        self.assertEqual(code, 1)

    def run_without_changelog(self, *extra: str) -> tuple[int, str]:
        buffer = io.StringIO()
        with contextlib.redirect_stdout(buffer):
            code = crt.main(["--version-file", VERSION_FILE, "--tag-prefix", PREFIX,
                             "--archive-root", ARCHIVE_ROOT, "--exceptions", "EXCEPTIONS.md",
                             "--root", str(self.base), *extra])
        return code, buffer.getvalue()

    def test_current_version_on_a_lightweight_legacy_tag_fails_without_changelog(self) -> None:
        self.repo.commit_version("1.0.0", changelog("1.0.0"))
        self.repo.tag("v1.0.0", annotated=False)  # old naming, and not annotated
        self.repo.archive("1.0.0")
        self.repo.write("EXCEPTIONS.md", "1.0.0 legacy-tag v1.0.0: old naming scheme\n")
        code, output = self.run_without_changelog()
        self.assertEqual(code, 1, output)
        self.assertIn("tag v1.0.0 is lightweight; it must be annotated", output)
        self.assertRegex(output, r"FAIL\s+1\.0\.0: current version is tagged \(v1\.0\.0\), but that tag fails")

    def test_current_version_on_a_legacy_tag_needs_matching_content_and_archive(self) -> None:
        older = self.repo.commit_version("0.9.0", changelog("0.9.0"))
        self.repo.commit_version("1.0.0", changelog("1.0.0"))
        self.repo.tag("v1.0.0", older)  # annotated, but on a commit whose version file reads 0.9.0
        self.repo.write("EXCEPTIONS.md", "1.0.0 legacy-tag v1.0.0: old naming scheme\n")
        code, output = self.run_without_changelog()
        self.assertEqual(code, 1, output)
        self.assertIn("version file reads '0.9.0' at the tag", output)
        self.assertIn("archive releases/fw/v1.0.0/ missing", output)

    def test_current_version_on_an_annotated_matching_legacy_tag_with_archive_passes(self) -> None:
        self.repo.commit_version("1.0.0", changelog("1.0.0"))
        self.repo.tag("v1.0.0")
        self.repo.archive("1.0.0")
        self.repo.write("EXCEPTIONS.md", "1.0.0 legacy-tag v1.0.0: old naming scheme\n")
        code, output = self.run_without_changelog("--require-current")
        self.assertEqual(code, 0, output)
        self.assertRegex(output, r"PASS\s+1\.0\.0: tag v1\.0\.0 -> \w+; version file matches; archive verified")
        self.assertRegex(output, r"PASS\s+1\.0\.0: current version is tagged \(v1\.0\.0\)\n")

    def test_older_version_reached_only_through_a_legacy_tag_exception_is_checked(self) -> None:
        # The probe: no changelog, no --check-history, the older release visible only through its
        # legacy-tag line, on a lightweight tag with no archive; it used to pass unseen.
        self.repo.commit_version("1.0.0", changelog("1.0.0"))
        self.repo.tag("v1.0.0", annotated=False)
        self.repo.commit_version("1.1.0", changelog("1.1.0", "1.0.0"))
        self.repo.tag("fw-v1.1.0")
        self.repo.archive("1.1.0")
        self.repo.write("EXCEPTIONS.md", "1.0.0 legacy-tag v1.0.0: old naming scheme\n")
        code, output = self.run_without_changelog()
        self.assertEqual(code, 1, output)
        self.assertRegex(output, r"FAIL\s+1\.0\.0: tag v1\.0\.0 is lightweight; it must be annotated")
        self.assertIn("archive releases/fw/v1.0.0/ missing", output)

    def test_legacy_tag_exception_naming_a_missing_tag_fails(self) -> None:
        self.repo.commit_version("1.1.0", changelog("1.1.0"))
        self.repo.tag("fw-v1.1.0")
        self.repo.archive("1.1.0")
        self.repo.write("EXCEPTIONS.md", "1.0.0 legacy-tag v1.0.0: old naming scheme\n")
        code, output = self.run_without_changelog()
        self.assertEqual(code, 1, output)
        self.assertRegex(output, r"FAIL\s+1\.0\.0: no tag fw-v1\.0\.0, and the legacy tag v1\.0\.0 that the "
                                 r"exceptions file names does not exist")

    def test_versions_named_by_no_archive_or_no_tag_exceptions_are_checked_for_the_rest(self) -> None:
        self.repo.commit_version("1.1.0", changelog("1.1.0"))
        self.repo.tag("fw-v1.1.0")
        self.repo.archive("1.1.0")
        # no-archive excuses the archive only: the release still needs its tag.
        self.repo.write("EXCEPTIONS.md", "1.0.0 no-archive: built before the archive scheme\n")
        code, output = self.run_without_changelog()
        self.assertEqual(code, 1, output)
        self.assertRegex(output, r"FAIL\s+1\.0\.0: no tag fw-v1\.0\.0")
        # no-tag excuses the tag: the release is listed as an excused warning, not silently skipped.
        self.repo.write("EXCEPTIONS.md", "0.9.0 no-tag: before the repository\n"
                                         "0.9.0 no-archive: before the archive scheme\n")
        code, output = self.run_without_changelog()
        self.assertEqual(code, 0, output)
        self.assertRegex(output, r"WARN\s+0\.9\.0: untagged, excused")

    def test_untagged_release_excused_as_no_tag_is_a_warning(self) -> None:
        self.repo.commit_version("1.0.1", changelog("1.0.1", "0.9.0"))
        self.repo.tag("fw-v1.0.1")
        self.repo.archive("1.0.1")
        code, output = self.run_checker()
        self.assertEqual(code, 1, output)
        self.repo.write("EXCEPTIONS.md", "0.9.0 no-tag: before the repository\n"
                                         "0.9.0 no-archive: before the archive scheme\n")
        code, output = self.run_checker("--exceptions", "EXCEPTIONS.md")
        self.assertEqual(code, 0, output)
        self.assertRegex(output, r"WARN\s+0\.9\.0: untagged, excused")

    def test_no_tag_does_not_excuse_the_archive(self) -> None:
        # The review probe: 0.9.0 no-tag with no archive used to exit 0.
        self.repo.commit_version("1.1.0", changelog("1.1.0"))
        self.repo.tag("fw-v1.1.0")
        self.repo.archive("1.1.0")
        self.repo.write("EXCEPTIONS.md", "0.9.0 no-tag: before the repository\n")
        code, output = self.run_without_changelog()
        self.assertEqual(code, 1, output)
        self.assertRegex(output, r"FAIL\s+0\.9\.0: untagged, excused by the exceptions file; archive releases/fw/v0\.9\.0/ missing")

    def test_no_tag_release_with_its_archive_is_an_excused_warning(self) -> None:
        self.repo.commit_version("1.1.0", changelog("1.1.0"))
        self.repo.tag("fw-v1.1.0")
        self.repo.archive("1.1.0")
        self.repo.archive("0.9.0")
        self.repo.write("EXCEPTIONS.md", "0.9.0 no-tag: before the repository\n")
        code, output = self.run_without_changelog()
        self.assertEqual(code, 0, output)
        self.assertRegex(output, r"WARN\s+0\.9\.0: untagged, excused by the exceptions file; archive verified")

    def test_current_version_named_by_an_exception_is_not_pending(self) -> None:
        # The current version with a no-tag line is a release: its archive is still required, and it is
        # not waved through as a pending release.
        self.repo.commit_version("1.0.0", changelog("1.0.0"))
        self.repo.write("EXCEPTIONS.md", "1.0.0 no-tag: tagged elsewhere\n")
        code, output = self.run_without_changelog()
        self.assertEqual(code, 1, output)
        self.assertNotIn("pending release", output)
        self.assertRegex(output, r"FAIL\s+1\.0\.0: untagged, excused by the exceptions file; archive releases/fw/v1\.0\.0/ missing")

    def test_tag_contents_must_match_the_version(self) -> None:
        self.repo.commit_version("1.0.0", changelog("1.0.0"), code_version="0.9.9")
        self.repo.tag("fw-v1.0.0")
        self.repo.archive("1.0.0")
        code, output = self.run_checker("--code-file", CODE_FILE, "--code-pattern", CODE_PATTERN)
        self.assertEqual(code, 1, output)
        self.assertIn("does not carry version 1.0.0 at the tag", output)

        code, output = self.run_checker()  # without the in-code check the tag passes
        self.assertEqual(code, 0, output)

    def test_lightweight_tag_is_rejected(self) -> None:
        self.repo.commit_version("1.0.0", changelog("1.0.0"))
        self.repo.tag("fw-v1.0.0", annotated=False)
        self.repo.archive("1.0.0")
        code, output = self.run_checker()
        self.assertEqual(code, 1, output)
        self.assertIn("is lightweight; it must be annotated", output)

    def test_archive_rules(self) -> None:
        self.repo.commit_version("1.0.0", changelog("1.0.0"))
        self.repo.tag("fw-v1.0.0")
        code, output = self.run_checker()
        self.assertEqual(code, 1, output)
        self.assertIn("archive releases/fw/v1.0.0/ missing", output)

        folder = self.repo.archive("1.0.0")
        code, output = self.run_checker()
        self.assertEqual(code, 0, output)

        (folder / "app.hex").write_bytes(b"tampered")
        code, output = self.run_checker()
        self.assertEqual(code, 1, output)
        self.assertIn("SHA-256 mismatch", output)

        self.repo.archive("1.0.0", tree="dirty")
        code, output = self.run_checker()
        self.assertEqual(code, 1, output)
        self.assertIn("built from a dirty tree", output)

        self.repo.archive("1.0.0")
        (folder / "extra.hex").write_bytes(b"x")
        code, output = self.run_checker()
        self.assertEqual(code, 1, output)
        self.assertIn("unlisted binaries: extra.hex", output)

    def test_missing_archive_can_be_excused_for_one_exact_version(self) -> None:
        self.repo.commit_version("1.0.0", changelog("1.0.0"))
        self.repo.tag("fw-v1.0.0")
        self.repo.write("EXCEPTIONS.md", "1.0.0 no-archive: built before the archive scheme\n")
        code, output = self.run_checker("--exceptions", "EXCEPTIONS.md")
        self.assertEqual(code, 0, output)
        self.assertIn("no archive, excused", output)

    def test_unrecognised_changelog_is_a_run_error_not_a_pass(self) -> None:
        self.repo.commit_version("1.0.0", "# C\n\nNothing structured here.\n")
        code, output = self.run_checker()
        self.assertEqual(code, 2, output)
        self.assertIn("no version entries recognised", output)

    def test_missing_version_file_is_a_run_error(self) -> None:
        self.repo.commit_version("1.0.0", changelog("1.0.0"))
        buffer = io.StringIO()
        with contextlib.redirect_stdout(buffer):
            code = crt.main(["--version-file", "NOPE", "--tag-prefix", PREFIX,
                             "--archive-root", ARCHIVE_ROOT, "--root", str(self.base)])
        self.assertEqual(code, 2, buffer.getvalue())

    def test_code_file_without_pattern_is_a_usage_error(self) -> None:
        with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as caught:
            crt.main(["--version-file", VERSION_FILE, "--archive-root", ARCHIVE_ROOT,
                      "--code-file", CODE_FILE, "--root", str(self.base)])
        self.assertEqual(caught.exception.code, 2)


if __name__ == "__main__":
    unittest.main()
