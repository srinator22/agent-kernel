#!/usr/bin/env python3
"""Check that every design number in the parameters file has a source and sits inside its bounds (rule PCB-4).

Purpose
    Design numbers live in one parameters file. Each carries where it came
    from and the bounds it may take, so a tool can fail a number that drifted
    and a reviewer can see which numbers are only estimates.

Inputs
    --params FILE     parameters.toml (default: <root>/parameters.toml)
    --root DIR        folder that source paths are relative to (default:
                      current directory)
    --decisions FILE  optional decision log; when given, a source of the form
                      "D-NNN" must be a "## D-NNN" section heading in it
    --require NAME    top-level table that must exist (repeatable)
    --json            print findings as JSON

parameters.toml format
    Any TOML table that has a `value` key is a parameter. It may sit at any
    depth, or in an array of tables ([[group.items]]); the dotted table path
    (with `name` or the index for array rows) is its name in messages.

        [power.input_current]
        value  = 18.0                      # a number, "pending", or a string
        unit   = "A"                       # required for numbers (WARN if absent)
        min    = 0.0                       # bounds: both given, or WARN
        max    = 20.0
        source = "datasheets/psu/part.pdf" # see below
        status = "datasheet"               # datasheet | decision | estimate | pending

        [mechanical.connector_edge]
        value   = "bottom"                 # a non-number needs `allowed`
        allowed = ["top", "bottom"]
        source  = "D-002"
        status  = "decision"

Rules
    - status must be one of datasheet, decision, estimate, pending (FAIL).
    - value must be a number, "pending", or a member of `allowed` (FAIL).
      A "pending" value must have status "pending" (FAIL) and is a WARN.
    - Numbers need min and max (WARN when absent); min greater than max FAILs;
      a value outside [min, max] FAILs; on a bound it passes.
    - source is required (FAIL; WARN for a pending value). status "datasheet"
      needs a source that is an existing file under --root (an optional
      "#anchor" suffix is ignored); status "decision" needs "D-NNN" that
      exists in --decisions when that is given. status "estimate" or
      "pending" accepts any text and always produces a WARN: an uncertain
      basis never yields a plain PASS.
    - Two parameters with the same dotted name FAIL (array rows with the same
      `name`).

Outputs
    One line per finding: LEVEL, check name, message; an INFO line counts the
    parameters by status. Exit 0 no FAIL, 1 at least one FAIL, 2 the tool
    could not run.

Dependencies
    Python 3.11+ standard library only (tomllib).

Assumptions
    Units are not converted; a unit is a label for the reader.

Validation source
    Generalised from a controller-PCB project check whose schema was specific
    to that board; this version reads any parameters file with the format
    above. Behaviour pinned by tests/test_check_parameters.py.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import tomllib
from dataclasses import asdict, dataclass
from pathlib import Path

CHECK = "parameters"
LEVELS = ("PASS", "WARN", "FAIL", "INFO")
VALID_STATUSES = ("datasheet", "decision", "estimate", "pending")
UNCERTAIN_STATUSES = ("estimate", "pending")
PENDING = "pending"
DECISION_ID = re.compile(r"^D-\d{3}\b")
DECISION_SECTION = re.compile(r"^## (D-\d{3})\b", re.MULTILINE)


class ToolError(Exception):
    """The tool could not run at all (exit code 2)."""


@dataclass(frozen=True)
class Finding:
    level: str
    check: str
    message: str


def _finding(level: str, aspect: str, message: str) -> Finding:
    return Finding(level, f"{CHECK}.{aspect}", message)


def is_number(value: object) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def collect(node: object, path: str = "") -> list[tuple[str, dict]]:
    """(dotted name, table) for every table that has a `value` key."""
    found: list[tuple[str, dict]] = []
    if isinstance(node, dict):
        if "value" in node:
            found.append((path or "(root)", node))
            return found
        for key, child in node.items():
            found.extend(collect(child, f"{path}.{key}" if path else str(key)))
    elif isinstance(node, list):
        for index, child in enumerate(node):
            label = child.get("name") if isinstance(child, dict) and isinstance(child.get("name"), str) else str(index)
            found.extend(collect(child, f"{path}[{label}]"))
    return found


def _source_findings(name: str, item: dict, root: Path, decisions: set[str] | None) -> list[Finding]:
    status, value, source = item.get("status"), item.get("value"), item.get("source")
    if not isinstance(source, str) or not source.strip():
        level = "WARN" if value == PENDING else "FAIL"
        return [_finding(level, "source", f"{name}: no source recorded")]
    source = source.strip()
    if status == "datasheet":
        target = root / source.split("#", 1)[0]
        if DECISION_ID.match(source):
            return [_finding("FAIL", "source", f"{name}: status datasheet but the source {source} is a decision")]
        if not target.is_file():
            return [_finding("FAIL", "source", f"{name}: source document {source} does not exist under {root}")]
    elif status == "decision":
        if not DECISION_ID.match(source):
            return [_finding("FAIL", "source", f"{name}: status decision needs a D-NNN source, got {source!r}")]
        if decisions is not None and DECISION_ID.match(source).group(0) not in decisions:
            return [_finding("FAIL", "source", f"{name}: decision {source} is not in the decision log")]
    return []


def check_item(name: str, item: dict, root: Path, decisions: set[str] | None) -> list[Finding]:
    findings: list[Finding] = []
    status, value = item.get("status"), item.get("value")
    if status not in VALID_STATUSES:
        findings.append(_finding("FAIL", "status", f"{name}: status {status!r} is not one of {', '.join(VALID_STATUSES)}"))
    findings.extend(_source_findings(name, item, root, decisions))

    if value == PENDING:
        if status != PENDING:
            findings.append(_finding("FAIL", "pending", f"{name}: value is pending but status is {status!r}, not pending"))
        else:
            findings.append(_finding("WARN", "pending", f"{name}: value is pending, not sized"))
        return findings
    if "allowed" in item:
        allowed = item["allowed"]
        if not isinstance(allowed, list) or value not in allowed:
            findings.append(_finding("FAIL", "allowed", f"{name}: value {value!r} is not in allowed {allowed!r}"))
        return _grade(findings, name, status, f"value {value!r} in the allowed list")
    if not is_number(value):
        findings.append(_finding("FAIL", "value", f"{name}: value {value!r} must be a number, 'pending', or have an allowed list"))
        return findings

    low, high = item.get("min"), item.get("max")
    if not (is_number(low) and is_number(high)):
        findings.append(_finding("WARN", "bounds", f"{name}: min and max are not both recorded, value {value:g} unchecked"))
    elif low > high:
        findings.append(_finding("FAIL", "bounds", f"{name}: min {low:g} is above max {high:g}"))
    elif not low <= value <= high:
        findings.append(_finding("FAIL", "bounds", f"{name}: value {value:g} is outside [{low:g}, {high:g}]"))
    else:
        unit = item.get("unit", "")
        findings = _grade(findings, name, status, f"{value:g} {unit}".rstrip() + f" within [{low:g}, {high:g}]")
    if not isinstance(item.get("unit"), str) or not item["unit"].strip():
        findings.append(_finding("WARN", "unit", f"{name}: no unit recorded"))
    return findings


def _grade(findings: list[Finding], name: str, status: object, message: str) -> list[Finding]:
    """A PASS for a firm basis; a WARN when the basis is an estimate or pending. Nothing is added after a FAIL."""
    if any(f.level == "FAIL" for f in findings):
        return findings
    if status in UNCERTAIN_STATUSES:
        findings.append(_finding("WARN", "basis", f"{name}: {message} (basis status: {status})"))
    else:
        findings.append(_finding("PASS", "value", f"{name}: {message}"))
    return findings


def run(params: dict, root: Path, decisions: set[str] | None = None, require: list[str] | None = None) -> list[Finding]:
    findings: list[Finding] = []
    for section in require or []:
        if section not in params:
            findings.append(_finding("FAIL", "section", f"required table [{section}] is missing"))
    items = collect(params)
    if not items:
        findings.append(_finding("FAIL", "empty", "no parameter (a table with a `value` key) found"))
    seen: dict[str, int] = {}
    for name, _ in items:
        seen[name] = seen.get(name, 0) + 1
    for name, count in sorted(seen.items()):
        if count > 1:
            findings.append(_finding("FAIL", "duplicate", f"{name}: defined {count} times"))
    counts: dict[str, int] = {}
    for name, item in items:
        findings.extend(check_item(name, item, Path(root), decisions))
        status = item.get("status") if isinstance(item.get("status"), str) else "none"
        counts[status] = counts.get(status, 0) + 1
    if items:
        findings.append(_finding("INFO", "status_summary", f"{len(items)} parameters by status: "
                                 + ", ".join(f"{k} {counts[k]}" for k in sorted(counts))))
    return findings


def load_params(path: Path) -> dict:
    try:
        with path.open("rb") as handle:
            return tomllib.load(handle)
    except FileNotFoundError as error:
        raise ToolError(f"parameters file not found: {path}") from error
    except tomllib.TOMLDecodeError as error:
        raise ToolError(f"parameters file is not valid TOML: {path}: {error}") from error


def load_decisions(path: Path | None) -> set[str] | None:
    if path is None:
        return None
    if not path.is_file():
        raise ToolError(f"decision log not found: {path}")
    return set(DECISION_SECTION.findall(path.read_text(encoding="utf-8")))


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
    parser.add_argument("--params", type=Path, help="parameters.toml (default <root>/parameters.toml)")
    parser.add_argument("--root", type=Path, default=Path.cwd(), help="folder source paths are relative to")
    parser.add_argument("--decisions", type=Path, help="decision log to resolve D-NNN sources against")
    parser.add_argument("--require", action="append", default=[], help="top-level table that must exist (repeatable)")
    parser.add_argument("--json", action="store_true", help="print findings as JSON")
    args = parser.parse_args(argv)
    try:
        params = load_params(args.params or args.root / "parameters.toml")
        findings = run(params, args.root, load_decisions(args.decisions), args.require)
    except ToolError as error:
        print(f"could not run: {error}")
        return 2
    return emit(findings, "parameters check", args.json)


if __name__ == "__main__":
    sys.exit(main())
