#!/usr/bin/env python3
"""Commit and push one work unit, limited to named paths, refusing unless the gate passes.

Purpose: shell chains of the form `check && write-message && git commit` skip the commit silently when an
earlier step exits non-zero for an innocent reason (grep finding no match, a message file never written), and
nobody notices until the push log shows the old HEAD. A plain `git commit -a` also carries along files another
worker staged or edited. This helper is the single commit path for a work unit: it verifies its arguments, runs
the gate, commits only the named paths, pushes, and prints exactly what it did.

Usage:
  python commit_unit.py --root REPO -F MSGFILE [--allowed PATH ...] [--gate-cmd CMD [--gate-pass-regex RE]]
                        [--no-push] [--dry-run] [--remote NAME] -- path1 path2 ...
  python commit_unit.py --root REPO -F MSGFILE --skip-gate --reason "why" -- path1 ...

Inputs:
  --root          the git repository root; paths are resolved against the current directory and must lie
                  inside it.
  --allowed       a folder or file (relative to root, repeatable) the paths must lie under; default is the
                  whole root. Use it to keep a worker inside the folders it owns.
  -F MSGFILE      the commit message, read from a file that must already exist and be non-empty (write it
                  first, before any check, so a failed check cannot leave the file unwritten).
  --gate-cmd      a command line run through the system shell from the root; exit 0 is a pass, anything else
                  refuses the commit and prints the last lines of its output. --gate-pass-regex additionally
                  requires a match in the output (a gate that exits 0 without printing its verdict is not a
                  pass). Operator-supplied, so it has the trust of the operator's own shell.
  --skip-gate     skip the gate; needs --reason, which is written into the message as `gate skipped: <reason>`.
  --no-push       commit only. --dry-run runs every check and the gate, then stops before git add.
Outputs: the new short HEAD hash and `pushed` or `not pushed`; refusals name the cause on stderr.
Exit codes: 0 committed (and pushed unless --no-push), 1 refused or a git step failed (nothing is ever
skipped silently), 2 could not run (bad arguments, not a repository, a path outside the allowed folders or
unknown to git, a missing message file).
Dependencies: Python 3 standard library and git.
Assumptions: the path argument may be a file, a folder, a staged deletion or the old side of a staged rename;
those last two are not given to `git add` (git refuses them) but are given to `git commit -- <path>`, which
records them. A path that is in neither the working tree nor the index nor the staged changes is refused
before the gate runs, because a typo would otherwise cost a whole gate run and then fail at git commit.
Safety: never forces. A force flag or a +refspec in any git call raises before it reaches git. A push refused
as non-fast-forward is reported and the commit stays local; fetch, rebase by hand, and rerun with the
same paths. The sha256 of every named file is recorded before the gate and compared again before git add and
before git commit, so a file edited during a long gate is refused as `changed during the gate` instead of
being committed in a state the gate never saw.
"""

from __future__ import annotations

import argparse
import hashlib
import re
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Sequence

GATE_TAIL_LINES = 15
FORCE_FLAGS = ("-f", "--mirror", "--delete")


class Refusal(Exception):
    """A refusal with its exit code (1 refused, 2 could not run)."""

    def __init__(self, message: str, code: int = 1):
        super().__init__(message)
        self.code = code


def _refuse_force(args: Sequence[str]) -> None:
    head = list(args[:args.index("--")]) if "--" in args else list(args)
    for arg in head[1:]:
        if arg in FORCE_FLAGS or arg.startswith("--force") or arg.startswith("+"):
            raise RuntimeError(f"commit_unit: internal error: a force option reached git ({' '.join(args)})")


def git(root: Path, *args: str) -> subprocess.CompletedProcess:
    argv = ["git", *args]
    _refuse_force(argv)
    return subprocess.run(argv, cwd=root, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                          check=False)


def tail(text: str, count: int = GATE_TAIL_LINES) -> str:
    return "\n".join((text or "").rstrip().splitlines()[-count:])


def rel_posix(path: Path, root: Path) -> str:
    return path.resolve().relative_to(root.resolve()).as_posix()


def resolve_paths(paths: Sequence[str], root: Path, allowed: Sequence[str], cwd: Path) -> list[str]:
    """Root-relative posix paths. Refuses a path outside root or outside every allowed folder (exit 2)."""
    root = root.resolve()
    allowed_abs = [(root / a).resolve() for a in allowed] if allowed else [root]
    result: list[str] = []
    for text in paths:
        p = Path(text)
        absolute = (p if p.is_absolute() else Path(cwd) / p).resolve()
        if not absolute.is_relative_to(root):
            raise Refusal(f"commit_unit: refused: outside the repository root: {text}", 2)
        if not any(absolute == a or absolute.is_relative_to(a) for a in allowed_abs):
            raise Refusal(f"commit_unit: refused: outside the allowed paths: {text}", 2)
        rel = rel_posix(absolute, root)
        if rel == ".":
            raise Refusal("commit_unit: refused: the repository root itself is not a pathspec; name files "
                          "or folders", 2)
        if rel not in result:
            result.append(rel)
    return result


def _names(entries: Sequence[str], spec: str) -> bool:
    return any(e == spec or e.startswith(spec.rstrip("/") + "/") for e in entries)


def classify_paths(root: Path, specs: Sequence[str]) -> tuple[list[str], list[str]]:
    """(paths for git add, paths left to git commit alone). A missing path must be known to git as a tracked
    file or a staged deletion or rename; anything else is refused with exit 2."""
    missing = [s for s in specs if not (root / s).exists()]
    if not missing:
        return list(specs), []
    known: list[str] = []
    for query in (["ls-files", "-z", "--cached", "--", *missing],
                  ["diff", "--cached", "--name-only", "--no-renames", "-z", "--", *missing]):
        answer = git(root, *query)
        if answer.returncode != 0:
            raise Refusal(f"commit_unit: git {query[0]} failed:\n{tail(answer.stdout)}", 1)
        known += [e for e in (answer.stdout or "").split("\0") if e]
    unknown = [s for s in missing if not _names(known, s)]
    if unknown:
        raise Refusal("\n".join(f"commit_unit: refused: not in the working tree or the index: {s}"
                                for s in unknown), 2)
    return [s for s in specs if s not in missing], missing


def _digest(path: Path) -> str | None:
    if not path.is_file():
        return None
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for block in iter(lambda: fh.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def snapshot(root: Path, specs: Sequence[str]) -> dict[str, str | None]:
    """sha256 per file for every named file (every file under a folder spec); None for a missing file."""
    state: dict[str, str | None] = {}
    for spec in specs:
        target = root / spec
        if target.is_dir():
            for f in sorted(target.rglob("*")):
                if f.is_file() and ".git" not in f.relative_to(root).parts:
                    state[f.relative_to(root).as_posix()] = _digest(f)
        else:
            state[spec] = _digest(target)
    return state


def changed_since(root: Path, specs: Sequence[str], before: dict[str, str | None]) -> list[str]:
    after = snapshot(root, specs)
    return sorted(k for k in set(before) | set(after) if before.get(k) != after.get(k))


def run_gate(root: Path, command: str, pass_regex: str | None) -> tuple[bool, str]:
    done = subprocess.run(command, cwd=root, shell=True, text=True, stdout=subprocess.PIPE,
                          stderr=subprocess.STDOUT, check=False)
    out = done.stdout or ""
    ok = done.returncode == 0 and (pass_regex is None or re.search(pass_regex, out, re.MULTILINE) is not None)
    return ok, out


def build_message(path: Path, skip_reason: str | None) -> str:
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as error:
        raise Refusal(f"commit_unit: refused: cannot read the message file {path}: {error}", 2)
    if not text.strip():
        raise Refusal(f"commit_unit: refused: the message file {path} is empty", 2)
    text = text.rstrip() + "\n"
    if skip_reason:
        text += f"\ngate skipped: {skip_reason}\n"
    return text


def current_branch(root: Path) -> str:
    answer = git(root, "symbolic-ref", "--short", "-q", "HEAD")
    if answer.returncode != 0 or not answer.stdout.strip():
        raise Refusal("commit_unit: refused: HEAD is detached; check out a branch first", 2)
    return answer.stdout.strip()


def run(args: argparse.Namespace, cwd: Path) -> int:
    root = Path(args.root).resolve()
    top = git(root, "rev-parse", "--show-toplevel")
    if top.returncode != 0:
        raise Refusal(f"commit_unit: refused: {root} is not inside a git repository", 2)
    if Path(top.stdout.strip()).resolve() != root:
        raise Refusal(f"commit_unit: refused: --root must be the repository root ({top.stdout.strip()})", 2)
    if not args.paths:
        raise Refusal("commit_unit: refused: name at least one path after --", 2)
    if args.skip_gate and not (args.reason or "").strip():
        raise Refusal("commit_unit: refused: --skip-gate needs --reason", 2)
    if args.reason and not args.skip_gate:
        raise Refusal("commit_unit: refused: --reason only applies with --skip-gate", 2)
    if args.skip_gate and args.gate_cmd:
        raise Refusal("commit_unit: refused: --skip-gate and --gate-cmd are exclusive", 2)
    if not args.skip_gate and not args.gate_cmd and not args.dry_run:
        raise Refusal("commit_unit: refused: give --gate-cmd, or --skip-gate with --reason", 2)
    if args.gate_pass_regex:
        try:
            re.compile(args.gate_pass_regex)
        except re.error as error:
            raise Refusal(f"commit_unit: refused: bad --gate-pass-regex: {error}", 2)
    message = build_message(Path(args.message_file), args.reason if args.skip_gate else None)
    specs = resolve_paths(args.paths, root, args.allowed, cwd)
    to_add, left_alone = classify_paths(root, specs)
    branch = current_branch(root)

    before = snapshot(root, specs)
    if args.gate_cmd:
        ok, out = run_gate(root, args.gate_cmd, args.gate_pass_regex)
        if not ok:
            print(tail(out), file=sys.stderr)
            raise Refusal("commit_unit: refused: the gate did not pass; nothing was committed", 1)
        print("commit_unit: gate passed")
    elif args.skip_gate:
        print(f"commit_unit: gate skipped ({args.reason})")
    if args.dry_run:
        print(f"commit_unit: dry run complete for {len(specs)} path(s); nothing added or committed")
        return 0

    def guard() -> None:
        moved = changed_since(root, specs, before)
        if moved:
            raise Refusal("\n".join(f"commit_unit: changed during the gate: {m}" for m in moved)
                          + "\ncommit_unit: nothing committed; rerun", 1)

    guard()
    if to_add:
        added = git(root, "add", "--", *to_add)
        if added.returncode != 0:
            raise Refusal(f"commit_unit: git add failed:\n{tail(added.stdout)}", 1)
    for spec in left_alone:
        print(f"commit_unit: {spec} is a staged deletion or rename; committed without git add")
    guard()
    # `git commit -- <paths>` records only those paths, so files another worker staged do not ride along.
    # The committed text (with any skip footer) goes through a temporary file; the operator's file is untouched.
    with tempfile.TemporaryDirectory() as scratch:
        msg_path = Path(scratch) / "message.txt"
        msg_path.write_text(message, encoding="utf-8")
        commit = git(root, "commit", "-q", "-F", str(msg_path), "--", *specs)
    if commit.returncode != 0:
        raise Refusal(f"commit_unit: git commit failed:\n{tail(commit.stdout)}", 1)
    head = git(root, "rev-parse", "--short", "HEAD").stdout.strip()
    if args.no_push:
        print(f"commit_unit: committed {head} on {branch}; not pushed")
        return 0
    pushed = git(root, "push", args.remote, branch)
    if pushed.returncode != 0:
        print(tail(pushed.stdout), file=sys.stderr)
        raise Refusal(f"commit_unit: committed {head} on {branch}; push to {args.remote} FAILED, commit kept "
                      "local (fetch and rebase by hand if it was non-fast-forward, then push)", 1)
    print(f"commit_unit: committed {head} on {branch}; pushed to {args.remote}")
    return 0


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        description="Commit and push one work unit, limited to the named paths, refusing unless the gate "
                    "passes. Paths follow a bare --.")
    p.add_argument("--root", required=True, help="the git repository root")
    p.add_argument("--allowed", action="append", default=[], metavar="PATH",
                   help="path (relative to root) the named paths must lie under; repeatable")
    p.add_argument("-F", "--message-file", required=True, help="commit message file (must exist)")
    p.add_argument("--gate-cmd", help="gate command run through the shell from the root; exit 0 is a pass")
    p.add_argument("--gate-pass-regex", help="regex the gate output must also match")
    p.add_argument("--skip-gate", action="store_true", help="skip the gate; needs --reason")
    p.add_argument("--reason", help="why the gate is skipped; written into the commit message")
    p.add_argument("--no-push", action="store_true", help="commit only")
    p.add_argument("--dry-run", action="store_true", help="check arguments and run the gate, then stop")
    p.add_argument("--remote", default="origin", help="remote to push to (default origin)")
    p.add_argument("paths", nargs="*", help="files or folders to commit, after --")
    return p


def main(argv: Sequence[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        return run(args, Path.cwd())
    except Refusal as refusal:
        print(str(refusal), file=sys.stderr)
        return refusal.code
    except RuntimeError as error:
        print(str(error), file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
