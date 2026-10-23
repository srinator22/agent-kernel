#!/usr/bin/env python3
"""Check part ratings, TVS devices and clamps against the voltage domains and the derating policy.

Purpose
    A part is only safe if its absolute-maximum ratings sit above what its
    domain can do to it, with margin. This check compares each part's voltage,
    continuous current, inductor saturation current and temperature grade
    with the operating values and the derating policy in the parameters
    file, so a rating that was never compared cannot hide.

Inputs
    --params FILE   parameters.toml (default: ./parameters.toml)
    --json          print findings as JSON

parameters.toml tables read
    [derating]                          every key required, all numbers
      voltage_steady_state_factor = 1.5   v_abs_max >= factor x steady voltage
      voltage_transient_margin    = 1.1   v_abs_max >= margin x domain clamp
      current_continuous_factor   = 0.7   demand <= factor x continuous rating
      inductor_saturation_factor  = 1.3   i_sat >= factor x peak current
      temperature_grade_min_c     = 105   part grade >= this
    [domains.<NAME>]                    one table per voltage domain
      v_steady_max = 12.6                 highest steady voltage (number)
      clamp_max_v = 30.0                  highest voltage the clamp lets through
      min_part_voltage_rating = 40.0      lowest v_abs_max any part there may have
      voltage_steady_state_factor = ...   optional override of the policy value
      voltage_transient_margin = ...      optional override
    [[parts]]
      ref = "U1"                          required
      domain = "12V"                      required, a [domains] name
      v_abs_max = 60.0                    number or "pending"; or
      v_abs_max_min_required = 40.0       a requirement for a part not chosen yet
      v_reverse_max = 40.0                a part with no supply rating
      status = "datasheet"                datasheet | decision | estimate | pending
      datasheet = "datasheets/u1.pdf"     "pending" or "NOT RETRIEVED..." warns
      i_cont_a = 5.0                      continuous current rating (or
      i_cont_a_per_ch = 2.0               per channel)
      demand = "item:loads:fan:i_a"       the current it must carry (sources below)
      parallel_devices = 2                demand is shared by this many devices
      l_uh = 4.7                          marks an inductor; then i_sat_a (or
      i_sat_a = 9.0                       i_sat_min_a) and i_peak_a (the
      i_peak_a = 5.0                      current it must carry) are needed
      temp_grade_c = 125
      rating_exception = "text"           a documented exception turns a rating
      clamp_rule_exception = "text"       FAIL into an owned WARN; the text is
      temp_grade_exception = "text"       shown in the message
      v_standoff = 13.0                   marks a TVS: standoff must cover the
      v_clamp_max = 21.0                  domain's v_steady_max and its clamp
                                          must not exceed the domain clamp_max_v
    [protection]                        optional
      fuse_rating_a = 25.0
      fuse_continuous_derating = 0.8
      trip_a = 22.0                       electronic limit (eFuse or breaker)
      ov_cutoff_v = 15.0                  and ov_domain = "12V": the cut-off must
      ov_domain = "12V"                   be below that domain's clamp_max_v
    Demand sources (`demand`): const:X | param:a.b | item:TABLE:NAME:FIELD
    (FIELD of the row named NAME in [[TABLE]], for example [[loads]]).

Outputs
    One line per finding: LEVEL, check name, message. A basis that is an
    estimate or pending never produces a plain PASS (WARN instead). Exit 0 no
    FAIL, 1 at least one FAIL, 2 the tool could not run.

Dependencies
    Python 3.11+ standard library only.

Assumptions
    Floats are compared with 1e-9 slack so a part exactly at its derated limit
    is not failed by rounding. A part with no demand source or no rating is
    counted in one INFO line, not silently skipped.

Validation source
    Generalised from a controller-PCB project check; behaviour pinned by
    tests/test_check_ratings.py on made-up fixtures.
"""

from __future__ import annotations

import argparse
import json
import sys
import tomllib
from dataclasses import asdict, dataclass
from pathlib import Path

CHECK = "ratings"
LEVELS = ("PASS", "WARN", "FAIL", "INFO")
UNCERTAIN_STATUSES = ("estimate", "pending")
PENDING = "pending"
EPSILON = 1e-9
POLICY_KEYS = ("voltage_steady_state_factor", "voltage_transient_margin", "current_continuous_factor",
               "inductor_saturation_factor", "temperature_grade_min_c")


class ToolError(Exception):
    """The tool could not run at all (exit code 2)."""


@dataclass(frozen=True)
class Finding:
    level: str
    check: str
    message: str


def is_number(value: object) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def is_pending(value: object) -> bool:
    return value == PENDING


def graded(status: object, check: str, message: str) -> Finding:
    """PASS for a datasheet/decision basis; WARN when the basis is uncertain."""
    if status in UNCERTAIN_STATUSES:
        return Finding("WARN", check, f"{message} (basis status: {status})")
    return Finding("PASS", check, message)


def _status_of(*records: dict) -> str | None:
    statuses = [record.get("status") for record in records]
    for status in statuses:
        if status in UNCERTAIN_STATUSES:
            return status
    return statuses[0] if statuses else None


def resolve_demand(spec: str, params: dict) -> float:
    """The current named by `spec`: 'const:X', 'param:a.b' or 'item:TABLE:NAME:FIELD'."""
    kind, _, rest = spec.partition(":")
    try:
        if kind == "const":
            return float(rest)
        if kind == "param":
            node = params
            for key in rest.split("."):
                node = node[key]
            value = node
        elif kind == "item":
            table, name, field = rest.split(":")
            rows = [r for r in params[table] if isinstance(r, dict) and r.get("name") == name]
            if len(rows) != 1:
                raise ToolError(f"demand {spec!r}: {len(rows)} rows named {name!r} in [[{table}]]")
            value = rows[0][field]
        else:
            raise ToolError(f"unknown demand source {spec!r} (const:, param:, item:)")
    except (KeyError, TypeError, ValueError) as error:
        raise ToolError(f"demand {spec!r} cannot be read: {error!r}") from error
    if not is_number(value):
        raise ToolError(f"demand {spec!r} is not a number ({value!r})")
    return float(value)


def _datasheet_findings(part: dict) -> list[Finding]:
    datasheet = str(part.get("datasheet", ""))
    if datasheet.startswith("NOT RETRIEVED"):
        return [Finding("WARN", f"{CHECK}.datasheet", f"{part['ref']}: unverified: datasheet missing")]
    if datasheet == PENDING:
        return [Finding("WARN", f"{CHECK}.datasheet", f"{part['ref']}: unverified: datasheet not yet stored")]
    return []


def _pending_finding(part: dict, field: str = "v_abs_max") -> Finding:
    path = part.get("datasheet", "no datasheet recorded")
    return Finding("WARN", f"{CHECK}.pending", f"{part['ref']}: {field} is pending; read it from {path}")


def _fail_or_exception(part: dict, check: str, text: str) -> Finding:
    """A documented `rating_exception` turns a rating FAIL into an owned WARN; the text is carried in the message."""
    exception = part.get("rating_exception")
    if isinstance(exception, str) and exception.strip():
        return Finding("WARN", check, f"{text}: excepted: {exception.strip()}")
    return Finding("FAIL", check, text)


def _domain_policy(domain: dict, policy: dict, key: str) -> tuple[float, str]:
    """A [domains.<d>] value overrides the global [derating] value; returns (value, note)."""
    if is_number(domain.get(key)):
        return domain[key], " (domain override)"
    return policy[key], ""


def _rating_findings(part: dict, minimum: float, domain: str) -> list[Finding]:
    ref, rating = part["ref"], part.get("v_abs_max")
    check = f"{CHECK}.rating"
    if is_pending(rating):
        return [_pending_finding(part)]
    if is_number(rating):
        text = f"{ref}: v_abs_max {rating:g} V vs {domain} domain minimum {minimum:g} V"
        if rating < minimum:
            return [_fail_or_exception(part, check, f"{text}: too low")]
        return [graded(part.get("status"), check, text)]
    required = part.get("v_abs_max_min_required")
    if is_number(required):
        text = f"{ref}: required v_abs_max {required:g} V vs {domain} domain minimum {minimum:g} V (part not chosen yet)"
        if required < minimum:
            return [Finding("FAIL", check, f"{text}: requirement is too low")]
        return [Finding("WARN", check, f"{text}: requirement is adequate, select a part meeting it")]
    reverse = part.get("v_reverse_max")
    if is_number(reverse):
        return [Finding("INFO", check, f"{ref}: no v_abs_max, v_reverse_max {reverse:g} V recorded: "
                                       "voltage derating rules skipped (not a supply-rated part)")]
    return [Finding("INFO", check, f"{ref}: no v_abs_max recorded (not a voltage-rated part)")]


def _tvs_findings(part: dict, domain_name: str, domain: dict) -> list[Finding]:
    ref = part["ref"]
    nominal = domain.get("v_steady_max")
    standoff, clamp = part["v_standoff"], part.get("v_clamp_max")
    if not is_number(nominal):
        return [Finding("WARN", f"{CHECK}.tvs", f"{ref}: no v_steady_max known for domain {domain_name}")]
    if not is_number(standoff):
        return [_pending_finding(part, "v_standoff")]
    if not is_number(clamp):
        return [_pending_finding(part, "v_clamp_max")]
    problems, exceptions = [], []
    if standoff < nominal:
        problems.append(f"v_standoff {standoff:g} V is below the domain's highest steady voltage {nominal:g} V")
    if is_number(domain.get("clamp_max_v")) and clamp > domain["clamp_max_v"]:
        reason = part.get("clamp_rule_exception")
        if isinstance(reason, str) and reason.strip():
            exceptions.append(Finding("WARN", f"{CHECK}.tvs",
                                      f"{ref}: v_clamp_max {clamp:g} V exceeds domain clamp {domain['clamp_max_v']:g} V; "
                                      f"recorded exception: {reason.strip()}"))
        else:
            problems.append(f"v_clamp_max {clamp:g} V exceeds domain clamp_max_v {domain['clamp_max_v']:g} V")
    if problems:
        return [Finding("FAIL", f"{CHECK}.tvs", f"{ref}: {'; '.join(problems)}")] + exceptions
    if exceptions:
        return exceptions
    return [graded(part.get("status"), f"{CHECK}.tvs",
                   f"{ref}: stands off {standoff:g} V (needs {nominal:g} V), clamps at {clamp:g} V "
                   f"(domain clamp_max_v {domain.get('clamp_max_v', 'not recorded')})")]


def _voltage_derating_findings(part: dict, domain_name: str, domain: dict, policy: dict) -> list[Finding]:
    """Steady-state and transient derating of v_abs_max; TVS parts never get here."""
    ref, rating = part["ref"], part.get("v_abs_max")
    if not is_number(rating):
        return []
    findings = []
    steady = domain.get("v_steady_max")
    factor, note = _domain_policy(domain, policy, "voltage_steady_state_factor")
    check = f"{CHECK}.derate_steady"
    if not is_number(steady):
        findings.append(Finding("WARN", check, f"{ref}: no v_steady_max known for domain {domain_name}"))
    else:
        needed = factor * steady
        text = f"{ref}: v_abs_max {rating:g} V vs {factor:g} x {domain_name} steady {steady:g} V = {needed:g} V{note}"
        if rating < needed - EPSILON:
            findings.append(_fail_or_exception(part, check, f"{text}: below the steady-state derating"))
        else:
            findings.append(graded(part.get("status"), check, text))
    clamp = domain.get("clamp_max_v")
    margin, note = _domain_policy(domain, policy, "voltage_transient_margin")
    check = f"{CHECK}.derate_transient"
    if not is_number(clamp):
        findings.append(Finding("WARN", check, f"{ref}: domain {domain_name} clamp_max_v is {clamp!r}, transient margin not checked"))
    else:
        needed = margin * clamp
        text = f"{ref}: v_abs_max {rating:g} V vs {margin:g} x {domain_name} clamp {clamp:g} V = {needed:g} V{note}"
        if rating < needed - EPSILON:
            findings.append(_fail_or_exception(part, check, f"{text}: below the transient margin"))
        else:
            findings.append(graded(part.get("status"), check, text))
    return findings


def _part_findings(part: dict, params: dict) -> list[Finding]:
    findings = _datasheet_findings(part)
    domains = params.get("domains", {})
    domain_name = part.get("domain")
    domain = domains.get(domain_name)
    if domain is None:
        return findings + [Finding("FAIL", f"{CHECK}.domain", f"{part['ref']}: domain {domain_name!r} is not in [domains]")]
    if "v_standoff" in part:
        return findings + _tvs_findings(part, domain_name, domain)
    minimum = domain.get("min_part_voltage_rating")
    if is_number(minimum):
        findings += _rating_findings(part, minimum, domain_name)
    else:
        findings.append(Finding("WARN", f"{CHECK}.rating", f"{part['ref']}: domain {domain_name} minimum rating is {minimum!r}"))
    return findings + _voltage_derating_findings(part, domain_name, domain, params["derating"])


def _current_rating(part: dict):
    for field in ("i_cont_a", "i_cont_a_per_ch"):
        if field in part:
            return field, part[field]
    return None, None


def _current_findings(params: dict) -> list[Finding]:
    """Continuous current derating: demand <= factor x rating."""
    factor = params["derating"]["current_continuous_factor"]
    check = f"{CHECK}.derate_current"
    findings, no_rating, no_demand = [], [], []
    for part in params.get("parts", []):
        ref = part["ref"]
        field, rating = _current_rating(part)
        spec = part.get("demand")
        if rating is None:
            if spec:
                no_rating.append(ref)
            continue
        if not spec:
            no_demand.append(ref)
            continue
        if not is_number(rating):
            findings.append(Finding("WARN", check, f"{ref}: rating {rating!r} ({field}); read it from "
                                                   f"{part.get('datasheet', 'no datasheet recorded')}"))
            continue
        amps = resolve_demand(spec, params)
        description = spec
        devices = part.get("parallel_devices")
        shared = ""
        if is_number(devices) and devices > 1:
            amps, shared = amps / devices, f" shared by {devices:g} parallel devices, per device"
            description = f"{spec} / {devices:g}"
        limit = factor * rating
        text = f"{ref}: demand {amps:g} A{shared} ({description}) vs {factor:g} x {field} {rating:g} A = {limit:g} A"
        if amps > limit + EPSILON:
            findings.append(Finding("FAIL", check, f"{text}: over the continuous-current derating"))
        else:
            findings.append(graded(part.get("status"), check, text))
    notes = []
    if no_rating:
        notes.append(f"no continuous current rating recorded for {', '.join(no_rating)}")
    if no_demand:
        notes.append(f"no demand source for {', '.join(no_demand)}")
    if notes:
        findings.append(Finding("INFO", check, f"current derating not evaluated: {'; '.join(notes)}"))
    return findings


def _inductor_findings(params: dict) -> list[Finding]:
    factor = params["derating"]["inductor_saturation_factor"]
    check = f"{CHECK}.derate_inductor"
    findings = []
    for part in params.get("parts", []):
        if "l_uh" not in part:
            continue
        ref = part["ref"]
        field = "i_sat_a" if "i_sat_a" in part else "i_sat_min_a"
        saturation = part.get(field)
        if not is_number(saturation):
            findings.append(Finding("WARN", check, f"{ref}: {field} is {saturation!r}; saturation current not recorded"))
            continue
        peak = part.get("i_peak_a")
        if not is_number(peak):
            findings.append(Finding("WARN", check, f"{ref}: i_peak_a is {peak!r}; the peak current is not recorded"))
            continue
        needed = factor * peak
        text = (f"{ref}: {field} {saturation:g} A vs {factor:g} x peak {peak:g} A = {needed:.2f} A "
                f"({part.get('i_peak_source', 'peak source not recorded')})")
        if saturation < needed - EPSILON:
            findings.append(Finding("FAIL", check, f"{text}: saturates before the derated peak"))
        else:
            findings.append(graded(part.get("status"), check, text))
    return findings


def _temperature_findings(params: dict) -> list[Finding]:
    minimum = params["derating"]["temperature_grade_min_c"]
    check = f"{CHECK}.temp_grade"
    findings, unrecorded = [], []
    for part in params.get("parts", []):
        grade = part.get("temp_grade_c")
        if not is_number(grade):
            unrecorded.append(part["ref"])
            continue
        text = f"{part['ref']}: temp_grade_c {grade:g} C vs minimum {minimum:g} C"
        if grade < minimum - EPSILON:
            reason = part.get("temp_grade_exception")
            if isinstance(reason, str) and reason.strip():
                findings.append(Finding("WARN", check, f"{text}: below the minimum; recorded exception: {reason.strip()}"))
                continue
            findings.append(Finding("FAIL", check, f"{text}: below the minimum temperature grade"))
        else:
            findings.append(graded(part.get("status"), check, text))
    if unrecorded:
        findings.append(Finding("INFO", check, f"{len(unrecorded)} parts have no temp_grade_c recorded (minimum "
                                               f"{minimum:g} C not checked): {', '.join(unrecorded)}"))
    return findings


def _domain_findings(params: dict) -> list[Finding]:
    findings = []
    for name, domain in params.get("domains", {}).items():
        clamp, minimum = domain.get("clamp_max_v"), domain.get("min_part_voltage_rating")
        if not (is_number(clamp) and is_number(minimum)):
            findings.append(Finding("WARN", f"{CHECK}.domain", f"domain {name}: clamp_max_v or minimum rating is pending"))
            continue
        text = f"domain {name}: clamp_max_v {clamp:g} V vs minimum part rating {minimum:g} V"
        if clamp > minimum:
            findings.append(Finding("FAIL", f"{CHECK}.domain", f"{text}: the clamp exceeds what a minimum-rated part survives"))
        elif clamp == minimum:
            findings.append(Finding("WARN", f"{CHECK}.domain", f"{text}: zero margin, a minimum-rated part sits exactly at its limit"))
        else:
            findings.append(Finding("INFO", f"{CHECK}.domain", f"{text}: margin {minimum - clamp:g} V"))
    return findings


def _protection_findings(params: dict) -> list[Finding]:
    protection = params.get("protection")
    if not isinstance(protection, dict):
        return []
    findings = []
    fuse, trip = protection.get("fuse_rating_a"), protection.get("trip_a")
    if is_number(fuse) and is_number(trip):
        derating = protection.get("fuse_continuous_derating", 1.0)
        continuous = fuse * derating
        first = "electronic limit" if trip < fuse else "fuse"
        text = (f"electronic limit trips at {trip:g} A; fuse is rated {fuse:g} A ({continuous:g} A continuous): "
                f"the {first} acts first on an overload")
        if trip > continuous:
            text += f"; between {continuous:g} A and {trip:g} A the fuse carries more than its continuous rating"
        findings.append(Finding("INFO", f"{CHECK}.protection_order", text))
    cutoff = protection.get("ov_cutoff_v")
    clamp = params.get("domains", {}).get(protection.get("ov_domain"), {}).get("clamp_max_v")
    if is_number(cutoff) and is_number(clamp):
        message = f"ov_cutoff_v {cutoff:g} V vs {protection['ov_domain']} domain clamp_max_v {clamp:g} V"
        if cutoff < clamp:
            findings.append(Finding("INFO", f"{CHECK}.ov_cutoff", f"{message}: the cut-off operates below the clamp"))
        else:
            findings.append(Finding("FAIL", f"{CHECK}.ov_cutoff", f"{message}: the cut-off must be below the clamp"))
    return findings


def _require_policy(params: dict) -> None:
    policy = params.get("derating")
    if not isinstance(policy, dict):
        raise ToolError("the parameters have no [derating] table")
    for key in POLICY_KEYS:
        if not is_number(policy.get(key)):
            raise ToolError(f"[derating] {key} is missing or not a number")
    for part in params.get("parts", []):
        if not isinstance(part, dict) or not isinstance(part.get("ref"), str):
            raise ToolError("every [[parts]] row needs a string `ref`")


def _policy_findings(params: dict) -> list[Finding]:
    policy = params["derating"]
    text = (f"derating policy: v_abs_max >= {policy['voltage_steady_state_factor']:g} x steady voltage and >= "
            f"{policy['voltage_transient_margin']:g} x domain clamp; continuous current <= "
            f"{policy['current_continuous_factor']:g} x rating; inductor Isat >= "
            f"{policy['inductor_saturation_factor']:g} x peak current; temperature grade >= "
            f"{policy['temperature_grade_min_c']:g} C; TVS parts keep their standoff and clamp checks")
    return [Finding("INFO", f"{CHECK}.policy", text)]


def run(params: dict) -> list[Finding]:
    _require_policy(params)
    findings = _policy_findings(params)
    for part in params.get("parts", []):
        findings.extend(_part_findings(part, params))
    findings.extend(_current_findings(params))
    findings.extend(_inductor_findings(params))
    findings.extend(_temperature_findings(params))
    findings.extend(_domain_findings(params))
    findings.extend(_protection_findings(params))
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
    parser.add_argument("--params", type=Path, default=Path("parameters.toml"), help="parameters.toml")
    parser.add_argument("--json", action="store_true", help="print findings as JSON")
    args = parser.parse_args(argv)
    try:
        findings = run(load_params(args.params))
    except ToolError as error:
        print(f"could not run: {error}")
        return 2
    return emit(findings, "ratings check", args.json)


if __name__ == "__main__":
    sys.exit(main())
