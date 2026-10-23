#!/usr/bin/env python3
"""Check a bill of materials against the construction policy: chip size, capacitor type, datasheets, grade.

Purpose
    The BOM must follow the design's construction policy before a board is
    ordered: no passive smaller than the assembly minimum, no capacitor
    chemistry or dielectric the policy forbids, a stored datasheet for every
    active part and connector, and a temperature grade at or above the
    minimum for active parts, inductors and crystals.

Inputs
    --bom FILE        component list, CSV (format below)
    --params FILE     parameters.toml (default: ./parameters.toml)
    --manifest FILE   datasheet manifest (default: ./datasheets/MANIFEST.md);
                      its File column says which datasheets are stored
    --json            print findings as JSON

BOM CSV format
    One row per placed component, header row required, column names
    case-insensitive. Required: ref, value, footprint. Optional (used when
    present): mpn, datasheet, description, rating_note, label, and any
    do-not-fit column named dnp, do_not_fit, fit, fitted, populate or
    fit_option. Any KiCad, Altium or spreadsheet BOM export works once its
    columns are renamed. A footprint names its chip size ("C_0603_1608Metric"
    gives 0603; a metric code is converted when no imperial one is present).

parameters.toml tables read
    [derating]                          all optional
      passive_size_min = "0603"         smallest allowed passive chip size
      temperature_grade_min_c = 105     minimum grade of U, Q, Y and L parts
      bulk_capacitance_f = 4.7e-6       from here a capacitor is "bulk"
      power_cap_size_min = "0805"       smallest allowed bulk capacitor size
    [[rails]]  name                     rail names recognised in a capacitor's
                                        value or rating_note (decoupling note)
    [[parts]]  mpn, alt, datasheet, temp_grade_c, temp_grade_exception
                                        the rated-parts list; a BOM part is
                                        matched to it by normalised part number

Rules
    - Passive (R, C, L, D prefix) below the minimum size: FAIL. Diodes in
      SMA, SMB, SMC or DO-218 packages are not chip passives.
    - Bulk capacitor (>= bulk_capacitance_f, not polarised) below
      power_cap_size_min: WARN. Small rail-decoupling capacitors in the
      minimum size are INFO (accepted practice), not WARN.
    - Capacitor type: Y5V, Z5U and tantalum always FAIL; X5R in a power path
      (size 1206 or larger, or 10 uF or more) FAILs; an electrolytic without
      "polymer" or "hybrid" FAILs; a polarised capacitor with no stated type
      WARNs; capacitors with no stated dielectric are counted (INFO).
    - Datasheet: an active part (prefix U, Q), connector (J, P) with a real
      part number and no stored datasheet FAILs; other prefixes WARN. A
      datasheet counts as stored when the part's own `datasheet` column or
      the matching [[parts]] row names a file listed in the manifest (a
      directory row covers everything below it). Test points, mounting holes,
      net ties and fiducials are exempt. Plain passives with generic values
      are summarised, not required to have a part number.
    - Grade: matching parts below the minimum FAIL unless the [[parts]] row
      has temp_grade_exception (then WARN); parts with no recorded grade are
      counted.
    - Do-not-fit and optional parts are listed (INFO).

Outputs
    One line per finding: LEVEL, check name, message. Exit 0 no FAIL, 1 at
    least one FAIL, 2 the tool could not run.

Dependencies
    Python 3.11+ standard library only.

Assumptions
    Reference prefixes follow the usual convention (R, C, L, D, U, Q, J, P,
    Y, TP, H, MH, NT, FID). A part number is a field that has a digit and a
    letter and is not a placeholder (pending, n/a, tbd, no part, not fitted).

Validation source
    Generalised from a controller-PCB project check that read a netlist
    exported by the CAD tool; this version reads a BOM CSV so it runs without
    the CAD application. Behaviour pinned by tests/test_check_bom.py.
"""

from __future__ import annotations

import argparse
import csv
import json
import re
import sys
import tomllib
from collections import Counter
from dataclasses import asdict, dataclass
from pathlib import Path

CHECK = "bom"
LEVELS = ("PASS", "WARN", "FAIL", "INFO")

SIZES = ("0201", "0402", "0603", "0805", "1206", "1210", "1812", "2010", "2512")
METRIC_TO_IMPERIAL = {"0603": "0201", "1005": "0402", "1608": "0603", "2012": "0805", "3216": "1206",
                      "3225": "1210", "4532": "1812", "5025": "2010", "6332": "2512"}
DEFAULT_BULK_F = 4.7e-6
DEFAULT_POWER_CAP_SIZE = "0805"
DEFAULT_SIZE_MIN = "0603"
DEFAULT_GRADE_MIN_C = 105.0

PASSIVE_REF = re.compile(r"^[RCLD]\d")
CAPACITOR_REF = re.compile(r"^C\d")
DIODE_PACKAGE = re.compile(r"(?<![A-Za-z])(?:SMA|SMB|SMC)(?![A-Za-z])|DO-218", re.IGNORECASE)
SIZE_CODE = re.compile(r"(?<!\d)(0201|0402|0603|0805|1206|1210|1812|2010|2512)(?!\d)")
METRIC_CODE = re.compile(r"(?<!\d)(\d{4})Metric")
DIELECTRIC = re.compile(r"\b(?:X7R|X7S|X7T|X6S|X8R|X5R|C0G|COG|NP0|Y5V|Z5U)\b", re.IGNORECASE)
FORBIDDEN_ALWAYS = (("Y5V", re.compile(r"\bY5V\b", re.IGNORECASE)),
                    ("Z5U", re.compile(r"\bZ5U\b", re.IGNORECASE)),
                    ("tantalum", re.compile(r"tantalum", re.IGNORECASE)))
X5R = re.compile(r"\bX5R\b", re.IGNORECASE)
ELECTROLYTIC = re.compile(r"electrolytic", re.IGNORECASE)
POLYMER_OR_HYBRID = re.compile(r"polymer|hybrid", re.IGNORECASE)
RAIL_WORDS = re.compile(r"\brail\b|\bdecoupl\w*", re.IGNORECASE)
CAP_VALUE = re.compile(r"^\s*(\d+(?:\.\d+)?)\s*([pnuµμm]?)\s*F?\b", re.IGNORECASE)
CAP_VALUE_INFIX = re.compile(r"^\s*(\d+)([pnuµμ])(\d+)\b", re.IGNORECASE)
CAP_MULTIPLIER = {"p": 1e-12, "n": 1e-9, "u": 1e-6, "µ": 1e-6, "μ": 1e-6, "m": 1e-3, "": 1.0}
POLARIZED_WORD = re.compile(r"(?<!un)polari[sz]ed", re.IGNORECASE)

NO_DATASHEET_PREFIXES = {"TP", "T", "H", "MH", "NT", "N", "FID"}
FAIL_WITHOUT_DATASHEET = {"U", "Q", "J", "P"}
GRADED_PREFIXES = {"U", "Q", "Y", "L"}
VALUE_AS_MPN_PREFIXES = {"U", "Q", "Y", "D", "J", "P"}
PLACEHOLDER = re.compile(r"^\s*(?:|-|n/?a|none|pending|tbd)\s*$|pending|no part|not fitted|\btbc\b", re.IGNORECASE)
GENERIC_VALUE = re.compile(r"^\s*(?:\d+(?:\.\d+)?\s*[pnuµμmkKMRG]?\s*(?:F|R|ohm|Ohm)?"
                           r"(?:\s+\d+(?:\.\d+)?\s*[mkK]?\s*(?:V|W))?|\d+[pnuµμkKMRG]\d+)\s*$")
MPN_LOOKS = re.compile(r"^(?=.*\d)(?=.*[A-Za-z])[A-Za-z0-9][A-Za-z0-9#+./\-]{3,}$")
DNP_FIELD_KEYS = ("dnp", "do_not_fit", "do not fit", "fit", "fitted", "populate", "fit_option", "fit option")
DNP_TEXT = re.compile(r"\bDNP\b|do not fit|fit optional|not fitted|optional fit", re.IGNORECASE)
CANONICAL_FIELDS = {"mpn": "MPN", "datasheet": "Datasheet", "description": "Description",
                    "rating_note": "Rating_note", "label": "Label"}
HEX_ROW_SEPARATOR = set("-: ")


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


# ---------------------------------------------------------------- BOM input

def read_bom(path: Path) -> list[dict]:
    """Components as {ref, value, footprint, fields} from a BOM CSV."""
    try:
        text = Path(path).read_text(encoding="utf-8-sig")
    except OSError as error:
        raise ToolError(f"BOM cannot be read: {path}: {error}") from error
    return parse_bom(text)


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
        if not ref:
            continue
        fields = {}
        for lowered, original in names.items():
            if lowered in ("ref", "value", "footprint"):
                continue
            fields[CANONICAL_FIELDS.get(lowered, original.strip())] = (row.get(original) or "").strip()
        components.append({"ref": ref, "value": (row.get(names["value"]) or "").strip(),
                           "footprint": (row.get(names["footprint"]) or "").strip(), "fields": fields})
    if not components:
        raise ToolError("the BOM has no component rows")
    return components


# ---------------------------------------------------------------- small parsers

def ref_prefix(ref: str) -> str:
    match = re.match(r"[A-Za-z]+", ref)
    return match.group().upper() if match else ""


def size_of(footprint: str) -> str | None:
    """The imperial chip size named in a footprint ('C_0603_1608Metric' gives '0603'), or None."""
    codes = SIZE_CODE.findall(footprint)
    if codes:
        return min(codes, key=SIZES.index)
    for metric in METRIC_CODE.findall(footprint):
        if metric in METRIC_TO_IMPERIAL:
            return METRIC_TO_IMPERIAL[metric]
    return None


def size_rank(size: str) -> int:
    return SIZES.index(size)


def capacitance_farads(value: str) -> float | None:
    """Capacitance from a Value like '100n 50V', '4.7uF' or '4u7'; None when it is not a plain capacitance."""
    infix = CAP_VALUE_INFIX.match(value)
    if infix:
        return float(f"{infix.group(1)}.{infix.group(3)}") * CAP_MULTIPLIER[infix.group(2).lower()]
    match = CAP_VALUE.match(value)
    if not match:
        return None
    return float(match.group(1)) * CAP_MULTIPLIER[match.group(2).lower()]


def ref_of(component: dict) -> str:
    return component["ref"]


def _text(component: dict) -> str:
    fields = component["fields"]
    return " ".join([component["value"], fields.get("Rating_note", ""), fields.get("Description", "")])


def _is_polarized(component: dict) -> bool:
    footprint = component["footprint"]
    return "CP_" in footprint or "Elec" in footprint or bool(POLARIZED_WORD.search(component["fields"].get("Description", "")))


def _norm(text: str) -> str:
    return re.sub(r"[^A-Z0-9]", "", text.upper())


def mpn_tokens(text: str) -> set[str]:
    """Normalised part-number candidates in a free-text MPN/alt: the whole text, each ' / ' item and the first word."""
    tokens: set[str] = set()
    for item in re.split(r"\s*/\s+|\s+/\s*", text):
        item = item.strip()
        if not item:
            continue
        tokens.add(_norm(item))
        first = re.split(r"[\s(]", item, maxsplit=1)[0]
        if re.search(r"\d", first):
            tokens.add(_norm(first))
    return {t for t in tokens if t}


def _tokens_match(left: set[str], right: set[str]) -> bool:
    for a in left:
        for b in right:
            if a == b or (min(len(a), len(b)) >= 6 and (a.startswith(b) or b.startswith(a))):
                return True
    return False


def component_mpn(component: dict) -> str | None:
    """The real part number, or None while it is still a placeholder ('pending', 'n/a', ...)."""
    mpn = component["fields"].get("MPN", "").strip()
    if mpn and not PLACEHOLDER.search(mpn):
        return mpn
    value = component["value"].strip()
    if ref_prefix(component["ref"]) in VALUE_AS_MPN_PREFIXES and MPN_LOOKS.match(value) \
            and not GENERIC_VALUE.match(value) and "_" not in value:
        return value
    return None


# ---------------------------------------------------------------- manifest keys

def datasheet_key(path: str, folder: str) -> str | None:
    """A datasheet field or manifest path as 'subfolder/FILE.pdf' under the documents folder; None for placeholders."""
    text = path.strip().strip("`").replace("\\", "/")
    if not text or PLACEHOLDER.search(text):
        return None
    index = text.lower().rfind(f"{folder.lower()}/")
    if index >= 0:
        text = text[index + len(folder) + 1:]
    return text.lstrip("./").lower()


def manifest_keys(manifest_text: str, folder: str) -> set[str]:
    """File-column paths of every Markdown table that has File and SHA-256 columns."""
    keys: set[str] = set()
    column: int | None = None
    for line in manifest_text.splitlines():
        if not line.lstrip().startswith("|"):
            column = None
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        lowered = [c.lower() for c in cells]
        if column is None:
            if "file" in lowered and "sha-256" in lowered:
                column = lowered.index("file")
            continue
        if all(set(c) <= HEX_ROW_SEPARATOR for c in cells) or column >= len(cells):
            continue
        cell = cells[column]
        link = re.search(r"\[[^\]]*\]\(([^)]+)\)", cell)
        key = datasheet_key(link.group(1) if link else cell, folder)
        if key:
            keys.add(key)
    return keys


def datasheet_is_stored(path: str, keys: set[str], folder: str) -> bool:
    key = datasheet_key(path, folder)
    if key is None:
        return False
    return key in keys or any(k.endswith("/") and key.startswith(k) for k in keys)


def _parts_index(params: dict) -> list[dict]:
    index = []
    for part in params.get("parts", []):
        text = " / ".join(str(part[key]) for key in ("mpn", "alt") if isinstance(part.get(key), str))
        if text:
            index.append({"part": part, "tokens": mpn_tokens(text)})
    return index


# ---------------------------------------------------------------- the checks

def _size_min(derating: dict) -> str:
    minimum = str(derating.get("passive_size_min", DEFAULT_SIZE_MIN))
    if minimum not in SIZES:
        raise ToolError(f"derating.passive_size_min {minimum!r} is not one of {', '.join(SIZES)}")
    return minimum


def check_passive_size(components: list[dict], derating: dict) -> list[Finding]:
    minimum = _size_min(derating)
    findings: list[Finding] = []
    chip_count = 0
    for c in components:
        if not PASSIVE_REF.match(c["ref"]) or DIODE_PACKAGE.search(c["footprint"]):
            continue
        size = size_of(c["footprint"])
        if size is None:
            continue
        chip_count += 1
        if size_rank(size) < size_rank(minimum):
            findings.append(_finding("FAIL", "passive_size",
                                     f"{size} passive: {ref_of(c)} ({c['value']}, {c['footprint']}); minimum is {minimum}"))
    if not findings:
        findings.append(_finding("PASS", "passive_size", f"no passive below {minimum} among {chip_count} sized passives"))
    return findings


def _rail_pattern(params: dict) -> re.Pattern:
    names = [str(r["name"]) for r in params.get("rails", []) if isinstance(r, dict) and r.get("name")]
    if not names:
        return RAIL_WORDS
    named = "|".join(re.escape(n) for n in sorted(names, key=len, reverse=True))
    return re.compile(rf"(?<![\w.])(?:{named})(?![\w])|{RAIL_WORDS.pattern}", re.IGNORECASE)


def check_power_rail_capacitors(components: list[dict], derating: dict, params: dict) -> list[Finding]:
    """WARN on bulk capacitors below the power-capacitor size; small local decoupling at the minimum size is accepted."""
    minimum = _size_min(derating)
    power_size = str(derating.get("power_cap_size_min", DEFAULT_POWER_CAP_SIZE))
    if power_size not in SIZES:
        raise ToolError(f"derating.power_cap_size_min {power_size!r} is not one of {', '.join(SIZES)}")
    bulk = derating.get("bulk_capacitance_f", DEFAULT_BULK_F)
    rail = _rail_pattern(params)
    findings: list[Finding] = []
    local = 0
    for c in components:
        if not CAPACITOR_REF.match(c["ref"]) or _is_polarized(c):
            continue
        size = size_of(c["footprint"])
        # A capacitor below the minimum already fails the size check; this is the gap up to the power size.
        if size is None or not size_rank(minimum) <= size_rank(size) < size_rank(power_size):
            continue
        farads = capacitance_farads(c["value"])
        if farads is not None and farads >= bulk * 0.999:
            findings.append(_finding("WARN", "power_rail_cap",
                                     f"bulk capacitor below {power_size}: {ref_of(c)} ({c['value']}, {size}); "
                                     f"the policy asks {power_size} or larger from {bulk * 1e6:g} uF"))
        elif rail.search(c["value"]) or rail.search(c["fields"].get("Rating_note", "")):
            local += 1
    if local:
        findings.append(_finding("INFO", "power_rail_cap",
                                 f"{local} rail-decoupling capacitors under {bulk * 1e6:g} uF in {minimum} (accepted local decoupling)"))
    return findings


def check_capacitor_type(components: list[dict]) -> list[Finding]:
    findings: list[Finding] = []
    no_dielectric: list[str] = []
    capacitors = 0
    for c in components:
        if not CAPACITOR_REF.match(c["ref"]):
            continue
        capacitors += 1
        text = _text(c)
        size = size_of(c["footprint"])
        farads = capacitance_farads(c["value"])
        power_class = (size is not None and size_rank(size) >= size_rank("1206")) or (farads is not None and farads >= 9.99e-6)
        bad = [name for name, pattern in FORBIDDEN_ALWAYS if pattern.search(text)]
        if X5R.search(text) and power_class:
            bad.append("X5R in a power path")
        if ELECTROLYTIC.search(text) and not POLYMER_OR_HYBRID.search(text):
            bad.append("electrolytic without polymer/hybrid")
        if bad:
            findings.append(_finding("FAIL", "capacitor_type", f"forbidden capacitor type ({'; '.join(bad)}): {ref_of(c)} ({c['value']})"))
        elif _is_polarized(c):
            if not POLYMER_OR_HYBRID.search(text) and not DIELECTRIC.search(text):
                findings.append(_finding("WARN", "capacitor_type",
                                         f"polarised capacitor with no stated polymer/hybrid type: {ref_of(c)} ({c['value']})"))
        elif not DIELECTRIC.search(text):
            no_dielectric.append(c["ref"])
    if not any(f.level == "FAIL" for f in findings):
        findings.insert(0, _finding("PASS", "capacitor_type", f"no forbidden capacitor type among {capacitors} capacitors"))
    if no_dielectric:
        findings.append(_finding("INFO", "dielectric",
                                 f"{len(no_dielectric)} capacitors without a stated dielectric (the assembler default "
                                 "must be fixed in the BOM export)"))
    return findings


def check_datasheets(components: list[dict], params: dict, stored: set[str], folder: str) -> list[Finding]:
    parts = _parts_index(params)
    findings: list[Finding] = []
    generic_passives: list[str] = []
    pending: list[str] = []
    checked = covered = 0
    for c in components:
        prefix = ref_prefix(c["ref"])
        if prefix in NO_DATASHEET_PREFIXES:
            continue
        mpn = component_mpn(c)
        if mpn is None:
            if prefix in ("R", "C") and (GENERIC_VALUE.match(c["value"]) or capacitance_farads(c["value"]) is not None):
                generic_passives.append(c["ref"])
            else:
                pending.append(c["ref"])
            continue
        checked += 1
        if datasheet_is_stored(c["fields"].get("Datasheet", ""), stored, folder) \
                or any(_tokens_match(mpn_tokens(mpn), p["tokens"])
                       and datasheet_is_stored(str(p["part"].get("datasheet", "")), stored, folder) for p in parts):
            covered += 1
            continue
        level = "FAIL" if prefix in FAIL_WITHOUT_DATASHEET else "WARN"
        findings.append(_finding(level, "datasheet", f"part without stored datasheet: {ref_of(c)} {mpn}"))
    if not any(f.level == "FAIL" for f in findings):
        findings.insert(0, _finding("PASS", "datasheet", f"no active part or connector lacks a stored datasheet "
                                                          f"({covered} of {checked} parts with a part number are covered)"))
    if generic_passives:
        findings.append(_finding("INFO", "datasheet", f"{len(generic_passives)} plain passives with generic values have no "
                                                       "part number; the assembler picks them within the policy"))
    if pending:
        counts = Counter(ref_prefix(r) for r in pending)
        findings.append(_finding("INFO", "pending_mpn", f"{len(pending)} other components have no part number yet ("
                                 + ", ".join(f"{p} {n}" for p, n in sorted(counts.items())) + ")"))
    return findings


def check_temperature_grade(components: list[dict], params: dict, derating: dict) -> list[Finding]:
    minimum = derating.get("temperature_grade_min_c", DEFAULT_GRADE_MIN_C)
    if not is_number(minimum):
        raise ToolError(f"derating.temperature_grade_min_c is not a number: {minimum!r}")
    parts = _parts_index(params)
    findings: list[Finding] = []
    ungraded: list[str] = []
    graded = 0
    for c in components:
        if ref_prefix(c["ref"]) not in GRADED_PREFIXES:
            continue
        mpn = component_mpn(c)
        if mpn is None:
            continue
        matches = [p["part"] for p in parts if _tokens_match(mpn_tokens(mpn), p["tokens"])]
        grades = [m["temp_grade_c"] for m in matches if is_number(m.get("temp_grade_c"))]
        if not grades:
            ungraded.append(c["ref"])
            continue
        graded += 1
        grade = min(grades)
        if grade >= minimum:
            continue
        exception = next((m.get("temp_grade_exception") for m in matches
                          if m.get("temp_grade_c") == grade and m.get("temp_grade_exception")), None)
        if exception:
            findings.append(_finding("WARN", "temp_grade",
                                     f"{grade:g} C part below the {minimum:g} C minimum, excepted: {ref_of(c)} {mpn} ({exception})"))
        else:
            findings.append(_finding("FAIL", "temp_grade",
                                     f"{grade:g} C part below the {minimum:g} C minimum with no exception: {ref_of(c)} {mpn}"))
    if not findings:
        findings.append(_finding("PASS", "temp_grade", f"all {graded} graded U/Q/Y/L parts meet {minimum:g} C"))
    if ungraded:
        findings.append(_finding("INFO", "temp_grade",
                                 f"{len(ungraded)} U/Q/Y/L components have no temperature grade recorded in the parameters"))
    return findings


def dnp_reason(component: dict) -> str | None:
    """Why a component is marked not fitted or optional, or None."""
    for key, value in component["fields"].items():
        lowered = key.strip().lower()
        if lowered in DNP_FIELD_KEYS:
            text = value.strip().lower()
            positive = lowered in ("fit", "fitted", "populate", "fit_option", "fit option")
            if positive and text in ("no", "false", "0", "dnp", "optional", "not fitted"):
                return f"{key} = {value}"
            if not positive and text not in ("", "no", "false", "0"):
                return f"{key} = {value}"
    for source in (component["value"], component["fields"].get("Rating_note", ""), component["fields"].get("Label", "")):
        match = DNP_TEXT.search(source)
        if match:
            return f"text '{match.group()}'"
    return None


def check_dnp(components: list[dict]) -> list[Finding]:
    return [_finding("INFO", "dnp", f"not fitted or optional: {ref_of(c)} ({c['value']}); {reason}")
            for c in components if (reason := dnp_reason(c))]


def check_summary(components: list[dict]) -> list[Finding]:
    counts = Counter(ref_prefix(c["ref"]) or "?" for c in components)
    return [_finding("INFO", "summary", f"{len(components)} components: " + ", ".join(f"{p} {n}" for p, n in sorted(counts.items())))]


def check(components: list[dict], params: dict, manifest_text: str, folder: str = "datasheets") -> list[Finding]:
    """All BOM policy findings for a parsed component list, the parameters and the manifest text."""
    derating = params.get("derating", {})
    stored = manifest_keys(manifest_text, folder)
    findings: list[Finding] = []
    findings += check_passive_size(components, derating)
    findings += check_power_rail_capacitors(components, derating, params)
    findings += check_capacitor_type(components)
    findings += check_datasheets(components, params, stored, folder)
    findings += check_temperature_grade(components, params, derating)
    findings += check_dnp(components)
    findings += check_summary(components)
    return findings


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
    parser.add_argument("--manifest", type=Path, default=Path("datasheets") / "MANIFEST.md", help="datasheet manifest")
    parser.add_argument("--json", action="store_true", help="print findings as JSON")
    args = parser.parse_args(argv)
    try:
        components = read_bom(args.bom)
        params = load_params(args.params)
        try:
            manifest_text = args.manifest.read_text(encoding="utf-8", errors="replace")
        except OSError as error:
            raise ToolError(f"manifest cannot be read: {args.manifest}: {error}") from error
        folder = args.manifest.resolve().parent.name
        findings = check(components, params, manifest_text, folder)
    except ToolError as error:
        print(f"could not run: {error}")
        return 2
    return emit(findings, "BOM policy check", args.json)


if __name__ == "__main__":
    sys.exit(main())
