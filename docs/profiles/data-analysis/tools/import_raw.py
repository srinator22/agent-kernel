#!/usr/bin/env python3
"""Import raw instrument files into a session folder, hash-verified, with a README row each.

Purpose: enforce rules DA-1 and DA-3 of the data-analysis profile. A raw file is copied byte for byte
into <session>/raw/, never over an existing file; the copy is re-read and its SHA-256 compared with the
source; only then does the session README gain a row (path, SHA-256, size, date, condition, version,
load) for the hash re-check gate to walk. The source is only ever opened for reading.

Usage:
  python import_raw.py --session DIR --date YYYY-MM-DD [--condition TEXT] [--version TEXT] [--load TEXT]
                       [--raw-subdir raw] SOURCE [SOURCE ...]

Inputs: the session folder (created when absent), the date, and the facts DA-3 asks for; a fact not given
is written as Unknown, never guessed. One or more source files.
Outputs: one line per file and a summary. Exit 0 every file imported; 1 a source cannot be read or a
copy failed verification (the bad copy is removed, no row is written for it); 2 refused before anything
was copied (usage error, an existing destination, two sources with one name).
Dependencies: Python 3 standard library only.
Assumptions: file names are unique within a session; parsing, malformed-row handling and analysis belong
to the project's analysers, not here. Several files per call are planned together so one clash imports
nothing. Port origin: generic part of a prior embedded controller firmware project's import tool.
"""

from __future__ import annotations

import argparse
import hashlib
import os
import re
import sys
from pathlib import Path

HEADER = "| File | SHA-256 | Bytes | Date | Condition | Version | Load |"
SEPARATOR = "|---|---|---|---|---|---|---|"
CHUNK = 1 << 20


class Refusal(Exception):
    """The import cannot start; nothing has been copied."""


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for block in iter(lambda: handle.read(CHUNK), b""):
            digest.update(block)
    return digest.hexdigest()


def copy_exclusive(source: Path, dest: Path) -> None:
    """Copy bytes to a new file; 'xb' makes an existing destination an error instead of an overwrite."""
    dest.parent.mkdir(parents=True, exist_ok=True)
    with open(source, "rb") as src, open(dest, "xb") as out:
        for block in iter(lambda: src.read(CHUNK), b""):
            out.write(block)
        out.flush()
        os.fsync(out.fileno())


def plan(session: Path, subdir: str, sources: list[Path]) -> list[tuple[Path, Path]]:
    pairs, names = [], {}
    for source in sources:
        if source.name in names:
            raise Refusal(f"{source} and {names[source.name]} have the same name {source.name!r}")
        names[source.name] = source
        dest = session / subdir / source.name
        if os.path.lexists(dest):
            raise Refusal(f"{dest} already exists; raw files are never replaced")
        pairs.append((source, dest))
    return pairs


def add_rows(readme: Path, rows: list[str]) -> None:
    """Insert rows after the last line of the File/SHA-256 table, or append a new table."""
    text = readme.read_text(encoding="utf-8") if readme.exists() else f"# {readme.parent.name}\n"
    lines = text.splitlines()
    if HEADER in lines:
        at = lines.index(HEADER) + 1
        while at < len(lines) and lines[at].startswith("|"):
            at += 1
        lines[at:at] = rows
    else:
        lines += ["", HEADER, SEPARATOR, *rows]
    tmp = readme.with_name(readme.name + ".tmp")
    tmp.write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
    os.replace(tmp, readme)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Import raw files, hash-verified, with a session README row.")
    parser.add_argument("--session", type=Path, required=True)
    parser.add_argument("--date", required=True, help="YYYY-MM-DD")
    parser.add_argument("--condition", default="Unknown")
    parser.add_argument("--version", default="Unknown", help="firmware or software version")
    parser.add_argument("--load", default="Unknown", help="load or configuration")
    parser.add_argument("--raw-subdir", default="raw")
    parser.add_argument("sources", nargs="+", type=Path)
    args = parser.parse_args(argv)
    if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", args.date):
        parser.error("--date must be YYYY-MM-DD")
    cells = [c.replace("|", "/").replace("\n", " ") for c in (args.date, args.condition, args.version, args.load)]
    try:
        pairs = plan(args.session, args.raw_subdir, args.sources)
    except Refusal as error:
        print(f"import_raw: refused: {error}", file=sys.stderr)
        return 2
    unreadable = [s for s, _ in pairs if not s.is_file()]
    if unreadable:
        for source in unreadable:
            print(f"import_raw: cannot read {source}: not a file", file=sys.stderr)
        return 1
    rows, failed = [], 0
    for source, dest in pairs:
        try:
            expected = sha256_file(source)
            copy_exclusive(source, dest)
            actual = sha256_file(dest)
        except OSError as error:
            print(f"import_raw: {source}: {error}", file=sys.stderr)
            failed += 1
            continue
        if actual != expected:
            dest.unlink()  # our own failed copy; leaving it would block a retry
            print(f"import_raw: {source}: hash mismatch (source {expected}, copy {actual}); copy removed", file=sys.stderr)
            failed += 1
            continue
        rows.append(f"| {args.raw_subdir}/{dest.name} | {expected} | {dest.stat().st_size} | " + " | ".join(cells) + " |")
        print(f"import_raw: {source.name}: copied, SHA-256 {expected}")
    if rows:
        add_rows(args.session / "README.md", rows)
    if failed:
        print(f"import_raw: FAIL {failed} of {len(pairs)} file(s) not imported")
        return 1
    print(f"import_raw: PASS {len(rows)} file(s) imported")
    return 0


if __name__ == "__main__":
    sys.exit(main())
