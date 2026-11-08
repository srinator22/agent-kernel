"""preferences.py - validates the preference registers in docs/preferences/.

Purpose: keep every durable owner preference traceable (a dated source) and
guarded (Review, or a named check that exists).
Inputs: --root REPO. Reads docs/preferences/*.md, the file list from
`git ls-files`, and the referenced files.
Outputs: "preferences: ok (...)" and exit 0, or one "file:line: problem" per
failure on stderr and exit 1.
Dependencies: Python 3.11 standard library, git on PATH.
Assumptions: rules tables start `| ID | Rule | Source | Check |` (an optional
`Repeats` column); baseline tables start `| Kind | Reference | Owns | Check |`.
Header cells may carry extra words after the name (`Source (date, words)`).
Fenced code blocks are skipped. In template mode (no .start-done) only
README.md is allowed, so the owner's words never reach the public template.
"""

import argparse
import os
import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
import dream as D  # noqa: E402  (shared table reader; the folder is not on sys.path under -I)

DATE_RE = re.compile(r"(?<!\d)\d{4}-(?:0[1-9]|1[0-2])(?:-(?:0[1-9]|[12]\d|3[01]))?(?!\d)")
TICK_RE = re.compile(r"`([^`]+)`")




class Checker:
    def __init__(self, root):
        self.root = root
        self.errors = []
        self.tracked = self._tracked()
        self.rules = 0
        self.baselines = 0

    def _tracked(self):
        try:
            out = subprocess.run(
                ["git", "-C", str(self.root), "ls-files"],
                capture_output=True,
                text=True,
                check=True,
            ).stdout
        except (OSError, subprocess.CalledProcessError):
            return []
        return [ln.strip() for ln in out.splitlines() if ln.strip()]

    def err(self, rel, lineno, problem):
        self.errors.append(f"{rel}:{lineno}: {problem}")

    def resolve_path(self, token):
        """Repo-relative path, or a bare file name found exactly once. Returns (Path|None, problem)."""
        if not token:
            return None, "empty path"
        cand = (self.root / token).resolve()
        try:
            cand.relative_to(self.root.resolve())
            if cand.exists():
                return cand, ""
        except ValueError:
            return None, f"path outside the repository: {token}"
        if "/" not in token:
            hits = [t for t in self.tracked if t.rsplit("/", 1)[-1] == token]
            if len(hits) == 1:
                return self.root / hits[0], ""
            if len(hits) > 1:
                return None, f"file name {token} is ambiguous ({len(hits)} tracked files); use a path"
        return None, f"unknown path: {token}"

    def check_ref(self, rel, lineno, label, ref):
        parts = ref.split()
        if not parts:
            self.err(rel, lineno, f"{label}: empty reference in backticks")
            return
        head = parts[0]
        path, _, name = head.partition("::")
        found, problem = self.resolve_path(path)
        if found is None:
            self.err(rel, lineno, f"{label}: {problem}")
            return
        if "::" in head:
            if not name:
                self.err(rel, lineno, f"{label}: empty ::name in {head}")
            elif found.is_dir():
                self.err(rel, lineno, f"{label}: ::{name} needs a file, {path} is a folder")
            else:
                text = found.read_text(encoding="utf-8", errors="replace")
                if not re.search(r"(?<![A-Za-z0-9_])" + re.escape(name) + r"(?![A-Za-z0-9_])", text):
                    self.err(rel, lineno, f"{label}: {name} not found in {path}")

    def check_check_cell(self, rel, lineno, label, cell):
        if re.match(r"Review\b", cell):
            return
        refs = TICK_RE.findall(cell)
        if not refs:
            self.err(rel, lineno, f"{label}: Check must be Review or a backticked reference, got: {cell or '(empty)'}")
            return
        for ref in refs:
            self.check_ref(rel, lineno, label, ref)

    def check_baseline_ref(self, rel, lineno, label, cell):
        if not DATE_RE.search(cell):
            self.err(rel, lineno, f"{label}: Reference needs a date (YYYY-MM or YYYY-MM-DD)")
        rest = DATE_RE.sub(" ", cell)
        ticks = TICK_RE.findall(rest)
        tokens = (ticks[0] if ticks else rest).split()
        if not tokens:
            self.err(rel, lineno, f"{label}: Reference names no path or commit")
            return
        tok = tokens[0].strip(",;:")
        found, _ = self.resolve_path(tok)
        if found is not None:
            return
        res = subprocess.run(
            ["git", "-C", str(self.root), "rev-parse", "--verify", "-q", f"{tok}^{{commit}}"],
            capture_output=True,
            text=True,
        )
        if res.returncode != 0:
            self.err(rel, lineno, f"{label}: Reference is neither an existing path nor a commit: {tok}")

    def check_file(self, path):
        rel = path.relative_to(self.root).as_posix()
        ids = set()
        for i, kind, cells in D.register_rows(path.read_text(encoding="utf-8", errors="replace")):
            self._row(rel, i, kind, cells, ids)

    def _row(self, rel, lineno, kind, cells, ids):
        if kind == "rules":
            self.rules += 1
            rid = cells[0] if cells else ""
            label = rid or "(no ID)"
            if len(cells) not in (4, 5):
                self.err(rel, lineno, f"{label}: row has {len(cells)} cells, expected 4 or 5")
                return
            if not rid:
                self.err(rel, lineno, "row has no ID")
            elif rid in ids:
                self.err(rel, lineno, f"{label}: duplicate ID in this file")
            ids.add(rid)
            if not cells[1]:
                self.err(rel, lineno, f"{label}: rule is empty")
            if not DATE_RE.search(cells[2]):
                self.err(rel, lineno, f"{label}: Source needs a date (YYYY-MM or YYYY-MM-DD)")
            self.check_check_cell(rel, lineno, label, cells[3])
            if len(cells) == 5 and cells[4] and not re.fullmatch(r"\d+", cells[4]):
                self.err(rel, lineno, f"{label}: Repeats must be an integer, got: {cells[4]}")
        else:
            self.baselines += 1
            label = cells[0] or "(no Kind)"
            if len(cells) != 4:
                self.err(rel, lineno, f"{label}: baseline row has {len(cells)} cells, expected 4")
                return
            if not cells[0]:
                self.err(rel, lineno, "baseline row has no Kind")
            if not cells[2]:
                self.err(rel, lineno, f"{label}: Owns is empty")
            self.check_baseline_ref(rel, lineno, label, cells[1])
            self.check_check_cell(rel, lineno, label, cells[3])


def main(argv=None):
    ap = argparse.ArgumentParser(description="Check docs/preferences registers")
    ap.add_argument("--root", default=".")
    args = ap.parse_args(argv)
    root = Path(args.root).resolve()
    pdir = root / "docs" / "preferences"
    files = sorted(pdir.glob("*.md")) if pdir.is_dir() else []
    if not any(f.name != "README.md" for f in files):
        print("preferences: no registers")
        return 0
    template_mode = not (root / ".start-done").exists()
    ck = Checker(root)
    for f in files:
        rel = f.relative_to(root).as_posix()
        if template_mode and f.name != "README.md":
            ck.err(rel, 1, "template mode (no .start-done): only README.md may live in docs/preferences, so the owner's words stay out of the template")
            continue
        ck.check_file(f)
    if ck.errors:
        for e in ck.errors:
            print(e, file=sys.stderr)
        print(f"preferences: FAILED ({len(ck.errors)} problem(s))", file=sys.stderr)
        return 1
    print(f"preferences: ok ({len(files)} file(s), {ck.rules} rule(s), {ck.baselines} baseline(s))")
    return 0


if __name__ == "__main__":
    sys.exit(main())
