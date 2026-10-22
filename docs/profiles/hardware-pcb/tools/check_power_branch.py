#!/usr/bin/env python3
"""Check a fused DC power branch for the second-order failures a part choice causes.

Purpose
    A fuse, wire, capacitor or converter chosen for one reason can fail for
    another: a larger bulk capacitor raises inrush above the fuse's melting
    I2t, a fast fuse sits in front of pulsed loads, a current limit raised
    later leaves the fuse sized on the old value. This check puts those
    couplings in numbers at part-selection time. Every rating is a number or
    null; null means UNKNOWN and is reported, never assumed away.

Checks
    - capacitor charge pulse I2t against the fuse's usable melting I2t
    - fast-acting fuse in front of bulk capacitance or pulsed loads
    - load peaks against the fuse rating and the maker's time-current points
    - continuous load current against the derated fuse rating
    - fuse rating against wire ampacity and holder rating
    - whether the source can deliver enough fault current to clear the fuse
    - rail maximum, overshoot and regeneration against capacitor, fuse and
      load voltage ratings
    - whether a passive zener or TVS can protect the load at all, and a given
      one; an active clamp (brake chopper) is credited on published energy only
    - sizing basis: the value a part was sized from against its current value
    - a branch with no fuse: can its source overheat the smallest wire?

Inputs
    BRANCH            branch description, JSON (format below)
    --strict          exit 1 on UNKNOWN as well as FAIL
    --root DIR        folder that sizing-basis files are read from (default:
                      the folder holding the branch file)
    --json            print findings as JSON

Branch file format (JSON; units are in the key names; null means UNKNOWN)
    name                     text
    rail                     nominal_v, max_v, overshoot_v (start-up or
                             load-release overshoot above max_v)
    source                   rating_a, current_limit_a (the current it really
                             limits at, published or measured), can_sink
    series_resistance_ohm    source_output, wiring, fuse_cold (with the
                             capacitor esr_ohm they bound a resistive pulse)
    capacitor                capacitance_f, voltage_rating_v, esr_ohm,
                             voltage_margin (default 1.25)
    fuse                     rating_a, type ("fast" or "time-delay"),
                             melting_i2t_a2s, pulse_derating (maker's factor
                             for repeated pulses), voltage_rating_v,
                             continuous_fraction (default 0.75),
                             temperature_rerating, time_current (list of
                             [multiple of rating, minimum opening time s])
    (no fuse)                the branch is judged unfused: FAIL when the
                             source current exceeds the smallest wire rating
    holder                   rating_a, derating
    wires                    list of {name, ampacity_a}
    loads                    list of {name, continuous_supply_a,
                             peak_supply_a, peak_duration_s, regeneration_j,
                             max_supply_v}; supply current is what the load
                             draws from this rail, not its phase current.
                             regeneration_j null is UNKNOWN; omit the key for
                             a load that cannot regenerate
    clamp                    optional: standoff_v, clamp_v, clamp_current_a;
                             active: true with energy_j for a brake chopper
    sizing_basis             list of {name, assumed, sizes} plus either
                             current (and current_source) or file and pattern
                             (a regex whose first group is the current value,
                             read from root/file)
    Put the source of each number in a sibling "<key>_source" entry; the tool
    ignores those keys, reviewers do not. A branch needs at least "rail".

Outputs
    One line per finding: STATUS (PASS WARN FAIL UNKNOWN INFO), check name,
    message, then a summary. Exit 0 pass, 1 any FAIL (or UNKNOWN with
    --strict), 2 the tool could not run (unreadable or invalid branch file).

Dependencies
    Python 3.11+ standard library only.

Assumptions
    Melting I2t is an adiabatic figure (pulses under 10 ms); longer pulses
    become WARN rather than FAIL because the fuse sheds heat while it warms.
    A source that cannot push 3x the fuse rating clears a short slowly or not
    at all. A passive clamp needs a load-limit to rail-maximum ratio of at
    least 1.3 to stay off at the rail and still hold the load limit.

Validation source
    Formulas: resistive charge I2t = C V^2 / (2 R); constant-current charge
    I2t = I C V (a capacitor charging from 0 V to V). Generalised from a
    selection-time check written after a fuse opened on a capacitor inrush the
    selection had not examined; the regression for that failure mode is
    UnboundedInrushRegressionTests in tests/test_check_power_branch.py, with
    made-up numbers.
"""

from __future__ import annotations

import argparse
import json
import math
import re
import sys
from dataclasses import asdict, dataclass
from pathlib import Path

PASS, WARN, FAIL, UNKNOWN, INFO = "PASS", "WARN", "FAIL", "UNKNOWN", "INFO"

# Melting I2t is a short-time (adiabatic) figure. For longer pulses the fuse
# loses heat while it warms, so the comparison becomes conservative.
ADIABATIC_LIMIT_S = 0.01
DEFAULT_CAPACITOR_VOLTAGE_MARGIN = 1.25
DEFAULT_CONTINUOUS_FRACTION = 0.75
# A source that cannot push this multiple of the fuse rating clears a short
# slowly or never; the fuse then only covers overload.
FAULT_CLEARING_MULTIPLE = 3.0
# Below this ratio of load maximum to rail maximum no passive zener or TVS
# can both stay off at the rail and clamp under the load limit.
PASSIVE_CLAMP_WINDOW = 1.3


class ToolError(Exception):
    """The tool could not run at all (exit code 2)."""


@dataclass
class Finding:
    status: str
    check: str
    message: str


def _value(mapping: dict, key: str):
    """Return a number or None; absent and null both mean UNKNOWN."""
    value = mapping.get(key) if mapping else None
    return None if value is None else float(value)


def _known(*values) -> bool:
    return all(value is not None for value in values)


def charge_pulse(capacitance_f: float, volts: float, resistance_ohm: float | None,
                 current_limit_a: float | None) -> dict | None:
    """Worst-case charge pulse of a capacitor from 0 V to `volts`.

    Resistive charge: I2t = C V^2 / (2 R), peak V / R, time constant R C.
    Constant-current charge at I: I2t = I C V, duration C V / I.
    With both known, the smaller peak governs.
    """
    charge = capacitance_f * volts
    resistive = None
    if resistance_ohm:
        resistive = {
            "model": f"resistive, R = {resistance_ohm * 1000:.1f} mOhm",
            "peak_a": volts / resistance_ohm,
            "i2t": capacitance_f * volts ** 2 / (2 * resistance_ohm),
            "duration_s": 3 * resistance_ohm * capacitance_f,
        }
    limited = None
    if current_limit_a:
        limited = {
            "model": f"current-limited at {current_limit_a:g} A",
            "peak_a": current_limit_a,
            "i2t": current_limit_a * charge,
            "duration_s": charge / current_limit_a,
        }
    if resistive and limited:
        return limited if limited["peak_a"] < resistive["peak_a"] else resistive
    return limited or resistive


def series_resistance(branch: dict) -> float | None:
    parts = branch.get("series_resistance_ohm", {})
    values = [parts.get(name) for name in ("source_output", "wiring", "fuse_cold")]
    values.append(branch.get("capacitor", {}).get("esr_ohm"))
    if any(value is None for value in values):
        return None
    return float(sum(values))


def usable_i2t(fuse: dict) -> tuple[float | None, str]:
    melting = _value(fuse, "melting_i2t_a2s")
    if melting is None:
        return None, "fuse melting I2t not given"
    derating = _value(fuse, "pulse_derating")
    if derating is None:
        return melting, "no pulse derating entered, so this holds for a single event only"
    return melting * derating, f"melting I2t {melting:g} A2s x pulse derating {derating:g}"


def check_capacitor_inrush(branch: dict) -> list[Finding]:
    capacitor = branch.get("capacitor")
    if not capacitor:
        return []
    findings: list[Finding] = []
    fuse = branch["fuse"]
    source = branch.get("source", {})
    volts = _value(branch["rail"], "max_v") or _value(branch["rail"], "nominal_v")
    capacitance = _value(capacitor, "capacitance_f")
    if not _known(volts, capacitance):
        return [Finding(UNKNOWN, "capacitor inrush", "capacitance or rail voltage not given")]
    charge = capacitance * volts
    energy = 0.5 * capacitance * volts ** 2
    findings.append(Finding(INFO, "capacitor charge",
                            f"{capacitance * 1e6:g} uF to {volts:g} V: Q = {charge:.3f} C, E = {energy:.2f} J"))
    usable, basis = usable_i2t(fuse)
    pulse = charge_pulse(capacitance, volts, series_resistance(branch), _value(source, "current_limit_a"))
    if pulse is None:
        rating = _value(source, "rating_a")
        what_if = ""
        if rating:
            hypothetical = charge_pulse(capacitance, volts, None, rating)
            what_if = (f" If the source limited at its {rating:g} A rating: "
                       f"I2t {hypothetical['i2t']:.2f} A2s over {hypothetical['duration_s'] * 1000:.1f} ms.")
        findings.append(Finding(
            UNKNOWN, "capacitor inrush",
            "charge pulse cannot be bounded: source current limit and the series "
            "resistance (source output, wiring, fuse cold resistance, capacitor ESR) "
            "are not all known. Do not rely on an unpublished soft start." + what_if))
        if fuse.get("type") == "fast":
            findings.append(Finding(
                WARN, "fuse type",
                "fast-acting fuse in front of bulk capacitance with an unbounded "
                "charge pulse: bound the pulse (published or measured source limit), "
                "or choose a fuse whose usable I2t covers the worst credible pulse, "
                "including live insertion against the source's own capacitance; a "
                "time-delay type helps only if inrush is the binding constraint"))
        return findings
    message = (f"{pulse['model']}: peak {pulse['peak_a']:.1f} A, I2t {pulse['i2t']:.2f} A2s "
               f"over {pulse['duration_s'] * 1000:.1f} ms")
    if usable is None:
        findings.append(Finding(UNKNOWN, "capacitor inrush", f"{message}; {basis}"))
        return findings
    ratio = pulse["i2t"] / usable
    message += f"; usable fuse I2t {usable:.2f} A2s ({basis}); pulse uses {ratio * 100:.0f} percent"
    if ratio <= 1.0:
        findings.append(Finding(PASS, "capacitor inrush", message))
    elif pulse["duration_s"] > ADIABATIC_LIMIT_S:
        findings.append(Finding(
            WARN, "capacitor inrush",
            message + f"; the pulse is longer than {ADIABATIC_LIMIT_S * 1000:g} ms so the "
            "I2t comparison is conservative: check the time-current curve"))
    else:
        findings.append(Finding(FAIL, "capacitor inrush", message + "; the fuse is expected to open"))
    return findings


def opening_band(fuse: dict, current_a: float, duration_s: float) -> tuple[str, str] | None:
    """Judge a sustained current against the maker's minimum opening times.

    `time_current` lists [multiple of rating, minimum opening time s]. Below the
    nearest published point the fuse is not stated to open; at or above the
    next point it may open in that point's minimum time. Between the two the
    datasheet says nothing, so the result is a warning, never a pass.
    """
    points = sorted(fuse.get("time_current") or [])
    rating = _value(fuse, "rating_a")
    if not points or rating is None:
        return None
    multiple = current_a / rating
    below = [point for point in points if point[0] <= multiple]
    above = [point for point in points if point[0] >= multiple]
    head = f"{current_a:g} A is {multiple * 100:.0f} percent of {rating:g} A for {duration_s:g} s"
    if below and duration_s >= below[-1][1]:
        return FAIL, f"{head}: at {below[-1][0] * 100:g} percent it may open in {below[-1][1]:g} s"
    if not above or duration_s < above[0][1]:
        return PASS, f"{head}: shorter than every published minimum opening time"
    return WARN, (f"{head}: between published points, and {above[0][0] * 100:g} percent may open "
                  f"in {above[0][1]:g} s; the datasheet does not settle it")


def check_load_pulses(branch: dict) -> list[Finding]:
    findings: list[Finding] = []
    fuse = branch["fuse"]
    usable, basis = usable_i2t(fuse)
    rating = _value(fuse, "rating_a")
    for load in branch.get("loads", []):
        peak = _value(load, "peak_supply_a")
        duration = _value(load, "peak_duration_s")
        name = load.get("name", "load")
        if peak is None:
            findings.append(Finding(UNKNOWN, f"{name} peak", "peak supply current not given"))
            continue
        if rating is not None and peak <= rating:
            findings.append(Finding(PASS, f"{name} peak", f"peak {peak:g} A within the {rating:g} A rating"))
            continue
        if duration is None:
            findings.append(Finding(UNKNOWN, f"{name} peak",
                                    f"peak {peak:g} A exceeds the fuse rating; duration not given"))
            continue
        band = opening_band(fuse, peak, duration)
        if band:
            findings.append(Finding(band[0], f"{name} peak", band[1]))
            continue
        pulse_i2t = peak ** 2 * duration
        if usable is None:
            findings.append(Finding(UNKNOWN, f"{name} peak",
                                    f"peak {peak:g} A for {duration:g} s, I2t {pulse_i2t:.2f} A2s; {basis}"))
            continue
        status = PASS if pulse_i2t <= usable else (WARN if duration > ADIABATIC_LIMIT_S else FAIL)
        findings.append(Finding(status, f"{name} peak",
                                f"peak {peak:g} A for {duration:g} s: I2t {pulse_i2t:.2f} A2s "
                                f"against usable {usable:.2f} A2s"
                                + ("; longer than the adiabatic range, check the time-current curve"
                                   if status == WARN else "")))
    return findings


def check_continuous(branch: dict) -> list[Finding]:
    fuse = branch["fuse"]
    rating = _value(fuse, "rating_a")
    loads = branch.get("loads", [])
    currents = [_value(load, "continuous_supply_a") for load in loads]
    if rating is None or not loads or any(current is None for current in currents):
        return [Finding(UNKNOWN, "fuse continuous", "fuse rating or a load's continuous supply current not given")]
    fraction = _value(fuse, "continuous_fraction") or DEFAULT_CONTINUOUS_FRACTION
    rerating = _value(fuse, "temperature_rerating") or 1.0
    allowed = rating * fraction * rerating
    total = sum(currents)
    message = (f"loads {total:.2f} A against {rating:g} A x {fraction:g} continuous "
               f"x {rerating:g} temperature = {allowed:.2f} A")
    if fuse.get("temperature_rerating") is None:
        message += "; no temperature rerating entered for the enclosure ambient"
    if total > allowed:
        return [Finding(FAIL, "fuse continuous", message)]
    if total > 0.9 * allowed or fuse.get("temperature_rerating") is None:
        return [Finding(WARN, "fuse continuous", message)]
    return [Finding(PASS, "fuse continuous", message)]


def check_protection_chain(branch: dict) -> list[Finding]:
    findings: list[Finding] = []
    fuse = branch["fuse"]
    rating = _value(fuse, "rating_a")
    if rating is None:
        return [Finding(UNKNOWN, "fuse rating", "fuse rating not given")]
    for wire in branch.get("wires", []):
        ampacity = _value(wire, "ampacity_a")
        name = wire.get("name", "wire")
        if ampacity is None:
            findings.append(Finding(UNKNOWN, f"wire {name}", "ampacity not given"))
        elif rating > ampacity:
            findings.append(Finding(FAIL, f"wire {name}", f"fuse {rating:g} A exceeds the wire's {ampacity:g} A ampacity"))
        else:
            findings.append(Finding(PASS, f"wire {name}", f"fuse {rating:g} A within {ampacity:g} A"))
    holder = _value(branch.get("holder", {}), "rating_a")
    if holder is not None:
        derating = _value(branch["holder"], "derating") or 1.0
        status = PASS if rating <= holder * derating else FAIL
        findings.append(Finding(status, "holder", f"fuse {rating:g} A in a {holder:g} A holder x {derating:g} derating"))
    source = branch.get("source", {})
    available = _value(source, "current_limit_a") or _value(source, "rating_a")
    if available is None:
        findings.append(Finding(UNKNOWN, "fault clearing", "source fault current not given"))
    elif available < FAULT_CLEARING_MULTIPLE * rating:
        findings.append(Finding(
            WARN, "fault clearing",
            f"source delivers about {available:g} A, under {FAULT_CLEARING_MULTIPLE:g}x the "
            f"{rating:g} A fuse: a short may be held by the source's limit rather than "
            "cleared, so the fuse covers overload, not short circuit"))
    else:
        findings.append(Finding(PASS, "fault clearing", f"source about {available:g} A against a {rating:g} A fuse"))
    return findings


def clamped_regeneration_peak(branch: dict, pumped: float, regeneration: float, findings: list[Finding]) -> float:
    """The regeneration peak after an active clamp, credited on published data only.

    A clamp (brake chopper) holds the rail at its clamping voltage only if its
    published pulse energy covers the regenerated energy; otherwise the rise
    from capacitance alone stands. Either way a scope on a real stop decides.
    """
    clamp = branch.get("clamp")
    if not clamp or not clamp.get("active"):
        return pumped
    clamp_v = _value(clamp, "clamp_v")
    energy = _value(clamp, "energy_j")
    if clamp_v is None or clamp_v >= pumped:
        return pumped
    if energy is None:
        findings.append(Finding(UNKNOWN, "regeneration clamp",
                                "active clamp energy rating not given, so the rise is not credited"))
        return pumped
    if energy < regeneration:
        findings.append(Finding(WARN, "regeneration clamp",
                                f"clamp absorbs {energy:g} J, less than the {regeneration:g} J regenerated"))
        return pumped
    findings.append(Finding(INFO, "regeneration clamp",
                            f"active clamp holds the rail at about {clamp_v:g} V ({energy:g} J rating "
                            f"against {regeneration:g} J); on paper only, scope a real stop"))
    return clamp_v


def check_voltages(branch: dict) -> list[Finding]:
    findings: list[Finding] = []
    rail = branch["rail"]
    maximum = _value(rail, "max_v")
    overshoot = _value(rail, "overshoot_v")
    if maximum is None:
        return [Finding(UNKNOWN, "rail maximum", "rail maximum voltage not given")]
    peak = maximum + (overshoot or 0.0)
    if overshoot is None:
        findings.append(Finding(UNKNOWN, "rail overshoot", "start-up and load-release overshoot not given or measured"))
    capacitor = branch.get("capacitor")
    regeneration = sum(_value(load, "regeneration_j") or 0.0 for load in branch.get("loads", []))
    # A load that lists regeneration_j as null is UNKNOWN, not zero: summing it
    # as 0.0 would show the rail peak at the bare rail voltage with no finding.
    # A load that omits the key is taken as one that cannot regenerate.
    unknown_regeneration = [load.get("name", "load") for load in branch.get("loads", [])
                            if "regeneration_j" in load and load["regeneration_j"] is None]
    if unknown_regeneration:
        findings.append(Finding(UNKNOWN, "regeneration",
                                f"regeneration energy not given for {', '.join(unknown_regeneration)}; "
                                "the rail peak below excludes it"))
    if capacitor and regeneration and not branch.get("source", {}).get("can_sink", False):
        capacitance = _value(capacitor, "capacitance_f")
        if capacitance:
            pumped = math.sqrt(peak ** 2 + 2 * regeneration / capacitance)
            findings.append(Finding(INFO, "regeneration",
                                    f"{regeneration:g} J into {capacitance * 1e6:g} uF with a source "
                                    f"that cannot sink lifts the rail to about {pumped:.1f} V"))
            peak = max(peak, clamped_regeneration_peak(branch, pumped, regeneration, findings))
    if capacitor:
        rated = _value(capacitor, "voltage_rating_v")
        margin = _value(capacitor, "voltage_margin") or DEFAULT_CAPACITOR_VOLTAGE_MARGIN
        if rated is None:
            findings.append(Finding(UNKNOWN, "capacitor voltage", "voltage rating not given"))
        else:
            status = PASS if rated >= margin * peak else FAIL
            findings.append(Finding(status, "capacitor voltage", f"{rated:g} V rating against {margin:g} x {peak:.1f} V"))
    fuse_volts = _value(branch["fuse"], "voltage_rating_v")
    if fuse_volts is not None:
        status = PASS if fuse_volts >= peak else FAIL
        findings.append(Finding(status, "fuse voltage", f"{fuse_volts:g} V rating against {peak:.1f} V"))
    for load in branch.get("loads", []):
        limit = _value(load, "max_supply_v")
        if limit is not None:
            status = PASS if peak <= limit else FAIL
            findings.append(Finding(status, f"{load.get('name', 'load')} supply limit",
                                    f"rail peak {peak:.1f} V against the load's {limit:g} V maximum"))
    return findings


def check_clamp(branch: dict) -> list[Finding]:
    """Can a passive zener or TVS protect the load at all, and does a given one?

    A passive clamp must stay off at the rail maximum and hold below the load's
    maximum at the current it carries; a TVS clamps at roughly 1.4 to 1.6 x
    its standoff, so a narrow window rules the passive kind out.
    """
    rail_max = _value(branch["rail"], "max_v")
    limits = [_value(load, "max_supply_v") for load in branch.get("loads", [])]
    limits = [limit for limit in limits if limit is not None]
    if rail_max is None or not limits:
        return []
    load_max = min(limits)
    window = load_max / rail_max
    findings: list[Finding] = []
    overshoot = _value(branch["rail"], "overshoot_v")
    regeneration = any(_value(load, "regeneration_j") for load in branch.get("loads", []))
    if window < PASSIVE_CLAMP_WINDOW:
        message = (f"load maximum {load_max:g} V over rail maximum {rail_max:g} V is {window:.2f}, "
                   f"under {PASSIVE_CLAMP_WINDOW:g}: no passive zener or TVS can stay off at the "
                   "rail and hold the load limit at real current; regeneration wants an active "
                   "clamp (brake chopper), source overshoot a series surge stopper or eFuse")
        status = WARN if regeneration or overshoot is None or overshoot > 0 else INFO
        findings.append(Finding(status, "clamp window", message))
    clamp = branch.get("clamp")
    if clamp:
        standoff = _value(clamp, "standoff_v")
        clamp_v = _value(clamp, "clamp_v")
        current = _value(clamp, "clamp_current_a")
        if standoff is None or clamp_v is None:
            findings.append(Finding(UNKNOWN, "clamp", "standoff or clamping voltage not given"))
            return findings
        if standoff < rail_max:
            findings.append(Finding(FAIL, "clamp standoff",
                                    f"{standoff:g} V standoff under the {rail_max:g} V rail maximum: "
                                    "it conducts in normal operation"))
        status = PASS if clamp_v <= load_max else FAIL
        at = f" at {current:g} A" if current is not None else ""
        findings.append(Finding(status, "clamp voltage", f"clamps at {clamp_v:g} V{at} against the load's {load_max:g} V maximum"))
    return findings


def current_basis_value(entry: dict, root: Path) -> tuple[float | None, str]:
    if entry.get("current") is not None:
        return float(entry["current"]), entry.get("current_source", "entered in the branch file")
    relative = entry.get("file")
    pattern = entry.get("pattern")
    if not relative or not pattern:
        return None, "no current value or file and pattern"
    path = root / relative
    if not path.exists():
        return None, f"{relative} not found"
    match = re.search(pattern, path.read_text(encoding="utf-8", errors="replace"))
    if not match:
        return None, f"pattern not found in {relative}"
    return float(match.group(1)), relative


def check_sizing_basis(branch: dict, root: Path) -> list[Finding]:
    findings: list[Finding] = []
    for entry in branch.get("sizing_basis", []):
        name = entry.get("name", "basis")
        assumed = entry.get("assumed")
        current, source = current_basis_value(entry, root)
        if current is None or assumed is None:
            findings.append(Finding(UNKNOWN, f"sizing basis {name}", source))
        elif not math.isclose(current, float(assumed)):
            findings.append(Finding(
                FAIL, f"sizing basis {name}",
                f"sized from {assumed:g}, now {current:g} ({source}): re-run the selection "
                f"for {entry.get('sizes', 'the parts sized from it')}"))
        else:
            findings.append(Finding(PASS, f"sizing basis {name}", f"{current:g} as sized ({source})"))
    return findings


def check_unfused(branch: dict) -> list[Finding]:
    """A branch with no fuse: can its source overheat the smallest wire?"""
    source = branch.get("source", {})
    available = _value(source, "current_limit_a") or _value(source, "rating_a")
    ampacities = [_value(wire, "ampacity_a") for wire in branch.get("wires", [])]
    known = [ampacity for ampacity in ampacities if ampacity is not None]
    if available is None or not known:
        return [Finding(UNKNOWN, "no fuse", "branch has no fuse, and the source's current or the wire ampacity is not given")]
    smallest = min(known)
    if available > smallest:
        return [Finding(FAIL, "no fuse", f"branch has no fuse and its source can deliver about "
                        f"{available:g} A into a wire rated {smallest:g} A")]
    return [Finding(PASS, "no fuse", f"no fuse, but the source's {available:g} A is within the smallest wire's {smallest:g} A")]


def evaluate(branch: dict, root: Path | None = None) -> list[Finding]:
    root = Path(root) if root is not None else Path.cwd()
    if not isinstance(branch.get("rail"), dict):
        raise ToolError("the branch file needs a 'rail' object (nominal_v, max_v, overshoot_v)")
    unfused: list[Finding] = []
    if not branch.get("fuse"):
        unfused = check_unfused(branch)
        branch = {**branch, "fuse": {}}
    return [
        *unfused,
        *check_sizing_basis(branch, root),
        *check_voltages(branch),
        *check_clamp(branch),
        *check_capacitor_inrush(branch),
        *check_load_pulses(branch),
        *check_continuous(branch),
        *check_protection_chain(branch),
    ]


def load_branch(path: Path) -> dict:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as error:
        raise ToolError(f"branch file not found: {path}") from error
    except ValueError as error:
        raise ToolError(f"branch file is not valid JSON: {path}: {error}") from error
    if not isinstance(data, dict):
        raise ToolError(f"branch file must hold a JSON object: {path}")
    return data


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("branch", type=Path, help="branch description, JSON")
    parser.add_argument("--strict", action="store_true", help="fail on UNKNOWN as well as FAIL")
    parser.add_argument("--root", type=Path, help="root for sizing-basis files (default: the branch file's folder)")
    parser.add_argument("--json", action="store_true", help="print findings as JSON")
    args = parser.parse_args(argv)
    try:
        branch = load_branch(args.branch)
        findings = evaluate(branch, args.root or args.branch.resolve().parent)
    except (ToolError, ValueError, TypeError, KeyError) as error:
        print(f"could not run: {error}")
        return 2
    counts = {status: sum(f.status == status for f in findings) for status in (FAIL, UNKNOWN, WARN)}
    if args.json:
        print(json.dumps({"name": branch.get("name", args.branch.name), "counts": counts,
                          "findings": [asdict(f) for f in findings]}, indent=2))
    else:
        print(f"Power branch: {branch.get('name', args.branch.name)}")
        for finding in findings:
            print(f"{finding.status:<8}{finding.check}: {finding.message}")
        print(f"Summary: {counts[FAIL]} FAIL, {counts[UNKNOWN]} UNKNOWN, {counts[WARN]} WARN")
    failed = counts[FAIL] or (args.strict and counts[UNKNOWN])
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
