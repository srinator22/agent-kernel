#!/usr/bin/env python3
"""Check datasheets/MANIFEST.md against the files on disk (rule PCB-2).

Purpose
    Every document in the datasheets folder has a manifest row, every row
    names a file that exists, and the recorded sha256 matches the file.

Inputs
    --root DIR        design folder (default: current directory)
    --manifest FILE   manifest (default: <root>/datasheets/MANIFEST.md)
    --datasheets DIR  documents folder (default: <root>/datasheets)
    --suffix .pdf     file suffix that must be listed; repeatable
                      (default: .pdf and .xlsx)
    --params FILE     optional parameters.toml; each [[parts]] row whose
                      `datasheet` is a path (relative to --root) must exist
                      and be listed ("pending" and "NOT RETRIEVED..." skip)
    --check-captures  also WARN for a saved web page (.html/.htm) outside the
                      folders named by --capture-allow
    --capture-allow PREFIX[:html]
                      root-relative folder where verbatim web captures are
                      allowed (repeatable); ":html" allows only .html/.htm
    --json            print findings as JSON

MANIFEST.md format
    Any Markdown table whose header row has columns "File" and "SHA-256"
    (case-insensitive; "Status", "Part" and "Document" are optional). Column
    order is free. Several tables may follow each other.
    - File cell: a path relative to the datasheets folder, plain, in
      backticks or as a Markdown link. A bare name (no slash) matches the one
      file of that name anywhere below the folder.
    - A path ending in "/" is a directory row: it lists the folder and covers
      every file below it; a second table with bare file names carries the
      per-file hashes.
    - "-" in the File cell means no file; the Status must then start with
      "NOT RETRIEVED" (a WARN) or the row FAILs.
    - SHA-256: 64 hex characters; anything else is a WARN (integrity not
      verified).

Outputs
    One line per finding: LEVEL, check name, message. Exit 0 no FAIL, 1 at
    least one FAIL, 2 the tool could not run (never a pass).

Dependencies
    Python 3.11+ standard library only.

Assumptions
    Hashes are compared case-insensitively. Only suffixes given by --suffix
    are required to be listed.

Validation source
    Generalised from a controller-PCB project check; behaviour pinned by
    tests/test_check_manifest.py on made-up fixtures.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
import tomllib
from dataclasses import asdict, dataclass
from pathlib import Path

CHECK = "manifest"
DEFAULT_SUFFIXES = (".pdf", ".xlsx")
HEX64 = re.compile(r"[0-9a-fA-F]{64}")
LINK = re.compile(r"\[[^\]]*\]\(([^)]+)\)")
NOT_RETRIEVED = "NOT RETRIEVED"
CAPTURE_SUFFIXES = (".html", ".htm")
LEVELS = ("PASS", "WARN", "FAIL", "INFO")


class ToolError(Exception):
    """The tool could not run at all (exit code 2)."""


@dataclass(frozen=True)
class Finding:
    level: str
    check: str
    message: str


@dataclass
class ManifestRow:
    label: str             # part and document text, for messages
    path: str | None       # as written, relative to the datasheets folder; None when absent
    sha256: str            # as written
    status: str

    @property
    def is_directory(self) -> bool:
        return bool(self.path) and self.path.endswith("/")


def _split_cells(line: str) -> list[str]:
    return [cell.strip() for cell in line.strip().strip("|").split("|")]


def _clean_path(cell: str) -> str | None:
    link = LINK.search(cell)
    text = link.group(1) if link else cell
    text = text.strip().strip("`").strip()
    return None if text in ("", "-") else text.replace("\\", "/")


def parse_manifest(text: str) -> tuple[bool, list[ManifestRow]]:
    """(whether any manifest table header was found, the rows of every such table)."""
    rows: list[ManifestRow] = []
    found_header = False
    columns: dict[str, int] | None = None
    for line in text.splitlines():
        if not line.lstrip().startswith("|"):
            columns = None
            continue
        cells = _split_cells(line)
        lowered = [cell.lower() for cell in cells]
        if columns is None:
            if "file" in lowered and "sha-256" in lowered:
                found_header = True
                columns = {name: lowered.index(name)
                           for name in ("file", "sha-256", "status", "part", "document") if name in lowered}
            continue
        if all(set(cell) <= set("-: ") for cell in cells):
            continue   # the |---|---| separator line
        file_cell = cells[columns["file"]] if columns["file"] < len(cells) else ""
        digest = cells[columns["sha-256"]] if columns["sha-256"] < len(cells) else ""
        status = cells[columns["status"]] if "status" in columns and columns["status"] < len(cells) else ""
        label = " ".join(cells[columns[name]] for name in ("part", "document")
                         if name in columns and columns[name] < len(cells)) or file_cell
        rows.append(ManifestRow(label, _clean_path(file_cell), digest, status))
    return found_header, rows


def sha256_of(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def _resolve(row_path: str, datasheets: Path, by_basename: dict[str, list[Path]]) -> tuple[Path | None, str]:
    """Find the file a row names; bare names (per-file tables) match by unique basename."""
    direct = datasheets / row_path
    if direct.is_file():
        return direct, ""
    if "/" not in row_path:
        matches = by_basename.get(row_path, [])
        if len(matches) == 1:
            return matches[0], ""
        if len(matches) > 1:
            return None, f"ambiguous: {len(matches)} files named {row_path}"
    return None, "missing"


def _verify_rows(rows: list[ManifestRow], datasheets: Path,
                 files: list[Path]) -> tuple[list[Finding], set[Path], list[Path]]:
    findings: list[Finding] = []
    listed: set[Path] = set()
    directories: list[Path] = []
    by_basename: dict[str, list[Path]] = {}
    for file in files:
        by_basename.setdefault(file.name, []).append(file)
    for row in rows:
        not_retrieved = row.status.startswith(NOT_RETRIEVED)
        if row.path is None:
            if not_retrieved:
                findings.append(Finding("WARN", f"{CHECK}.not_retrieved", f"{row.label}: {row.status}"))
            else:
                findings.append(Finding("FAIL", f"{CHECK}.row",
                                        f"{row.label}: row has no file path and is not marked {NOT_RETRIEVED}"))
            continue
        if row.is_directory:
            folder = datasheets / row.path
            if folder.is_dir():
                directories.append(folder)
            else:
                findings.append(Finding("FAIL", f"{CHECK}.missing", f"{row.label}: folder {row.path} does not exist"))
            continue
        target, problem = _resolve(row.path, datasheets, by_basename)
        if target is None:
            level = "WARN" if not_retrieved else "FAIL"
            findings.append(Finding(level, f"{CHECK}.missing", f"{row.path}: listed but {problem}"))
            continue
        listed.add(target)
        if not HEX64.fullmatch(row.sha256):
            findings.append(Finding("WARN", f"{CHECK}.hash", f"{row.path}: no SHA-256 recorded, integrity not verified"))
        elif sha256_of(target).lower() != row.sha256.lower():
            findings.append(Finding("FAIL", f"{CHECK}.hash", f"{row.path}: SHA-256 does not match the manifest"))
    return findings, listed, directories


def _part_findings(params: dict, root: Path, listed: set[Path], covered: set[Path]) -> list[Finding]:
    findings = []
    for part in params.get("parts", []):
        datasheet = part.get("datasheet")
        ref = part.get("ref", "?")
        # "pending" and NOT RETRIEVED mean no file exists yet; another tool warns about both.
        if not datasheet or datasheet == "pending" or str(datasheet).startswith(NOT_RETRIEVED):
            continue
        target = root / datasheet
        if not target.exists():
            findings.append(Finding("FAIL", f"{CHECK}.part_datasheet", f"{ref}: datasheet {datasheet} does not exist"))
        elif target not in listed and target not in covered:
            findings.append(Finding("WARN", f"{CHECK}.part_datasheet",
                                    f"{ref}: datasheet {datasheet} is not listed in the manifest"))
    return findings


def _capture_allowed(relative: str, allow: list[tuple[str, bool]]) -> bool:
    return any(relative.startswith(prefix) and (not html_only or relative.lower().endswith(CAPTURE_SUFFIXES))
               for prefix, html_only in allow)


def _capture_findings(datasheets: Path, root: Path, allow: list[tuple[str, bool]]) -> list[Finding]:
    """WARN for an .html or .htm capture under the documents folder outside the allowed prefixes."""
    findings = []
    for path in sorted(datasheets.rglob("*")):
        if not path.is_file() or path.suffix.lower() not in CAPTURE_SUFFIXES:
            continue
        try:
            relative = path.relative_to(root).as_posix()
        except ValueError:
            relative = path.as_posix()
        if not _capture_allowed(relative, allow):
            findings.append(Finding("WARN", f"{CHECK}.capture_path",
                                    f"{relative}: a web capture outside the allowed capture folders"))
    return findings


def parse_capture_allow(items: list[str]) -> list[tuple[str, bool]]:
    allow = []
    for item in items:
        prefix, _, mode = item.partition(":")
        allow.append((prefix.replace("\\", "/"), mode.lower() == "html"))
    return allow


def run(params: dict, root: Path, manifest: Path | None = None, datasheets: Path | None = None,
        suffixes: tuple[str, ...] = DEFAULT_SUFFIXES, check_captures: bool = False,
        capture_allow: list[tuple[str, bool]] | None = None) -> list[Finding]:
    root = Path(root)
    datasheets = Path(datasheets) if datasheets else root / "datasheets"
    manifest = Path(manifest) if manifest else datasheets / "MANIFEST.md"
    if not manifest.is_file():
        raise ToolError(f"manifest not found: {manifest}")
    if not datasheets.is_dir():
        raise ToolError(f"documents folder not found: {datasheets}")
    found_header, rows = parse_manifest(manifest.read_text(encoding="utf-8"))
    if not found_header:
        return [Finding("FAIL", f"{CHECK}.parse", "no manifest table with File and SHA-256 columns found")]

    wanted = tuple(s.lower() for s in suffixes)
    files = sorted(path for path in datasheets.rglob("*") if path.is_file() and path.suffix.lower() in wanted)
    findings, listed, directories = _verify_rows(rows, datasheets, files)
    covered = {file for file in files if any(folder in file.parents for folder in directories)}
    for file in files:
        if file not in listed and file not in covered:
            findings.append(Finding("FAIL", f"{CHECK}.unlisted", f"unlisted file: {file.relative_to(datasheets).as_posix()}"))
    findings.extend(_part_findings(params, root, listed, covered))
    if check_captures:
        findings.extend(_capture_findings(datasheets, root, capture_allow or []))
    if not any(f.level == "FAIL" for f in findings):
        findings.append(Finding("PASS", f"{CHECK}.consistent",
                                f"{len(files)} documents on disk are all listed; {len(listed)} hashes checked"))
    return findings


def load_params(path: Path | None) -> dict:
    if path is None:
        return {}
    try:
        with Path(path).open("rb") as handle:
            return tomllib.load(handle)
    except FileNotFoundError as error:
        raise ToolError(f"parameters file not found: {path}") from error
    except tomllib.TOMLDecodeError as error:
        raise ToolError(f"parameters file is not valid TOML: {path}: {error}") from error


def emit(findings: list[Finding], title: str, as_json: bool) -> int:
    counts = {level: sum(f.level == level for f in findings) for level in LEVELS}
    if as_json:
        print(json.dumps({"title": title, "counts": counts, "findings": [asdict(f) for f in findings]}, indent=2))
    else:
        for f in findings:
            print(f"{f.level:<5} {f.check}: {f.message}")
        print("  ".join(f"{level}: {counts[level]}" for level in LEVELS))
    return 1 if counts["FAIL"] else 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.strip().splitlines()[0])
    parser.add_argument("--root", type=Path, default=Path.cwd(), help="design folder (default: current directory)")
    parser.add_argument("--manifest", type=Path, help="manifest file (default <root>/datasheets/MANIFEST.md)")
    parser.add_argument("--datasheets", type=Path, help="documents folder (default <root>/datasheets)")
    parser.add_argument("--suffix", action="append", help="suffix that must be listed (repeatable)")
    parser.add_argument("--params", type=Path, help="parameters.toml with [[parts]] datasheet paths")
    parser.add_argument("--check-captures", action="store_true", help="WARN for web captures outside --capture-allow")
    parser.add_argument("--capture-allow", action="append", default=[], help="folder[:html] where captures are allowed")
    parser.add_argument("--json", action="store_true", help="print findings as JSON")
    args = parser.parse_args(argv)
    try:
        findings = run(load_params(args.params), args.root, args.manifest, args.datasheets,
                       tuple(args.suffix) if args.suffix else DEFAULT_SUFFIXES,
                       args.check_captures, parse_capture_allow(args.capture_allow))
    except ToolError as error:
        print(f"could not run: {error}")
        return 2
    return emit(findings, "manifest check", args.json)


if __name__ == "__main__":
    sys.exit(main())
