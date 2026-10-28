#!/usr/bin/env python3
"""Lint a render-extract/1 document against a named render preset: settings, units, textures, lights, keyed-but-hidden objects.

Purpose: catch the settings mistakes that waste a render before it starts: a preset value that drifted
(samples, animated seed, view transform, filter width), wrong units or scale, a missing texture, a glass
material under too few samples, a dead or wildly uneven light, an object that is keyed but never rendered.
Usage: python scene_lint.py EXTRACT.json --preset PRESET.json [--json OUT]
Inputs: EXTRACT.json from blender_extract; PRESET.json:
  {"name": "final", "settings": {"scene.cycles.samples": 512, "scene.view_transform": "AgX", ...},
   "transparent_min_samples": 1024, "allow_units": ["METRIC"], "max_light_ratio": 1000,
   "require_oidn_albedo_normal": true, "film_grain": false}
  `settings` keys are dotted paths into the extract (e.g. scene.resolution); numbers compare with a tiny
  tolerance, lists element-wise, text exactly. Unknown preset keys exit 2 (a typo must not pass silently).
  film_grain is accepted but cannot be checked (the extract holds no compositor data): it is listed as advisory.
Findings (exit 1): a setting differing from the preset (both values shown); a setting that is null or absent
  in the extract ("unreadable"); unit system not in allow_units (default METRIC) or scale_length not 1.0;
  a material image whose file does not exist; a material with transmission >= 0.5 while engine is CYCLES and
  cycles.samples < transparent_min_samples; a light with energy <= 0 or unreadable; brightest / dimmest light
  energy above max_light_ratio (warning level, still a finding); an object that is hide_render and animated;
  denoiser not OpenImageDenoise with albedo+normal passes when require_oidn_albedo_normal is true and
  denoising is on.
Advisory (printed, not a finding): a light visible to camera and to glossy rays while transmissive materials
  exist - "check rim light in glossy/transmission".
Outputs: one line per finding, then `scene_lint: PASS ...` or `scene_lint: FAIL n finding(s) ...`.
Exit codes: 0 pass, 1 findings, 2 could not run (bad extract or preset).
Dependencies: Python 3.10+ standard library; blender_extract (validator).
Assumptions: the extract was taken from the scene that will be rendered.
Origin: new (rules from the research and the double-transform note).
"""

from __future__ import annotations

import argparse
import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import blender_extract as bx  # noqa: E402
import render_common as rc  # noqa: E402

TOOL = "scene_lint"
PRESET_KEYS = {"name", "settings", "transparent_min_samples", "allow_units", "max_light_ratio",
               "require_oidn_albedo_normal", "film_grain",
               "label", "notes"}  # label and notes document the preset; nothing checks them
_MISSING = object()


def dotted(doc, path):
    cur = doc
    for part in path.split("."):
        if not isinstance(cur, dict) or part not in cur:
            return _MISSING
        cur = cur[part]
    return cur


def _is_num(v):
    return isinstance(v, (int, float)) and not isinstance(v, bool)


def same(a, b) -> bool:
    if isinstance(a, bool) or isinstance(b, bool):
        return isinstance(a, bool) and isinstance(b, bool) and a == b
    if _is_num(a) and _is_num(b):
        return math.isclose(a, b, rel_tol=1e-6, abs_tol=1e-9)
    if isinstance(a, (list, tuple)) and isinstance(b, (list, tuple)):
        return len(a) == len(b) and all(same(x, y) for x, y in zip(a, b))
    return a == b


def show(v) -> str:
    return "absent" if v is _MISSING else json.dumps(v)


def load_preset(path) -> dict:
    try:
        with open(path, "r", encoding="utf-8") as fh:
            p = json.load(fh)
    except (OSError, ValueError) as e:
        raise rc.CannotRun(f"cannot read preset {path}: {e}")
    if not isinstance(p, dict):
        raise rc.CannotRun(f"preset {path}: expected a JSON object")
    unknown = sorted(set(p) - PRESET_KEYS)
    if unknown:
        raise rc.CannotRun(f"preset {path}: unknown key(s) {', '.join(unknown)} (known: {', '.join(sorted(PRESET_KEYS))})")
    if not isinstance(p.get("settings", {}), dict):
        raise rc.CannotRun(f"preset {path}: 'settings' must be an object of dotted keys")
    for k in ("transparent_min_samples", "max_light_ratio"):
        if k in p and not (_is_num(p[k]) and p[k] > 0):
            raise rc.CannotRun(f"preset {path}: '{k}' must be a positive number")
    if "allow_units" in p and not (isinstance(p["allow_units"], list) and all(isinstance(u, str) for u in p["allow_units"])):
        raise rc.CannotRun(f"preset {path}: 'allow_units' must be a list of strings")
    return p


def lint(doc, preset) -> tuple:
    """(findings, advisory) lists."""
    F, adv = [], []

    def add(kind, msg):
        F.append({"kind": kind, "message": msg})

    sc = doc["scene"]
    for key, want in sorted(preset.get("settings", {}).items()):
        got = dotted(doc, key)
        if got is _MISSING or got is None:
            add("unreadable", f"{key} is {show(got)} in the extract (preset wants {show(want)})")
        elif not same(got, want):
            add("setting", f"{key} is {show(got)}, preset wants {show(want)}")
    allowed = preset.get("allow_units", ["METRIC"])
    if sc["unit_system"] is None:
        add("unreadable", "scene.unit_system is null in the extract")
    elif sc["unit_system"] not in allowed:
        add("units", f"unit system is {sc['unit_system']}, allowed: {', '.join(allowed)}")
    if sc["scale_length"] is None:
        add("unreadable", "scene.scale_length is null in the extract")
    elif not same(sc["scale_length"], 1.0):
        add("units", f"scale_length is {sc['scale_length']:g}, expected 1.0")
    for m in doc["materials"]:
        for im in m["images"]:
            if im["exists"] is False:
                add("texture", f"material {m['name']}: image file missing: {im['abs'] or im['path']}")
            elif im["exists"] is None:
                add("unreadable", f"material {m['name']}: cannot tell whether image {im['path']!r} exists")
    glass = [m["name"] for m in doc["materials"] if m["transmission"] is not None and m["transmission"] >= 0.5]
    min_s, samples = preset.get("transparent_min_samples"), sc["cycles"]["samples"]
    if glass and min_s is not None and sc["engine"] == "CYCLES":
        if samples is None:
            add("unreadable", "scene.cycles.samples is null; cannot check samples for transmissive materials")
        elif samples < min_s:
            add("samples", f"transmissive material(s) {', '.join(glass)} with {samples} samples; the preset "
                           f"wants at least {min_s:g} for glass")
    energies = []
    for L in doc["lights"]:
        if L["energy"] is None:
            add("unreadable", f"light {L['name']}: energy is null in the extract")
        elif L["energy"] <= 0:
            add("light", f"light {L['name']} has energy {L['energy']:g} (dead light)")
        else:
            energies.append((L["energy"], L["name"]))
        if glass and L["visible_camera"] is True and L["visible_glossy"] is True:
            adv.append(f"light {L['name']}: check rim light in glossy/transmission")
    ratio = preset.get("max_light_ratio")
    if ratio is not None and len(energies) >= 2:
        hi, lo = max(energies), min(energies)
        if hi[0] / lo[0] > ratio:
            add("warning:light-ratio", f"brightest light {hi[1]} ({hi[0]:g}) is {hi[0] / lo[0]:.4g} x the dimmest "
                                       f"{lo[1]} ({lo[0]:g}); limit {ratio:g}")
    for o in doc["objects"]:
        if o["hide_render"] is True and o["animated"] is True:
            add("hidden-keyed", f"object {o['name']} is animated but hidden from render (keyed, never rendered)")
    if preset.get("require_oidn_albedo_normal") and sc["engine"] == "CYCLES":
        cy = sc["cycles"]
        if cy["use_denoising"] is True and (cy["denoiser"] != "OPENIMAGEDENOISE"
                                            or cy["denoising_input_passes"] != "RGB_ALBEDO_NORMAL"):
            add("denoiser", f"denoiser is {cy['denoiser']} with passes {cy['denoising_input_passes']}; the "
                            "preset wants OPENIMAGEDENOISE with RGB_ALBEDO_NORMAL")
        elif cy["use_denoising"] is None:
            add("unreadable", "scene.cycles.use_denoising is null; cannot check the denoiser")
    if "film_grain" in preset:
        adv.append(f"film_grain={preset['film_grain']} in the preset cannot be checked: the extract holds no "
                   "compositor data")
    return F, adv


def make_parser() -> argparse.ArgumentParser:
    ap = argparse.ArgumentParser(
        prog="scene_lint.py",
        description="Lint a render-extract/1 JSON against a preset JSON (settings, units, textures, glass samples, "
                    "light power, keyed-but-hidden objects).",
        epilog="Exit: 0 pass, 1 findings, 2 could not run. Preset keys: name, settings (dotted keys), "
               "transparent_min_samples, allow_units, max_light_ratio, require_oidn_albedo_normal, film_grain; "
               "label and notes are documentation only.")
    ap.add_argument("extract", help="render-extract/1 JSON from blender_extract")
    ap.add_argument("--preset", required=True, help="preset JSON (see the module docstring)")
    ap.add_argument("--json", help="write the machine report here")
    return ap


def main(argv=None) -> int:
    args = make_parser().parse_args(argv)
    try:
        doc = bx.load_extract(args.extract)
        preset = load_preset(args.preset)
        findings, advisory = lint(doc, preset)
    except rc.CannotRun as e:
        rc.error(TOOL, str(e))
        return rc.CANNOT
    for a in advisory:
        print(f"advisory: {a}")
    name = preset.get("name", os.path.basename(args.preset))
    return rc.finish(TOOL, findings, f"preset {name!r}, {len(doc['lights'])} light(s), "
                     f"{len(doc['materials'])} material(s), {len(doc['objects'])} object(s)", args.json,
                     {"extract": args.extract, "preset": args.preset, "advisory": advisory})


if __name__ == "__main__":
    sys.exit(main())
