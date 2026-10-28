#!/usr/bin/env python3
"""Render a frame range as chunks that can be killed and resumed, with a STATE file and one log per chunk.

Purpose: a long render must survive a closed lid, a crash or a killed terminal without redoing finished work
and without anyone guessing what is done. This tool splits a frame range into chunks, runs one command per
chunk (any command: usually blender_run.py with a scene script), records progress in a STATE file after every
chunk, and on the next run skips frames that already exist on disk. Run it under the project's background
wrapper (scripts/bg.sh) for long jobs; STATE files live under .work/jobs/render/.

Usage:
  python render_chunks.py plan   --state ABS.json --first N --last M --chunk K --out ABS_DIR
                                 [--pattern frame_####.png] --cmd JSON_LIST [--logs ABS_DIR]
                                 [--device ID] [--force] [--allow-in-repo]
  python render_chunks.py run    --state ABS.json [--max-chunks N] [--stop-on-fail]
  python render_chunks.py status --state ABS.json [--json OUT]

Inputs:
  --cmd      a JSON list, the command for one chunk. Placeholders, replaced in every element:
             {first} {last} {out} {device} {log}, for example
             ["python","blender_run.py","--lock","blender.lock.json","--log","{log}","scene.py","--",
              "{out}","{first}","{last}","preview"].
             At least {first} or {last} must appear, or every chunk would render the same thing.
  --pattern  frame file name; one run of # is the zero-padded frame number (default frame_####.png).
  --out      absolute folder the frames are written to; must be outside any git work tree (--allow-in-repo
             overrides) and should not be in a cloud-synced folder (OneDrive, Dropbox, iCloud, Google Drive;
             a warning is printed).
  --logs     absolute folder for one log per chunk (default: <state folder>/<state name>_logs).
  --device   a GPU id placed into {device} (default 0).
One process per GPU: parallel runs use one STATE per GPU with disjoint frame ranges and a --device each. A
second process on a GPU that is already busy gives no speed-up. `plan` refuses (exit 2) a range that overlaps
another render_chunks STATE file in the same folder with the same --out.
Behaviour: a frame is present when its file exists and is not empty; a zero-size file (crash-truncated) is
missing, is deleted before the chunk runs, and is rendered again. Frames already present are never given to
the command: for a partly finished chunk the command runs once per contiguous run of missing frames, with
{first} and {last} set to that run. After the command, the frames are checked again; all present marks the
chunk done, otherwise failed with the missing list. STATE is replaced atomically after every step, so a kill
at any moment resumes exactly. A chunk left "running" by a kill is run again.
Outputs: progress lines and a summary line `render_chunks: PASS ...` or `render_chunks: FAIL n finding(s) ...`.
Exit codes: 0 all chunks done, 1 any chunk failed or not yet done (for example stopped by --max-chunks),
2 could not run (bad arguments, bad STATE, the command cannot be started, overlap with another STATE).
status: measured seconds per frame = sum of chunk seconds / sum of frames rendered over done chunks that
rendered something; ETA = frames still missing x that figure.
Dependencies: Python 3.10+ standard library.
Assumptions: the chunk command writes frames named by --pattern into --out. Two runs on the same STATE at
the same time are not supported.
Origin: generic port of the chunk run scripts of a product film project (loop over frame chunks, one log
each), plus STATE, skip and verify.
"""

from __future__ import annotations

import argparse
import datetime as _dt
import glob
import json
import os
import re
import stat
import subprocess
import sys
import time

TOOL = "render_chunks"
STATUSES = ("todo", "running", "done", "failed")
CLOUD_SEGMENTS = ("onedrive", "dropbox", "icloud", "icloud drive", "google drive", "googledrive")
HASH_RUN = re.compile(r"#+")
MISSING_LISTED = 200


class StateError(Exception):
    """Could not run (exit 2)."""


def now_iso() -> str:
    return _dt.datetime.now().astimezone().isoformat(timespec="seconds")


def err(message: str) -> None:
    print(f"{TOOL}: ERROR {message}", file=sys.stderr)


def in_git_worktree(path: str) -> bool:
    p = os.path.abspath(path)
    while True:
        if os.path.exists(os.path.join(p, ".git")):
            return True
        parent = os.path.dirname(p)
        if parent == p:
            return False
        p = parent


def cloud_synced(path: str) -> str | None:
    for seg in os.path.abspath(path).replace("\\", "/").split("/"):
        low = seg.lower()
        if low in CLOUD_SEGMENTS or low.startswith("onedrive -") or low.startswith("onedrive-"):
            return seg
    return None


def norm(path: str) -> str:
    return os.path.normcase(os.path.normpath(os.path.abspath(path)))


def frame_name(pattern: str, number: int) -> str:
    m = HASH_RUN.search(pattern)
    return pattern[:m.start()] + str(number).zfill(len(m.group())) + pattern[m.end():]


def frame_present(out: str, pattern: str, number: int) -> bool:
    try:
        st = os.stat(os.path.join(out, frame_name(pattern, number)))
    except OSError:
        return False
    return stat.S_ISREG(st.st_mode) and st.st_size > 0


def missing_frames(out: str, pattern: str, first: int, last: int) -> list[int]:
    return [n for n in range(first, last + 1) if not frame_present(out, pattern, n)]


def runs_of(numbers: list[int]) -> list[tuple[int, int]]:
    runs: list[tuple[int, int]] = []
    for n in numbers:
        if runs and runs[-1][1] == n - 1:
            runs[-1] = (runs[-1][0], n)
        else:
            runs.append((n, n))
    return runs


def expand(cmd: list[str], first: int, last: int, out: str, device: str, log: str) -> list[str]:
    table = {"{first}": str(first), "{last}": str(last), "{out}": out, "{device}": device, "{log}": log}
    result = []
    for element in cmd:
        for key, value in table.items():
            element = element.replace(key, value)
        result.append(element)
    return result


def fmt_duration(seconds: float) -> str:
    s = int(round(seconds))
    return f"{s // 3600}:{(s % 3600) // 60:02d}:{s % 60:02d}"


def save_state(path: str, state: dict) -> None:
    state["updated"] = now_iso()
    tmp = f"{path}.tmp{os.getpid()}"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(state, fh, indent=2)
        fh.write("\n")
        fh.flush()
        os.fsync(fh.fileno())
    os.replace(tmp, path)


def load_state(path: str) -> dict:
    if not os.path.isabs(path):
        raise StateError(f"--state must be an absolute path: {path}")
    try:
        with open(path, "r", encoding="utf-8") as fh:
            state = json.load(fh)
    except (OSError, ValueError) as exc:
        raise StateError(f"cannot read STATE {path}: {exc}")
    try:
        if not isinstance(state, dict) or state.get("tool") != TOOL:
            raise ValueError("not a render_chunks STATE file")
        for key in ("first", "last", "chunk"):
            if not isinstance(state[key], int) or isinstance(state[key], bool):
                raise ValueError(f"'{key}' must be an integer")
        if state["first"] < 0 or state["last"] < state["first"] or state["chunk"] < 1:
            raise ValueError("bad first/last/chunk")
        for key in ("out", "pattern", "device", "logs"):
            if not isinstance(state[key], str):
                raise ValueError(f"'{key}' must be a string")
        if not os.path.isabs(state["out"]) or not os.path.isabs(state["logs"]):
            raise ValueError("'out' and 'logs' must be absolute")
        if not HASH_RUN.search(state["pattern"]):
            raise ValueError("'pattern' has no #")
        cmd = state["cmd"]
        if not isinstance(cmd, list) or not cmd or not all(isinstance(x, str) for x in cmd):
            raise ValueError("'cmd' must be a non-empty list of strings")
        chunks = state["chunks"]
        if not isinstance(chunks, list) or not chunks:
            raise ValueError("'chunks' must be a non-empty list")
        for c in chunks:
            if not isinstance(c, dict) or c.get("status") not in STATUSES:
                raise ValueError("a chunk has no valid status")
            if not all(isinstance(c.get(k), int) and not isinstance(c.get(k), bool) for k in ("first", "last")):
                raise ValueError("a chunk has non-integer first/last")
            if c["last"] < c["first"] or not isinstance(c.get("log"), str):
                raise ValueError("a chunk has a bad range or log")
    except (KeyError, ValueError) as exc:
        raise StateError(f"STATE {path} is malformed: {exc}")
    return state


def cmd_plan(args) -> int:
    for label, value in (("--state", args.state), ("--out", args.out), ("--logs", args.logs)):
        if value is not None and not os.path.isabs(value):
            raise StateError(f"{label} must be an absolute path: {value}")
    if args.first < 0 or args.last < args.first:
        raise StateError("need 0 <= --first <= --last")
    if args.chunk < 1:
        raise StateError("--chunk must be at least 1")
    if not HASH_RUN.search(args.pattern) or len(HASH_RUN.findall(args.pattern)) != 1 or "/" in args.pattern \
            or "\\" in args.pattern:
        raise StateError("--pattern needs exactly one run of # and no folder part, e.g. frame_####.png")
    try:
        cmd = json.loads(args.cmd)
    except ValueError as exc:
        raise StateError(f"--cmd is not valid JSON: {exc}")
    if not isinstance(cmd, list) or not cmd or not all(isinstance(x, str) and x for x in cmd):
        raise StateError("--cmd must be a non-empty JSON list of non-empty strings")
    if not any("{first}" in x or "{last}" in x for x in cmd):
        raise StateError("--cmd must contain {first} or {last}, or every chunk renders the same frames")
    if os.path.exists(args.state) and not args.force:
        raise StateError(f"STATE exists (use --force to replace): {args.state}")
    if in_git_worktree(args.out) and not args.allow_in_repo:
        raise StateError(f"--out is inside a git work tree (frames must not be committed); "
                         f"use --allow-in-repo to override: {args.out}")
    seg = cloud_synced(args.out)
    if seg:
        print(f"{TOOL}: WARNING --out is in a cloud-synced folder ({seg}); frames will be synced", file=sys.stderr)
    folder = os.path.dirname(args.state)
    for other in sorted(glob.glob(os.path.join(glob.escape(folder), "*.json"))):
        if norm(other) == norm(args.state):
            continue
        try:
            with open(other, "r", encoding="utf-8") as fh:
                data = json.load(fh)
            o_first, o_last, o_out = data["first"], data["last"], data["out"]
            if data.get("tool") != TOOL or not (isinstance(o_first, int) and isinstance(o_last, int)):
                continue
        except (OSError, ValueError, KeyError, TypeError):
            continue
        if norm(o_out) == norm(args.out) and not (args.last < o_first or args.first > o_last):
            raise StateError(f"frames {args.first}-{args.last} overlap {o_first}-{o_last} in {other} "
                             f"(same --out); one STATE per GPU needs disjoint ranges")
    logs = args.logs or os.path.join(folder, os.path.splitext(os.path.basename(args.state))[0] + "_logs")
    chunks = []
    start, index = args.first, 1
    while start <= args.last:
        end = min(start + args.chunk - 1, args.last)
        chunks.append({"index": index, "first": start, "last": end, "status": "todo",
                       "log": os.path.join(logs, f"chunk_{index:04d}_f{start}-{end}.log"),
                       "started": None, "ended": None, "seconds": None, "frames_rendered": None})
        start, index = end + 1, index + 1
    state = {"tool": TOOL, "version": 1, "created": now_iso(), "first": args.first, "last": args.last,
             "chunk": args.chunk, "out": args.out, "pattern": args.pattern, "cmd": cmd, "logs": logs,
             "device": str(args.device), "chunks": chunks}
    os.makedirs(folder, exist_ok=True)
    save_state(args.state, state)
    total = args.last - args.first + 1
    print(f"{TOOL}: PASS planned {len(chunks)} chunk(s), {total} frame(s) {args.first}-{args.last} "
          f"into {args.out}; STATE {args.state}")
    return 0


def run_one(state: dict, chunk: dict, first: int, last: int) -> int:
    """Run the command once for first-last, appending to the chunk log. Returns the return code."""
    argv = expand(state["cmd"], first, last, state["out"], state["device"], chunk["log"])
    os.makedirs(os.path.dirname(chunk["log"]), exist_ok=True)
    with open(chunk["log"], "ab") as fh:
        fh.write(f"=== render_chunks: {now_iso()} frames {first}-{last} ===\n".encode("ascii"))
        fh.write(("=== command: " + json.dumps(argv) + " ===\n").encode("utf-8", "replace"))
        fh.flush()
        try:
            proc = subprocess.Popen(argv, stdin=subprocess.DEVNULL, stdout=fh, stderr=subprocess.STDOUT)
        except OSError as exc:
            raise StateError(f"cannot start the chunk command {argv[0]}: {exc}")
        return proc.wait()


def cmd_run(args) -> int:
    state = load_state(args.state)
    out, pattern = state["out"], state["pattern"]
    os.makedirs(out, exist_ok=True)
    total, executed, failed = len(state["chunks"]), 0, 0
    for chunk in state["chunks"]:
        if chunk["status"] == "done":
            continue
        if args.max_chunks is not None and executed >= args.max_chunks:
            break
        label = f"chunk {chunk['index']}/{total} frames {chunk['first']}-{chunk['last']}"
        missing = missing_frames(out, pattern, chunk["first"], chunk["last"])
        if not missing:
            chunk.update(status="done", seconds=0.0, frames_rendered=0, ended=now_iso(), missing=[])
            save_state(args.state, state)
            print(f"{TOOL}: {label}: all frames already present -> done")
            continue
        for n in missing:
            path = os.path.join(out, frame_name(pattern, n))
            if os.path.isfile(path) and os.path.getsize(path) == 0:
                os.remove(path)  # crash-truncated frame, must not be skipped by no-overwrite settings
        chunk.update(status="running", started=now_iso(), ended=None, seconds=None, frames_rendered=None)
        save_state(args.state, state)
        t0 = time.monotonic()
        rcs = []
        try:
            for run_first, run_last in runs_of(missing):
                rc = run_one(state, chunk, run_first, run_last)
                rcs.append(rc)
                if rc != 0:
                    break
        except StateError:
            chunk.update(status="failed", ended=now_iso(), seconds=time.monotonic() - t0, frames_rendered=0)
            save_state(args.state, state)
            raise
        elapsed = time.monotonic() - t0
        still = missing_frames(out, pattern, chunk["first"], chunk["last"])
        chunk.update(ended=now_iso(), seconds=elapsed, frames_rendered=len(missing) - len(still),
                     returncodes=rcs, missing=still[:MISSING_LISTED], missing_count=len(still))
        executed += 1
        if still:
            chunk["status"] = "failed"
            failed += 1
            print(f"{TOOL}: finding: {label}: failed, {len(still)} frame(s) missing "
                  f"{still[:10]}{' ...' if len(still) > 10 else ''} (return codes {rcs}); log {chunk['log']}")
            save_state(args.state, state)
            if args.stop_on_fail:
                break
            continue
        chunk["status"] = "done"
        note = f" (command returned {rcs[-1]} but every frame is present)" if rcs and rcs[-1] != 0 else ""
        print(f"{TOOL}: {label}: rendered {chunk['frames_rendered']} frame(s) in {elapsed:.1f} s -> done{note}")
        save_state(args.state, state)
    remaining = sum(1 for c in state["chunks"] if c["status"] != "done")
    if remaining == 0:
        print(f"{TOOL}: PASS all {total} chunk(s) done")
        return 0
    why = f"{failed} failed" if failed else "stopped before the end"
    print(f"{TOOL}: FAIL {remaining} finding(s) {remaining} of {total} chunk(s) not done ({why}); "
          f"run again to resume")
    return 1


def measured(state: dict) -> tuple[float | None, int, int]:
    """(seconds per frame, frames it is based on, chunks it is based on)."""
    secs = frames = chunks = 0
    for c in state["chunks"]:
        n = c.get("frames_rendered")
        if c["status"] == "done" and isinstance(n, int) and n > 0 and isinstance(c.get("seconds"), (int, float)):
            secs += c["seconds"]
            frames += n
            chunks += 1
    return (secs / frames if frames else None), frames, chunks


def cmd_status(args) -> int:
    state = load_state(args.state)
    out, pattern = state["out"], state["pattern"]
    findings, present_total, expected_total, missing_total, rows = [], 0, 0, 0, []
    for c in state["chunks"]:
        expected = c["last"] - c["first"] + 1
        missing = len(missing_frames(out, pattern, c["first"], c["last"]))
        present = expected - missing
        present_total, expected_total, missing_total = present_total + present, expected_total + expected, \
            missing_total + missing
        secs = c.get("seconds")
        extra = f", {secs:.1f} s" if isinstance(secs, (int, float)) else ""
        print(f"{TOOL}: chunk {c['index']} frames {c['first']}-{c['last']}: {c['status']}, "
              f"{present}/{expected} frames{extra}")
        if c["status"] != "done":
            findings.append(f"chunk {c['index']} is {c['status']}")
        elif missing:
            findings.append(f"chunk {c['index']} is done but {missing} frame(s) are missing now")
        rows.append({"index": c["index"], "first": c["first"], "last": c["last"], "status": c["status"],
                     "frames_present": present, "frames_expected": expected, "seconds": secs})
    spf, basis_frames, basis_chunks = measured(state)
    if spf is None:
        print(f"{TOOL}: measured: none yet (no done chunk has rendered frames); ETA unknown")
        eta = None
    else:
        eta = spf * missing_total
        print(f"{TOOL}: measured: {spf:.3f} s/frame over {basis_frames} frame(s) in {basis_chunks} chunk(s); "
              f"ETA {fmt_duration(eta)} for {missing_total} frame(s) missing")
    print(f"{TOOL}: frames present {present_total}/{expected_total}")
    for f in findings:
        print(f"{TOOL}: finding: {f}")
    status = "pass" if not findings else "fail"
    if args.json:
        with open(args.json, "w", encoding="utf-8") as fh:
            json.dump({"tool": TOOL, "status": status, "findings": findings, "state": args.state,
                       "frames_present": present_total, "frames_expected": expected_total,
                       "frames_missing": missing_total, "seconds_per_frame": spf, "eta_seconds": eta,
                       "chunks": rows}, fh, indent=2)
            fh.write("\n")
    if findings:
        print(f"{TOOL}: FAIL {len(findings)} finding(s) {present_total}/{expected_total} frames present")
        return 1
    print(f"{TOOL}: PASS all {len(rows)} chunk(s) done, {present_total}/{expected_total} frames present")
    return 0


def make_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="render_chunks.py",
        description="Chunked, resumable frame rendering with a STATE file. One process per GPU: run one "
                    "STATE per GPU with disjoint frame ranges and a --device each (a second process on a "
                    "busy GPU gives no speed-up). Exit: 0 all done, 1 not all done, 2 could not run.")
    sub = p.add_subparsers(dest="command", required=True)
    plan = sub.add_parser("plan", help="write a STATE file with the chunk list")
    plan.add_argument("--state", required=True)
    plan.add_argument("--first", type=int, required=True)
    plan.add_argument("--last", type=int, required=True)
    plan.add_argument("--chunk", type=int, required=True, help="frames per chunk")
    plan.add_argument("--out", required=True, help="absolute folder for the frames")
    plan.add_argument("--pattern", default="frame_####.png")
    plan.add_argument("--cmd", required=True, help="JSON list; placeholders {first} {last} {out} {device} {log}")
    plan.add_argument("--logs")
    plan.add_argument("--device", default="0")
    plan.add_argument("--force", action="store_true", help="replace an existing STATE")
    plan.add_argument("--allow-in-repo", action="store_true", help="allow --out inside a git work tree")
    run = sub.add_parser("run", help="run every chunk that is not done")
    run.add_argument("--state", required=True)
    run.add_argument("--max-chunks", type=int, help="run at most N chunks, then stop")
    run.add_argument("--stop-on-fail", action="store_true", help="stop at the first failed chunk")
    status = sub.add_parser("status", help="per-chunk status, measured s/frame and ETA")
    status.add_argument("--state", required=True)
    status.add_argument("--json", help="write a machine report")
    return p


def main(argv=None) -> int:
    args = make_parser().parse_args(argv)
    try:
        if args.command == "plan":
            return cmd_plan(args)
        if args.command == "run":
            if args.max_chunks is not None and args.max_chunks < 1:
                raise StateError("--max-chunks must be at least 1")
            return cmd_run(args)
        return cmd_status(args)
    except StateError as exc:
        err(str(exc))
        return 2
    except OSError as exc:
        err(str(exc))
        return 2


if __name__ == "__main__":
    sys.exit(main())
