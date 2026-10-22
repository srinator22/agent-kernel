#!/usr/bin/env python3
"""Check that the parts on the BOM are the parts the parameters file rates.

Purpose
    The ratings checks trust the [[parts]] rows of the parameters file. If
    the schematic fits a different part (or the alternate) than the row
    names, every margin computed from that row is about the wrong part. This
    check compares each [[parts]] row that names a part number with the
    components actually fitted, and lists fitted part numbers no row rates.

Inputs
    --bom FILE      component list, CSV: columns ref, value, footprint
                    required; mpn optional; case-insensitive (the same file
                    check_bom reads)
    --params FILE   parameters.toml (default: ./parameters.toml)
    --json          print findings as JSON

parameters.toml tables read
    [[parts]]
      ref   = "U1" | "J5, J6" | "U_REG"   a reference designator (letters then
                                          digits), a comma list of them, or a
                                          role name (anything else)
      mpn   = "REG100ABC"                 the rated part; " / " lists variants,
                                          "pending" or empty means not chosen
      alt   = "REG100XYZ (second source)" accepted alternates (parentheses are
                                          commentary and ignored)
      status = "datasheet" | "pending" ...  a pending row says so in messages
      not_a_symbol = "carried as a field of another part"
                                          a BOM-only item: reported, not failed

Rules
    - A designator row: each named designator must exist in the BOM and carry
      the part number (MPN column or Value). Carrying an alternate is a WARN,
      anything else a FAIL, a missing designator a FAIL.
    - A role row: some component must carry the part number; only an
      alternate fitted is a WARN; none is a FAIL.
    - Part numbers are compared after normalisation: first word, no "#..."
      suffix, no tape-and-reel suffix, letters and digits only.
    - A row with no part number yet is counted (INFO) and not checked.
    - A fitted part number mentioned by no row is a WARN (once per part
      number, listing the designators); passives, test points and mechanical
      parts (R, C, L, FB, TP, H, JP, NT) are aggregated as INFO.

Outputs
    One line per finding: LEVEL, check name, message. Exit 0 no FAIL, 1 at
    least one FAIL, 2 the tool could not run.

Dependencies
    Python 3.11+ standard library only.

Validation source
    Generalised from a controller-PCB project check that read a CAD netlist;
    this version reads a BOM CSV. Behaviour pinned by
    tests/test_check_part_roles.py on made-up fixtures.
"""

from __future__ import annotations

import argparse
import csv
import json
import re
import sys
import tomllib
from dataclasses import asdict, dataclass
from pathlib import Path

CHECK = "part_roles"
LEVELS = ("PASS", "WARN", "FAIL", "INFO")
PENDING = "pending"
REFDES = re.compile(r"^[A-Za-z]{1,4}\d+$")
PASSIVE_PREFIXES = {"R", "C", "L", "FB", "TP", "H", "JP", "NT"}
PACKAGING_SUFFIX = re.compile(r"[-_]?(?:TR|T|R)$")
PARENTHETICAL = re.compile(r"\([^)]*\)")
ITEM_SPLIT = re.compile(r"\s+/\s+|\s*;\s*")
WORD_SPLIT = re.compile(r"[\s,;]+")
MAX_REFS_SHOWN = 12
PLACEHOLDER = re.compile(r"^\s*(?:|-|n/?a|none|pending|tbd)\s*$|pending|no part|not fitted|\btbc\b", re.IGNORECASE)
GENERIC_VALUE = re.compile(r"^\s*(?:\d+(?:\.\d+)?\s*[pnuµμmkKMRG]?\s*(?:F|R|ohm|Ohm)?"
                           r"(?:\s+\d+(?:\.\d+)?\s*[mkK]?\s*(?:V|W))?|\d+[pnuµμkKMRG]\d+)\s*$")
MPN_LOOKS = re.compile(r"^(?=.*\d)(?=.*[A-Za-z])[A-Za-z0-9][A-Za-z0-9#+./\-]{3,}$")
VALUE_AS_MPN_PREFIXES = {"U", "Q", "Y", "D", "J", "P"}


class ToolError(Exception):
    """The tool could not run at all (exit code 2)."""


@dataclass(frozen=True)
class Finding:
    level: str
    check: str
    message: str


def _finding(level: str, aspect: str, message: str) -> Finding:
    return Finding(level, f"{CHECK}.{aspect}", message)


def parse_bom(text: str) -> list[dict]:
    reader = csv.DictReader(text.splitlines())
    if not reader.fieldnames:
        raise ToolError("the BOM is empty")
    names = {name.strip().lower(): name for name in reader.fieldnames if name}
    missing = [column for column in ("ref", "value", "footprint") if column not in names]
    if missing:
        raise ToolError(f"the BOM lacks the column(s): {', '.join(missing)}")
    components = []
    for row in reader:
        ref = (row.get(names["ref"]) or "").strip()
        if ref:
            components.append({"ref": ref, "value": (row.get(names["value"]) or "").strip(),
                               "fields": {"MPN": (row.get(names["mpn"]) or "").strip() if "mpn" in names else ""}})
    if not components:
        raise ToolError("the BOM has no component rows")
    return components


def ref_prefix(ref: str) -> str:
    match = re.match(r"[A-Za-z]+", ref)
    return match.group().upper() if match else ""


def component_mpn(component: dict) -> str | None:
    """The real part number, or None while it is still a placeholder."""
    mpn = component["fields"].get("MPN", "").strip()
    if mpn and not PLACEHOLDER.search(mpn):
        return mpn
    value = component["value"].strip()
    if ref_prefix(component["ref"]) in VALUE_AS_MPN_PREFIXES and MPN_LOOKS.match(value) \
            and not GENERIC_VALUE.match(value) and "_" not in value:
        return value
    return None


# ---------------------------------------------------------------- part-number normaliser

def normalise_mpn(text: str) -> str:
    """Comparable form of a part number: first word, no '#...' suffix, no packaging code, letters and digits only.

    'PART-A100#PBF' gives 'PARTA100', 'PART-B200,215' gives 'PARTB200', 'PART-C300R' gives 'PARTC300'.
    The same function is applied to both sides, so only the equality of the results matters.
    """
    words = WORD_SPLIT.split(text.strip().upper(), maxsplit=1)
    word = words[0].split("#")[0] if words else ""
    stripped = PACKAGING_SUFFIX.sub("", word)
    if len(re.sub(r"[^A-Z0-9]", "", stripped)) >= 4 and re.search(r"\d", stripped):
        word = stripped
    return re.sub(r"[^A-Z0-9]", "", word)


def free_text_tokens(text: str) -> set[str]:
    """Normalised part-number candidates in free text: every word that has a digit and at least three characters."""
    tokens = set()
    for word in WORD_SPLIT.split(PARENTHETICAL.sub(" ", text)):
        if len(word) >= 3 and re.search(r"\d", word):
            token = normalise_mpn(word)
            if token:
                tokens.add(token)
    return tokens


def _is_placeholder(value: object) -> bool:
    return not isinstance(value, str) or not value.strip() or value.strip().lower() in (PENDING, "tbd", "n/a", "none", "-")


def expected_tokens(part: dict) -> list[str]:
    """The part numbers a row names in `mpn`: each ' / ' item's first word, normalised."""
    mpn = part.get("mpn")
    if _is_placeholder(mpn):
        return []
    return [t for t in (normalise_mpn(item) for item in ITEM_SPLIT.split(str(mpn))) if t]


def alt_tokens(part: dict) -> set[str]:
    alt = part.get("alt")
    if _is_placeholder(alt):
        return set()
    tokens: set[str] = set()
    for item in ITEM_SPLIT.split(str(alt)):
        tokens |= free_text_tokens(item)
    return tokens


def component_tokens(component: dict) -> set[str]:
    """Part numbers a component carries in its MPN field or its Value."""
    tokens: set[str] = set()
    for text in (component["fields"].get("MPN", ""), component["value"]):
        if text and not _is_placeholder(text):
            tokens |= free_text_tokens(text)
            first = normalise_mpn(text)
            if first and re.search(r"\d", first):
                tokens.add(first)
    return tokens


# ---------------------------------------------------------------- the checks

def _refs_text(refs: list[str]) -> str:
    if len(refs) <= MAX_REFS_SHOWN:
        return ", ".join(refs)
    return ", ".join(refs[:MAX_REFS_SHOWN]) + f" and {len(refs) - MAX_REFS_SHOWN} more"


def _unique_rows(params: dict) -> list[dict]:
    """The [[parts]] rows that name a role, with exact repeats dropped."""
    rows, seen = [], set()
    for part in params.get("parts", []):
        if not isinstance(part, dict) or not isinstance(part.get("ref"), str) or not part["ref"].strip():
            continue
        key = (part["ref"], str(part.get("mpn")), str(part.get("alt")))
        if key not in seen:
            seen.add(key)
            rows.append(part)
    return rows


def _role(role: str, status: str) -> str:
    return f"role {role} (row status pending)" if status == PENDING else f"role {role}"


def check_roles(components: list[dict], params: dict) -> list[Finding]:
    """Every [[parts]] row that names an MPN against the components actually on the BOM."""
    findings: list[Finding] = []
    by_ref = {c["ref"]: c for c in components}
    all_tokens = [(c, component_tokens(c)) for c in components]
    matched = 0
    pending_roles: list[str] = []
    for part in _unique_rows(params):
        role = part["ref"].strip()
        expected = expected_tokens(part)
        if not expected:
            pending_roles.append(role)
            continue
        alts = alt_tokens(part)
        mpn_text = str(part["mpn"]).strip()
        label = _role(role, str(part.get("status", "")))
        if part.get("not_a_symbol"):
            findings.append(_finding("INFO", "not_a_symbol",
                                     f"parameters {label} ({mpn_text}) is a BOM-only item with no schematic symbol: {part['not_a_symbol']}"))
            continue
        ref_tokens = [t.strip() for t in role.split(",") if t.strip()]
        refdes = [t for t in ref_tokens if REFDES.match(t)]
        if refdes:
            ok = True
            for ref in refdes:
                component = by_ref.get(ref)
                if component is None:
                    ok = False
                    findings.append(_finding("FAIL", "refdes", f"parameters {label} names {ref} with MPN {mpn_text} but the BOM has no component {ref}"))
                    continue
                tokens = component_tokens(component)
                carried = component["fields"].get("MPN", "").strip() or component["value"]
                if tokens & set(expected):
                    continue
                if tokens & alts:
                    findings.append(_finding("WARN", "alt", f"parameters {label} names MPN {mpn_text} for {ref}: alternative fitted "
                                                            f"({carried}; alt: {part.get('alt')})"))
                    continue
                ok = False
                findings.append(_finding("FAIL", "refdes", f"parameters {label} names MPN {mpn_text} for {ref} but {ref} carries {carried}"))
            matched += ok
            continue
        if any(tokens & set(expected) for _, tokens in all_tokens):
            matched += 1
            continue
        alt_holders = [c["ref"] for c, tokens in all_tokens if tokens & alts]
        if alt_holders:
            findings.append(_finding("WARN", "alt", f"parameters {label} names MPN {mpn_text}: alternative fitted on "
                                                    f"{_refs_text(alt_holders)} (alt: {part.get('alt')})"))
            continue
        findings.append(_finding("FAIL", "mpn", f"parameters {label} names MPN {mpn_text} but no component carries it"))
    if not any(f.level == "FAIL" for f in findings):
        findings.insert(0, _finding("PASS", "mpn", f"every parameters role with an MPN is on the BOM ({matched} roles matched)"))
    if pending_roles:
        findings.append(_finding("INFO", "pending", f"{len(pending_roles)} parameters roles name no MPN yet and are not checked: "
                                 + _refs_text(pending_roles)))
    return findings


def _is_passive(ref: str) -> bool:
    return ref.startswith("#") or ref_prefix(ref) in PASSIVE_PREFIXES


def check_unlisted(components: list[dict], params: dict) -> list[Finding]:
    """Fitted parts no [[parts]] row mentions: their ratings are not checked."""
    listed: set[str] = set()
    for part in _unique_rows(params):
        listed |= set(expected_tokens(part)) | alt_tokens(part)
        if not _is_placeholder(part.get("mpn")):
            listed |= free_text_tokens(str(part["mpn"]))
    unlisted: dict[str, list[str]] = {}
    passives: dict[str, list[str]] = {}
    for c in components:
        mpn = component_mpn(c)
        if mpn is None or component_tokens(c) & listed:
            continue
        (passives if _is_passive(c["ref"]) else unlisted).setdefault(mpn.strip(), []).append(c["ref"])
    findings = [_finding("WARN", "unlisted", f"MPN {mpn} on {_refs_text(refs)} ({len(refs)} part{'s' if len(refs) != 1 else ''}): "
                                              "no parameters row mentions it, ratings not checked")
                for mpn, refs in sorted(unlisted.items())]
    if passives:
        count = sum(len(refs) for refs in passives.values())
        findings.append(_finding("INFO", "passive", f"{count} passives, test points and mechanical parts carry {len(passives)} "
                                                     "MPNs that no parameters row mentions (not rated individually)"))
    return findings


def check(components: list[dict], params: dict) -> list[Finding]:
    return check_roles(components, params) + check_unlisted(components, params)


def load_params(path: Path) -> dict:
    try:
        with path.open("rb") as handle:
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
    parser.add_argument("--bom", type=Path, required=True, help="component list, CSV")
    parser.add_argument("--params", type=Path, default=Path("parameters.toml"), help="parameters.toml")
    parser.add_argument("--json", action="store_true", help="print findings as JSON")
    args = parser.parse_args(argv)
    try:
        try:
            text = args.bom.read_text(encoding="utf-8-sig")
        except OSError as error:
            raise ToolError(f"BOM cannot be read: {args.bom}: {error}") from error
        findings = check(parse_bom(text), load_params(args.params))
    except ToolError as error:
        print(f"could not run: {error}")
        return 2
    return emit(findings, "part role check", args.json)


if __name__ == "__main__":
    sys.exit(main())
