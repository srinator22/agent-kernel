#!/usr/bin/env python3
"""Validate the defect-memory table (docs/DEFECT_MEMORY.md): a fix without a well-formed row is not done.

Purpose: keep the table the bughunt procedure reads trustworthy. Memory that rots silently (a gap in the
ids, an empty defence cell, a "fixed" row that names no commit, a defence that points at a file that no
longer exists) stops being queryable memory.
Inputs: the Markdown file (default <root>/docs/DEFECT_MEMORY.md). Only the table under the `## Rows` heading is
judged (the whole file when there is no such heading); the format example in the file's prose is not.
Table format (the template's): columns
  ID | Symptom and discovery route | Root cause | Permanent defence | Status
IDs are M-nnn (module), I-nnn (interface), U-nnn (UI), W-nnn (workflow), sequential per prefix from 001,
never reused. Status is `open`, `fixed (<commit hash>)` or `accepted (<reason and owner>)`, optionally with
`superseded by <ID>`; a superseded row stays.
Checks (each FAIL names the row):
  - the header is exactly the expected columns; every row has the right cell count; no cell is empty;
  - ids are well formed, sequential per prefix with no gap, no duplicate;
  - status is one of the forms above; `fixed` names a hex commit hash; `accepted` gives a reason;
  - `superseded by <ID>` points at a row that exists;
  - for a `fixed` row, every backticked path in the defence cell (a token with a `/` and a file extension, no
    spaces or wildcards) exists under --root (switch off with --no-path-check);
  - rows with an EXAMPLE id are skipped (they are the template's placeholders); --no-examples fails if any
    remain, for an initialised project.
Outputs: one line per finding on stdout (`FAIL  <aspect>: <message>`), then `PASS` or `FAIL` summary.
Exit codes: 0 pass, 1 check failed, 2 could not run (file missing, no table).
Dependencies: Python 3 standard library only.
Assumptions: cells contain no unescaped pipe character (write `\\|` for a literal one).
Validation source: ported from a checker for a project-specific column layout; adapted to the template's
column layout and ID scheme.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

CHECK = "defect_memory"
COLUMNS = ("id", "symptom and discovery route", "root cause", "permanent defence", "status")
PREFIXES = "MIUW"
ID_RE = re.compile(rf"^([{PREFIXES}])-(\d{{3,}})$")
EXAMPLE_RE = re.compile(rf"^[{PREFIXES}]-000 EXAMPLE$")
SUPERSEDED_RE = re.compile(rf"[,;]?\s*superseded by\s+([{PREFIXES}]-\d{{3,}})", re.IGNORECASE)
FIXED_RE = re.compile(r"^fixed \(\s*[^)]*\b[0-9a-f]{7,40}\b[^)]*\)$", re.IGNORECASE)
ACCEPTED_RE = re.compile(r"^accepted \(\s*\S[^)]*\)$", re.IGNORECASE)
BACKTICK_RE = re.compile(r"`([^`]+)`")
UNESCAPED_PIPE = re.compile(r"(?<!\\)\|")
SEPARATOR_LINE = re.compile(r"[|\s:-]+")


class CouldNotRun(Exception):
    pass


def split_cells(line: str) -> list[str]:
    inner = line.strip()
    inner = inner[1:] if inner.startswith("|") else inner
    inner = inner[:-1] if inner.endswith("|") and not inner.endswith("\\|") else inner
    return [c.strip().replace("\\|", "|") for c in UNESCAPED_PIPE.split(inner)]


def rows_section(text: str) -> str:
    """The text after the `## Rows` heading up to the next `## ` heading, or the whole text."""
    lines = text.splitlines()
    start = next((i for i, ln in enumerate(lines) if re.match(r"^##\s+Rows\s*$", ln)), None)
    if start is None:
        return text
    end = next((i for i in range(start + 1, len(lines)) if lines[i].startswith("## ")), len(lines))
    return "\n".join(lines[start + 1:end])


def parse(text: str) -> tuple[list[str], list[list[str]]]:
    table = [ln for ln in rows_section(text).splitlines() if ln.lstrip().startswith("|")]
    if not table:
        return [], []
    header = split_cells(table[0])
    rows = [split_cells(ln) for ln in table[1:] if not SEPARATOR_LINE.fullmatch(ln.strip())]
    return header, rows


def defence_paths(cell: str) -> list[str]:
    found = []
    for token in BACKTICK_RE.findall(cell):
        token = token.strip()
        if not re.search(r"[\s*?<>{}|]", token) and "/" in token and not token.startswith(("http", "-")) \
                and re.search(r"\.[A-Za-z0-9]+$", token.rsplit("/", 1)[-1]):
            found.append(token)
    return found


def check(text: str, root: Path, path_check: bool = True, forbid_examples: bool = False) -> list[tuple[str, str]]:
    """(aspect, message) per FAIL; empty means the table is sound."""
    header, rows = parse(text)
    if not header:
        raise CouldNotRun("no table found (expected one under the `## Rows` heading)")
    if tuple(c.lower() for c in header) != COLUMNS:
        return [("header", f"table header is {header}, expected {[c.title() if c != 'id' else 'ID' for c in COLUMNS]}")]
    fails: list[tuple[str, str]] = []
    ids: set[str] = set()
    next_number = {p: 1 for p in PREFIXES}
    real_rows = []
    for position, cells in enumerate(rows, start=1):
        label = cells[0] if cells and cells[0] else f"row {position}"
        if len(cells) != len(COLUMNS):
            fails.append(("cells", f"{label}: {len(cells)} cells, expected {len(COLUMNS)}"))
            continue
        row = dict(zip(COLUMNS, cells))
        if EXAMPLE_RE.match(row["id"]):
            if forbid_examples:
                fails.append(("example", f"{label}: placeholder row still present"))
            continue
        real_rows.append((label, row))
        match = ID_RE.match(row["id"])
        if not match:
            fails.append(("id", f"{label}: id must look like M-001, I-001, U-001 or W-001"))
        elif row["id"] in ids:
            fails.append(("duplicate", f"{label}: id is used twice (ids are never reused)"))
        else:
            ids.add(row["id"])
            prefix, number = match.group(1), int(match.group(2))
            if number != next_number[prefix]:
                fails.append(("sequence", f"{label}: expected {prefix}-{next_number[prefix]:03d} here "
                                          "(sequential per prefix, no gaps)"))
            next_number[prefix] = number + 1
        for column in COLUMNS:
            if not row[column]:
                fails.append(("empty", f"{label}: empty cell '{column}'"))
    for label, row in real_rows:
        status = row["status"]
        if not status:
            continue
        links = SUPERSEDED_RE.findall(status)
        base = SUPERSEDED_RE.sub("", status).strip(" ,;")
        for target in links:
            if target not in ids:
                fails.append(("superseded", f"{label}: superseded by {target}, which is not a row"))
        if base.lower() == "open":
            pass
        elif base.lower().startswith("fixed"):
            if not FIXED_RE.match(base):
                fails.append(("status", f"{label}: 'fixed' must name the commit, e.g. fixed (abc1234)"))
            elif path_check:
                for name in defence_paths(row["permanent defence"]):
                    if not (root / name).exists():
                        fails.append(("defence", f"{label}: defence names {name}, which does not exist"))
        elif base.lower().startswith("accepted"):
            if not ACCEPTED_RE.match(base):
                fails.append(("status", f"{label}: 'accepted' must give the reason and owner in parentheses"))
        elif base or not links:
            fails.append(("status", f"{label}: status '{status}' is not open, fixed (<commit>) or "
                                    "accepted (<reason>)"))
    return fails


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Validate the defect-memory table (docs/DEFECT_MEMORY.md).")
    parser.add_argument("--root", default=".", help="repository root (default: current directory)")
    parser.add_argument("--file", default=None, help="table file (default: <root>/docs/DEFECT_MEMORY.md)")
    parser.add_argument("--no-path-check", action="store_true",
                        help="do not require paths named in a fixed row's defence to exist")
    parser.add_argument("--no-examples", action="store_true", help="fail while EXAMPLE placeholder rows remain")
    args = parser.parse_args(argv)
    root = Path(args.root).resolve()
    path = Path(args.file) if args.file else root / "docs" / "DEFECT_MEMORY.md"
    try:
        if not path.is_file():
            raise CouldNotRun(f"{path} is missing")
        text = path.read_text(encoding="utf-8")
        fails = check(text, root, path_check=not args.no_path_check, forbid_examples=args.no_examples)
    except CouldNotRun as error:
        print(f"{CHECK}: could not run: {error}", file=sys.stderr)
        return 2
    except UnicodeDecodeError as error:
        print(f"{CHECK}: could not run: {path} is not UTF-8 ({error})", file=sys.stderr)
        return 2
    for aspect, message in fails:
        print(f"FAIL  {CHECK}.{aspect}: {message}")
    if fails:
        print(f"{CHECK}: FAIL ({len(fails)} finding(s))")
        return 1
    _, rows = parse(text)
    real = sum(1 for r in rows if r and not EXAMPLE_RE.match(r[0]))
    print(f"{CHECK}: PASS ({real} row(s), {len(rows) - real} example row(s))")
    return 0


if __name__ == "__main__":
    sys.exit(main())
