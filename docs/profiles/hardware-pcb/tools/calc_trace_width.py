#!/usr/bin/env python3
"""Required copper width for each power net (IPC-2221) and a stack-up impedance check (IPC-2141).

Purpose
    Size the copper for a current at a temperature rise, per net, from the
    parameters file; roll nets up into net-class track widths; optionally
    compare those with the CAD project's class widths; and check a stored
    differential or single-ended trace width against the stack-up. A result
    informs layout, it does not replace the fabricator's impedance
    calculator or an IPC-2152 review (the report says so).

Inputs
    --params FILE     parameters.toml (default: ./parameters.toml)
    --kicad-pro FILE  optional KiCad project (JSON): net_settings.classes[]
                      track_width is compared with each class width
    --json            print findings as JSON

parameters.toml tables read
    [traces]
      temp_rise_c_default = 10          # C, required
      copper_oz_outer = 1.0             # ounces, required
      copper_oz_inner = 0.5             # ounces, required
      class_width_step_mm = 0.1         # optional, class widths round up to it
    [[traces.nets]]
      name = "MAIN_IN"                  # required
      i_a = 20.0                        # design current, A (a number, or
                                        # "pending": a WARN, net not sized)
      layer = "outer"                   # exactly "outer" (default) or "inner";
                                        # any other value, a case or spacing
                                        # variant included, is an error
                                        # (exit 2), checked on every net,
                                        # pending ones too
      temp_rise_c = 20                  # optional per-net override
      netclass = "Power"                # optional, for class widths
      i_source = "item:loads:fan:i_a"   # optional: the current this net must
                                        # carry; the design current may not be
                                        # below it (sources below)
      i_source_scale = 0.5              # optional, one phase of several
    [stackup]                           # optional, one value per copper layer
      stackup_name = "stack-4L"
      layer_names = ["L1", "L2", "L3", "L4"]
      copper_thickness_mm = [0.035, 0.0152, 0.0152, 0.035]   # finished
      copper_oz = [1.0, 0.5, 0.5, 1.0]  # optional, checked against [traces]
      dielectric_thickness_mm = [0.2, 0.9, 0.2]   # one fewer than layers
      dielectric_dk = [4.3, 4.3, 4.3]
      finished_thickness_sum_mm = 1.6   # optional, checked against the rows
    [impedance]                         # optional
      stackup = "stack-4L"              # must equal stackup_name when given
      model_band_pct = 8.0              # optional, default 8
      [impedance.usb]                   # any sub-table with width_mm and
        layer = "L1"                    # zdiff_ohm (pair) or z0_ohm (single)
        reference_layer = "L2"
        width_mm = 0.3
        gap_mm = 0.15                   # pairs only
        zdiff_ohm = 90.0                # or z0_ohm = 50.0
        controlled = true               # false: reported, not judged
        minimum_legal = { width_mm = 0.1, gap_mm = 0.1 }   # fabricator minimums

Current sources (i_source)
    const:X                 the number X
    param:a.b               a number at a dotted path in the parameters file
    item:TABLE:NAME:FIELD   FIELD of the row whose `name` is NAME in the array
                            of tables TABLE, for example [[loads]] or [[rails]]
    An unknown or non-number source is an error (exit 2), never a pass.

Model
    IPC-2221: I = k dT^0.44 A^0.725, A in mil^2, k = 0.048 external and 0.024
    internal; width = A / copper thickness. Thickness is the stack-up's
    finished figure (thinner outer layer for an outer net, thinnest inner
    layer for an inner net) when [stackup] has copper rows, else the nominal
    1.378 mil per ounce (the report says which). IPC-2141 microstrip:
    Z0 = 87 / sqrt(er + 1.41) ln(5.98 h / (0.8 w + t)); edge-coupled pair
    Zdiff = 2 Z0 (1 - 0.48 exp(-0.96 s / h)).

Outputs
    A table of nets, then one line per finding. Exit 0 no FAIL, 1 at least
    one FAIL, 2 the tool could not run (a [[traces.nets]] layer that is not
    "outer" or "inner" included). The layer of an [impedance] row is a
    different field, a [stackup] layer name, checked against layer_names.

Dependencies
    Python 3.11+ standard library only.

Assumptions
    A net wider than 6 mm is reported as a candidate for a pour or plane.
    IPC-2221 is conservative for short, wide traces and optimistic for long
    ones; confirm against IPC-2152 before layout freeze.

Validation source
    IPC-2221 and IPC-2141 formulas; golden values in
    tests/test_calc_trace_width.py are hand calculations from the formulas
    above, not copies of tool output.
"""

from __future__ import annotations

import argparse
import json
import math
import sys
import tomllib
from dataclasses import asdict, dataclass, field
from pathlib import Path

CHECK = "trace_width"
LEVELS = ("PASS", "WARN", "FAIL", "INFO")
K_EXTERNAL = 0.048
K_INTERNAL = 0.024
MIL_PER_OZ = 1.378        # copper thickness of 1 oz in mil
MM_PER_MIL = 0.0254
POUR_THRESHOLD_MM = 6.0   # wider than this, use a pour or plane
IPC_NOTE = "confirm against IPC-2152 before layout freeze"
CLASS_STEP_DEFAULT_MM = 0.1
MODEL_BAND_DEFAULT_PCT = 8.0
LAYERS = ("outer", "inner")   # the only [[traces.nets]] layer values; no synonyms
LAYER_DEFAULT = "outer"


class ToolError(Exception):
    """The tool could not run at all (exit code 2)."""


@dataclass(frozen=True)
class Finding:
    level: str
    check: str
    message: str


@dataclass
class NetResult:
    name: str
    i_a: float
    temp_rise_c: float
    layer: str
    oz: float
    width_mm: float
    netclass: str = ""
    i_source: str = ""
    i_derived_a: float | None = None
    thickness_mm: float = 0.0
    thickness_from: str = ""      # "stack-up" or "nominal"


@dataclass
class ClassRow:
    netclass: str
    width_mm: float = 0.0         # the widest requirement rounded up to the step
    required_mm: float = 0.0
    nets: list[str] = field(default_factory=list)
    widest: str = ""


def is_number(value: object) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def nominal_thickness_mm(copper_oz: float) -> float:
    """The textbook thickness of `copper_oz` ounces: 1.378 mil per ounce (35 um at 1 oz)."""
    return MIL_PER_OZ * copper_oz * MM_PER_MIL


def width_mm(current_a: float, temp_rise_c: float, copper_oz: float, internal: bool,
             thickness_mm: float | None = None) -> float:
    """IPC-2221 width in mm. `thickness_mm` (finished copper) replaces the nominal ounce thickness."""
    if current_a <= 0 or temp_rise_c <= 0 or copper_oz <= 0:
        raise ValueError("current, temperature rise and copper weight must be positive")
    if thickness_mm is not None and thickness_mm <= 0:
        raise ValueError("copper thickness must be positive")
    k = K_INTERNAL if internal else K_EXTERNAL
    area_mil2 = (current_a / (k * temp_rise_c ** 0.44)) ** (1.0 / 0.725)
    thickness = nominal_thickness_mm(copper_oz) if thickness_mm is None else thickness_mm
    return area_mil2 / (thickness / MM_PER_MIL) * MM_PER_MIL


# ---------------------------------------------------------------- copper from the parameters

def board_thickness(params: dict) -> tuple[float | None, float | None, str]:
    """(outer mm, inner mm, where from): finished copper of the stack-up rows. The outer figure is the thinner of the
    first and last layer, the inner figure the thinnest between; None where the rows give none (nominal is used)."""
    stack = params.get("stackup")
    thickness = stack.get("copper_thickness_mm") if isinstance(stack, dict) else None
    names = stack.get("layer_names") if isinstance(stack, dict) else None
    if (not isinstance(thickness, list) or not isinstance(names, list) or len(thickness) != len(names)
            or len(thickness) < 2 or not all(is_number(t) and t > 0 for t in thickness)):
        return None, None, "nominal ounce thickness: the parameters carry no stack-up copper rows"
    outer = min(thickness[0], thickness[-1])
    inner = min(thickness[1:-1]) if len(thickness) > 2 else None
    return float(outer), None if inner is None else float(inner), f"stack-up {stack.get('stackup_name', '?')} copper rows"


def _stack_weights(params: dict) -> tuple[float | None, float | None]:
    stack = params.get("stackup")
    oz = stack.get("copper_oz") if isinstance(stack, dict) else None
    if not isinstance(oz, list) or len(oz) < 2 or not all(is_number(v) and v > 0 for v in oz):
        return None, None
    return float(min(oz[0], oz[-1])), (float(min(oz[1:-1])) if len(oz) > 2 else None)


def _traces(params: dict) -> dict:
    traces = params.get("traces")
    if not isinstance(traces, dict):
        raise ToolError("the parameters have no [traces] table")
    for key in ("temp_rise_c_default", "copper_oz_outer", "copper_oz_inner"):
        if not is_number(traces.get(key)) or traces[key] <= 0:
            raise ToolError(f"[traces] {key} must be a positive number")
    if not isinstance(traces.get("nets"), list):
        raise ToolError("[traces] needs a [[traces.nets]] array")
    for net in traces["nets"]:
        net_layer(net)
    return traces


def net_layer(net: dict) -> str:
    """The net's layer, "outer" when omitted. Anything but exactly "outer" or "inner" is an error: a misspelling
    once fell through to the outer coefficient, which is twice the inner one, and understated an inner width."""
    layer = net.get("layer", LAYER_DEFAULT) if isinstance(net, dict) else None
    if layer not in LAYERS:
        name = net.get("name") if isinstance(net, dict) else net
        raise ToolError(f"net {name}: layer {layer!r} is not {' or '.join(repr(v) for v in LAYERS)}")
    return layer


# ---------------------------------------------------------------- design currents

def _number(value: object, spec: str) -> float:
    if not is_number(value):
        raise ToolError(f"current source {spec!r} is not a number ({value!r})")
    return float(value)


def resolve_current(spec: str, params: dict) -> float:
    """The current named by `spec`: 'const:X', 'param:a.b' or 'item:TABLE:NAME:FIELD'."""
    kind, _, rest = spec.partition(":")
    try:
        if kind == "const":
            return float(rest)
        if kind == "param":
            node = params
            for key in rest.split("."):
                node = node[key]
            return _number(node, spec)
        if kind == "item":
            table, name, field_name = rest.split(":")
            rows = [row for row in params[table] if isinstance(row, dict) and row.get("name") == name]
            if len(rows) != 1:
                raise ToolError(f"current source {spec!r}: {len(rows)} rows named {name!r} in [[{table}]]")
            return _number(rows[0][field_name], spec)
    except (KeyError, TypeError, ValueError) as error:
        raise ToolError(f"current source {spec!r} cannot be read: {error!r}") from error
    raise ToolError(f"unknown current source {spec!r} (const:, param:, item:)")


# ---------------------------------------------------------------- widths

def compute_nets(params: dict) -> list[NetResult]:
    traces = _traces(params)
    outer_mm, inner_mm, _where = board_thickness(params)
    results = []
    for net in traces["nets"]:
        if not is_number(net.get("i_a")):
            continue
        internal = net_layer(net) == "inner"
        oz = traces["copper_oz_inner" if internal else "copper_oz_outer"]
        finished = inner_mm if internal else outer_mm
        thickness = finished if finished is not None else nominal_thickness_mm(oz)
        rise = net.get("temp_rise_c", traces["temp_rise_c_default"])
        source = net.get("i_source", "")
        derived = resolve_current(source, params) * net.get("i_source_scale", 1.0) if source else None
        try:
            width = width_mm(net["i_a"], rise, oz, internal, thickness_mm=finished)
        except ValueError as error:
            raise ToolError(f"net {net.get('name')}: {error}") from error
        results.append(NetResult(net["name"], net["i_a"], rise, "inner" if internal else "outer", oz, width,
                                 net.get("netclass", ""), source, derived, thickness,
                                 "stack-up" if finished is not None else "nominal"))
    return results


def class_widths(params: dict) -> list[ClassRow]:
    """One row per net class: the widest requirement of its nets rounded up to [traces] class_width_step_mm."""
    step = _traces(params).get("class_width_step_mm", CLASS_STEP_DEFAULT_MM)
    rows: dict[str, ClassRow] = {}
    for net in compute_nets(params):
        if not net.netclass:
            continue
        row = rows.setdefault(net.netclass, ClassRow(net.netclass))
        row.nets.append(net.name)
        if net.width_mm > row.required_mm:
            row.required_mm, row.widest = net.width_mm, net.name
    for row in rows.values():
        row.width_mm = round(math.ceil(row.required_mm / step - 1e-9) * step, 6)
    return list(rows.values())


def project_class_widths(path: Path) -> dict[str, float]:
    """{class: track width} of a KiCad project file (JSON)."""
    try:
        data = json.loads(Path(path).read_text(encoding="utf-8"))
        classes = data["net_settings"]["classes"]
    except OSError as error:
        raise ToolError(f"project file cannot be read: {path}: {error}") from error
    except (ValueError, KeyError, TypeError) as error:
        raise ToolError(f"project file has no net_settings.classes: {path}") from error
    return {c["name"]: c.get("track_width") for c in classes if isinstance(c, dict) and "name" in c}


# ---------------------------------------------------------------- impedance (IPC-2141)

def z0_microstrip(width: float, h: float, t: float, er: float) -> float:
    """Single-ended microstrip impedance in ohms; width, dielectric height h and copper thickness t in mm."""
    if min(width, h, er) <= 0 or t < 0 or 0.8 * width + t <= 0:
        raise ValueError("width, dielectric height and permittivity must be positive")
    return 87.0 / math.sqrt(er + 1.41) * math.log(5.98 * h / (0.8 * width + t))


def zdiff_microstrip(width: float, gap: float, h: float, t: float, er: float) -> float:
    """Differential impedance of an edge-coupled microstrip pair (gap = edge to edge)."""
    if gap <= 0:
        raise ValueError("gap must be positive")
    return 2.0 * z0_microstrip(width, h, t, er) * (1.0 - 0.48 * math.exp(-0.96 * gap / h))


def _solve(func, target: float, low: float = 0.02, high: float = 3.0) -> float:
    """Width where the (falling) impedance function crosses the target, by bisection."""
    for _ in range(80):
        mid = 0.5 * (low + high)
        if func(mid) > target:
            low = mid
        else:
            high = mid
    return 0.5 * (low + high)


def solve_diff_width(zdiff: float, gap: float, h: float, t: float, er: float) -> float:
    return _solve(lambda w: zdiff_microstrip(w, gap, h, t, er), zdiff)


def solve_single_width(z0: float, h: float, t: float, er: float) -> float:
    return _solve(lambda w: z0_microstrip(w, h, t, er), z0)


def stack_geometry(stack: dict, layer: str, reference: str) -> tuple[float, float, float]:
    """(h, t, er) of a signal layer over an adjacent reference layer of a [stackup] table."""
    names = list(stack["layer_names"])
    try:
        i, j = names.index(layer), names.index(reference)
    except ValueError as error:
        raise ToolError(f"[stackup] layer_names {names} lack {layer!r} or {reference!r}") from error
    if abs(i - j) != 1:
        raise ToolError(f"{layer} and its reference {reference} are not adjacent copper layers")
    gap_index = min(i, j)
    return (float(stack["dielectric_thickness_mm"][gap_index]), float(stack["copper_thickness_mm"][i]),
            float(stack["dielectric_dk"][gap_index]))


def _stackup_findings(params: dict) -> list[Finding]:
    stack = params.get("stackup")
    if not isinstance(stack, dict) or "layer_names" not in stack:
        return []
    count = len(stack["layer_names"])
    name = stack.get("stackup_name", "?")
    problems = []
    for key, expect in (("copper_thickness_mm", count), ("copper_oz", count),
                        ("dielectric_thickness_mm", count - 1), ("dielectric_dk", count - 1)):
        if key in stack and len(stack[key]) != expect:
            problems.append(f"{key} has {len(stack[key])} entries, {expect} expected for {count} copper layers")
    if problems:
        return [Finding("FAIL", f"{CHECK}.stackup", f"{name}: " + "; ".join(problems))]
    if "copper_thickness_mm" not in stack or "dielectric_thickness_mm" not in stack:
        return []
    stated = stack.get("finished_thickness_sum_mm")
    total = sum(stack["copper_thickness_mm"]) + sum(stack["dielectric_thickness_mm"])
    if is_number(stated) and abs(stated - total) > 0.0005:
        return [Finding("FAIL", f"{CHECK}.stackup",
                        f"{name}: the rows sum to {total:.4f} mm, finished_thickness_sum_mm says {stated:g}")]
    return [Finding("INFO", f"{CHECK}.stackup", f"{name}: {count} copper layers, rows sum to {total:.4f} mm")]


def _impedance_findings(params: dict) -> list[Finding]:
    table = params.get("impedance")
    stack = params.get("stackup")
    if not isinstance(table, dict) or not isinstance(stack, dict) or "layer_names" not in stack:
        return []
    band = table.get("model_band_pct", MODEL_BAND_DEFAULT_PCT)
    name = stack.get("stackup_name", "?")
    findings = []
    if table.get("stackup") not in (None, name):
        findings.append(Finding("FAIL", f"{CHECK}.impedance",
                                f"the impedance rows are for stack-up {table['stackup']} but this design is {name}"))
    for key, row in table.items():
        if not isinstance(row, dict) or "width_mm" not in row or not ({"zdiff_ohm", "z0_ohm"} & set(row)):
            continue
        pair = "zdiff_ohm" in row
        target = row["zdiff_ohm"] if pair else row["z0_ohm"]
        try:
            h, t, er = stack_geometry(stack, row["layer"], row["reference_layer"])
            if pair:
                model = zdiff_microstrip(row["width_mm"], row["gap_mm"], h, t, er)
            else:
                model = z0_microstrip(row["width_mm"], h, t, er)
        except (KeyError, ValueError, IndexError, ToolError) as error:
            findings.append(Finding("FAIL", f"{CHECK}.impedance", f"{key}: {error}"))
            continue
        geometry = f"{row['width_mm']:g} mm" + (f" / {row['gap_mm']:g} mm" if pair else "")
        text = (f"{key}: {geometry} on {name} ({row['layer']} over {row['reference_layer']}, h {h:g} mm, er {er:g}, "
                f"t {t:g} mm) gives {model:.1f} ohm, target {target:g} ohm")
        if row.get("controlled") is False:
            findings.append(Finding("INFO", f"{CHECK}.impedance", f"{text}: not a controlled trace, not judged"))
            continue
        error_pct = abs(model / target - 1.0) * 100.0
        minimum = row.get("minimum_legal") or {}
        below = [f"{k[:-3]} {row[k]:g} < {minimum[k]:g}" for k in ("width_mm", "gap_mm")
                 if k in minimum and row.get(k, minimum[k]) + 1e-9 < minimum[k]]
        if below:
            findings.append(Finding("FAIL", f"{CHECK}.impedance", f"{text}: below the legal minimum ({', '.join(below)})"))
        elif error_pct > band:
            findings.append(Finding("FAIL", f"{CHECK}.impedance",
                                    f"{text}: {error_pct:.1f} percent off, outside the {band:g} percent model band"))
        else:
            findings.append(Finding("PASS", f"{CHECK}.impedance",
                                    f"{text}: {error_pct:.1f} percent off (model band {band:g} percent)"))
    return findings


# ---------------------------------------------------------------- findings

def _um(mm: float | None) -> str:
    return "no" if mm is None else f"{mm * 1000.0:.1f} um"


def run(params: dict, project_classes: dict | None = None) -> list[Finding]:
    traces = _traces(params)
    findings = []
    outer_oz, inner_oz = traces["copper_oz_outer"], traces["copper_oz_inner"]
    outer_mm, inner_mm, where = board_thickness(params)
    sized = (f"sized on {_um(outer_mm)} outer and {_um(inner_mm)} inner finished copper ({where})"
             if outer_mm is not None else f"sized on the {where}")
    findings.append(Finding("INFO", f"{CHECK}.copper", f"copper {outer_oz:g} oz outer, {inner_oz:g} oz inner; {sized}"))
    stack_outer, stack_inner = _stack_weights(params)
    for key, mine, theirs in (("copper_oz_outer", outer_oz, stack_outer), ("copper_oz_inner", inner_oz, stack_inner)):
        if theirs is not None and abs(mine - theirs) > 1e-9:
            findings.append(Finding("FAIL", f"{CHECK}.copper",
                                    f"{key} is {mine:g} oz but the stack-up rows give {theirs:g} oz: the weight was "
                                    "typed twice and one is stale"))
    for net in traces["nets"]:
        if not is_number(net.get("i_a")):
            findings.append(Finding("WARN", f"{CHECK}.pending", f"net {net.get('name')}: current is {net.get('i_a')!r}, not sized"))
    for row in compute_nets(params):
        findings.append(Finding(
            "INFO", f"{CHECK}.net",
            f"{row.name}: {row.i_a:g} A, {row.temp_rise_c:g} C rise, {row.oz:g} oz ({_um(row.thickness_mm)} "
            f"{row.thickness_from}) {row.layer}: {row.width_mm:.2f} mm"))
        if row.width_mm > POUR_THRESHOLD_MM:
            findings.append(Finding("INFO", f"{CHECK}.pour",
                                    f"{row.name}: {row.width_mm:.1f} mm exceeds {POUR_THRESHOLD_MM:g} mm, use a pour or plane"))
        if row.i_derived_a is not None:
            if row.i_a + 1e-9 < row.i_derived_a:
                findings.append(Finding("FAIL", f"{CHECK}.current",
                                        f"{row.name}: design current {row.i_a:g} A is below {row.i_source} = {row.i_derived_a:.2f} A"))
            else:
                findings.append(Finding("PASS", f"{CHECK}.current",
                                        f"{row.name}: design current {row.i_a:g} A against {row.i_source} = "
                                        f"{row.i_derived_a:.2f} A: margin {row.i_a - row.i_derived_a:.2f} A"))
    classes = class_widths(params)
    for row in classes:
        findings.append(Finding("INFO", f"{CHECK}.class",
                                f"class {row.netclass} {row.width_mm:.1f} mm ({row.widest} needs {row.required_mm:.2f} mm; "
                                f"{', '.join(row.nets)})"))
    if project_classes is not None:
        for row in classes:
            have = project_classes.get(row.netclass)
            if have is None:
                findings.append(Finding("FAIL", f"{CHECK}.project",
                                        f"class {row.netclass} needs {row.width_mm:.1f} mm and the project file has no "
                                        "track width for it"))
            elif have + 1e-9 < row.width_mm:
                findings.append(Finding("FAIL", f"{CHECK}.project",
                                        f"class {row.netclass} is {have:g} mm in the project file, {row.width_mm:.1f} mm "
                                        f"needed ({row.widest}, {row.required_mm:.2f} mm)"))
            else:
                findings.append(Finding("PASS", f"{CHECK}.project",
                                        f"class {row.netclass} {have:g} mm in the project file against {row.width_mm:.1f} mm needed"))
    findings.extend(_stackup_findings(params))
    findings.extend(_impedance_findings(params))
    findings.append(Finding("INFO", f"{CHECK}.ipc2152", IPC_NOTE))
    return findings


def net_table(params: dict) -> str:
    headers = ["Net", "I A", "dT C", "Layer", "oz", "Width mm", "Class"]
    rows = [[r.name, f"{r.i_a:g}", f"{r.temp_rise_c:g}", r.layer, f"{r.oz:g}", f"{r.width_mm:.2f}", r.netclass or "-"]
            for r in compute_nets(params)]
    widths = [max(len(str(c)) for c in col) for col in zip(headers, *rows)]
    lines = ["  ".join(str(c).ljust(w) for c, w in zip(line, widths)).rstrip() for line in [headers, *rows]]
    return "\n".join([lines[0], "  ".join("-" * w for w in widths), *lines[1:]])


def load_params(path: Path) -> dict:
    try:
        with path.open("rb") as handle:
            return tomllib.load(handle)
    except FileNotFoundError as error:
        raise ToolError(f"parameters file not found: {path}") from error
    except tomllib.TOMLDecodeError as error:
        raise ToolError(f"parameters file is not valid TOML: {path}: {error}") from error


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.strip().splitlines()[0])
    parser.add_argument("--params", type=Path, default=Path("parameters.toml"), help="parameters.toml")
    parser.add_argument("--kicad-pro", type=Path, help="KiCad project file to compare net-class widths with")
    parser.add_argument("--json", action="store_true", help="print findings as JSON")
    args = parser.parse_args(argv)
    try:
        params = load_params(args.params)
        classes = project_class_widths(args.kicad_pro) if args.kicad_pro else None
        findings = run(params, classes)
        table = net_table(params)
    except ToolError as error:
        print(f"could not run: {error}")
        return 2
    counts = {level: sum(f.level == level for f in findings) for level in LEVELS}
    if args.json:
        print(json.dumps({"title": "trace width", "counts": counts, "findings": [asdict(f) for f in findings]}, indent=2))
    else:
        print(table + "\n")
        for f in findings:
            print(f"{f.level:<5} {f.check}: {f.message}")
        print("  ".join(f"{level}: {counts[level]}" for level in LEVELS))
    return 1 if counts["FAIL"] else 0


if __name__ == "__main__":
    sys.exit(main())
