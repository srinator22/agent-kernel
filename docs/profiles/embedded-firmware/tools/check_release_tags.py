#!/usr/bin/env python3
"""Check that every released version has an annotated tag and an archive folder.

Purpose: enforce rule FW-14 of the embedded-firmware profile. A version counts
as released when the changelog lists it (a heading that matches the changelog
pattern), when a tag with the prefix already exists, when the exceptions file
names it (every exception form, no-tag, no-archive and legacy-tag, says a
release of that version exists), or, with --check-history, when the version
file ever held it in a commit. A version named only by the exceptions file
gets rules A, B and D like any other release; only the rule its own exception
line excuses is relaxed (no-tag: the tag and so rules A and B; no-archive:
rule D; legacy-tag: the tag name, never the annotation, the content or the
archive). A legacy-tag line whose tag does not exist is a FAIL.

Rules, per released version:
  A. An annotated tag <tag-prefix>vX.Y.Z exists (an exceptions-file line can
     excuse one exact version; patterns are never accepted).
  B. At the tag's commit the version file reads X.Y.Z and, when --code-file is
     given, the in-code version string matches too.
  C. The working-tree version is tagged, or it is the newest changelog entry
     (a pending release: tag before upload). --require-current turns the
     pending case into a failure; the release flow uses it after tagging.
     A tagged current version always gets rules A, B and D through the tag
     name that resolves it, the prefixed name or a legacy-tag exception,
     with or without a changelog or --check-history.
  D. <archive-root>/vX.Y.Z/ holds a sums file whose entries verify and an info
     file; an info file that says the tree was dirty fails.

Inputs (all arguments, nothing project-specific is built in):
  --version-file PATH         file holding the current version (required)
  --version-pattern REGEX     one capture group; default a bare vX.Y.Z or X.Y.Z
  --changelog PATH            optional; released versions come from its headings
  --changelog-pattern REGEX   one capture group; default '## v1.2.3 (date)' style
  --tag-prefix TEXT           tag is <prefix>v1.2.3, for example 'fw-' or ''
  --archive-root PATH         archives live in <root>/v1.2.3/
  --code-file PATH            optional file carrying the in-code version string
  --code-pattern REGEX        regex containing {version}; required with --code-file
  --exceptions PATH           optional file, one exact pair per line:
                                <version> no-tag: <reason>
                                <version> no-archive: <reason>
                                <version> legacy-tag <tag name>: <reason>
  --sums-name, --info-name, --dirty-marker   archive file names and marker
  --root PATH                 repository root (default: current directory)

Outputs: one PASS, WARN or FAIL line per version, a summary, exit status
0 pass, 1 a check failed, 2 the check could not run (bad arguments, unreadable
files, unrecognised changelog, shallow clone).

Dependencies: Python 3 standard library and the git command line.
Assumptions: the repository has full history with tags; the tool only reads.
Validation source: the ported checker's regression suite, rebuilt as
tools/tests/test_check_release_tags.py against a throwaway git repository.
"""

from __future__ import annotations

import argparse
import hashlib
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

SEMVER = r"\d+\.\d+\.\d+"
DEFAULT_VERSION_PATTERN = rf"^\s*v?({SEMVER})\s*$"
DEFAULT_CHANGELOG_PATTERN = rf"^## \[?v?({SEMVER})\]?(?:\s|$)"
EXCEPTION_LINE = re.compile(
    rf"^(?:- )?({SEMVER}) (no-tag|no-archive|legacy-tag)(?: (\S+))?: (\S.*)$"
)


class RunError(Exception):
    """The check could not run; maps to exit status 2."""


def version_key(value: str) -> tuple[int, int, int]:
    major, minor, patch = (int(part) for part in value.split("."))
    return major, minor, patch


def compile_single_group(pattern: str, label: str, flags: int = 0) -> re.Pattern[str]:
    try:
        compiled = re.compile(pattern, flags)
    except re.error as error:
        raise RunError(f"{label} is not a valid regex: {error}") from error
    if compiled.groups != 1:
        raise RunError(f"{label} must contain exactly one capture group")
    return compiled


def parse_changelog(text: str, pattern: re.Pattern[str], source: str) -> list[str]:
    """Return released versions in file order; fenced blocks are skipped.

    A heading that looks like a release but does not match the pattern is a
    format error, so a new heading style fails loudly instead of matching
    nothing.
    """
    versions: list[str] = []
    in_fence = False
    for number, raw in enumerate(text.splitlines(), start=1):
        line = raw.rstrip()
        if line.startswith("```"):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        match = pattern.match(line)
        if match:
            version = match.group(1)
            if version in versions:
                raise RunError(f"{source}:{number}: version {version} listed twice")
            versions.append(version)
        elif re.match(rf"^##\s+\[?v?{SEMVER}", line):
            raise RunError(f"{source}:{number}: heading {line!r} looks like a release "
                           "but does not match --changelog-pattern")
    if not versions:
        raise RunError(f"{source}: no version entries recognised")
    return versions


def parse_exceptions(text: str, source: str) -> dict[tuple[str, str], str]:
    """Return {(version, kind): detail}; detail is the legacy tag name or ''."""
    found: dict[tuple[str, str], str] = {}
    for number, raw in enumerate(text.splitlines(), start=1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        match = EXCEPTION_LINE.match(line)
        if not match:
            raise RunError(f"{source}:{number}: unrecognised exception line {line!r}")
        version, kind, tag_name, _reason = match.groups()
        if (kind == "legacy-tag") != (tag_name is not None):
            raise RunError(f"{source}:{number}: legacy-tag needs a tag name, others take none")
        key = (version, kind)
        if key in found:
            raise RunError(f"{source}:{number}: {version} {kind} listed twice")
        found[key] = tag_name or ""
    return found


class Git:
    def __init__(self, root: Path) -> None:
        self.root = root

    def run(self, *args: str) -> str:
        try:
            result = subprocess.run(
                ["git", *args], cwd=self.root, capture_output=True,
                check=False, encoding="utf-8", errors="replace",
            )
        except OSError as error:
            raise RunError(f"cannot run git: {error}") from error
        if result.returncode != 0:
            raise RunError(f"git {' '.join(args)} failed: {result.stderr.strip()}")
        return result.stdout

    def is_shallow(self) -> bool:
        return self.run("rev-parse", "--is-shallow-repository").strip() == "true"

    def tags(self) -> dict[str, tuple[str, str]]:
        """Return {tag name: (object type, commit sha)}."""
        output = self.run(
            "for-each-ref", "refs/tags",
            "--format=%(refname:short)%09%(objecttype)%09%(*objectname)%09%(objectname)",
        )
        tags: dict[str, tuple[str, str]] = {}
        for line in output.splitlines():
            name, kind, peeled, target = line.split("\t")
            tags[name] = (kind, peeled if kind == "tag" else target)
        return tags

    def blob(self, commit: str, path: str) -> str | None:
        """Return a file's text at a commit, or None when it does not exist there."""
        try:
            return self.run("show", f"{commit}:{path}")
        except RunError:
            return None

    def history(self, path: str) -> list[tuple[str, str]]:
        """Return (commit, added line) for every commit that changed the file."""
        output = self.run(
            "log", "--reverse", "--no-renames", "--no-color", "-p",
            "--format=@@commit %H", "--", path,
        )
        rows: list[tuple[str, str]] = []
        commit = ""
        for line in output.splitlines():
            if line.startswith("@@commit "):
                commit = line.split()[1]
            elif line.startswith("+") and not line.startswith("+++"):
                rows.append((commit, line[1:]))
        return rows


@dataclass
class Line:
    status: str  # PASS, WARN, FAIL
    version: str
    reasons: list[str]

    def render(self) -> str:
        return f"{self.status:<4}  {self.version}: " + "; ".join(self.reasons)


def worst(statuses: list[str]) -> str:
    for status in ("FAIL", "WARN"):
        if status in statuses:
            return status
    return "PASS"


def verify_archive(args: argparse.Namespace, version: str,
                   require_clean: bool = True) -> tuple[str, str]:
    """Rule D on the filesystem. Returns (PASS or FAIL, reason)."""
    relative = f"{args.archive_root.as_posix().rstrip('/')}/v{version}"
    folder = args.root / relative
    if not folder.is_dir():
        return "FAIL", f"archive {relative}/ missing"
    sums = folder / args.sums_name
    if not sums.is_file():
        return "FAIL", f"{relative}/{args.sums_name} missing"
    info = folder / args.info_name
    if not info.is_file():
        return "FAIL", f"{relative}/{args.info_name} missing"
    listed: set[str] = set()
    for number, raw in enumerate(sums.read_text(encoding="utf-8").splitlines(), start=1):
        if not raw.strip():
            continue
        match = re.fullmatch(r"([0-9a-fA-F]{64}) [ *](.+)", raw.strip())
        if not match:
            return "FAIL", f"{relative}/{args.sums_name} line {number} unreadable"
        name = match.group(2)
        target = folder / name
        if "/" in name or "\\" in name or not target.is_file():
            return "FAIL", f"{relative}/{name} listed but missing"
        if hashlib.sha256(target.read_bytes()).hexdigest().lower() != match.group(1).lower():
            return "FAIL", f"{relative}/{name} SHA-256 mismatch"
        listed.add(name)
    if not listed:
        return "FAIL", f"{relative}/{args.sums_name} lists no files"
    unlisted = sorted(
        path.name for path in folder.iterdir()
        if path.suffix.lower() in {".hex", ".elf", ".bin"} and path.name not in listed
    )
    if unlisted:
        return "FAIL", f"{relative} holds unlisted binaries: {', '.join(unlisted)}"
    dirty = args.dirty_marker in info.read_text(encoding="utf-8", errors="replace")
    if dirty and require_clean:
        return "FAIL", f"{relative} was built from a dirty tree; rebuild it from the clean tagged commit"
    return "PASS", f"archive verified ({len(listed)} files, {'dirty' if dirty else 'clean'} tree)"


def run_check(args: argparse.Namespace) -> list[Line]:
    root: Path = args.root
    version_re = compile_single_group(args.version_pattern, "--version-pattern", re.MULTILINE)
    changelog_re = compile_single_group(args.changelog_pattern, "--changelog-pattern")
    git = Git(root)
    if git.is_shallow():
        raise RunError("shallow clone: tags and history are incomplete; "
                       "run git fetch --unshallow --tags first")
    tags = git.tags()

    exceptions: dict[tuple[str, str], str] = {}
    if args.exceptions:
        exceptions = parse_exceptions(
            (root / args.exceptions).read_text(encoding="utf-8"), args.exceptions)

    def read_version(text: str, source: str) -> str:
        match = version_re.search(text)
        if not match:
            raise RunError(f"{source}: --version-pattern matched nothing")
        return match.group(1)

    try:
        current = read_version((root / args.version_file).read_text(encoding="utf-8"),
                               args.version_file)
    except OSError as error:
        raise RunError(f"cannot read {args.version_file}: {error}") from error
    if not re.fullmatch(SEMVER, current):
        raise RunError(f"{args.version_file}: expected MAJOR.MINOR.PATCH, found {current!r}")

    released: list[str] = []
    if args.changelog:
        try:
            text = (root / args.changelog).read_text(encoding="utf-8")
        except OSError as error:
            raise RunError(f"cannot read {args.changelog}: {error}") from error
        released = parse_changelog(text, changelog_re, args.changelog)
    newest = max(released, key=version_key) if released else None

    def tag_for(version: str) -> str | None:
        name = f"{args.tag_prefix}v{version}"
        if name in tags:
            return name
        legacy = exceptions.get((version, "legacy-tag"))
        return legacy if legacy and legacy in tags else None

    first_commit: dict[str, str] = {}
    if args.check_history:
        for commit, added in git.history(args.version_file):
            match = version_re.search(added)
            if match:
                first_commit.setdefault(match.group(1), commit)

    required: dict[str, str] = {version: "changelog release" for version in released}
    for version, _commit in first_commit.items():
        required.setdefault(version, "version-file history")
    for name in tags:
        if name.startswith(f"{args.tag_prefix}v"):
            candidate = name[len(f"{args.tag_prefix}v"):]
            if re.fullmatch(SEMVER, candidate):
                required.setdefault(candidate, "tag")
    # An exception line exists only for a released version, so the version it names is checked even when
    # no changelog, history or prefixed tag shows it (a legacy-tag release would otherwise go unchecked).
    for version, kind in sorted(exceptions, key=lambda key: (version_key(key[0]), key[1])):
        required.setdefault(version, f"exceptions file {kind}")
    current_tag = tag_for(current)
    if current_tag:
        # A tagged current version gets rules A, B and D through whichever name resolves it, including a
        # legacy-tag exception that the prefixed-tag discovery above cannot see.
        required.setdefault(current, "current version")
    # A version named by an exception line is a release, never a pending one, so it keeps the checks
    # its exception does not excuse.
    named = {version for version, _kind in exceptions}
    pending = current_tag is None and current not in named and (newest is None or current == newest)
    if pending:
        required.pop(current, None)

    lines: list[Line] = []
    for version in sorted(required, key=version_key):
        statuses: list[str] = []
        reasons: list[str] = []
        name = tag_for(version)
        if name is None:
            legacy = exceptions.get((version, "legacy-tag"))
            if (version, "no-tag") in exceptions:
                # no-tag excuses rules A and B only; rule D (the archive) still applies unless a
                # no-archive line excuses it too.
                statuses = ["WARN"]
                reasons = ["untagged, excused by the exceptions file"]
                status, reason = verify_archive(args, version)
                if status == "FAIL" and (version, "no-archive") in exceptions:
                    statuses.append("WARN")
                    reasons.append("no archive, excused by the exceptions file")
                else:
                    statuses.append(status)
                    reasons.append(reason)
                lines.append(Line(worst(statuses), version, reasons))
            elif legacy:
                lines.append(Line("FAIL", version, [
                    f"no tag {args.tag_prefix}v{version}, and the legacy tag {legacy} that the exceptions "
                    "file names does not exist"]))
            else:
                hint = (f"version file first read it at {first_commit[version][:7]}"
                        if version in first_commit else required[version])
                lines.append(Line("FAIL", version,
                                  [f"no tag {args.tag_prefix}v{version} ({hint})"]))
            continue
        kind, commit = tags[name]
        if kind != "tag":
            statuses.append("FAIL")
            reasons.append(f"tag {name} is lightweight; it must be annotated")
        else:
            reasons.append(f"tag {name} -> {commit[:7]}")

        text = git.blob(commit, args.version_file)
        if text is None:
            statuses.append("FAIL")
            reasons.append("no version file at the tagged commit")
        else:
            found = version_re.search(text)
            if not found or found.group(1) != version:
                statuses.append("FAIL")
                reasons.append(f"version file reads {found.group(1) if found else 'nothing'!r} at the tag")
            else:
                reasons.append("version file matches")

        if args.code_file:
            code = git.blob(commit, args.code_file)
            expected = args.code_pattern.replace("{version}", re.escape(version))
            if code is None:
                statuses.append("FAIL")
                reasons.append(f"no {args.code_file} at the tagged commit")
            elif not re.search(expected, code):
                statuses.append("FAIL")
                reasons.append(f"{args.code_file} does not carry version {version} at the tag")
            else:
                reasons.append("in-code version matches")

        status, reason = verify_archive(args, version)
        if status == "FAIL" and (version, "no-archive") in exceptions:
            statuses.append("WARN")
            reasons.append("no archive, excused by the exceptions file")
        else:
            statuses.append(status)
            reasons.append(reason)
        lines.append(Line(worst(statuses), version, reasons))

    if current_tag:
        checked = next(line for line in lines if line.version == current)
        reason = f"current version is tagged ({current_tag})"
        if checked.status != "PASS":
            reason += f", but that tag fails the checks above: {'; '.join(checked.reasons)}"
        lines.append(Line(checked.status, current, [reason]))
    elif current in named:
        pass  # checked above as a release under its exception; nothing is pending
    elif pending:
        reasons = [f"pending release: tag before upload (current {current} has no tag)"]
        if (root / args.archive_root / f"v{current}").exists():
            status, reason = verify_archive(args, current, require_clean=False)
            reasons.append(reason if status == "PASS" else f"archive problem: {reason}")
        lines.append(Line("FAIL" if args.require_current else "WARN", current, reasons))
    else:
        lines.append(Line("FAIL", current, [
            f"current version {current} is neither tagged nor the newest changelog entry "
            f"(newest is {newest})"]))
    return lines


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--version-file", required=True)
    parser.add_argument("--version-pattern", default=DEFAULT_VERSION_PATTERN)
    parser.add_argument("--changelog")
    parser.add_argument("--changelog-pattern", default=DEFAULT_CHANGELOG_PATTERN)
    parser.add_argument("--tag-prefix", default="", help="text before 'vX.Y.Z' in the tag name")
    parser.add_argument("--archive-root", type=Path, required=True)
    parser.add_argument("--code-file")
    parser.add_argument("--code-pattern", help="regex with {version}; required with --code-file")
    parser.add_argument("--exceptions")
    parser.add_argument("--sums-name", default="SHA256SUMS.txt")
    parser.add_argument("--info-name", default="BUILD_INFO.md")
    parser.add_argument("--dirty-marker", default="Tree state: dirty")
    parser.add_argument("--check-history", action="store_true",
                        help="also require a tag for every value the version file ever held")
    parser.add_argument("--require-current", action="store_true",
                        help="fail when the working-tree version has no tag")
    parser.add_argument("--root", type=Path, default=Path.cwd())
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    args.root = args.root.resolve()
    if args.code_file and not args.code_pattern:
        parser.error("--code-pattern is required with --code-file")
    try:
        lines = run_check(args)
    except RunError as error:
        print(f"ERROR {error}")
        return 2
    for line in lines:
        print(line.render())
    counts = {s: sum(1 for line in lines if line.status == s) for s in ("PASS", "WARN", "FAIL")}
    print()
    print(f"Summary: {counts['PASS']} PASS, {counts['WARN']} WARN, {counts['FAIL']} FAIL")
    failed = counts["FAIL"] > 0
    print("Release tags and archives:", "FAIL" if failed else "PASS")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
