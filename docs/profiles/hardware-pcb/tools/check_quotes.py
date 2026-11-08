#!/usr/bin/env python3
"""Check that quoted text in design notes appears in the stored document it cites (rule PCB-2).

Purpose
    A quote in a design note must actually appear in the stored document it
    cites, on the page it cites. Catches fabricated text and paraphrases
    presented as datasheet quotes.

Inputs
    PATH...           Markdown files or folders (folders are scanned
                      recursively for *.md, skipping .git, .venv,
                      node_modules and __pycache__). Default: --root.
    --root DIR        design folder (default: current directory). A citation
                      path resolves first relative to the citing file's
                      folder, then relative to --root; the first existing
                      file wins.
    --json            print findings as JSON

Citation format
    A straight double-quoted string immediately followed (optional
    whitespace) by a bracketed citation of a file path and an optional page:
        "Output current is limited to 3.5 A" [datasheets/power/tps54331.pdf p.12]
        "quoted text" [datasheets/power/x.pdf, p. 12]
        "quoted text" [datasheets/power/x.pdf page 12]
        "quoted text" [notes/source.txt]
    The path must contain no spaces or commas and end in a file suffix.
    Fenced code blocks and inline code spans are ignored. A quoted string not
    followed by a bracketed citation is not a citation and is ignored.

Verification
    Quote and source text are normalised (Unicode NFKC, lowercase, every
    non-alphanumeric character removed) so line-break hyphenation, spacing
    and punctuation do not matter. The quote is verified when its normalised
    form is a substring of the normalised source.
    - Text sources (.md, .txt, .csv and other text): the quote is verified
      against the whole file; a cited page cannot be checked (INFO).
    - .pdf: text is extracted per page. With a cited page the quote must be
      on that page (1-based); on another page or beyond the page count is a
      FAIL. Without a cited page every page is searched and a hit is a PASS
      with a WARN to cite the page.
    - Missing source file: FAIL. Binary source (.xlsx, .png, ...), a PDF
      without extractable text, or pymupdf not installed: UNCHECKED.

Outputs
    One line per finding: LEVEL, file:line of the citation, message; then a
    summary count. Levels: PASS, WARN, FAIL, INFO, UNCHECKED. Exit 0 no FAIL
    and no UNCHECKED, 1 at least one FAIL, 2 no FAIL but at least one
    UNCHECKED or the tool could not run (an unverified quote is never a
    pass). No citations found: "no cited quotes found", exit 0.

Dependencies
    Python 3.11+ standard library. PDF text needs the optional pymupdf
    package, imported lazily; without it PDF quotes are UNCHECKED.

Assumptions
    Quotes shorter than 1 or longer than 500 characters, or spanning lines,
    are not read as citations. A quote with no letters or digits cannot be
    verified and is UNCHECKED. A PDF is searched by its extracted text layer;
    scanned pages without a text layer cannot be verified.

Validation source
    idea re-expressed from a public knowledge-base citation validator;
    behaviour pinned by tests/test_check_quotes.py on made-up fixtures.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import unicodedata
from dataclasses import asdict, dataclass
from pathlib import Path

CHECK = "quotes"
LEVELS = ("PASS", "WARN", "FAIL", "INFO", "UNCHECKED")
SKIP_DIRS = {".git", ".venv", "node_modules", "__pycache__"}
BINARY_SUFFIXES = {
    ".xlsx", ".xlsm", ".xls", ".docx", ".doc", ".pptx", ".ppt", ".zip", ".gz", ".7z", ".rar",
    ".png", ".jpg", ".jpeg", ".gif", ".bmp", ".tif", ".tiff", ".webp", ".step", ".stp",
    ".kicad_pcb", ".bin", ".exe", ".dll", ".so",
}
CITATION = re.compile(
    r'"([^"\n]{1,500})"\s*\[([^\]\s,]+\.[A-Za-z0-9]{1,5})(?:,?\s*(?:p\.|page)\s*(\d+))?\]')
INLINE_CODE = re.compile(r"(`+)(.+?)\1")
FENCE = re.compile(r"^\s*(`{3,}|~{3,})")
QUOTE_SHOWN = 50


class ToolError(Exception):
    """The tool could not run at all (exit code 2)."""


class PdfUnavailable(Exception):
    """PDF text cannot be extracted (pymupdf missing or the file unreadable)."""


@dataclass(frozen=True)
class Finding:
    level: str
    check: str
    location: str
    message: str


@dataclass(frozen=True)
class Citation:
    file: Path
    line: int
    quote: str
    source: str          # as written
    page: int | None


def normalise(text: str) -> str:
    folded = unicodedata.normalize("NFKC", text).lower()
    return "".join(ch for ch in folded if ch.isalnum())


def parse_citations(text: str, file: Path) -> list[Citation]:
    """Cited quotes in a Markdown text, with code fences and inline code skipped."""
    citations: list[Citation] = []
    fence: str | None = None
    for number, line in enumerate(text.splitlines(), start=1):
        marker = FENCE.match(line)
        if fence is not None:
            if marker and marker.group(1)[0] == fence[0] and len(marker.group(1)) >= len(fence) \
                    and not line.strip().strip(fence[0]):
                fence = None
            continue
        if marker:
            fence = marker.group(1)
            continue
        visible = INLINE_CODE.sub(lambda m: " " * len(m.group(0)), line)
        for match in CITATION.finditer(visible):
            page = int(match.group(3)) if match.group(3) else None
            citations.append(Citation(file, number, match.group(1), match.group(2), page))
    return citations


def extract_pdf_pages(path: Path) -> list[str]:
    """Text of each page of a PDF (index 0 is page 1). Raises PdfUnavailable."""
    module = None
    for name in ("pymupdf", "fitz"):
        try:
            module = __import__(name)
        except ImportError:
            continue
        if hasattr(module, "open"):
            break
        module = None
    if module is None:
        raise PdfUnavailable("pymupdf is not installed")
    try:
        with module.open(str(path)) as document:
            return [page.get_text() for page in document]
    except Exception as error:   # pymupdf raises its own error types for damaged files
        raise PdfUnavailable(f"cannot read PDF: {error}") from error


def _resolve(source: str, citing: Path, root: Path) -> Path | None:
    relative = source.replace("\\", "/")
    for base in (citing.parent, root):
        candidate = base / relative
        if candidate.is_file():
            return candidate
    return None


def _shown(quote: str) -> str:
    text = " ".join(quote.split())
    return f'"{text[:QUOTE_SHOWN]}..."' if len(text) > QUOTE_SHOWN else f'"{text}"'


def _location(citation: Citation, root: Path) -> str:
    try:
        name = citation.file.resolve().relative_to(root.resolve()).as_posix()
    except ValueError:
        name = citation.file.as_posix()
    return f"{name}:{citation.line}"


def _pages_text(pages: list[int]) -> str:
    return ("page " if len(pages) == 1 else "pages ") + ", ".join(str(p) for p in pages)


def _check_pdf(citation: Citation, needle: str, pages: list[str], where: str) -> list[Finding]:
    shown = _shown(citation.quote)
    if not any(page.strip() for page in pages):
        return [Finding("UNCHECKED", f"{CHECK}.no_text", where,
                        f"{citation.source}: no extractable text (scanned PDF?), {shown} not verified")]
    hits = [number for number, page in enumerate(pages, start=1) if needle in normalise(page)]
    if citation.page is None:
        if not hits:
            return [Finding("FAIL", f"{CHECK}.mismatch", where,
                            f"{shown} not found in {citation.source}")]
        return [Finding("PASS", f"{CHECK}.match", where, f"{shown} found in {citation.source}"),
                Finding("WARN", f"{CHECK}.no_page", where,
                        f"cite the page: {shown} is on {_pages_text(hits)} of {citation.source}")]
    if not 1 <= citation.page <= len(pages):
        return [Finding("FAIL", f"{CHECK}.page_range", where,
                        f"{citation.source}: cited page {citation.page} is outside the document's "
                        f"{len(pages)} pages")]
    if citation.page in hits:
        return [Finding("PASS", f"{CHECK}.match", where,
                        f"{shown} found in {citation.source} page {citation.page}")]
    if hits:
        return [Finding("FAIL", f"{CHECK}.wrong_page", where,
                        f"{shown} found on {_pages_text(hits)}, cited page {citation.page} "
                        f"of {citation.source}")]
    return [Finding("FAIL", f"{CHECK}.mismatch", where, f"{shown} not found in {citation.source}")]


def _check_text(citation: Citation, needle: str, haystack: str, where: str) -> list[Finding]:
    shown = _shown(citation.quote)
    if needle not in haystack:
        return [Finding("FAIL", f"{CHECK}.mismatch", where, f"{shown} not found in {citation.source}")]
    findings = [Finding("PASS", f"{CHECK}.match", where, f"{shown} found in {citation.source}")]
    if citation.page is not None:
        findings.append(Finding("INFO", f"{CHECK}.page_unchecked", where,
                                f"{citation.source}: page {citation.page} not checked "
                                f"(a text source has no pages)"))
    return findings


def check_citations(citations: list[Citation], root: Path) -> list[Finding]:
    root = Path(root)
    findings: list[Finding] = []
    pdf_cache: dict[Path, list[str] | str] = {}      # pages, or the reason they are unavailable
    text_cache: dict[Path, str | None] = {}          # normalised text, or None for binary
    for citation in citations:
        where = _location(citation, root)
        shown = _shown(citation.quote)
        needle = normalise(citation.quote)
        target = _resolve(citation.source, citation.file, root)
        if target is None:
            findings.append(Finding("FAIL", f"{CHECK}.missing_source", where,
                                    f"cited source does not exist: {citation.source} ({shown})"))
            continue
        suffix = target.suffix.lower()
        if not needle:
            findings.append(Finding("UNCHECKED", f"{CHECK}.empty_quote", where,
                                    f"{shown} has no letters or digits to verify"))
            continue
        if suffix == ".pdf":
            if target not in pdf_cache:
                try:
                    pdf_cache[target] = extract_pdf_pages(target)
                except PdfUnavailable as error:
                    pdf_cache[target] = str(error)
            pages = pdf_cache[target]
            if isinstance(pages, str):
                findings.append(Finding("UNCHECKED", f"{CHECK}.pdf_unavailable", where,
                                        f"{citation.source}: {pages}, {shown} not verified"))
            else:
                findings.extend(_check_pdf(citation, needle, pages, where))
            continue
        if target not in text_cache:
            data = target.read_bytes()
            binary = suffix in BINARY_SUFFIXES or b"\x00" in data[:8192]
            text_cache[target] = None if binary else normalise(data.decode("utf-8", errors="replace"))
        haystack = text_cache[target]
        if haystack is None:
            findings.append(Finding("UNCHECKED", f"{CHECK}.binary_source", where,
                                    f"cannot extract text from {suffix or 'this file type'}: "
                                    f"{citation.source}, {shown} not verified"))
            continue
        findings.extend(_check_text(citation, needle, haystack, where))
    return findings


def collect_files(paths: list[Path]) -> list[Path]:
    """Markdown files named by the arguments; folders are scanned recursively."""
    files: list[Path] = []
    for path in paths:
        if path.is_file():
            files.append(path)
        elif path.is_dir():
            for folder, dirs, names in os.walk(path):
                dirs[:] = sorted(d for d in dirs if d not in SKIP_DIRS)
                files.extend(Path(folder) / n for n in sorted(names) if n.lower().endswith(".md"))
        else:
            raise ToolError(f"input path not found: {path}")
    return files


def run(paths: list[Path], root: Path) -> list[Finding]:
    root = Path(root)
    if not root.is_dir():
        raise ToolError(f"root folder not found: {root}")
    citations: list[Citation] = []
    for file in collect_files([Path(p) for p in paths] or [root]):
        try:
            text = file.read_text(encoding="utf-8", errors="replace")
        except OSError as error:
            raise ToolError(f"cannot read {file}: {error}") from error
        citations.extend(parse_citations(text, file))
    return check_citations(citations, root)


def emit(findings: list[Finding], title: str, as_json: bool) -> int:
    counts = {level: sum(f.level == level for f in findings) for level in LEVELS}
    if as_json:
        print(json.dumps({"title": title, "counts": counts, "findings": [asdict(f) for f in findings]}, indent=2))
    else:
        if not findings:
            print("no cited quotes found")
        for f in findings:
            print(f"{f.level:<9} {f.location}: {f.message}")
        print("  ".join(f"{level}: {counts[level]}" for level in LEVELS))
    if counts["FAIL"]:
        return 1
    return 2 if counts["UNCHECKED"] else 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.strip().splitlines()[0])
    parser.add_argument("paths", nargs="*", type=Path, metavar="PATH",
                        help="Markdown files or folders (default: --root)")
    parser.add_argument("--root", type=Path, default=Path.cwd(), help="design folder (default: current directory)")
    parser.add_argument("--json", action="store_true", help="print findings as JSON")
    args = parser.parse_args(argv)
    try:
        findings = run(args.paths, args.root)
    except ToolError as error:
        print(f"could not run: {error}")
        return 2
    return emit(findings, "quote check", args.json)


if __name__ == "__main__":
    sys.exit(main())
