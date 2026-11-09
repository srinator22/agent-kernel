"""preferences.py - validates the preference registers in docs/preferences/.

Purpose: keep every durable owner preference traceable (a dated source) and
guarded (Review, or a named check that exists).
Inputs: --root REPO. Reads docs/preferences/*.md, the file list from
`git ls-files`, and the referenced files.
Outputs: "preferences: ok (...)" and exit 0, or one "file:line: problem" per
failure on stderr and exit 1.
Writer: write_rows(root, area, adds, revises, removes, floor) is the one function
that adds, revises and removes rows (taste apply and port call it); port(...)
copies rows from another project. Rows go after the last data row of the file's
first rules table (a rules table is added before any baselines table; a new
file gets a title, a purpose line and the rules header). A pipe in a cell is
written with an escaped pipe, and a newline is refused. The ID prefix is the one most rows in
the file use, else the area upper-cased without punctuation; numbers have 3
digits, are above the file's highest number and the caller's floor (the floor
is what keeps a removed top number from coming back). An add whose folded text (case, whitespace)
exists in any register file, or earlier in the call, is skipped. A revise
replaces the Rule and appends "; date: "words"" to Source. Line endings are
kept, template mode refuses, and the result must pass the register check.
CLI: `write-rows --root R --area A --json FILE [--floor N]` (JSON {adds,
revises, removes}; prints the result as JSON) and `port --from PATH
[--area A]... [--id ID]... [--apply]`.
Dependencies: Python 3.11 standard library, git on PATH.
Assumptions: rules tables start `| ID | Rule | Source | Check |` (an optional
`Repeats` column); baseline tables start `| Kind | Reference | Owns | Check |`.
Header cells may carry extra words after the name (`Source (date, words)`).
Fenced code blocks are skipped. In template mode (no .start-done) only
README.md is allowed, so the owner's words never reach the public template.
"""

import argparse
import json
import os
import re
import subprocess
import sys
from datetime import date
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
        if kind == "rules-extra":
            self.rules += 1
            self.err(rel, lineno, "%s: the table header has columns other than ID, Rule, Source, Check "
                     "and an optional Repeats" % (cells[0] if cells and cells[0] else "(no ID)"))
            return
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


class PrefError(Exception):
    """A refusal the caller shows to the owner as is (exit 1 in the CLI)."""


AREA_RE = re.compile(r"[A-Za-z0-9][A-Za-z0-9_-]*")
ID_RE = re.compile(r"(.+)-(\d+)")
RULES_HEAD = "| ID | Rule | Source | Check | Repeats |"
RULES_SEP = "|---|---|---|---|---|"


def fold(text):
    """Duplicate key: case and whitespace folded, an escaped pipe read as a pipe."""
    return " ".join(text.replace("\\|", "|").lower().split())


def _cell(text, what):
    """Cell text ready to write: a newline would split the row, the writer escapes a pipe."""
    if not isinstance(text, str):
        raise PrefError("%s must be text" % what)
    if "\n" in text or "\r" in text:
        raise PrefError("%s holds a newline; a register cell is one line" % what)
    return text.strip()


def _row_line(cells, ncols):
    cells = list(cells) + [""] * (ncols - len(cells))
    return "| " + " | ".join(c.replace("|", "\\|") for c in cells[:ncols]) + " |"


def _scan(lines):
    """(rules tables, baseline header lines, data rows) of a register's lines.
    A table is {head, end, ncols}: the header's line index, the last line index
    of its contiguous run of table lines and its column count. Rows are
    {idx, cells, table}."""
    tables, bases, rows = [], [], []
    fence, cur, kind = False, None, None
    for i, ln in enumerate(lines):
        if ln.lstrip().startswith(("```", "~~~")):
            fence, cur, kind = not fence, None, None
            continue
        if fence:
            continue
        if not ln.lstrip().startswith("|"):
            cur, kind = None, None
            continue
        cells = D.table_cells(ln)
        head = D.register_table_kind(cells)
        if head:
            kind = head
            if head == "baselines":
                bases.append(i)
                cur = None
            else:
                cur = {"head": i, "end": i, "ncols": len(cells)}
                tables.append(cur)
            continue
        if cur is not None:
            cur["end"] = i
        if kind in ("rules", "rules-extra") and cells and not all(set(x) <= set(":- ") for x in cells):
            rows.append({"idx": i, "cells": cells, "table": cur})
    return tables, bases, rows


def _id_parts(rid):
    m = ID_RE.fullmatch(rid)
    return (m.group(1), int(m.group(2))) if m else (None, None)


def _existing_folded(root):
    """{folded rule text: 'area:ID'} over every register file of the project."""
    return {fold(text): key for key, text in D.register_rules(str(root)) if fold(text)}


def _area_title(area):
    return " ".join(w[:1].upper() + w[1:] for w in re.split(r"[-_]+", area) if w)


def _new_text(area):
    return "# %s\n\nThe owner's lasting preferences for %s.\n" % (
        _area_title(area), " ".join(w for w in re.split(r"[-_]+", area) if w).lower())


def _validate(root, path):
    ck = Checker(root)
    ck.check_file(path)
    return ck.errors


def write_rows(root, area, adds, revises, removes, floor, warn=None):
    """Add, revise and remove rows of docs/preferences/<area>.md; the one writer
    the taste pass and port both call.

    adds:    [{"rule": str, "source": str, "check": str (default "Review"),
               "repeats": str (default "")}]
    revises: [{"id": "FILM-001", "rule": str, "words": str, "date": "YYYY-MM-DD"}]
    removes: [{"id": "FILM-001"}]
    floor:   int; new numbers are above it and above the file's highest number
             for the prefix (the taste pass passes its ledger's high-water mark,
             port passes 0); a removed top number comes back unless the
             floor covers it.
    warn:    callable(str) for warnings; default prints "warning: ..." on stderr.

    Returns {"added": [ids], "skipped": [{"rule", "existing"}], "revised": [ids],
    "removed": [ids], "warnings": [str]}. An add whose folded rule text exists in
    any register file of the project, or earlier in the same call, is skipped
    ("existing" is "area:ID" or "this call"). Raises PrefError, writing nothing,
    in template mode, on a bad area, a newline in a cell, an unknown ID, or when
    the result fails the register check. The file's line endings are kept."""
    root = Path(root).resolve()
    if not (root / ".start-done").exists():
        raise PrefError("template mode (no .start-done): preference rows are written only in a started project")
    if not isinstance(area, str) or not AREA_RE.fullmatch(area) or area.lower() == "readme":
        raise PrefError("area must be letters, digits, - or _ and not README: %r" % (area,))
    if not isinstance(floor, int) or isinstance(floor, bool) or floor < 0:
        raise PrefError("floor must be a whole number, got %r" % (floor,))
    warnings = []
    emit = warn if warn is not None else (lambda m: print("warning: " + m, file=sys.stderr))

    path = root / "docs" / "preferences" / (area + ".md")
    original = path.read_bytes().decode("utf-8") if path.exists() else None
    if original is None and (revises or removes):
        raise PrefError("docs/preferences/%s.md does not exist, so there is no row to revise or remove" % area)
    crlf = original is not None and "\r\n" in original
    text = _new_text(area) if original is None else original.replace("\r\n", "\n")
    lines = text.split("\n")
    if lines and lines[-1] == "":
        lines.pop()

    # Validate every cell before touching anything, so a refusal writes nothing.
    new_adds = []
    for a in adds:
        rule = _cell(a.get("rule", ""), "a rule")
        if not rule:
            raise PrefError("an add has an empty rule")
        new_adds.append((rule, _cell(a.get("source", ""), "a Source"),
                         _cell(a.get("check") or "Review", "a Check"), _cell(a.get("repeats") or "", "Repeats")))
    new_revs = []
    for r in revises:
        rule = _cell(r.get("rule", ""), "a rule")
        words = _cell(r.get("words", ""), "owner words")
        date = _cell(r.get("date", ""), "a date")
        if not rule or not words or not DATE_RE.fullmatch(date):
            raise PrefError("a revise of %s needs a rule, the owner's words and a YYYY-MM-DD date" % r.get("id"))
        new_revs.append((r.get("id"), rule, words, date))

    tables, bases, rows = _scan(lines)
    by_id = {r["cells"][0]: r for r in rows if r["cells"] and r["cells"][0]}
    for rid in [x[0] for x in new_revs] + [x.get("id") for x in removes]:
        if rid not in by_id:
            raise PrefError("no row %s in docs/preferences/%s.md" % (rid, area))

    prefixes, top = {}, {}
    for rid in by_id:
        p, n = _id_parts(rid)
        if p is not None:
            prefixes[p] = prefixes.get(p, 0) + 1
            top[p] = max(top.get(p, 0), n)
    if prefixes:
        prefix = max(prefixes, key=lambda p: prefixes[p])  # ties: first seen
    else:
        prefix = re.sub(r"[^A-Za-z0-9]", "", area).upper()
    number = max(top.get(prefix, 0), floor)

    def tell(rid, row):
        check = row["cells"][3] if len(row["cells"]) > 3 else ""
        refs = TICK_RE.findall(check) if not re.match(r"Review\b", check) else []
        if refs:
            msg = "%s in %s.md is guarded by %s; update that check too" % (rid, area, ", ".join(refs))
            warnings.append(msg)
            emit(msg)

    revised, removed = [], []
    gone = set()
    for rid, rule, words, date in new_revs:
        row = by_id[rid]
        tell(rid, row)
        cells = list(row["cells"])
        cells[1] = rule.replace("\\|", "|")
        cells[2] = "%s; %s: \"%s\"" % (cells[2], date, words.replace("\\|", "|"))
        lines[row["idx"]] = _row_line(cells, row["table"]["ncols"] if row["table"] else len(cells))
        revised.append(rid)
    drop = set()
    for rm in removes:
        row = by_id[rm["id"]]
        tell(rm["id"], row)
        drop.add(row["idx"])
        gone.add(rm["id"])
        removed.append(rm["id"])
    if drop:
        lines = [ln for i, ln in enumerate(lines) if i not in drop]

    # Duplicate texts live in any register file; rows this call revises or
    # removes no longer hold their old text.
    seen = _existing_folded(root)
    me = {"%s:%s" % (area, rid) for rid in list(gone) + revised}
    seen = {k: v for k, v in seen.items() if v not in me}
    for rid, rule, _, _ in new_revs:
        seen[fold(rule)] = "%s:%s" % (area, rid)

    added, skipped, fresh = [], [], []
    for rule, source, check, repeats in new_adds:
        key = fold(rule)
        if key in seen:
            skipped.append({"rule": rule.replace("\\|", "|"), "existing": seen[key]})
            continue
        number += 1
        rid = "%s-%03d" % (prefix, number)
        seen[key] = "this call"
        added.append(rid)
        fresh.append((rid, rule, source, check, repeats))

    if fresh:
        tables, bases, rows = _scan(lines)
        if tables:
            t = tables[0]
            ncols = t["ncols"]
            at = t["end"] + 1
            block = [_row_line([rid, rule, source, check, repeats], ncols) for rid, rule, source, check, repeats in fresh]
            lines[at:at] = block
        else:
            block = [RULES_HEAD, RULES_SEP] + [_row_line(list(f), 5) for f in fresh]
            if bases:
                at = bases[0]
                prev = at - 1
                while prev >= 0 and not lines[prev].strip():
                    prev -= 1
                if prev >= 0 and lines[prev].lstrip().startswith("#"):
                    at = prev
                block = block + [""]
                if at > 0 and lines[at - 1].strip():
                    block = [""] + block
            else:
                at = len(lines)
                if at and lines[-1].strip():
                    block = [""] + block
            lines[at:at] = block

    result = {"added": added, "skipped": skipped, "revised": revised, "removed": removed, "warnings": warnings}
    if not (fresh or revised or removed):
        return result
    out = "\n".join(lines) + "\n"
    if crlf:
        out = out.replace("\n", "\r\n")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(out.encode("utf-8"))
    errors = _validate(root, path)
    if errors:
        if original is None:
            path.unlink()
        else:
            path.write_bytes(original.encode("utf-8"))
        raise PrefError("the result fails the register check, nothing was written:\n" + "\n".join(errors))
    return result


def port(root, src, areas, ids, apply, today=None, out=print):
    """Copy rules rows from another project's registers (the owner asked for it).

    Lists each row that would be copied and each skipped as a duplicate; with
    apply, writes them through write_rows (floor 0). Source becomes
    "<today>: ported from <folder> (<original source>)", Check "Review (was
    <original check> in <folder>)" or plain "Review" when it was Review,
    Repeats empty. Baselines are never copied. Raises PrefError on template
    mode, this project's own root, or a path with no registers. Returns the
    number of rows copied (apply) or listed (dry run)."""
    root = Path(root).resolve()
    if not (root / ".start-done").exists():
        raise PrefError("template mode (no .start-done): port writes only in a started project")
    src = Path(src).resolve()
    if src == root:
        raise PrefError("--from is this project's own root; name another project")
    sdir = src / "docs" / "preferences"
    files = sorted(p for p in sdir.glob("*.md") if p.name != "README.md") if sdir.is_dir() else []
    if not files:
        raise PrefError("no registers in %s (docs/preferences/<area>.md); nothing to port" % src)
    folder = src.name
    today = today or date.today().isoformat()
    seen = _existing_folded(root)
    plan, copied = {}, 0
    for f in files:
        area = f.stem
        if areas and area not in areas:
            continue
        for _, kind, cells in D.register_rows(f.read_text(encoding="utf-8", errors="replace")):
            if kind not in ("rules", "rules-extra") or len(cells) < 4 or not cells[0] or not cells[1]:
                continue
            if ids and cells[0] not in ids:
                continue
            key = fold(cells[1])
            if key in seen:
                out("skip (duplicate of %s)  %s %s  %s" % (seen[key], area, cells[0], cells[1]))
                continue
            seen[key] = "this port"
            orig = cells[3]
            check = "Review" if re.match(r"Review\b", orig) else "Review (was %s in %s)" % (orig, folder)
            plan.setdefault(area, []).append({
                "rule": cells[1],
                "source": "%s: ported from %s (%s)" % (today, folder, cells[2]),
                "check": check,
                "_id": cells[0],
            })
            out("%s %s %s  %s" % ("copy" if apply else "would copy", area, cells[0], cells[1]))
            copied += 1
    if apply:
        for area, adds in plan.items():
            res = write_rows(root, area, [{k: v for k, v in a.items() if k != "_id"} for a in adds], [], [], 0)
            for a, rid in zip(adds, res["added"]):
                out("wrote %s:%s from %s" % (area, rid, a["_id"]))
    return copied


def cli_write_rows(argv):
    """Hidden entry for write_rows: write-rows --root R --area A --json FILE [--floor N]."""
    ap = argparse.ArgumentParser(prog="preferences.py write-rows")
    ap.add_argument("--root", default=".")
    ap.add_argument("--area", required=True)
    ap.add_argument("--floor", type=int, default=0)
    ap.add_argument("--json", required=True, help="file holding {adds, revises, removes}")
    args = ap.parse_args(argv)
    try:
        spec = json.loads(Path(args.json).read_text(encoding="utf-8"))
        res = write_rows(args.root, args.area, spec.get("adds", []), spec.get("revises", []),
                         spec.get("removes", []), args.floor)
    except (OSError, ValueError) as e:
        print("preferences: %s" % e, file=sys.stderr)
        return 1
    except PrefError as e:
        print("preferences: %s" % e, file=sys.stderr)
        return 1
    print(json.dumps(res))
    return 0


def cli_port(argv):
    ap = argparse.ArgumentParser(prog="preferences.sh port")
    ap.add_argument("--root", default=".")
    ap.add_argument("--from", dest="src", required=True)
    ap.add_argument("--area", action="append", default=[])
    ap.add_argument("--id", action="append", default=[], dest="ids")
    ap.add_argument("--apply", action="store_true")
    args = ap.parse_args(argv)
    if args.ids and not args.area:
        ap.error("--id needs --area")
    try:
        n = port(args.root, args.src, args.area, args.ids, args.apply)
    except PrefError as e:
        print("preferences: %s" % e, file=sys.stderr)
        return 1
    print("preferences: %d row(s) %s%s" % (n, "ported" if args.apply else "would be ported", "" if args.apply else " (dry run; add --apply to write)"))
    return 0


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    if argv and argv[0] == "write-rows":
        return cli_write_rows(argv[1:])
    if argv and argv[0] == "port":
        return cli_port(argv[1:])
    ap = argparse.ArgumentParser(description="Check docs/preferences registers")
    ap.add_argument("--root", default=".")
    args = ap.parse_args(argv)
    root = Path(args.root).resolve()
    pdir = root / "docs" / "preferences"
    files = sorted(pdir.glob("*.md")) if pdir.is_dir() else []
    others = sorted(p for p in pdir.rglob("*") if p.is_file() and p != pdir / "README.md") if pdir.is_dir() else []
    template_mode = not (root / ".start-done").exists()
    if template_mode and others:
        ck = Checker(root)
        for f in others:
            ck.err(f.relative_to(root).as_posix(), 1, "template mode (no .start-done): only README.md may live in docs/preferences, so the owner's words stay out of the template")
    elif not any(f.name != "README.md" for f in files):
        print("preferences: no registers")
        return 0
    else:
        ck = Checker(root)
        for f in files:
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
