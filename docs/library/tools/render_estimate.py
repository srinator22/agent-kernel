#!/usr/bin/env python3
"""Estimate render time and cost from measured seconds per frame and a dated price table the user supplies.

Purpose: a final render must be approved with a time estimate that rests on a measurement, not a guess, and
any cloud price must be dated and sourced because prices move. This tool turns a measured seconds-per-frame
(typed in, or read from a render_chunks STATE file) and a frame count into local hours, and optionally into
cost under each row of a price file. NO prices ship with this tool; the price file is the user's, and a row
without a date, source or currency is refused. A row older than the allowed age is reported as a VERIFY
finding so a stale price cannot be quoted by accident.

Usage:
  python render_estimate.py (--state ABS.json | --sec-per-frame S --frames N)
                            [--processes P] [--processes-per-gpu K] [--prices PRICES.json]
                            [--max-price-age-days 30] [--today YYYY-MM-DD] [--json OUT]

Inputs:
  --state              a render_chunks STATE file: seconds per frame is measured over its done chunks that
                       rendered frames; total frames from its range; remaining frames counted from the files
                       present in its output folder. Refused (exit 2) when nothing has been measured yet.
  --sec-per-frame/--frames  a typed measurement and the frame count (all remaining).
  --processes P        parallel render processes, one per GPU (default 1). This is the user's claim.
  --processes-per-gpu K  processes sharing one GPU (default 1). With K > 1 a warning is printed: two
                       processes on one busy GPU give no speed-up, so the estimate uses ceil(P / K) GPUs.
  --prices             JSON list (or {"prices": [...]}) of rows {"name", "currency", "price_per_hour",
                       "unit": "gpu-hour", "speed_ratio", "date": "YYYY-MM-DD", "source": "<url>"}.
                       speed_ratio is the rented GPU speed relative to the machine the seconds per frame
                       were measured on (2.0 = twice as fast).
  --today              the reference date for price age (default: the current date).
Method: local hours = frames x seconds per frame / GPUs / 3600. Cost uses GPU-hours, which do not depend on how
many GPUs share the work: gpu_hours = remaining frames x seconds per frame / 3600 / speed_ratio, and
cost = gpu_hours x price_per_hour. The table lists name | gpu-hours | cost with currency | source | date and
is for the remaining frames.
Outputs: estimate lines, the price table, `render_estimate: finding:` lines, and a summary line
`render_estimate: PASS ...` or `render_estimate: FAIL n finding(s) ...`. --json writes a machine report.
Exit codes: 0 estimate produced, 1 a price row is older than --max-price-age-days (line
"VERIFY: price row <name> dated <date> is older than N days"), 2 could not run (bad arguments, malformed
STATE or price file, a row missing date, source or currency, a date in the future).
Dependencies: Python 3.10+ standard library.
Assumptions: speed scales linearly with GPUs and with speed_ratio; the estimate is a planning figure, and a
stage record should keep the measured value beside it.
Origin: new (no prior source).
"""

from __future__ import annotations

import argparse
import datetime as _dt
import json
import math
import os
import re
import stat
import sys

TOOL = "render_estimate"
HASH_RUN = re.compile(r"#+")


class InputError(Exception):
    """Could not run (exit 2)."""


def err(message: str) -> None:
    print(f"{TOOL}: ERROR {message}", file=sys.stderr)


def positive_float(text: str) -> float:
    try:
        value = float(text)
    except ValueError:
        raise argparse.ArgumentTypeError(f"not a number: {text}")
    if not (math.isfinite(value) and value > 0):
        raise argparse.ArgumentTypeError(f"must be a positive number: {text}")
    return value


def parse_date(text, what: str) -> _dt.date:
    if not isinstance(text, str) or not re.fullmatch(r"\d{4}-\d{2}-\d{2}", text):
        raise InputError(f"{what}: date must be YYYY-MM-DD, got {text!r}")
    try:
        return _dt.datetime.strptime(text, "%Y-%m-%d").date()
    except ValueError:
        raise InputError(f"{what}: not a real date: {text}")


def frame_present(out: str, pattern: str, number: int) -> bool:
    m = HASH_RUN.search(pattern)
    name = pattern[:m.start()] + str(number).zfill(len(m.group())) + pattern[m.end():]
    try:
        st = os.stat(os.path.join(out, name))
    except OSError:
        return False
    return stat.S_ISREG(st.st_mode) and st.st_size > 0


def read_state(path: str) -> dict:
    """Measured seconds per frame, total and remaining frames from a render_chunks STATE file."""
    if not os.path.isabs(path):
        raise InputError(f"--state must be an absolute path: {path}")
    try:
        with open(path, "r", encoding="utf-8") as fh:
            state = json.load(fh)
    except (OSError, ValueError) as exc:
        raise InputError(f"cannot read STATE {path}: {exc}")
    try:
        if not isinstance(state, dict) or state.get("tool") != "render_chunks":
            raise ValueError("not a render_chunks STATE file")
        first, last, out, pattern = state["first"], state["last"], state["out"], state["pattern"]
        if not (isinstance(first, int) and isinstance(last, int) and 0 <= first <= last):
            raise ValueError("bad first/last")
        if not (isinstance(out, str) and isinstance(pattern, str) and HASH_RUN.search(pattern)):
            raise ValueError("bad out or pattern")
        secs = frames = chunks = 0
        for c in state["chunks"]:
            n, s = c.get("frames_rendered"), c.get("seconds")
            if c["status"] == "done" and isinstance(n, int) and n > 0 and isinstance(s, (int, float)) and s >= 0:
                secs, frames, chunks = secs + s, frames + n, chunks + 1
    except (KeyError, ValueError, TypeError, AttributeError) as exc:
        raise InputError(f"STATE {path} is malformed: {exc}")
    if frames == 0:
        raise InputError(f"STATE {path} has no measurement yet (no done chunk rendered frames); "
                         f"run a check chunk first or give --sec-per-frame and --frames")
    remaining = sum(1 for n in range(first, last + 1) if not frame_present(out, pattern, n))
    return {"sec_per_frame": secs / frames, "basis_frames": frames, "basis_chunks": chunks,
            "total": last - first + 1, "remaining": remaining, "out": out}


def read_prices(path: str, today: _dt.date) -> list[dict]:
    try:
        with open(path, "r", encoding="utf-8") as fh:
            data = json.load(fh)
    except (OSError, ValueError) as exc:
        raise InputError(f"cannot read prices {path}: {exc}")
    rows = data.get("prices") if isinstance(data, dict) else data
    if not isinstance(rows, list) or not rows:
        raise InputError(f"prices {path}: expected a non-empty JSON list of rows")
    result = []
    for i, row in enumerate(rows, start=1):
        label = f"prices {path} row {i}"
        if not isinstance(row, dict):
            raise InputError(f"{label}: not an object")
        for key in ("name", "currency", "date", "source"):
            if not isinstance(row.get(key), str) or not row[key].strip():
                raise InputError(f"{label}: '{key}' is missing or empty (every row needs name, currency, "
                                 f"date and source)")
        if row.get("unit") != "gpu-hour":
            raise InputError(f"{label}: unit must be 'gpu-hour', got {row.get('unit')!r}")
        for key in ("price_per_hour", "speed_ratio"):
            v = row.get(key)
            if isinstance(v, bool) or not isinstance(v, (int, float)) or not math.isfinite(v) or \
                    v < 0 or (key == "speed_ratio" and v == 0):
                raise InputError(f"{label}: '{key}' must be a finite number "
                                 f"{'> 0' if key == 'speed_ratio' else '>= 0'}, got {v!r}")
        when = parse_date(row["date"], label)
        if when > today:
            raise InputError(f"{label}: date {row['date']} is after the reference date {today}")
        result.append(dict(row, age_days=(today - when).days))
    return result


def hours_text(hours: float) -> str:
    total = int(round(hours * 3600))
    return f"{hours:.2f} h ({total // 3600}:{(total % 3600) // 60:02d}:{total % 60:02d})"


def make_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="render_estimate.py",
        description="Estimate render hours and cost from a measured seconds per frame and a user-supplied, "
                    "dated price file (no prices ship with the tool). Exit: 0 ok, 1 stale price row, 2 error.")
    p.add_argument("--state", help="absolute path of a render_chunks STATE file")
    p.add_argument("--sec-per-frame", type=positive_float)
    p.add_argument("--frames", type=int)
    p.add_argument("--processes", type=int, default=1)
    p.add_argument("--processes-per-gpu", type=int, default=1)
    p.add_argument("--prices", help="JSON price rows with date, source, currency")
    p.add_argument("--max-price-age-days", type=int, default=30)
    p.add_argument("--today", help="YYYY-MM-DD, default today")
    p.add_argument("--json", help="write a machine report")
    return p


def main(argv=None) -> int:
    args = make_parser().parse_args(argv)
    try:
        typed = args.sec_per_frame is not None or args.frames is not None
        if args.state and typed:
            raise InputError("give either --state or --sec-per-frame with --frames, not both")
        if not args.state and not (args.sec_per_frame is not None and args.frames is not None):
            raise InputError("give --state, or both --sec-per-frame and --frames")
        if args.frames is not None and args.frames < 1:
            raise InputError("--frames must be at least 1")
        if args.processes < 1 or args.processes_per_gpu < 1:
            raise InputError("--processes and --processes-per-gpu must be at least 1")
        if args.max_price_age_days < 0:
            raise InputError("--max-price-age-days must not be negative")
        today = parse_date(args.today, "--today") if args.today else _dt.date.today()
        if args.state:
            basis = read_state(args.state)
            spf, total, remaining = basis["sec_per_frame"], basis["total"], basis["remaining"]
            basis_text = (f"measured {spf:.3f} s/frame over {basis['basis_frames']} frame(s) in "
                          f"{basis['basis_chunks']} done chunk(s) of {args.state}")
        else:
            spf, total, remaining = args.sec_per_frame, args.frames, args.frames
            basis_text = f"supplied {spf:g} s/frame (not measured here)"
        prices = read_prices(args.prices, today) if args.prices else []
    except InputError as exc:
        err(str(exc))
        return 2
    gpus = max(1, math.ceil(args.processes / args.processes_per_gpu))
    local_total = total * spf / gpus / 3600.0
    local_remaining = remaining * spf / gpus / 3600.0
    gpu_hours_work = remaining * spf / 3600.0
    print(f"{TOOL}: basis: {basis_text}")
    print(f"{TOOL}: frames: total {total}, remaining {remaining}")
    if args.processes_per_gpu > 1:
        print(f"{TOOL}: WARNING {args.processes} process(es) at {args.processes_per_gpu} per GPU: two "
              f"processes on one busy GPU give no speed-up; the estimate uses {gpus} GPU(s)")
    print(f"{TOOL}: local: {args.processes} process(es) on {gpus} GPU(s): total {hours_text(local_total)}, "
          f"remaining {hours_text(local_remaining)}")
    findings, table = [], []
    for row in prices:
        hours = gpu_hours_work / row["speed_ratio"]
        cost = hours * row["price_per_hour"]
        table.append({"name": row["name"], "gpu_hours": hours, "cost": cost, "currency": row["currency"],
                      "source": row["source"], "date": row["date"], "age_days": row["age_days"]})
        if row["age_days"] > args.max_price_age_days:
            findings.append(f"VERIFY: price row {row['name']} dated {row['date']} is older than "
                            f"{args.max_price_age_days} days")
    if table:
        print(f"{TOOL}: cost for the {remaining} remaining frame(s), {gpu_hours_work:.2f} GPU-hours of local work")
        cells = [("name", "gpu-hours", "cost", "source", "date")] + [
            (t["name"], f"{t['gpu_hours']:.2f}", f"{t['cost']:.2f} {t['currency']}", t["source"], t["date"])
            for t in table]
        widths = [max(len(r[i]) for r in cells) for i in range(5)]
        for r in cells:
            print(f"{TOOL}: " + " | ".join(c.ljust(widths[i]) for i, c in enumerate(r)).rstrip())
    for f in findings:
        print(f"{TOOL}: finding: {f}")
    if args.json:
        try:
            with open(args.json, "w", encoding="utf-8") as fh:
                json.dump({"tool": TOOL, "status": "fail" if findings else "pass", "findings": findings,
                           "basis": basis_text, "sec_per_frame": spf, "frames_total": total,
                           "frames_remaining": remaining, "processes": args.processes,
                           "processes_per_gpu": args.processes_per_gpu, "gpus": gpus,
                           "local_hours_total": local_total, "local_hours_remaining": local_remaining,
                           "gpu_hours_remaining": gpu_hours_work, "prices": table, "today": str(today)},
                          fh, indent=2)
                fh.write("\n")
        except OSError as exc:
            err(f"cannot write {args.json}: {exc}")
            return 2
    if findings:
        print(f"{TOOL}: FAIL {len(findings)} finding(s) {len(table)} price row(s) checked")
        return 1
    print(f"{TOOL}: PASS remaining {hours_text(local_remaining)} on {gpus} GPU(s), {len(table)} price row(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
