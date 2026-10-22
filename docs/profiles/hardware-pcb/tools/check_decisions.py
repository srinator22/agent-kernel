#!/usr/bin/env python3
"""Check the decision log and the open-questions table for ID, status and structure errors (rule PCB-3).

Purpose
    The decision log is the "why" record. This check keeps it machine-sound:
    sequential IDs, required fields, a summary table that agrees with the
    sections, and supersession that points at a real, marked decision.

Inputs
    --root DIR          design folder (default: current directory)
    --decisions FILE    decision log (default: <root>/DECISIONS.md)
    --questions FILE    open-questions table (default: <root>/OPEN_QUESTIONS.md)
    --no-questions      skip the open-questions check
    --json              print findings as JSON

DECISIONS.md format
    - One section per decision, heading "## D-NNN <title>" (three digits,
      sequential from D-001, in order of appearance, no duplicates).
    - Each section carries the labels **Date:**, **Status:**, **Decision:**
      and **Rationale:** (bold, with the colon inside the bold).
    - Status text starts with "Accepted", "Proposed" or "Superseded by D-NNN".
    - A summary table anywhere in the file has one row per decision:
      "| D-NNN | ... | <status> |" with the status in the LAST cell. The
      table status must name the same category (and target) as the section.
    - A decision whose text says "Supersedes D-NNN" requires D-NNN to carry
      the status "Superseded by <this decision>" (the target is marked).
    - The words TODO and TBD anywhere in the file FAIL: a logged decision is
      made; an unknown goes to the open-questions table instead.

OPEN_QUESTIONS.md format
    A Markdown table whose first cell is "Q-NN" (two or more digits),
    sequential from Q-01, unique. Closed questions stay in the table.

Outputs
    One line per finding: LEVEL, check name, message. Exit 0 no FAIL, 1 at
    least one FAIL, 2 the tool could not run.

Dependencies
    Python 3.11+ standard library only.

Validation source
    Generalised from a controller-PCB project check; behaviour pinned by
    tests/test_check_decisions.py on made-up fixtures.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import asdict, dataclass
from pathlib import Path

CHECK = "decisions"
LEVELS = ("PASS", "WARN", "FAIL", "INFO")
SECTION_HEADING = re.compile(r"^## (D-\d{3})\b.*$", re.MULTILINE)
TABLE_ROW = re.compile(r"^\|\s*(D-\d{3})\s*\|(.*)\|\s*$", re.MULTILINE)
QUESTION_ROW = re.compile(r"^\|\s*(Q-\d+)\s*\|", re.MULTILINE)
SUPERSEDED = re.compile(r"^Superseded by (D-\d{3})\b")
SUPERSEDES = re.compile(r"\bSupersedes\s+((?:D-\d{3}(?:\s*(?:,|and|&)\s*)?)+)")
DECISION_ID = re.compile(r"D-\d{3}")
PLACEHOLDER = re.compile(r"\b(TODO|TBD)\b")
REQUIRED_LABELS = ("**Date:**", "**Status:**", "**Decision:**", "**Rationale:**")


class ToolError(Exception):
    """The tool could not run at all (exit code 2)."""


@dataclass(frozen=True)
class Finding:
    level: str
    check: str
    message: str


def _fail(aspect: str, message: str) -> Finding:
    return Finding("FAIL", f"{CHECK}.{aspect}", message)


def _sequence_problems(ids: list[str], prefix: str, width: int, label: str) -> list[Finding]:
    """Duplicates, and any departure from <prefix>-001... in order of appearance."""
    findings = []
    seen: set[str] = set()
    for item in ids:
        if item in seen:
            findings.append(_fail("duplicate", f"{label}: {item} appears more than once"))
        seen.add(item)
    unique = list(dict.fromkeys(ids))
    for position, item in enumerate(unique, start=1):
        expected = f"{prefix}-{position:0{width}d}"
        if item != expected:
            findings.append(_fail("sequence", f"{label}: IDs are not sequential, expected {expected} but found {item}"))
            break
    return findings


def status_category(status: str) -> tuple[str, str | None]:
    """('Accepted'|'Proposed'|'Superseded'|'invalid', superseding ID or None)."""
    if status.startswith("Accepted"):
        return "Accepted", None
    if status.startswith("Proposed"):
        return "Proposed", None
    match = SUPERSEDED.match(status)
    if match:
        return "Superseded", match.group(1)
    return "invalid", None


def split_sections(text: str) -> dict[str, str]:
    matches = list(SECTION_HEADING.finditer(text))
    sections: dict[str, str] = {}
    for index, match in enumerate(matches):
        end = matches[index + 1].start() if index + 1 < len(matches) else len(text)
        sections.setdefault(match.group(1), text[match.start():end])
    return sections


def decision_ids(text: str) -> set[str]:
    return set(SECTION_HEADING.findall(text))


def question_ids(text: str) -> set[str]:
    return set(QUESTION_ROW.findall(text))


def _section_status(body: str) -> tuple[str, bool]:
    """(status text, whether a Status label exists)."""
    match = re.search(r"\*\*Status:\*\*\s*(.+)", body)
    return (match.group(1).strip(), True) if match else ("", False)


def check_decisions_text(text: str) -> list[Finding]:
    findings: list[Finding] = []
    section_ids = SECTION_HEADING.findall(text)
    table = {m.group(1): [c.strip() for c in m.group(2).split("|")] for m in TABLE_ROW.finditer(text)}
    table_ids = [m.group(1) for m in TABLE_ROW.finditer(text)]
    findings += _sequence_problems(section_ids, "D", 3, "sections")
    findings += _sequence_problems(table_ids, "D", 3, "summary table")

    sections = split_sections(text)
    for missing in sorted(set(sections) - set(table)):
        findings.append(_fail("table", f"{missing} has a section but no row in the summary table"))
    for missing in sorted(set(table) - set(sections)):
        findings.append(_fail("table", f"{missing} is in the summary table but has no section"))

    statuses: dict[str, tuple[str, str | None]] = {}
    for decision_id, body in sections.items():
        for label in REQUIRED_LABELS:
            if label not in body:
                findings.append(_fail("label", f"{decision_id}: missing {label}"))
        section_status, has_status = _section_status(body)
        category, target = status_category(section_status)
        statuses[decision_id] = (category, target)
        if category == "invalid":
            if has_status:
                findings.append(_fail("status", f"{decision_id}: status {section_status!r} is not Accepted, "
                                                "Proposed or Superseded by D-NNN"))
        elif target is not None and target not in sections:
            findings.append(_fail("status", f"{decision_id}: superseded by {target}, which does not exist"))
        elif target == decision_id:
            findings.append(_fail("status", f"{decision_id}: superseded by itself"))
        row = table.get(decision_id)
        if row:
            table_category, table_target = status_category(row[-1])
            if table_category == "invalid":
                findings.append(_fail("status", f"{decision_id}: summary table status {row[-1]!r} is not Accepted, "
                                                "Proposed or Superseded by D-NNN"))
            elif table_target is not None and table_target not in sections:
                findings.append(_fail("status", f"{decision_id}: table says superseded by {table_target}, "
                                                "which does not exist"))
            elif category != "invalid" and (table_category, table_target) != (category, target):
                findings.append(_fail("status", f"{decision_id}: table status {row[-1]!r} disagrees with "
                                                f"section status {section_status!r}"))

    # "Supersedes D-A" in D-B's text: D-A must be marked "Superseded by D-B".
    for decision_id, body in sections.items():
        for clause in SUPERSEDES.findall(body):
            for target in DECISION_ID.findall(clause):
                if target not in sections:
                    findings.append(_fail("supersession", f"{decision_id}: supersedes {target}, which does not exist"))
                elif statuses[target] != ("Superseded", decision_id):
                    findings.append(_fail("supersession",
                                          f"{decision_id}: supersedes {target}, but {target} is not marked "
                                          f"'Superseded by {decision_id}'"))

    for placeholder in sorted(set(PLACEHOLDER.findall(text))):
        findings.append(_fail("placeholder", f"document contains {placeholder}"))
    if not findings:
        findings.append(Finding("PASS", f"{CHECK}.decisions",
                                f"{len(sections)} decisions: IDs, statuses, labels and summary table are consistent"))
    return findings


def check_questions_text(text: str) -> list[Finding]:
    ids = QUESTION_ROW.findall(text)
    findings = _sequence_problems(ids, "Q", 2, "open questions")
    if not findings:
        findings.append(Finding("PASS", f"{CHECK}.questions", f"{len(ids)} open questions: IDs unique and sequential"))
    return findings


def read_document(path: Path) -> str:
    if not path.is_file():
        raise ToolError(f"document not found: {path}")
    return path.read_text(encoding="utf-8")


def run(root: Path, decisions: Path | None = None, questions: Path | None = None,
        skip_questions: bool = False) -> list[Finding]:
    root = Path(root)
    findings = check_decisions_text(read_document(Path(decisions) if decisions else root / "DECISIONS.md"))
    if not skip_questions:
        findings += check_questions_text(read_document(Path(questions) if questions else root / "OPEN_QUESTIONS.md"))
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
    parser.add_argument("--decisions", type=Path, help="decision log (default <root>/DECISIONS.md)")
    parser.add_argument("--questions", type=Path, help="open questions (default <root>/OPEN_QUESTIONS.md)")
    parser.add_argument("--no-questions", action="store_true", help="skip the open-questions check")
    parser.add_argument("--json", action="store_true", help="print findings as JSON")
    args = parser.parse_args(argv)
    try:
        findings = run(args.root, args.decisions, args.questions, args.no_questions)
    except ToolError as error:
        print(f"could not run: {error}")
        return 2
    return emit(findings, "decision log check", args.json)


if __name__ == "__main__":
    sys.exit(main())
