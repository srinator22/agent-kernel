"""papercut.py - file and list papercuts: small reports of friction an agent
hit while working (a flag the help lists and the tool rejects, an exit 0 on an
error, a doc that names a missing file, a guard that refused a command).

Purpose: scripts/papercut.sh runs this. "add" appends one JSON line to <main
checkout>/.work/papercuts/log.jsonl; "list" prints the log grouped. The log is
evidence for the dream digest and the retro, never a rule or a lesson.
Inputs: add --tool --tried --expected --got --fix (each 1 to 300 characters,
stored exactly as given) and --refusal correct|wrong|none (correct: a guard
refused and was right, so the entry is not a defect; wrong: the refusal was the
defect; none: no refusal involved). PAPERCUT_NOW (ISO time) replaces the clock.
Outputs: one log line with keys v, ts (UTC), tool, tried, expected, got, fix,
refusal and nothing else; the folder holds a .gitignore of "*". Past 200
entries the oldest lines are dropped and one stderr line says how many. list
prints defect groups (same tool, same "got" after whitespace normalization)
newest first, then correct refusals in their own section, then the count of
malformed lines skipped.
Dependencies: Python 3 standard library, git (main checkout), dream.py beside
this file (the folder, the limits, the reader and the grouping, shared with the
digest; dream.py never imports this).
Assumptions: one agent files at a time (each add rewrites the log through a
replace, so a reader never sees half a line). Exit codes: 0 ok; 2 a missing, empty, repeated, unknown,
too long or invalid argument, with nothing written.
"""
import datetime as dt
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
import dream as D  # noqa: E402  (shared helpers; the folder is not on sys.path under -I)

FLAGS = D.PAPERCUT_TEXT + ("refusal",)
USAGE = """usage: scripts/papercut.sh add --tool NAME --tried TEXT --expected TEXT --got TEXT --fix TEXT --refusal correct|wrong|none
       scripts/papercut.sh list
File a papercut the moment a tool, doc or guard gets in your way.
  --tool      the script, command or doc at fault
  --tried     what you ran or looked for
  --expected  what should have happened
  --got       what happened (the same wording groups repeats)
  --fix       the change you suggest
  --refusal   correct: a guard refused and was right (not a defect);
              wrong: the refusal was the defect; none: no refusal was involved
Each text is 1 to %d characters; a longer one is refused, never cut.
Privacy: describe in your own words. Write no prompt text, no file contents, no secrets, no private names.
Only these fields and a UTC time are stored, in .work/papercuts/log.jsonl (local, git-ignored, newest %d kept).
Reports are evidence for the dream and the retro; only the owner turns one into a rule or a lesson.
""" % (D.PAPERCUT_FIELD, D.PAPERCUT_CAP)


def out(text, stream=None):
    # Bytes as UTF-8: a text-mode stream uses the locale encoding, which cannot
    # print every character an entry may hold.
    stream = stream or sys.stdout
    stream.flush()
    stream.buffer.write((text + "\n").encode("utf-8", "backslashreplace"))
    stream.buffer.flush()


def fail(msg):
    out("papercut: " + msg, sys.stderr)
    return 2


def parse_add(argv):
    """The six fields from argv, or a message. A flag takes the next argument
    as its value whatever it looks like, so a value may start with "--"."""
    vals, i = {}, 0
    while i < len(argv):
        name = argv[i][2:] if argv[i].startswith("--") else ""
        if name not in FLAGS:
            return None, 'unknown argument "%s" (run scripts/papercut.sh help)' % argv[i]
        if name in vals:
            return None, "--%s given twice" % name
        if i + 1 >= len(argv):
            return None, "--%s needs a value" % name
        vals[name] = argv[i + 1]
        i += 2
    for name in FLAGS:
        v = vals.get(name)
        if v is None:
            return None, "--%s is required (run scripts/papercut.sh help)" % name
        if not v.strip():
            return None, "--%s is empty; give a short text" % name
        try:
            v.encode("utf-8")
        except UnicodeEncodeError:
            return None, "--%s is not valid UTF-8 text" % name
        if len(v) > D.PAPERCUT_FIELD:
            return None, ("--%s is %d characters; the limit is %d. Shorten it yourself: nothing was "
                          "written and nothing is cut" % (name, len(v), D.PAPERCUT_FIELD))
    if vals["refusal"] not in D.PAPERCUT_REFUSALS:
        return None, '--refusal must be correct, wrong or none (got "%s")' % vals["refusal"]
    return vals, None


def cmd_add(folder, argv):
    vals, err = parse_add(argv)
    if err:
        return fail(err)
    now = os.environ.get("PAPERCUT_NOW")
    when = D.parse_iso(now) if now else dt.datetime.now(dt.timezone.utc)
    if when is None:
        return fail("PAPERCUT_NOW is not an ISO time: " + now)
    entry = {"v": 1, "ts": D.iso(when.astimezone(dt.timezone.utc))}
    entry.update((k, vals[k]) for k in FLAGS)
    line = json.dumps(entry, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    D.ensure_dir(folder)
    path = os.path.join(folder, "log.jsonl")
    try:
        with open(path, "rb") as f:
            old = [ln for ln in f.read().split(b"\n") if ln.strip()]
    except OSError:
        old = []
    dropped = max(0, len(old) + 1 - D.PAPERCUT_CAP)
    kept = old[dropped:] + [line]
    tmp = path + ".tmp"
    with open(tmp, "wb") as f:
        f.write(b"\n".join(kept) + b"\n")
    os.replace(tmp, path)
    if dropped:
        out("papercut: log is capped at %d entries; dropped the %d oldest" % (D.PAPERCUT_CAP, dropped), sys.stderr)
    out("papercut: filed (%d entries in %s)" % (len(kept), path))
    return 0


def cmd_list(folder):
    got = D.read_papercuts(os.path.join(folder, "log.jsonl"))
    if got is None or not got[1]:
        out("papercuts: none")
        return 0
    entries, _, bad = got
    groups, right, n_rest, n_right = D.papercut_groups(entries)
    lines = ["papercuts: %d entries in %d groups; correct refusals: %d entries in %d groups; "
             "malformed lines skipped: %d" % (n_rest, len(groups), n_right, len(right), bad)]
    if groups:
        lines.append("## Defect candidates (newest first)")
    for g in groups:
        lines += D.papercut_lines(g)
    if right:
        lines.append("## Correct refusals (not defects)")
    for g in right:
        lines += D.papercut_lines(g, detail=False)
    out("\n".join(lines))
    return 0


def main():
    argv = sys.argv[1:]
    cmd = argv[0] if argv else ""
    if cmd in ("help", "-h", "--help"):
        out(USAGE.rstrip("\n"))
        return 0
    root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.realpath(__file__))))
    if cmd == "add":
        return cmd_add(D.papercut_dir(root), argv[1:])
    if cmd == "list" and len(argv) == 1:
        return cmd_list(D.papercut_dir(root))
    out(USAGE.rstrip("\n"), sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
