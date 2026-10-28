#!/usr/bin/env python3
"""Run one Blender script headless and fail on any Python error, with a log and a run record.

Purpose: Blender's exit code alone is not a safe signal. A script that raises can still leave a process that
exits 0 (when --python-exit-code is forgotten) and the traceback is then buried in a log nobody reads. This
tool runs one script with a fixed, auditable command line, streams all output to a log file, scans that log
for tracebacks and script errors, checks the Blender version against a pinned lock file, and writes a run
record. Every run of a render project that touches Blender goes through it.

Usage:
  python blender_run.py (--lock LOCK.json | --blender EXE | --blender-cmd JSON_LIST)
                        [--blend FILE] --log ABS.log [--record ABS.json] [--timeout SEC]
                        SCRIPT.py [-- ARGS...]
  python blender_run.py (--lock LOCK.json | --blender EXE | --blender-cmd JSON_LIST) --self-test [--log ABS.log]

Inputs:
  --lock          JSON file {"version": "5.2.3", "path": "<exe>", "sha256": "<optional>"}. A relative path is
                  resolved against the lock file's folder. A missing executable, or a sha256 that does not
                  match the file, exits 2. When the log's first "Blender X.Y.Z" line disagrees with the lock
                  version (or no such line is found), that is a finding.
  --blender       the executable, no lock check.
  --blender-cmd   a JSON list that replaces the executable in the command (for wrappers and test fakes).
  --blend         a .blend file opened before the script runs.
  --log           absolute path; stdout and stderr are merged into it as they happen (not held in memory).
  --record        absolute or relative path of a JSON run record: blender path, version parsed, argv, cwd,
                  start and end ISO times, seconds, return code, findings. (--json is an alias.)
  --timeout       seconds; on expiry the process is killed and that is a finding.
  --self-test     run Blender with a generated script that raises RuntimeError and pass only when this tool
                  itself detects the failure. This is a Blender gate run by the procedure, not by CI.
  SCRIPT.py       the Python file run with -P. Everything after a bare -- is passed to the script after the
                  Blender "--" separator (read it from sys.argv after "--").
The command is: [exe] -b [blend] --factory-startup --python-exit-code 1 -P SCRIPT -- ARGS...

Outputs: one finding per line on stdout, then a summary line `blender_run: PASS ...` or
`blender_run: FAIL n finding(s) ...`; errors on stderr prefixed `blender_run: ERROR`.
Findings (exit 1): non-zero return code; a line "Traceback (most recent call last)"; a line starting with
"Error: " (this includes "Error: Python:"); a version mismatch; a timeout. Each log finding carries its
line number.
Exit codes: 0 pass, 1 findings, 2 could not run (bad arguments, missing input or executable, lock problem).
Self-test exit codes: 0 failure was detected, 1 it went unnoticed, 2 Blender could not run.
Dependencies: Python 3.10+ standard library.
Assumptions: Blender prints "Blender X.Y.Z" within the first lines of its output in background mode. The
working directory is left unchanged. At most 50 log findings are listed; the rest are counted.
Origin: new (prior project ran Blender from shell loops with no traceback scan).
"""

from __future__ import annotations

import argparse
import datetime as _dt
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time

TOOL = "blender_run"
MAX_LOG_FINDINGS = 50
VERSION_SCAN_LINES = 20
VERSION_RE = re.compile(r"\s*Blender (\d+\.\d+(?:\.\d+)?)")


class RunError(Exception):
    """Could not run (exit 2)."""


def now_iso() -> str:
    return _dt.datetime.now().astimezone().isoformat(timespec="seconds")


def err(message: str) -> None:
    print(f"{TOOL}: ERROR {message}", file=sys.stderr)


def sha256_file(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for block in iter(lambda: fh.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def versions_agree(lock_version: str, seen: str) -> bool:
    """The lock may name fewer components than Blender prints (5.2 matches 5.2.3)."""
    want = lock_version.strip().split(".")
    got = seen.split(".")
    return got[:len(want)] == want


def load_lock(lock_path: str) -> tuple[list[str], str, str | None]:
    """Returns (executable command, pinned version, sha256 or None). Raises RunError."""
    try:
        with open(lock_path, "r", encoding="utf-8") as fh:
            data = json.load(fh)
    except (OSError, ValueError) as exc:
        raise RunError(f"cannot read lock file {lock_path}: {exc}")
    if not isinstance(data, dict):
        raise RunError(f"lock file {lock_path} is not a JSON object")
    version, path, digest = data.get("version"), data.get("path"), data.get("sha256")
    if not isinstance(version, str) or not version.strip():
        raise RunError(f"lock file {lock_path}: 'version' must be a non-empty string")
    if not isinstance(path, str) or not path.strip():
        raise RunError(f"lock file {lock_path}: 'path' must be a non-empty string")
    if digest is not None and (not isinstance(digest, str) or not digest.strip()):
        raise RunError(f"lock file {lock_path}: 'sha256' must be a string when present")
    if not os.path.isabs(path):
        path = os.path.join(os.path.dirname(os.path.abspath(lock_path)), path)
    if not os.path.isfile(path):
        raise RunError(f"lock file {lock_path}: Blender executable not found: {path}")
    if digest:
        actual = sha256_file(path)
        if actual.lower() != digest.strip().lower():
            raise RunError(f"lock file {lock_path}: sha256 of {path} is {actual}, the lock pins {digest}")
    return [path], version.strip(), digest


def build_command(exe_cmd: list[str], blend: str | None, script: str, extra: list[str]) -> list[str]:
    cmd = list(exe_cmd) + ["-b"]
    if blend:
        cmd.append(blend)
    cmd += ["--factory-startup", "--python-exit-code", "1", "-P", script, "--"] + list(extra)
    return cmd


def run_streaming(cmd: list[str], log_path: str, timeout: float | None) -> dict:
    """Run cmd with stdout and stderr merged straight into log_path. Raises RunError if it cannot start."""
    os.makedirs(os.path.dirname(log_path), exist_ok=True)
    start_wall = now_iso()
    t0 = time.monotonic()
    timed_out = False
    with open(log_path, "wb") as fh:
        try:
            proc = subprocess.Popen(cmd, stdin=subprocess.DEVNULL, stdout=fh, stderr=subprocess.STDOUT)
        except OSError as exc:
            raise RunError(f"cannot start {cmd[0]}: {exc}")
        try:
            rc = proc.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            timed_out = True
            proc.kill()
            rc = proc.wait()
    return {"returncode": rc, "timed_out": timed_out, "start": start_wall, "end": now_iso(),
            "seconds": time.monotonic() - t0}


def scan_log(log_path: str) -> tuple[list[dict], str | None, int]:
    """Stream the log. Returns (log findings, parsed version, number of findings not listed)."""
    findings: list[dict] = []
    version = None
    omitted = 0
    with open(log_path, "r", encoding="utf-8", errors="replace") as fh:
        for number, raw in enumerate(fh, start=1):
            line = raw.rstrip("\r\n")
            if version is None and number <= VERSION_SCAN_LINES:
                m = VERSION_RE.match(line)
                if m:
                    version = m.group(1)
            kind = None
            if "Traceback (most recent call last)" in line:
                kind = "traceback"
            elif line.startswith("Error: "):
                kind = "script-error"
            if kind:
                if len(findings) < MAX_LOG_FINDINGS:
                    findings.append({"kind": kind, "line": number, "text": line[:200]})
                else:
                    omitted += 1
    return findings, version, omitted


def execute(exe_cmd: list[str], lock_version: str | None, blend: str | None, script: str, extra: list[str],
            log_path: str, timeout: float | None) -> dict:
    cmd = build_command(exe_cmd, blend, script, extra)
    run = run_streaming(cmd, log_path, timeout)
    log_findings, version, omitted = scan_log(log_path)
    findings: list[dict] = []
    if run["timed_out"]:
        findings.append({"kind": "timeout", "line": None, "text": f"killed after {timeout} s"})
    if run["returncode"] != 0 and not run["timed_out"]:
        findings.append({"kind": "returncode", "line": None, "text": f"return code {run['returncode']}"})
    findings += log_findings
    if lock_version is not None:
        if version is None:
            findings.append({"kind": "version", "line": None,
                             "text": f"no 'Blender X.Y.Z' line in the first {VERSION_SCAN_LINES} log lines; "
                                     f"cannot confirm pinned version {lock_version}"})
        elif not versions_agree(lock_version, version):
            findings.append({"kind": "version", "line": 1,
                             "text": f"log says Blender {version}, the lock pins {lock_version}"})
    return {"cmd": cmd, "run": run, "version": version, "findings": findings, "omitted": omitted}


def split_extra(argv: list[str]) -> tuple[list[str], list[str]]:
    if "--" in argv:
        i = argv.index("--")
        return argv[:i], argv[i + 1:]
    return argv, []


def make_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="blender_run.py",
        description="Run one Blender script headless; fail on non-zero exit, traceback, script error or "
                    "version mismatch. Put script arguments after a bare --.",
        epilog="Exit: 0 pass, 1 findings, 2 could not run. See the module docstring for the full contract.")
    which = p.add_mutually_exclusive_group(required=True)
    which.add_argument("--lock", help="lock JSON: version, path, optional sha256")
    which.add_argument("--blender", help="Blender executable (no version pin)")
    which.add_argument("--blender-cmd", help="JSON list replacing the executable in the command")
    p.add_argument("--blend", help=".blend file to open")
    p.add_argument("--log", help="absolute path of the merged stdout+stderr log")
    p.add_argument("--record", "--json", dest="record", help="path of the JSON run record")
    p.add_argument("--timeout", type=float, help="seconds before the process is killed")
    p.add_argument("--self-test", action="store_true",
                   help="run a script that raises and pass only if this tool detects it")
    p.add_argument("script", nargs="?", help="Python script run with -P")
    return p


def resolve_executable(args) -> tuple[list[str], str | None]:
    if args.lock:
        exe, version, _ = load_lock(args.lock)
        return exe, version
    if args.blender:
        path = args.blender
        if not os.path.isfile(path):
            raise RunError(f"Blender executable not found: {path}")
        return [path], None
    try:
        cmd = json.loads(args.blender_cmd)
    except ValueError as exc:
        raise RunError(f"--blender-cmd is not valid JSON: {exc}")
    if not isinstance(cmd, list) or not cmd or not all(isinstance(x, str) and x for x in cmd):
        raise RunError("--blender-cmd must be a non-empty JSON list of non-empty strings")
    return cmd, None


def report(result: dict, extra_summary: str) -> int:
    findings = result["findings"]
    for f in findings:
        where = f"log line {f['line']}: " if f["line"] else ""
        print(f"{TOOL}: finding: {f['kind']}: {where}{f['text']}")
    if result["omitted"]:
        print(f"{TOOL}: finding: {result['omitted']} more log finding(s) not listed")
    n = len(findings) + (1 if result["omitted"] else 0)
    run = result["run"]
    tail = f"rc={run['returncode']} blender={result['version'] or 'unknown'} seconds={run['seconds']:.1f}"
    if n:
        print(f"{TOOL}: FAIL {n} finding(s) {tail}{extra_summary}")
        return 1
    print(f"{TOOL}: PASS {tail}{extra_summary}")
    return 0


def self_test(args, exe_cmd: list[str], lock_version: str | None) -> int:
    tmp = tempfile.mkdtemp(prefix="blender_run_selftest_")
    script = os.path.join(tmp, "selftest_raise.py")
    with open(script, "w", encoding="utf-8") as fh:
        fh.write("raise RuntimeError('blender_run self-test: this exception must be detected')\n")
    log = os.path.abspath(args.log) if args.log else os.path.join(tmp, "selftest.log")
    try:
        result = execute(exe_cmd, lock_version, None, script, [], log, args.timeout or 300.0)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)  # a folder this function just created
    kinds = {f["kind"] for f in result["findings"]}
    detected = bool(kinds & {"returncode", "traceback"})
    if result["run"]["timed_out"]:
        err("self-test: Blender did not finish before the timeout; it could not be exercised")
        return 2
    if detected:
        print(f"{TOOL}: PASS self-test: failure detected ({', '.join(sorted(kinds))}) "
              f"rc={result['run']['returncode']} blender={result['version'] or 'unknown'}")
        return 0
    print(f"{TOOL}: FAIL 1 finding(s) self-test: the script raised RuntimeError but rc was "
          f"{result['run']['returncode']} and the log had no traceback")
    return 1


def main(argv=None) -> int:
    argv = list(sys.argv[1:] if argv is None else argv)
    head, extra = split_extra(argv)
    args = make_parser().parse_args(head)
    try:
        if args.timeout is not None and not args.timeout > 0:
            raise RunError("--timeout must be a positive number of seconds")
        if args.blend and not os.path.isfile(args.blend):
            raise RunError(f".blend file not found: {args.blend}")
        exe_cmd, lock_version = resolve_executable(args)
        if args.self_test:
            if args.script or extra:
                raise RunError("--self-test takes no SCRIPT and no script arguments")
            if args.log and not os.path.isabs(args.log):
                raise RunError(f"--log must be an absolute path: {args.log}")
            return self_test(args, exe_cmd, lock_version)
        if not args.script:
            raise RunError("SCRIPT.py is required (or use --self-test)")
        if not os.path.isfile(args.script):
            raise RunError(f"script not found: {args.script}")
        if not args.log:
            raise RunError("--log is required")
        if not os.path.isabs(args.log):
            raise RunError(f"--log must be an absolute path: {args.log}")
        script = os.path.abspath(args.script)
        blend = os.path.abspath(args.blend) if args.blend else None
        result = execute(exe_cmd, lock_version, blend, script, extra, args.log, args.timeout)
    except RunError as exc:
        err(str(exc))
        return 2
    code = report(result, f" log={args.log}")
    if args.record:
        run = result["run"]
        record = {
            "tool": TOOL, "status": "pass" if code == 0 else "fail",
            "blender": exe_cmd[-1] if len(exe_cmd) == 1 else exe_cmd,
            "blender_version": result["version"], "lock_version": lock_version,
            "argv": result["cmd"], "cwd": os.getcwd(), "log": args.log,
            "start": run["start"], "end": run["end"], "seconds": run["seconds"],
            "returncode": run["returncode"], "timed_out": run["timed_out"],
            "findings": result["findings"], "findings_omitted": result["omitted"],
        }
        try:
            parent = os.path.dirname(os.path.abspath(args.record))
            os.makedirs(parent, exist_ok=True)
            with open(args.record, "w", encoding="utf-8") as fh:
                json.dump(record, fh, indent=2)
                fh.write("\n")
        except OSError as exc:
            err(f"cannot write record {args.record}: {exc}")
            return 2
    return code


if __name__ == "__main__":
    sys.exit(main())
