#!/usr/bin/env python3
"""Assemble one delivered version: the video, the exact scripts that made it, run records and a hash manifest.

Purpose: a delivered video is only reproducible if the exact scene scripts, presets and asset list that made
it travel with it. Keeping them "by hand" beside each delivery drifts. This tool builds a new, never
overwritten folder <dest>/<version>/ holding the video, a source/ folder with copies of the files you name, a
records/ folder with the run records (for example blender_run records), a README.txt with the commands and
the Blender version found in the records, and MANIFEST.sha256 listing the sha256 of every file. It then
verifies the manifest by hashing everything again. The delivery root is a local folder; this tool never
uploads anything.

Usage:
  python render_bundle.py --dest ABS_DELIVERY_ROOT --version NAME --video FILE
                          [--include PATH ...] [--commands FILE.txt] [--record RUN.json ...]
                          [--note TEXT] [--allow-in-repo] [--json OUT]

Inputs:
  --dest        absolute delivery root; created if missing. Refused (exit 2) inside a git work tree unless
                --allow-in-repo; a warning is printed for cloud-synced folders (OneDrive, Dropbox, iCloud,
                Google Drive).
  --version     the folder name: letters, digits, dot, underscore, hyphen; at most 64 characters. The folder
                <dest>/<version> must not exist (exit 2); nothing is ever overwritten.
  --video       the delivered file, copied to <version>/<its name>.
  --include     a file or folder, repeatable. A relative path keeps its relative name under source/ (so
                render/scenes/a.py becomes source/render/scenes/a.py); an absolute path, or one climbing out
                with .., is stored under its last name. Folders are copied with their contents (.git and
                __pycache__ are skipped). Two includes that land on the same file are refused.
  --commands    a text file with the commands that rebuild the video; its contents go into README.txt.
  --record      a JSON run record, repeatable, copied to records/. A "blender_version" (or "version") field
                is reported in the README; differing versions are called out.
  --note        free text written into README.txt.
Outputs: the folder above and a summary line `render_bundle: PASS <path> n file(s) ...`. All inputs are
checked before anything is created, and a copy failure removes the folder this run created.
Exit codes: 0 bundle written and manifest verified, 1 the manifest check found a mismatch (the bundle is kept
for inspection), 2 could not run (bad arguments, missing inputs, folder exists, path in a git work tree).
Dependencies: Python 3.10+ standard library.
Assumptions: file names are plain (no newlines). The manifest format is sha256sum compatible: run
`sha256sum -c MANIFEST.sha256` inside the folder to check it later.
Origin: new (prior project kept exact scripts beside each delivery by hand).
"""

from __future__ import annotations

import argparse
import datetime as _dt
import hashlib
import json
import os
import re
import shutil
import sys

TOOL = "render_bundle"
CLOUD_SEGMENTS = ("onedrive", "dropbox", "icloud", "icloud drive", "iclouddrive", "google drive", "googledrive")
VERSION_RE = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]{0,63}")
RESERVED = {"readme.txt", "manifest.sha256", "source", "records"}
SKIP_DIRS = {".git", "__pycache__"}


class BundleError(Exception):
    """Could not run (exit 2)."""


def err(message: str) -> None:
    print(f"{TOOL}: ERROR {message}", file=sys.stderr)


def sha256_file(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for block in iter(lambda: fh.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


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


def posix(path: str) -> str:
    return path.replace(os.sep, "/")


def include_name(text: str) -> str:
    """The name an include gets under source/."""
    if not os.path.isabs(text):
        norm = os.path.normpath(text)
        if not norm.startswith("..") and norm != ".":
            return posix(norm)
    base = os.path.basename(os.path.normpath(os.path.abspath(text)))
    if not base:
        raise BundleError(f"cannot name the include: {text}")
    return base


def plan_include(text: str) -> list[tuple[str, str]]:
    """[(source file, relative path under source/)] for one --include. Raises BundleError."""
    if not os.path.exists(text):
        raise BundleError(f"--include not found: {text}")
    name = include_name(text)
    if os.path.isfile(text):
        return [(os.path.abspath(text), name)]
    pairs = []
    for root, dirs, files in os.walk(text):
        dirs[:] = sorted(d for d in dirs if d not in SKIP_DIRS)
        for f in sorted(files):
            full = os.path.join(root, f)
            pairs.append((os.path.abspath(full), posix(os.path.join(name, os.path.relpath(full, text)))))
    return pairs


def read_record(path: str) -> dict:
    try:
        with open(path, "r", encoding="utf-8") as fh:
            data = json.load(fh)
    except (OSError, ValueError) as exc:
        raise BundleError(f"--record is not readable JSON: {path}: {exc}")
    if not isinstance(data, dict):
        raise BundleError(f"--record is not a JSON object: {path}")
    return data


def write_manifest(root: str) -> list[str]:
    lines = []
    for base, dirs, files in os.walk(root):
        dirs.sort()
        for f in files:
            full = os.path.join(base, f)
            rel = posix(os.path.relpath(full, root))
            if rel == "MANIFEST.sha256":
                continue
            lines.append((rel, sha256_file(full)))
    lines.sort()
    with open(os.path.join(root, "MANIFEST.sha256"), "w", encoding="utf-8", newline="\n") as fh:
        for rel, digest in lines:
            fh.write(f"{digest}  {rel}\n")
    return [rel for rel, _ in lines]


def verify_manifest(root: str) -> list[str]:
    """Hash everything again. Returns the problems found (empty = verified)."""
    problems = []
    listed = {}
    with open(os.path.join(root, "MANIFEST.sha256"), "r", encoding="utf-8") as fh:
        for number, line in enumerate(fh, start=1):
            line = line.rstrip("\n")
            digest, sep, rel = line.partition("  ")
            if not sep or len(digest) != 64 or not rel:
                problems.append(f"manifest line {number} is malformed")
                continue
            listed[rel] = digest
    for rel, digest in listed.items():
        full = os.path.join(root, *rel.split("/"))
        if not os.path.isfile(full):
            problems.append(f"{rel}: listed but missing")
        elif sha256_file(full) != digest:
            problems.append(f"{rel}: sha256 differs from the manifest")
    for base, _, files in os.walk(root):
        for f in files:
            rel = posix(os.path.relpath(os.path.join(base, f), root))
            if rel != "MANIFEST.sha256" and rel not in listed:
                problems.append(f"{rel}: present but not listed")
    return problems


def readme_text(version: str, video_name: str, video_bytes: int, note: str | None, commands: str | None,
                versions: dict[str, list[str]], n_source: int, n_records: int) -> str:
    out = [f"Delivery {version}", f"Created: {_dt.datetime.now().astimezone().isoformat(timespec='seconds')}",
           f"Video: {video_name} ({video_bytes} bytes)"]
    if note:
        out.append(f"Note: {note}")
    if not versions:
        out.append("Blender version: not recorded (no run record with a version was given)")
    elif len(versions) == 1:
        out.append(f"Blender version: {next(iter(versions))} (from {', '.join(next(iter(versions.values())))})")
    else:
        out.append("Blender version: WARNING the records disagree: " +
                   "; ".join(f"{v} in {', '.join(files)}" for v, files in sorted(versions.items())))
    out += ["", "Contents:", f"  {video_name}   the delivered video",
            f"  source/   {n_source} file(s): the exact scripts, presets and lists used",
            f"  records/  {n_records} run record(s)",
            "  MANIFEST.sha256   sha256 and relative path of every other file",
            "", "Verify: inside this folder run  sha256sum -c MANIFEST.sha256", "", "Commands that rebuild the video:"]
    out.append(commands.rstrip("\n") if commands is not None else "(no commands file was given)")
    return "\n".join(out) + "\n"


def make_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="render_bundle.py",
        description="Build <dest>/<version>/ with the video, copies of the exact scripts and records, a README "
                    "and a verified sha256 manifest. Never overwrites. Exit: 0 ok, 1 manifest mismatch, "
                    "2 could not run.")
    p.add_argument("--dest", required=True, help="absolute delivery root")
    p.add_argument("--version", required=True, help="folder name for this delivery")
    p.add_argument("--video", required=True)
    p.add_argument("--include", action="append", default=[], help="file or folder copied to source/ (repeatable)")
    p.add_argument("--commands", help="text file of the commands that rebuild the video")
    p.add_argument("--record", action="append", default=[], help="run record JSON copied to records/ (repeatable)")
    p.add_argument("--note")
    p.add_argument("--allow-in-repo", action="store_true", help="allow --dest inside a git work tree")
    p.add_argument("--json", help="write a machine report")
    return p


def main(argv=None) -> int:
    args = make_parser().parse_args(argv)
    try:
        if not os.path.isabs(args.dest):
            raise BundleError(f"--dest must be an absolute path: {args.dest}")
        if not VERSION_RE.fullmatch(args.version):
            raise BundleError(f"--version must match [A-Za-z0-9][A-Za-z0-9._-]* (max 64 chars): {args.version!r}")
        if in_git_worktree(args.dest) and not args.allow_in_repo:
            raise BundleError(f"--dest is inside a git work tree (a delivery must not be committed); "
                              f"use --allow-in-repo to override: {args.dest}")
        final = os.path.join(args.dest, args.version)
        if os.path.exists(final):
            raise BundleError(f"the delivery folder already exists and is never overwritten: {final}")
        if not os.path.isfile(args.video):
            raise BundleError(f"--video is not a file: {args.video}")
        video_name = os.path.basename(args.video)
        if video_name.lower() in RESERVED:
            raise BundleError(f"the video name collides with a reserved bundle name: {video_name}")
        commands = None
        if args.commands:
            try:
                with open(args.commands, "r", encoding="utf-8") as fh:
                    commands = fh.read()
            except (OSError, UnicodeDecodeError) as exc:
                raise BundleError(f"--commands is not a readable UTF-8 text file: {args.commands}: {exc}")
        sources: list[tuple[str, str]] = []
        seen: dict[str, str] = {}
        final_key = os.path.normcase(os.path.abspath(final))
        for text in args.include:
            inc_key = os.path.normcase(os.path.abspath(text))
            if os.path.isdir(text) and (final_key == inc_key or final_key.startswith(inc_key.rstrip(os.sep) + os.sep)):
                raise BundleError(f"--include contains the delivery folder itself: {text}")
            for src, rel in plan_include(text):
                if rel in seen:
                    raise BundleError(f"two includes land on source/{rel}: {seen[rel]} and {src}")
                seen[rel] = src
                sources.append((src, rel))
        records, versions, names = [], {}, set()
        for path in args.record:
            data = read_record(path)
            name = os.path.basename(path)
            if name in names:
                raise BundleError(f"two --record files share the name {name}")
            names.add(name)
            records.append((os.path.abspath(path), name))
            v = data.get("blender_version") or data.get("version")
            if isinstance(v, str) and v.strip():
                versions.setdefault(v.strip(), []).append(name)
        try:
            os.makedirs(args.dest, exist_ok=True)
            os.mkdir(final)
        except FileExistsError:
            raise BundleError(f"the delivery folder already exists and is never overwritten: {final}")
        except OSError as exc:
            raise BundleError(f"cannot create {final}: {exc}")
    except BundleError as exc:
        err(str(exc))
        return 2
    seg = cloud_synced(args.dest)
    if seg:
        print(f"{TOOL}: WARNING --dest is in a cloud-synced folder ({seg}); the delivery will be synced",
              file=sys.stderr)
    try:
        shutil.copy2(args.video, os.path.join(final, video_name))
        for src, rel in sources:
            target = os.path.join(final, "source", *rel.split("/"))
            os.makedirs(os.path.dirname(target), exist_ok=True)
            shutil.copy2(src, target)
        if records:
            os.makedirs(os.path.join(final, "records"))
            for src, name in records:
                shutil.copy2(src, os.path.join(final, "records", name))
        text = readme_text(args.version, video_name, os.path.getsize(args.video), args.note, commands, versions,
                           len(sources), len(records))
        with open(os.path.join(final, "README.txt"), "w", encoding="utf-8", newline="\n") as fh:
            fh.write(text)
        files = write_manifest(final)
    except OSError as exc:
        shutil.rmtree(final, ignore_errors=True)  # the folder this run just created
        err(f"copy failed, the partial delivery folder was removed: {exc}")
        return 2
    problems = verify_manifest(final)
    total = sum(os.path.getsize(os.path.join(final, *rel.split("/"))) for rel in files)
    if args.json:
        try:
            with open(args.json, "w", encoding="utf-8") as fh:
                json.dump({"tool": TOOL, "status": "fail" if problems else "pass", "findings": problems,
                           "folder": final, "files": files, "bytes": total,
                           "blender_versions": versions}, fh, indent=2)
                fh.write("\n")
        except OSError as exc:
            err(f"cannot write {args.json}: {exc}")
            return 2
    for prob in problems:
        print(f"{TOOL}: finding: {prob}")
    if problems:
        print(f"{TOOL}: FAIL {len(problems)} finding(s) manifest verification of {final}; the folder is kept")
        return 1
    print(f"{TOOL}: PASS {final} {len(files)} file(s), {total} bytes, manifest verified")
    return 0


if __name__ == "__main__":
    sys.exit(main())
