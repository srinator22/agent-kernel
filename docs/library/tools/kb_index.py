#!/usr/bin/env python3
"""Local full-text knowledge-base index over Markdown, text, PDF and spreadsheet files, with ranked search.

Purpose: find a number, a part limit or a decision with its file and page without opening every document.
One SQLite file (FTS5, bm25 ranking) holds one row per Markdown `## ` section, per PDF page, per spreadsheet
sheet and per text file. The index is rebuildable from the documents, so keep it out of git.

Usage:
  python kb_index.py build  [--root DIR] [--db FILE] [--doc-dir NAME ...] [--exclude PREFIX ...] [--rebuild]
                            [--require-pdf]
  python kb_index.py search QUERY [--root DIR] [--db FILE] [--kind KIND] [--file SUBSTRING] [--limit N]
Query syntax: bare words are ANDed; "double quotes" make a phrase; OR between words is allowed; a trailing *
makes a prefix match. Identifiers and numbers with punctuation (SOME_SETTING, 4.2) match as phrases of their
parts because the index splits on punctuation. Unquoted multi-word queries list exact-phrase hits first.

Inputs: --root (default current directory). Markdown is indexed anywhere under it. Files inside the --doc-dir
folders (repeatable; default `datasheets`, `knowledge`, `reference`, relative to root) are also indexed when they
are .pdf, .xlsx or .txt, and the folder name becomes the row's kind (every other row has kind `doc`).
Folders starting with `.`, `.venv`, `node_modules`, `__pycache__` and the --exclude prefixes are never indexed.
Outputs: the index at --db (default <root>/.kb/index.sqlite) and a build summary or ranked hits on stdout.
Exit codes: 0 success, 1 a file could not be indexed, 2 the tool could not run (no FTS5 in this Python, no
index yet, a bad query, or with --require-pdf a PDF to index and no PDF library).
Dependencies: Python 3 standard library only for Markdown, text and search. ONE optional dependency each, never
required: `pymupdf` for PDF text extraction and `openpyxl` for spreadsheets. When one is missing, files of that
kind are skipped with a printed note (or exit 2 with --require-pdf) and everything else is still indexed.
Assumptions: the Python's sqlite3 was built with FTS5 (checked at start). Unchanged files (same sha256) are
skipped on rebuild and vanished files are removed from the index.
Validation source: ported from a project-local index tool that was used to answer datasheet and decision
questions; behaviour of the query builder and the section splitter is kept.
"""

from __future__ import annotations

import argparse
import hashlib
import re
import sqlite3
import sys
from dataclasses import dataclass, field
from pathlib import Path

DEFAULT_DOC_DIRS = ("datasheets", "knowledge", "reference")
SKIPPED_DIR_NAMES = {".venv", "__pycache__", "node_modules"}
BM25_WEIGHTS = "0.0, 3.0, 0.0, 1.0, 0.0"  # table order: path, title, page, text, kind
SNIPPET_TOKENS = 30
UNIT_LABELS = {".pdf": "p.", ".xlsx": "sheet "}
QUERY_PIECE = re.compile(r'"([^"]*)"|(\S+)')
WORD_PART = re.compile(r"[^\W_]+")

Row = tuple[int, str, str]  # (1-based ordinal, title, text)


class KbError(Exception):
    """The tool could not run at all (exit code 2)."""


@dataclass
class Source:
    path: Path
    rel: str
    kind: str
    format: str  # "md" | "txt" | "pdf" | "xlsx"


@dataclass
class Extracted:
    rows: list[Row]
    pages: int
    notes: list[str] = field(default_factory=list)


@dataclass
class BuildSummary:
    indexed: list[str] = field(default_factory=list)
    unchanged: list[str] = field(default_factory=list)
    removed: list[str] = field(default_factory=list)
    skipped: list[str] = field(default_factory=list)
    errors: list[str] = field(default_factory=list)
    rows_added: int = 0
    total_files: int = 0
    total_rows: int = 0


# ------------------------------------------------------------------ database

def sha256_of(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def require_fts5(connection: sqlite3.Connection) -> None:
    try:
        connection.execute("CREATE VIRTUAL TABLE temp._fts5_probe USING fts5(x)")
        connection.execute("DROP TABLE temp._fts5_probe")
    except sqlite3.OperationalError as error:
        raise KbError(f"SQLite {sqlite3.sqlite_version} in this Python has no FTS5 support ({error}). "
                      "Use a Python build whose sqlite3 includes FTS5.") from error


def open_db(db_path: Path, create: bool = True) -> sqlite3.Connection:
    if not create and not db_path.exists():
        raise KbError(f"no index at {db_path}. Build it first with: python kb_index.py build")
    db_path.parent.mkdir(parents=True, exist_ok=True)
    connection = sqlite3.connect(db_path)
    try:
        require_fts5(connection)
        connection.execute(
            "CREATE VIRTUAL TABLE IF NOT EXISTS docs USING fts5("
            "path UNINDEXED, title, page UNINDEXED, text, kind UNINDEXED, "
            "tokenize = 'unicode61 remove_diacritics 2')")
        connection.execute(
            "CREATE TABLE IF NOT EXISTS files("
            "path TEXT PRIMARY KEY, sha256 TEXT NOT NULL, mtime REAL NOT NULL, pages INTEGER NOT NULL)")
        connection.commit()
    except Exception:
        connection.close()
        raise
    return connection


# ----------------------------------------------------------------- discovery

def relative_path(path: Path, root: Path) -> str:
    return path.resolve().relative_to(root.resolve()).as_posix()


def wanted_format(rel: str, suffix: str, doc_dirs: tuple[str, ...]) -> str | None:
    top = rel.split("/", 1)[0]
    if suffix == ".md":
        return "md"
    if top in doc_dirs and suffix in (".pdf", ".xlsx", ".txt"):
        return suffix[1:]
    return None


def discover_sources(root: Path, doc_dirs: tuple[str, ...], exclude: tuple[str, ...], skip: Path | None = None
                     ) -> list[Source]:
    sources: list[Source] = []
    for path in sorted(root.rglob("*")):
        if not path.is_file() or (skip is not None and path.resolve() == skip.resolve()):
            continue
        rel = relative_path(path, root)
        parts = rel.split("/")
        if any(p in SKIPPED_DIR_NAMES or p.startswith(".") for p in parts[:-1]):
            continue
        if any(rel.startswith(prefix) for prefix in exclude):
            continue
        fmt = wanted_format(rel, path.suffix.lower(), doc_dirs)
        if fmt:
            top = parts[0]
            sources.append(Source(path, rel, top if top in doc_dirs else "doc", fmt))
    return sources


# ---------------------------------------------------------------- extraction

def split_markdown(text: str, fallback_title: str) -> list[Row]:
    """Split on `## ` headings outside code fences; text before the first is section 1, titled by `# `."""
    sections: list[tuple[str, list[str]]] = [(fallback_title, [])]
    in_fence = False
    for line in text.splitlines():
        if line.lstrip().startswith(("```", "~~~")):
            in_fence = not in_fence
        elif not in_fence and line.startswith("## "):
            sections.append((line[3:].strip(), []))
            continue
        elif not in_fence and line.startswith("# ") and len(sections) == 1 and sections[0][0] == fallback_title:
            sections[0] = (line[2:].strip() or fallback_title, sections[0][1])
        sections[-1][1].append(line)
    rows: list[Row] = []
    for title, lines in sections:
        body = "\n".join(lines).strip()
        if body:
            rows.append((len(rows) + 1, title, body))
    return rows


def read_text_file(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace")


def extract_markdown(source: Source) -> Extracted:
    rows = split_markdown(read_text_file(source.path), source.path.stem)
    return Extracted(rows, len(rows))


def extract_text(source: Source) -> Extracted:
    body = read_text_file(source.path).strip()
    rows = [(1, source.path.stem, body)] if body else []
    return Extracted(rows, len(rows))


def pymupdf_available() -> bool:
    try:
        import pymupdf  # noqa: F401
    except ImportError:
        return False
    return True


def openpyxl_available() -> bool:
    try:
        import openpyxl  # noqa: F401
    except ImportError:
        return False
    return True


def extract_pdf(source: Source) -> Extracted:
    import pymupdf  # optional dependency; the caller checked pymupdf_available()
    rows: list[Row] = []
    with pymupdf.open(source.path) as document:
        title = (document.metadata or {}).get("title", "").strip()
        if len(title) < 3:
            title = source.path.stem
        page_count = document.page_count
        for index, page in enumerate(document, start=1):
            text = page.get_text("text").strip()
            if text:
                rows.append((index, title, text))
    notes = []
    if page_count - len(rows):
        notes.append(f"{page_count - len(rows)} page(s) without extractable text")
    return Extracted(rows, page_count, notes)


def extract_xlsx(source: Source) -> Extracted:
    import openpyxl  # optional dependency; the caller checked openpyxl_available()
    workbook = openpyxl.load_workbook(source.path, read_only=True, data_only=True)
    rows: list[Row] = []
    try:
        for index, sheet in enumerate(workbook.worksheets, start=1):
            lines = []
            for cells in sheet.iter_rows(values_only=True):
                values = [str(v) for v in cells if v not in (None, "")]
                if values:
                    lines.append(" | ".join(values))
            if lines:
                rows.append((index, sheet.title, "\n".join(lines)))
        sheet_count = len(workbook.worksheets)
    finally:
        workbook.close()
    return Extracted(rows, sheet_count)


EXTRACTORS = {"md": extract_markdown, "txt": extract_text, "pdf": extract_pdf, "xlsx": extract_xlsx}
LIBRARY_CHECKS = {"pdf": ("pymupdf", "pymupdf_available"), "xlsx": ("openpyxl", "openpyxl_available")}


# --------------------------------------------------------------------- build

def build_index(root: Path, db_path: Path, doc_dirs: tuple[str, ...] = DEFAULT_DOC_DIRS,
                exclude: tuple[str, ...] = (), rebuild: bool = False, require_pdf: bool = False) -> BuildSummary:
    summary = BuildSummary()
    sources = discover_sources(root, doc_dirs, exclude, skip=db_path)
    connection = open_db(db_path)
    try:
        if rebuild:
            connection.execute("DELETE FROM docs")
            connection.execute("DELETE FROM files")
            connection.commit()
        known = dict(connection.execute("SELECT path, sha256 FROM files"))
        digests = {s.rel: sha256_of(s.path) for s in sources}
        todo = []
        for source in sources:
            if known.get(source.rel) == digests[source.rel]:
                summary.unchanged.append(source.rel)
            else:
                todo.append(source)
        available = {fmt: globals()[check]() for fmt, (_, check) in LIBRARY_CHECKS.items()}
        if require_pdf and any(s.format == "pdf" for s in todo) and not available["pdf"]:
            raise KbError("pymupdf is not installed in this Python and --require-pdf was given. "
                          "Install it with: python -m pip install pymupdf")
        for gone in sorted(set(known) - {s.rel for s in sources}):
            connection.execute("DELETE FROM docs WHERE path = ?", (gone,))
            connection.execute("DELETE FROM files WHERE path = ?", (gone,))
            summary.removed.append(gone)
        for source in todo:
            if source.format in available and not available[source.format]:
                summary.skipped.append(f"{source.rel}: {LIBRARY_CHECKS[source.format][0]} is not installed")
                continue
            try:
                extracted = EXTRACTORS[source.format](source)
            except Exception as error:  # one bad file must not stop the build
                summary.errors.append(f"{source.rel}: {type(error).__name__}: {error}")
                continue
            connection.execute("DELETE FROM docs WHERE path = ?", (source.rel,))
            connection.executemany(
                "INSERT INTO docs(path, title, page, text, kind) VALUES (?, ?, ?, ?, ?)",
                [(source.rel, title, page, text, source.kind) for page, title, text in extracted.rows])
            connection.execute(
                "INSERT OR REPLACE INTO files(path, sha256, mtime, pages) VALUES (?, ?, ?, ?)",
                (source.rel, digests[source.rel], source.path.stat().st_mtime, extracted.pages))
            summary.indexed.append(source.rel)
            summary.rows_added += len(extracted.rows)
            summary.skipped.extend(f"{source.rel}: {note}" for note in extracted.notes)
        connection.commit()
        summary.total_files = connection.execute("SELECT COUNT(*) FROM files").fetchone()[0]
        summary.total_rows = connection.execute("SELECT COUNT(*) FROM docs").fetchone()[0]
    finally:
        connection.close()
    return summary


def print_summary(summary: BuildSummary, db_path: Path) -> None:
    print(f"Index: {db_path}")
    print(f"Indexed {len(summary.indexed)} file(s), {summary.rows_added} page/section rows added")
    print(f"Unchanged (skipped): {len(summary.unchanged)}")
    print(f"Removed (file gone): {len(summary.removed)}")
    for gone in summary.removed:
        print(f"  removed: {gone}")
    print(f"Notes/skipped: {len(summary.skipped)}")
    for item in summary.skipped:
        print(f"  note: {item}")
    for item in summary.errors:
        print(f"  ERROR: {item}")
    print(f"Index now holds {summary.total_files} file(s), {summary.total_rows} row(s)")


# -------------------------------------------------------------------- search

def build_match_expression(query: str) -> str:
    """Turn a user query into a safe FTS5 MATCH expression ("" if no terms)."""
    terms: list[str] = []
    for phrase, bare in QUERY_PIECE.findall(query):
        if bare == "OR":
            if terms and terms[-1] != "OR":
                terms.append("OR")
            continue
        parts = WORD_PART.findall(phrase or bare)
        if not parts:
            continue
        prefix = "*" if bare.endswith("*") and not phrase else ""
        terms.append('"' + " ".join(parts) + '"' + prefix)
    while terms and terms[-1] == "OR":
        terms.pop()
    expression = ""
    for index, term in enumerate(terms):
        if index and term != "OR" and terms[index - 1] != "OR":
            expression += " AND "
        elif index:
            expression += " "
        expression += term
    return expression


def build_phrase_expression(query: str) -> str | None:
    """The whole query as one phrase, or None when that adds nothing."""
    if '"' in query or "*" in query or re.search(r"\bOR\b", query):
        return None
    parts = WORD_PART.findall(query)
    return '"' + " ".join(parts) + '"' if len(parts) >= 2 else None


def location_label(path: str, page: int) -> str:
    return f"{UNIT_LABELS.get(Path(path).suffix.lower(), 'sec ')}{page}"


def escape_like(text: str) -> str:
    return text.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")


def search(connection: sqlite3.Connection, expression: str, kind: str | None, file_part: str | None,
           limit: int) -> list[sqlite3.Row]:
    sql = ("SELECT path, page, title, kind, "
           f"bm25(docs, {BM25_WEIGHTS}) AS score, "
           f"snippet(docs, 3, '[', ']', ' ... ', {SNIPPET_TOKENS}) AS text_snippet, "
           "snippet(docs, 1, '[', ']', ' ... ', 12) AS title_snippet "
           "FROM docs WHERE docs MATCH ?")
    arguments: list[object] = [expression]
    if kind:
        sql += " AND kind = ?"
        arguments.append(kind)
    if file_part:
        sql += " AND path LIKE ? ESCAPE '\\'"
        arguments.append("%" + escape_like(file_part.replace("\\", "/")) + "%")
    sql += " ORDER BY score LIMIT ?"
    arguments.append(limit)
    connection.row_factory = sqlite3.Row
    return connection.execute(sql, arguments).fetchall()


def search_phrase_first(connection: sqlite3.Connection, query: str, expression: str, kind: str | None,
                        file_part: str | None, limit: int) -> list[sqlite3.Row]:
    """Exact-phrase hits first (bm25 order), then all-words hits, no repeats."""
    phrase = build_phrase_expression(query)
    hits: list[sqlite3.Row] = []
    seen: set[tuple[str, int]] = set()
    if phrase:
        for row in search(connection, phrase, kind, file_part, limit):
            seen.add((row["path"], row["page"]))
            hits.append(row)
    if len(hits) < limit:
        for row in search(connection, expression, kind, file_part, limit + len(seen)):
            if (row["path"], row["page"]) not in seen and len(hits) < limit:
                hits.append(row)
    return hits


def format_hit(rank: int, row: sqlite3.Row) -> str:
    snippet = " ".join(row["text_snippet"].split())
    if "[" not in snippet and "[" in row["title_snippet"]:
        snippet = "(title) " + " ".join(row["title_snippet"].split())
    return (f"{rank:>2}. {row['path']}  {location_label(row['path'], row['page'])}"
            f"  [{row['kind']}]  bm25 {row['score']:.2f}\n    {row['title']}\n    {snippet}")


# ----------------------------------------------------------------------- CLI

def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Local full-text knowledge-base index and search.")
    sub = parser.add_subparsers(dest="command", required=True)

    def common(p: argparse.ArgumentParser) -> None:
        p.add_argument("--root", type=Path, default=Path("."), help="project folder (default: current directory)")
        p.add_argument("--db", type=Path, default=None, help="index file (default: <root>/.kb/index.sqlite)")

    b = sub.add_parser("build", help="build or update the index")
    common(b)
    b.add_argument("--doc-dir", action="append", default=None, metavar="NAME",
                   help=f"folder whose pdf/xlsx/txt files are indexed (repeatable; default {', '.join(DEFAULT_DOC_DIRS)})")
    b.add_argument("--exclude", action="append", default=[], metavar="PREFIX",
                   help="root-relative path prefix never indexed (repeatable)")
    b.add_argument("--rebuild", action="store_true", help="drop everything and index all files again")
    b.add_argument("--require-pdf", action="store_true", help="exit 2 when a PDF needs indexing and pymupdf is missing")

    s = sub.add_parser("search", help="search the index with bm25 ranking")
    common(s)
    s.add_argument("query", help='words (ANDed) and "quoted phrases"')
    s.add_argument("--kind", help="only this kind of document (a doc-dir name, or doc)")
    s.add_argument("--file", dest="file_part", metavar="SUBSTRING", help="only paths containing this text")
    s.add_argument("--limit", type=int, default=10, help="hits to show (default 10)")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    root = args.root.resolve()
    db_path = args.db or root / ".kb" / "index.sqlite"
    try:
        if args.command == "build":
            doc_dirs = tuple(args.doc_dir) if args.doc_dir else DEFAULT_DOC_DIRS
            summary = build_index(root, db_path, doc_dirs, tuple(args.exclude), args.rebuild, args.require_pdf)
            print_summary(summary, db_path)
            return 1 if summary.errors else 0
        expression = build_match_expression(args.query)
        if not expression:
            raise KbError("the query has no searchable words")
        connection = open_db(db_path, create=False)
        try:
            hits = search_phrase_first(connection, args.query, expression, args.kind, args.file_part, args.limit)
        except sqlite3.OperationalError as error:
            raise KbError(f"could not run query {expression!r}: {error}") from error
        finally:
            connection.close()
        if not hits:
            print("no matches")
            return 0
        for rank, row in enumerate(hits, start=1):
            print(format_hit(rank, row))
        return 0
    except KbError as error:
        print(f"kb_index: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(errors="replace")
    sys.exit(main())
