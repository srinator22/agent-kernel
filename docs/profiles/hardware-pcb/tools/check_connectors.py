#!/usr/bin/env python3
"""Check connector ports: cross-plug damage analysis, per-contact current loading and header pin lists.

Purpose
    Two connectors that physically mate must not be able to destroy each
    other, and no contact may carry more than its rating. The check walks
    every pair of port groups that can mate (by coding), plugs pin n into
    socket pin n, and fails a pairing where a driving socket pin meets a
    pin class it would damage. It also divides each port's current over its
    contacts and compares that with the contact rating.

Inputs
    --params FILE   parameters.toml (default: ./parameters.toml)
    --json          print findings as JSON

parameters.toml tables read
    [connector_matability]              coding -> list of codings it mates with
      "round4" = ["round4"]             (a plug of the key mates sockets listed)
    [connector_hazard]
      damaging_if_socket_drives = ["24V", "12V"]   pin classes that, driven by
      onto_plug_classes = ["5V", "SIG", "GND"]     the socket, damage a plug pin
      damaging_pairs = [["24V", "12V"]]            extra (socket, plug) class
                                                   pairs that damage, optional
    [[ports]]
      id = "P1"                         required, unique label
      name = "Main input"
      coding = "round4"                 required; no entry in
                                        connector_matability is a FAIL elsewhere
      pins = { 1 = "24V", 2 = "GND" }   pin number -> class; ports with the
                                        same coding and the same pins are
                                        interchangeable (INFO: label them)
      load = "motor"                    a [[loads]] row; its i_peak is the current
      contacts_per_pole = 2             contacts sharing a pole (default 1)
      contact_rating_a = 10.0           per-contact rating
      retired = "reason"                history row: listed, never compared
      kind = "header"                   a board header a panel pigtail lands on:
      part = "J5"                       the [[parts]] row (ref) giving i_cont_a
      circuits = 6                      circuit count fitted
      contacts = [ { net = "VBUS", pins = [1, 2], loads = { motor = 1 }, i_a = 0.0,
                     current = "peak" }, { net = "SIG", pins = [3], signal = true } ]
    [input]                             optional
      port = "P1"                       the port that carries the input current
      i_design_max = 20.0               and its number, with status
      status = "datasheet"
    [[loads]]  name, i_nominal, i_peak, status
    [[parts]]  ref (comma-separated refs allowed), i_cont_a, status
    [derating]  current_continuous_factor   (needed only when a header exists)

Rules
    - Cross-plug: FAIL for a damaging pairing, INFO for a benign one, INFO for
      interchangeable ports.
    - Contact loading: current / contacts_per_pole over contact_rating_a: FAIL
      over the rating, WARN above 80 percent or when the current is an
      estimate or pending, else PASS. A port with no load and not the input
      port is listed once as unmapped, not silently skipped.
    - Headers: per-circuit current over the part's i_cont_a derated by
      current_continuous_factor, with the same 80 percent warning; a pin
      outside 1..circuits or listed twice FAILs; two live headers with the
      same coding FAIL (a pigtail fits both).

Outputs
    One line per finding: LEVEL, check name, message. Exit 0 no FAIL, 1 at
    least one FAIL, 2 the tool could not run.

Dependencies
    Python 3.11+ standard library only.

Assumptions
    Pin numbers of a plug and a socket meet pin to pin by the same label;
    mirrored pinouts must be written mirrored in the parameters.

Validation source
    Generalised from a controller-PCB project check; behaviour pinned by
    tests/test_check_connectors.py on made-up fixtures.
"""

from __future__ import annotations

import argparse
import json
import sys
import tomllib
from dataclasses import asdict, dataclass
from pathlib import Path

CHECK = "connectors"
LEVELS = ("PASS", "WARN", "FAIL", "INFO")
UNCERTAIN_STATUSES = ("estimate", "pending")
WARN_FRACTION = 0.80
HEADER_KIND = "header"
CURRENT_FIELDS = {"nominal": "i_nominal", "peak": "i_peak"}


class ToolError(Exception):
    """The tool could not run at all (exit code 2)."""


@dataclass(frozen=True)
class Finding:
    level: str
    check: str
    message: str


def is_number(value: object) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def by_name(items) -> dict[str, dict]:
    return {item["name"]: item for item in items if isinstance(item, dict) and "name" in item}


def _live(ports: list[dict]) -> list[dict]:
    return [port for port in ports if not port.get("retired")]


def _pin_order(pin: str) -> tuple[int, str]:
    return (int(pin), pin) if str(pin).isdigit() else (10 ** 6, str(pin))


def _groups(ports: list[dict]) -> list[list[dict]]:
    """Group ports with the same coding and identical pinout (interchangeable)."""
    grouped: dict[tuple, list[dict]] = {}
    for port in ports:
        if port.get("pins"):
            key = (port["coding"], tuple(sorted((str(k), v) for k, v in port["pins"].items())))
            grouped.setdefault(key, []).append(port)
    return list(grouped.values())


def _ids(group: list[dict]) -> str:
    return ", ".join(port["id"] for port in group)


def _is_damaging(socket_class: str, plug_class: str, hazard: dict) -> bool:
    if socket_class in hazard.get("damaging_if_socket_drives", []) and plug_class in hazard.get("onto_plug_classes", []):
        return True
    return [socket_class, plug_class] in [list(pair) for pair in hazard.get("damaging_pairs", [])]


def _damaging_pins(plug: dict, socket: dict, hazard: dict) -> list[str]:
    """Plug pin n meets socket pin n for every pin both ports have."""
    plug_pins = {str(k): v for k, v in plug["pins"].items()}
    socket_pins = {str(k): v for k, v in socket["pins"].items()}
    bad = []
    for pin in sorted(set(plug_pins) & set(socket_pins), key=_pin_order):
        if _is_damaging(socket_pins[pin], plug_pins[pin], hazard):
            bad.append(f"pin {pin}: socket {socket_pins[pin]} onto plug {plug_pins[pin]}")
    return bad


def cross_plug_findings(params: dict) -> list[Finding]:
    matability = params.get("connector_matability", {})
    hazard = params.get("connector_hazard", {})
    groups = _groups(_live(params.get("ports", [])))
    findings = []
    for group in groups:
        if len(group) > 1:
            findings.append(Finding("INFO", f"{CHECK}.interchangeable",
                                    f"ports {_ids(group)} ({group[0]['coding']}) are interchangeable - label the ports"))
    for plug_group in groups:
        for socket_group in groups:
            if plug_group is socket_group:
                continue
            plug, socket = plug_group[0], socket_group[0]
            if socket["coding"] not in matability.get(plug["coding"], []):
                continue
            where = f"plug {_ids(plug_group)} into socket {_ids(socket_group)}"
            bad = _damaging_pins(plug, socket, hazard)
            if bad:
                findings.append(Finding("FAIL", f"{CHECK}.cross_plug", f"{where}: DAMAGING, {'; '.join(bad)}"))
            else:
                findings.append(Finding("INFO", f"{CHECK}.cross_plug", f"{where}: benign"))
    return findings


def coding_findings(params: dict) -> list[Finding]:
    """Every live port's coding must be a key of connector_matability, and every mate must be one too."""
    matability = params.get("connector_matability", {})
    findings = []
    for port in _live(params.get("ports", [])):
        if port.get("coding") not in matability:
            findings.append(Finding("FAIL", f"{CHECK}.coding",
                                    f"port {port['id']}: coding {port.get('coding')!r} has no connector_matability entry"))
    for plug, sockets in matability.items():
        for socket in sockets:
            if socket not in matability:
                findings.append(Finding("FAIL", f"{CHECK}.coding", f"connector_matability {plug}: mates with unknown coding {socket!r}"))
    return findings


def _contact_current(port: dict, params: dict):
    """(amps through the port, label, status of that number) or None if unmapped."""
    if "load" in port:
        load = by_name(params.get("loads", [])).get(port["load"])
        if load is None:
            raise ToolError(f"port {port['id']}: load {port['load']!r} is not in [[loads]]")
        return load.get("i_peak"), f"{port['load']} i_peak", load.get("status")
    inputs = params.get("input", {})
    if inputs.get("port") and port["id"] == inputs["port"]:
        return inputs.get("i_design_max"), "input i_design_max", inputs.get("status")
    return None


def contact_loading_findings(params: dict) -> list[Finding]:
    """The wall ports (every live row that is not a header): current over contacts_per_pole against contact_rating_a."""
    findings, unmapped = [], []
    retired = [port["id"] for port in params.get("ports", []) if port.get("retired")]
    for port in _live(params.get("ports", [])):
        if port.get("kind") == HEADER_KIND:
            continue
        mapped = _contact_current(port, params)
        rating = port.get("contact_rating_a")
        if mapped is None or not is_number(rating):
            unmapped.append(port["id"])
            continue
        current, label, status = mapped
        name = f"{port['id']} {port.get('name', '')}".rstrip()
        if not is_number(current):
            findings.append(Finding("WARN", f"{CHECK}.contact_load", f"{name}: {label} is {current!r}, loading not computed"))
            continue
        contacts = port.get("contacts_per_pole", 1)
        per_contact = current / contacts
        text = (f"{name}: {label} {current:g} A / {contacts} contact(s) = {per_contact:.2f} A per contact "
                f"vs {rating:g} A rating ({per_contact / rating:.0%})")
        if per_contact > rating:
            findings.append(Finding("FAIL", f"{CHECK}.contact_load", f"{text}: over rating"))
        elif per_contact > WARN_FRACTION * rating:
            findings.append(Finding("WARN", f"{CHECK}.contact_load", f"{text}: above {WARN_FRACTION:.0%} of rating"))
        elif status in UNCERTAIN_STATUSES:
            findings.append(Finding("WARN", f"{CHECK}.contact_load", f"{text}: within rating but the current is {status}"))
        else:
            findings.append(Finding("PASS", f"{CHECK}.contact_load", text))
    if unmapped:
        findings.append(Finding("INFO", f"{CHECK}.unmapped",
                                f"no load mapped or no contact rating, contact loading not checked: {', '.join(unmapped)}"))
    if retired:
        findings.append(Finding("INFO", f"{CHECK}.retired",
                                f"retired rows, neither cross-plug compared nor rated: {', '.join(retired)}"))
    return findings


# --------------------------------------------------------------------------- grouped-port headers

def _part_row(params: dict, ref: str) -> dict | None:
    """The [[parts]] row whose ref list (comma separated) names ref."""
    for part in params.get("parts", []):
        if ref in [r.strip() for r in str(part.get("ref", "")).split(",")]:
            return part
    return None


def _contact_amps(contact: dict, loads: dict[str, dict]) -> tuple[float, list[str], list[str]]:
    """(amps through the contact group, unknown load names, uncertain statuses) from i_a and/or loads {name: qty}."""
    field = CURRENT_FIELDS.get(contact.get("current", "nominal"), contact.get("current", "nominal"))
    amps = float(contact.get("i_a", 0.0))
    unknown, uncertain = [], []
    for name, qty in (contact.get("loads") or {}).items():
        load = loads.get(name)
        value = load.get(field) if load is not None else None
        if load is None or not is_number(value):
            unknown.append(f"{name}.{field}")
            continue
        amps += qty * value
        if load.get("status") in UNCERTAIN_STATUSES:
            uncertain.append(f"{name} {load['status']}")
    return amps, unknown, uncertain


def _pin_problems(header: dict) -> list[str]:
    circuits = header.get("circuits")
    seen: dict[int, str] = {}
    problems = []
    for contact in header.get("contacts", []):
        for pin in contact.get("pins", []):
            if not isinstance(pin, int) or not is_number(circuits) or not 1 <= pin <= circuits:
                problems.append(f"{contact.get('net')} pin {pin} is outside 1 to {circuits}")
            elif pin in seen:
                problems.append(f"pin {pin} is listed for {seen[pin]} and {contact.get('net')}")
            else:
                seen[pin] = contact.get("net")
    return problems


def _header_load(header: dict, params: dict) -> Finding:
    head = f"{header['id']} {header.get('name', '')}".rstrip()
    check = f"{CHECK}.header_load"
    loads = by_name(params.get("loads", []))
    rated = [c for c in header.get("contacts", []) if not c.get("signal")]
    signal = sum(len(c.get("pins", [])) for c in header.get("contacts", []) if c.get("signal"))
    tail = f"; {signal} signal circuit(s) not rated" if signal else ""
    if not rated:
        return Finding("INFO", check, f"{head}: {signal} signal circuit(s), no power contact to rate")
    part = _part_row(params, header.get("part", header["id"]))
    if part is None:
        return Finding("FAIL", check, f"{head}: no [[parts]] row for {header.get('part', header['id'])}, "
                                      "so its contacts cannot be rated")
    rating = part.get("i_cont_a")
    if not is_number(rating):
        return Finding("WARN", check, f"{head}: [[parts]] {part.get('ref')} i_cont_a is {rating!r}, contact loading not computed{tail}")
    factor = params.get("derating", {}).get("current_continuous_factor")
    if not is_number(factor):
        raise ToolError("a header needs [derating] current_continuous_factor")
    derated = factor * rating
    worst, worst_text, unknown, uncertain = -1.0, "", [], []
    for contact in rated:
        amps, missing, doubt = _contact_amps(contact, loads)
        unknown += missing
        uncertain += doubt
        pins = contact.get("pins", [])
        per = amps / len(pins) if pins else float("inf")
        if per > worst:
            worst = per
            worst_text = (f"worst {contact.get('net')} {amps:.2f} A over {len(pins)} circuit(s) = {per:.2f} A per "
                          f"circuit vs {rating:g} A x {factor:g} = {derated:.2f} A derated ({per / derated:.0%})")
    if unknown:
        return Finding("FAIL", check, f"{head}: unknown load or field {', '.join(sorted(set(unknown)))}")
    text = f"{head}: {worst_text}{tail}"
    if worst > derated:
        return Finding("FAIL", check, f"{text}: over the derated rating")
    if worst > WARN_FRACTION * derated:
        return Finding("WARN", check, f"{text}: above {WARN_FRACTION:.0%} of the derated rating")
    if uncertain or part.get("status") in UNCERTAIN_STATUSES:
        what = ", ".join(sorted(set(uncertain))) or f"rating {part.get('status')}"
        return Finding("WARN", check, f"{text}: within the derated rating, but the current is uncertain ({what})")
    return Finding("PASS", check, text)


def header_findings(params: dict) -> list[Finding]:
    """One header_load line per live header, a header_pins FAIL per bad pin list and a header_coding FAIL per coding
    two live headers share (the distinct circuit counts that stop a pigtail entering the wrong header)."""
    headers = [port for port in _live(params.get("ports", [])) if port.get("kind") == HEADER_KIND]
    findings = []
    by_coding: dict[str, list[str]] = {}
    for header in headers:
        by_coding.setdefault(header.get("coding"), []).append(header["id"])
        for problem in _pin_problems(header):
            findings.append(Finding("FAIL", f"{CHECK}.header_pins", f"{header['id']}: {problem}"))
        findings.append(_header_load(header, params))
    for coding, ids in by_coding.items():
        if len(ids) > 1:
            findings.append(Finding("FAIL", f"{CHECK}.header_coding",
                                    f"headers {', '.join(ids)} share coding {coding!r}: a pigtail fits more than one"))
    return findings


def run(params: dict) -> list[Finding]:
    ports = params.get("ports")
    if not isinstance(ports, list) or not ports:
        raise ToolError("the parameters have no [[ports]] rows")
    for port in ports:
        if not isinstance(port, dict) or "id" not in port:
            raise ToolError("every [[ports]] row needs an `id`")
    ids = [port["id"] for port in ports]
    duplicates = sorted({i for i in ids if ids.count(i) > 1})
    findings = [Finding("FAIL", f"{CHECK}.duplicate", f"port id {i} appears more than once") for i in duplicates]
    return findings + coding_findings(params) + cross_plug_findings(params) + contact_loading_findings(params) + header_findings(params)


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
    parser.add_argument("--params", type=Path, default=Path("parameters.toml"), help="parameters.toml")
    parser.add_argument("--json", action="store_true", help="print findings as JSON")
    args = parser.parse_args(argv)
    try:
        findings = run(load_params(args.params))
    except ToolError as error:
        print(f"could not run: {error}")
        return 2
    return emit(findings, "connector check", args.json)


if __name__ == "__main__":
    sys.exit(main())
