#!/usr/bin/env python3
"""Check REQUIREMENTS.md rows and the decision and question references in the design documents.

Purpose
    Requirement IDs are unique and gapless per group, every requirement names
    a source and a verification, and every cited decision (D-NNN) and open
    question (Q-NN) exists. A stale reference is a document that points at a
    decision nobody logged.

Inputs
    --root DIR          design folder (default: current directory)
    --requirements FILE requirements file (default: <root>/REQUIREMENTS.md)
    --decisions FILE    decision log (default: <root>/DECISIONS.md)
    --questions FILE    open questions (default: <root>/OPEN_QUESTIONS.md)
    --doc FILE          extra document scanned for D-/Q- references
                        (repeatable; default ARCHITECTURE.md, skipped when it
                        does not exist; an explicitly named file must exist)
    --json              print findings as JSON

REQUIREMENTS.md format
    A Markdown table; each requirement row starts with an ID cell
    "<GROUP>-<NN>" (group = capital letters, for example PWR, SAF, MFG). The
    LAST two cells are Source and Verification and must be non-empty (text
    with a stray "|" in the requirement cell cannot shift them). IDs within a
    group are unique and sequential from 01.

References
    A decision reference is "D-NNN" (three digits); a question reference is
    "Q-NN" (two or more digits). Each must be a "## D-NNN" section heading in
    the decision log, or a "| Q-NN |" row in the open-questions table. The
    requirements file itself is also scanned.

Outputs
    One line per finding: LEVEL, check name, message. Exit 0 no FAIL, 1 at
    least one FAIL, 2 the tool could not run.

Dependencies
    Python 3.11+ standard library only.

Validation source
    Generalised from a controller-PCB project check; behaviour pinned by
    tests/test_check_requirements.py on made-up fixtures.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import asdict, dataclass
from pathlib import Path

CHECK = "requirements"
LEVELS = ("PASS", "WARN", "FAIL", "INFO")
REQUIREMENT_ROW = re.compile(r"^\|\s*([A-Z]+)-(\d+)\s*\|(.*)\|\s*$", re.MULTILINE)
DECISION_REF = re.compile(r"(?<![A-Za-z0-9])D-(\d{3})(?!\d)")
QUESTION_REF = re.compile(r"(?<![A-Za-z0-9])Q-(\d{2,})(?!\d)")
DECISION_SECTION = re.compile(r"^## (D-\d{3})\b", re.MULTILINE)
QUESTION_ROW = re.compile(r"^\|\s*(Q-\d+)\s*\|", re.MULTILINE)
DEFAULT_EXTRA_DOCS = ("ARCHITECTURE.md",)


class ToolError(Exception):
    """The tool could not run at all (exit code 2)."""


@dataclass(frozen=True)
class Finding:
    level: str
    check: str
    message: str


def _fail(aspect: str, message: str) -> Finding:
    return Finding("FAIL", f"{CHECK}.{aspect}", message)


def check_requirements_text(text: str) -> list[Finding]:
    findings: list[Finding] = []
    numbers: dict[str, list[int]] = {}
    count = 0
    for match in REQUIREMENT_ROW.finditer(text):
        prefix, number = match.group(1), int(match.group(2))
        requirement_id = f"{prefix}-{match.group(2)}"
        cells = [cell.strip() for cell in match.group(3).split("|")]
        count += 1
        numbers.setdefault(prefix, []).append(number)
        if len(cells) < 3:
            findings.append(_fail("row", f"{requirement_id}: row has fewer than four cells"))
            continue
        source, verification = cells[-2], cells[-1]
        if not source:
            findings.append(_fail("source", f"{requirement_id}: Source cell is empty"))
        if not verification:
            findings.append(_fail("verification", f"{requirement_id}: Verification cell is empty"))
    for prefix, values in numbers.items():
        for value in sorted({v for v in values if values.count(v) > 1}):
            findings.append(_fail("duplicate", f"{prefix}-{value:02d} appears more than once"))
        if sorted(set(values)) != list(range(1, len(set(values)) + 1)):
            findings.append(_fail("sequence", f"{prefix} IDs are not sequential from {prefix}-01: {sorted(set(values))}"))
    if not count:
        findings.append(_fail("rows", "no requirement rows found (expected rows starting '| ABC-01 |')"))
    if not findings:
        findings.append(Finding("PASS", f"{CHECK}.rows",
                                f"{count} requirements in {len(numbers)} groups: IDs sequential, Source and Verification filled"))
    return findings


def check_references(texts: dict[str, str], known_decisions: set[str], known_questions: set[str]) -> list[Finding]:
    missing: dict[str, list[str]] = {}
    for name, text in texts.items():
        for number in DECISION_REF.findall(text):
            reference = f"D-{number}"
            if reference not in known_decisions and name not in missing.setdefault(reference, []):
                missing[reference].append(name)
        for number in QUESTION_REF.findall(text):
            reference = f"Q-{number}"
            if reference not in known_questions and name not in missing.setdefault(reference, []):
                missing[reference].append(name)
    findings = [_fail("reference", f"{reference} is referenced in {', '.join(names)} but does not exist")
                for reference, names in sorted(missing.items()) if names]
    if not findings:
        findings.append(Finding("PASS", f"{CHECK}.references", f"every D-/Q- reference in {len(texts)} documents resolves"))
    return findings


def _read(path: Path) -> str:
    if not path.is_file():
        raise ToolError(f"document not found: {path}")
    return path.read_text(encoding="utf-8")


def run(root: Path, requirements: Path | None = None, decisions: Path | None = None,
        questions: Path | None = None, docs: list[Path] | None = None) -> list[Finding]:
    root = Path(root)
    requirements = Path(requirements) if requirements else root / "REQUIREMENTS.md"
    texts = {requirements.name: _read(requirements)}
    skipped = []
    if docs:
        for doc in docs:
            texts[Path(doc).name] = _read(Path(doc))
    else:
        for name in DEFAULT_EXTRA_DOCS:
            path = root / name
            if path.is_file():
                texts[name] = path.read_text(encoding="utf-8")
            else:
                skipped.append(name)
    known_decisions = set(DECISION_SECTION.findall(_read(Path(decisions) if decisions else root / "DECISIONS.md")))
    known_questions = set(QUESTION_ROW.findall(_read(Path(questions) if questions else root / "OPEN_QUESTIONS.md")))
    findings = check_requirements_text(texts[requirements.name]) + check_references(texts, known_decisions, known_questions)
    if skipped:
        findings.append(Finding("INFO", f"{CHECK}.skipped", f"default document not present, not scanned: {', '.join(skipped)}"))
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
    parser.add_argument("--requirements", type=Path, help="requirements file (default <root>/REQUIREMENTS.md)")
    parser.add_argument("--decisions", type=Path, help="decision log (default <root>/DECISIONS.md)")
    parser.add_argument("--questions", type=Path, help="open questions (default <root>/OPEN_QUESTIONS.md)")
    parser.add_argument("--doc", type=Path, action="append", help="extra document scanned for references (repeatable)")
    parser.add_argument("--json", action="store_true", help="print findings as JSON")
    args = parser.parse_args(argv)
    try:
        findings = run(args.root, args.requirements, args.decisions, args.questions, args.doc)
    except ToolError as error:
        print(f"could not run: {error}")
        return 2
    return emit(findings, "requirements check", args.json)


if __name__ == "__main__":
    sys.exit(main())
