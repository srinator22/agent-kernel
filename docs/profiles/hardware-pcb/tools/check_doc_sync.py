#!/usr/bin/env python3
"""Check that design documents carry no superseded terms and agree with the parameters file (rule PCB-3).

Purpose
    After a decision changes a design number or name, old statements linger
    in other documents. This check FAILs a document line that still uses a
    superseded term, states a hole coordinate the parameters file does not
    have, or places the connector wall on the wrong edge, and FAILs an en or
    em dash in the project's own text files.

Inputs
    --root DIR     design folder (default: current directory); document paths
                   in the sync file are relative to it
    --sync FILE    sync file (default: <root>/doc_sync.toml), format below
    --params FILE  parameters.toml (default: <root>/parameters.toml when it
                   exists; without one the hole and edge checks are skipped)
    --no-typography  skip the dash scan
    --json         print findings as JSON

doc_sync.toml format
    [doc_sync]
    docs = ["README.md", "ARCHITECTURE.md"]       # required, root-relative
    history_words = ["rejected", "superseded", "replaced", "formerly",
                     "no longer", "withdrawn"]   # a line with any of these
                                                  # (case-insensitive) is history
    hole_words = ["mounting hole"]                # optional; lines containing
                                                  # one are scanned for (x, y)
    hole_key = "mechanism_holes_mm"               # optional, [floorplan] key
    known_keys = ["tooling_holes_mm"]             # optional, [floorplan] keys
                                                  # whose points are also valid
    typography_skip = ["third_party"]             # optional, extra folder names

    [[doc_sync.superseded]]                       # one table per stale term
    term  = "regex of the old name or value"
    by    = "D-002"                              # the superseding decision
    note  = "what replaced it"
    allow = "optional regex; a line matching it may keep the term"

    [doc_sync.edge_patterns]                      # optional overrides; regexes
    words  = "connector wall|connector edge"      # phrases introducing an edge
    top    = "\\(top\\)|top (long )?edge"
    bottom = "\\(bottom\\)|bottom (long )?edge"
    left   = "..." ; right = "..."

parameters.toml keys read
    [floorplan]  <hole_key> = [[x, y], ...]       hole coordinates in mm
                 <known_keys> = list of [x, y] pairs, or table name -> [x, y]
                 connector_wall_edge = "top" | "bottom" | "left" | "right"

Rules
    - A superseded term on a line without a history word and without the
      term's own `allow` match is a FAIL.
    - On a line containing a hole word and no history word, every "(x, y)"
      pair must equal (within 0.05) a hole or a known point, else FAIL.
    - A connector-edge phrase followed within 40 characters by the marker of
      an edge other than connector_wall_edge is a FAIL.
    - A document listed in the sync file that does not exist is a WARN.
    - Typography: any U+2013 or U+2014 in a .md, .toml, .csv or .py file
      under the root (skipping .git, .venv, __pycache__, node_modules and
      typography_skip folders) FAILs.

Outputs
    One line per finding: LEVEL, check name, message. At most 12 stale
    statements are listed. Exit 0 no FAIL, 1 at least one FAIL, 2 the tool
    could not run.

Dependencies
    Python 3.11+ standard library only (tomllib).

Validation source
    Generalised from a controller-PCB project check; behaviour pinned by
    tests/test_check_doc_sync.py on made-up fixtures.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import tomllib
from dataclasses import asdict, dataclass
from pathlib import Path

CHECK = "doc_sync"
LEVELS = ("PASS", "WARN", "FAIL", "INFO")
PAIR_RE = re.compile(r"\((-?\d+(?:\.\d+)?),\s*(-?\d+(?:\.\d+)?)\)")
SHOW_MAX = 12
DASH_RE = re.compile("[\\u2013\\u2014]")
TYPO_SUFFIXES = {".md", ".toml", ".csv", ".py"}
TYPO_SKIP_PARTS = {".git", ".venv", "__pycache__", "node_modules"}
DEFAULT_HISTORY = ["rejected", "superseded", "replaced", "formerly", "no longer", "withdrawn"]
DEFAULT_EDGE_PATTERNS = {
    "words": r"connector (?:wall|edge|belt)|receptacles? (?:are |mounted |on )",
    "top": r"\(top\)|top (?:long )?edge",
    "bottom": r"\(bottom\)|bottom (?:long )?edge",
    "left": r"\(left\)|left (?:short )?edge",
    "right": r"\(right\)|right (?:short )?edge",
}
EDGES = ("top", "bottom", "left", "right")
POINT_TOLERANCE_MM = 0.05


class ToolError(Exception):
    """The tool could not run at all (exit code 2)."""


@dataclass(frozen=True)
class Finding:
    level: str
    check: str
    message: str


def _finding(level: str, aspect: str, message: str) -> Finding:
    return Finding(level, f"{CHECK}.{aspect}", message)


def load_toml(path: Path, what: str) -> dict:
    try:
        return tomllib.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as error:
        raise ToolError(f"{what} not found: {path}") from error
    except tomllib.TOMLDecodeError as error:
        raise ToolError(f"{what} is not valid TOML: {path}: {error}") from error


def load_sync(path: Path) -> dict:
    sync = load_toml(path, "sync file").get("doc_sync")
    if not isinstance(sync, dict) or not sync.get("docs"):
        raise ToolError(f"{path}: [doc_sync] with a non-empty docs list is required")
    return sync


def _is_history(line: str, words: list[str]) -> bool:
    low = line.lower()
    return any(word.lower() in low for word in words)


def check_terms(doc: str, lines: list[str], sync: dict) -> list[Finding]:
    findings = []
    history = sync.get("history_words", DEFAULT_HISTORY)
    for entry in sync.get("superseded", []):
        try:
            pattern = re.compile(entry["term"])
            allow = re.compile(entry["allow"]) if entry.get("allow") else None
        except (re.error, KeyError, TypeError) as error:
            raise ToolError(f"superseded term invalid: {entry!r}: {error}") from error
        for number, line in enumerate(lines, 1):
            match = pattern.search(line)
            if match and not _is_history(line, history) and not (allow and allow.search(line)):
                findings.append(_finding(
                    "FAIL", "superseded",
                    f"{doc}:{number}: '{match.group(0)}' superseded by {entry.get('by', '?')}: {entry.get('note', '')}"))
    return findings


def _points(value: object) -> list[list[float]]:
    """Coordinates in a list of pairs or a table name -> pair; anything else gives none."""
    items = value.values() if isinstance(value, dict) else value if isinstance(value, (list, tuple)) else []
    return [[float(p[0]), float(p[1])] for p in items
            if isinstance(p, (list, tuple)) and len(p) == 2 and all(isinstance(v, (int, float)) for v in p)]


def check_holes(doc: str, lines: list[str], sync: dict, holes: list[list[float]],
                known: list[list[float]]) -> list[Finding]:
    findings = []
    words = [w.lower() for w in sync.get("hole_words", [])]
    if not words or not holes:
        return findings
    accept = holes + known
    for number, line in enumerate(lines, 1):
        low = line.lower()
        if not any(word in low for word in words) or _is_history(line, sync.get("history_words", DEFAULT_HISTORY)):
            continue
        for x_text, y_text in PAIR_RE.findall(line):
            x, y = float(x_text), float(y_text)
            if not any(abs(x - hx) < POINT_TOLERANCE_MM and abs(y - hy) < POINT_TOLERANCE_MM for hx, hy in accept):
                findings.append(_finding(
                    "FAIL", "holes",
                    f"{doc}:{number}: hole coordinate ({x_text}, {y_text}) is not one of the parameter holes "
                    + ", ".join(f"({hx:g}, {hy:g})" for hx, hy in holes)))
    return findings


def check_edge(doc: str, lines: list[str], sync: dict, edge: str) -> list[Finding]:
    patterns = {**DEFAULT_EDGE_PATTERNS, **sync.get("edge_patterns", {})}
    words = re.compile(patterns["words"], re.IGNORECASE)
    stale = {name: re.compile(patterns[name], re.IGNORECASE) for name in EDGES if name != edge and name in patterns}
    findings = []
    for number, line in enumerate(lines, 1):
        if _is_history(line, sync.get("history_words", DEFAULT_HISTORY)):
            continue
        for match in words.finditer(line):
            tail = line[match.end():match.end() + 40]
            wrong = next((name for name, pattern in stale.items() if pattern.search(tail)), None)
            if wrong:
                findings.append(_finding(
                    "FAIL", "connector_edge",
                    f"{doc}:{number}: connector wall described on the {wrong} edge; "
                    f"parameters connector_wall_edge is {edge}"))
                break
    return findings


def check_typography(root: Path, extra_skip: list[str]) -> list[Finding]:
    skip = TYPO_SKIP_PARTS | set(extra_skip)
    offenders = []
    for path in sorted(root.rglob("*")):
        relative_parts = path.relative_to(root).parts
        if path.suffix.lower() not in TYPO_SUFFIXES or not path.is_file() or any(p in skip for p in relative_parts):
            continue
        try:
            text = path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        count = len(DASH_RE.findall(text))
        if count:
            offenders.append(f"{path.relative_to(root).as_posix()} ({count})")
    if offenders:
        shown = ", ".join(offenders[:SHOW_MAX]) + (f" and {len(offenders) - SHOW_MAX} more"
                                                   if len(offenders) > SHOW_MAX else "")
        return [_finding("FAIL", "typography", f"en/em dash in {len(offenders)} files: {shown}")]
    return [_finding("PASS", "typography", "no en or em dash in the project's own text files")]


def run(root: Path, sync_path: Path | None = None, params: dict | None = None,
        typography: bool = True) -> list[Finding]:
    root = Path(root)
    sync = load_sync(Path(sync_path) if sync_path else root / "doc_sync.toml")
    floorplan = (params or {}).get("floorplan", {})
    hole_key = sync.get("hole_key", "mechanism_holes_mm")
    holes = _points(floorplan.get(hole_key, []))
    known = [p for key in sync.get("known_keys", []) for p in _points(floorplan.get(key, []))]
    edge = floorplan.get("connector_wall_edge")
    if edge is not None and edge not in EDGES:
        raise ToolError(f"[floorplan] connector_wall_edge {edge!r} is not one of {', '.join(EDGES)}")
    findings: list[Finding] = []
    checked = 0
    for doc in sync["docs"]:
        path = root / doc
        if not path.is_file():
            findings.append(_finding("WARN", "missing", f"{doc} listed in the sync file does not exist"))
            continue
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
        checked += 1
        findings.extend(check_terms(doc, lines, sync))
        findings.extend(check_holes(doc, lines, sync, holes, known))
        if edge is not None:
            findings.extend(check_edge(doc, lines, sync, edge))
    skipped = []
    if not holes:
        skipped.append("hole coordinates")
    if edge is None:
        skipped.append("connector wall edge")
    if skipped:
        findings.append(_finding("INFO", "skipped", f"not checked, the parameters give no {' and no '.join(skipped)}"))
    if typography:
        findings.extend(check_typography(root, sync.get("typography_skip", [])))
    fails = [f for f in findings if f.level == "FAIL"]
    if len(fails) > SHOW_MAX:
        findings = [f for f in findings if f.level != "FAIL"] + fails[:SHOW_MAX]
        findings.append(_finding("FAIL", "more", f"and {len(fails) - SHOW_MAX} more stale statements"))
    if not fails:
        findings.append(_finding("PASS", "documents",
                                 f"{checked} documents carry none of the {len(sync.get('superseded', []))} superseded terms "
                                 "and agree with the parameters"))
    return findings


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
    parser.add_argument("--sync", type=Path, help="sync file (default <root>/doc_sync.toml)")
    parser.add_argument("--params", type=Path, help="parameters.toml (default <root>/parameters.toml when present)")
    parser.add_argument("--no-typography", action="store_true", help="skip the en/em dash scan")
    parser.add_argument("--json", action="store_true", help="print findings as JSON")
    args = parser.parse_args(argv)
    try:
        params_path = args.params
        if params_path is None and (args.root / "parameters.toml").is_file():
            params_path = args.root / "parameters.toml"
        params = load_toml(params_path, "parameters file") if params_path else {}
        findings = run(args.root, args.sync, params, not args.no_typography)
    except ToolError as error:
        print(f"could not run: {error}")
        return 2
    return emit(findings, "document sync check", args.json)


if __name__ == "__main__":
    sys.exit(main())
