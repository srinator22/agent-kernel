"""dream.py - reduce Claude Code transcripts to a small signal digest for a dream.

Purpose: an offline, model-free pass over this repository's session transcripts.
It keeps only user-visible signal (corrections, messages, interrupts, denials,
hook blocks, failed tool calls), reads each transcript line once ever, and
reports memory-file hygiene. A model reads only the resulting digest.

Inputs: JSONL transcripts at <projects>/<dir>/<session>.jsonl (top level only;
subagent transcripts are not read). A line belongs to this repository when its
cwd equals a root or sits under it; roots are the repository, its git
worktrees, roots remembered in state, and --match paths. Environment overrides:
DREAM_PROJECTS_DIR (projects folder), DREAM_NOW (ISO time used as "now").
Outputs: <state-dir>/digest.md, <state-dir>/state.next.json (proposed offsets).
No tracked file is ever edited. The default state folder is the main
worktree's .work/dream (shared by all linked worktrees); it holds a .gitignore
of "*" so it never shows in git status. --max-bytes must be at least 2000.
State: <state-dir>/state.json {version, files{path: {offset, m}}, known_roots,
last_dream}; <state-dir>/offered holds the day:retro-count fingerprint of the
last offer. "done" commits state.next.json, so an unfinished dream loses nothing.
The per-file flag m marks transcripts that ever held lines for this repository,
so activity in unrelated projects never makes a dream due. Unseen transcripts
count for "due" only in folders named exactly after a root (the repository, a
git worktree, a saved root) or under <slug(root)>--claude-worktrees-; sibling
names such as Foo-bar for Foo never match.
Exit codes: 0 ok (due: due); 1 not due; 2 usage error or ordering error;
3 digest found no new signal. Dependencies: Python 3 standard library, git
(optional, for worktrees). Assumption: a transcript line is complete only when
it ends in a newline; a partial last line is left for the next run. Malformed
lines are counted only among lines that pass the raw path prefilter.
"""
import argparse
import datetime as dt
import glob
import json
import os
import re
import subprocess
import sys

EPOCH = dt.datetime(1970, 1, 1, tzinfo=dt.timezone.utc)
MSG_LIMIT = 400
ERR_LIMIT = 300
MIN_BYTES = 2000
CORRECTION = re.compile(
    r"^(no|nope|don't|dont|do not|stop|wrong|that's not|thats not|not what|"
    r"why did|undo|revert|actually|instead|you didn't|you did not)\b", re.I)
DENIED = ("permission for this action was denied", "doesn't want to proceed",
          "was rejected", "denied by")
HOOK = ("hook error", "blocked by")
PRIORITY = {"C": 0, "D": 0, "H": 0, "I": 0, "E": 1, "U": 2, "M": 2}
HYGIENE_FILES = ["AGENTS.md", "BACKLOG.md", "docs/DEFECT_MEMORY.md",
                 "docs/lessons/INDEX.md", "docs/lessons/PENDING.md",
                 "docs/lessons/UPSTREAM.md", "docs/lessons/QUARANTINE.md"]


def die(msg, code=2):
    print(msg, file=sys.stderr)
    sys.exit(code)


def norm(p):
    return p.replace("\\", "/").lower().rstrip("/")


def slug(p):
    return re.sub(r"[^A-Za-z0-9]", "-", p)


def parse_iso(v):
    try:
        d = dt.datetime.fromisoformat(v.replace("Z", "+00:00"))
    except (ValueError, AttributeError):
        return None
    return d if d.tzinfo else d.replace(tzinfo=dt.timezone.utc)


def now_utc():
    v = os.environ.get("DREAM_NOW")
    if not v:
        return dt.datetime.now(dt.timezone.utc)
    d = parse_iso(v)
    if d is None:
        die("dream: DREAM_NOW is not an ISO time: " + v)
    return d


def iso(d):
    return d.strftime("%Y-%m-%dT%H:%M:%SZ")


class Ctx:
    def __init__(self, a):
        here = os.path.dirname(os.path.realpath(__file__))
        self.root = os.path.realpath(a.root) if a.root else os.path.dirname(here)
        self.projects = (a.projects_dir or os.environ.get("DREAM_PROJECTS_DIR")
                         or os.path.join(os.path.expanduser("~"), ".claude", "projects"))
        self.state_dir = a.state_dir or os.path.join(main_worktree(self.root), ".work", "dream")
        self.now = now_utc()
        self.state = self.load_state()

    def load_state(self):
        p = os.path.join(self.state_dir, "state.json")
        try:
            with open(p, encoding="utf-8") as f:
                s = json.load(f)
        except FileNotFoundError:
            s = {}
        except (ValueError, OSError) as e:
            die("dream: unreadable state file %s: %s" % (p, e))
        s.setdefault("version", 1)
        s.setdefault("files", {})
        s.setdefault("known_roots", [])
        s.setdefault("last_dream", None)
        return s

    def sp(self, name):
        return os.path.join(self.state_dir, name)

    def worktrees(self):
        try:
            r = subprocess.run(["git", "-C", self.root, "worktree", "list", "--porcelain"],
                               capture_output=True, text=True, timeout=10)
        except (OSError, subprocess.SubprocessError):
            return []
        if r.returncode != 0:
            return []
        return [norm(l[9:]) for l in r.stdout.splitlines() if l.startswith("worktree ")]

    def last(self):
        return parse_iso(self.state.get("last_dream") or "") or EPOCH


def ensure_dir(d):
    """Create the state folder and make it ignore itself, so the digest and
    state never show in git status whatever the project's .gitignore says."""
    os.makedirs(d, exist_ok=True)
    g = os.path.join(d, ".gitignore")
    if not os.path.exists(g):
        with open(g, "w", encoding="utf-8", newline="\n") as f:
            f.write("*\n")


def main_worktree(root):
    """The main worktree of root's repository, so every linked worktree shares
    one state folder; root itself outside git or when it cannot be resolved."""
    try:
        r = subprocess.run(["git", "-C", root, "rev-parse", "--path-format=absolute", "--git-common-dir"],
                           capture_output=True, text=True, timeout=10)
    except (OSError, subprocess.SubprocessError):
        return root
    out = r.stdout.strip()
    if r.returncode != 0 or not out:
        return root
    common = os.path.realpath(out)
    if os.path.basename(common) != ".git":
        return root
    return os.path.dirname(common)


def write_json(path, obj):
    ensure_dir(os.path.dirname(path))
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8", newline="\n") as f:
        json.dump(obj, f, indent=1, sort_keys=True)
        f.write("\n")
    os.replace(tmp, path)


def markers(roots):
    out = set()
    for r in roots:
        out.add(r.encode("utf-8"))
        out.add(r.replace("/", "\\\\").encode("utf-8"))
    return list(out)


def cwd_match(cwd, roots):
    c = norm(cwd if isinstance(cwd, str) else "")
    return any(c == r or c.startswith(r + "/") for r in roots)


def clean(text, limit):
    t = " ".join(text.split())
    return t[:limit] + "..." if len(t) > limit else t


def texts(content):
    if isinstance(content, str):
        return [content]
    if isinstance(content, list):
        return [i["text"] for i in content
                if isinstance(i, dict) and i.get("type") == "text" and isinstance(i.get("text"), str)]
    return []


def is_correction(s):
    return CORRECTION.match(s.strip().replace("\u2019", "'")) is not None


def extract(obj):
    """Yield (kind, text) signals from one parsed transcript line."""
    t = obj.get("type")
    if t == "user":
        msg = obj.get("message")
        content = msg.get("content") if isinstance(msg, dict) else None
        for s in texts(content):
            s = s.strip()
            if not s or s.startswith("<"):
                continue
            if s.startswith("[Request interrupted by user"):
                yield "I", clean(s, MSG_LIMIT)
            elif is_correction(s):
                yield "C", clean(s, MSG_LIMIT)
            else:
                yield "U", clean(s, MSG_LIMIT)
        if isinstance(content, list):
            for i in content:
                if isinstance(i, dict) and i.get("type") == "tool_result" and i.get("is_error"):
                    s = " ".join(texts(i.get("content")))
                    low = s.lower()
                    if any(k in low for k in DENIED):
                        k = "D"
                    elif any(k in low for k in HOOK):
                        k = "H"
                    else:
                        k = "E"
                    yield k, clean(s, ERR_LIMIT)
    elif t == "attachment":
        att = obj.get("attachment")
        if isinstance(att, dict) and att.get("type") == "queued_command":
            p = att.get("prompt")
            if isinstance(p, str) and p.strip() and not p.strip().startswith("<"):
                yield ("C" if is_correction(p) else "M"), clean(p, MSG_LIMIT)


def count_lines(b):
    return b.count(b"\n") + (1 if b and not b.endswith(b"\n") else 0)


def hygiene_text(c, memory_dir=None):
    out = []
    for rel in HYGIENE_FILES:
        p = os.path.join(c.root, rel)
        if os.path.isfile(p):
            with open(p, "rb") as f:
                b = f.read()
            out.append("%s: %d lines, %d bytes" % (rel, count_lines(b), len(b)))
        else:
            out.append("%s: missing" % rel)

    def read(path):
        try:
            with open(path, encoding="utf-8", errors="replace") as f:
                return f.read()
        except OSError:
            return ""

    idx = read(os.path.join(c.root, "docs", "lessons", "INDEX.md")).splitlines()
    # Count lessons the way scripts/lessons.sh does: skip fenced examples and
    # the documented format line, whose text starts with a "<...>" placeholder.
    appr, fence = [], False
    for l in idx:
        if l.startswith("```"):
            fence = not fence
            continue
        m = re.match(r"- \[L\d+\] (.*)", l)
        if not fence and m and not m.group(1).startswith("<"):
            appr.append(l)
    unused = [l for l in appr if re.search(r"used:\s*0\b", l)]
    out.append("approved lessons: %d (%d with used: 0)" % (len(appr), len(unused)))

    pend = read(os.path.join(c.root, "docs", "lessons", "PENDING.md"))
    ages = []
    for e in re.split(r"(?m)^(?=### )", pend):
        if not e.startswith("### "):
            continue
        title = e.splitlines()[0][4:].strip()
        m = re.search(r"\d{4}-\d{2}-\d{2}", e)
        age = None
        if m:
            try:
                age = (c.now.date() - dt.date.fromisoformat(m.group(0))).days
            except ValueError:
                age = None
        ages.append((title, age))
    known = [a for _, a in ages if a is not None]
    line = "pending lessons: %d" % len(ages)
    if known:
        line += " (oldest %d days, %d older than 30 days)" % (max(known), sum(1 for a in known if a > 30))
    out.append(line)
    for title, age in ages:
        out.append("  - %s: %s" % (title, "undated" if age is None else "%d days" % age))

    mdir = memory_dir or os.path.join(c.projects, slug(c.root), "memory")
    mfiles = sorted(glob.glob(os.path.join(mdir, "*.md"))) if os.path.isdir(mdir) else []
    mm = os.path.join(mdir, "MEMORY.md")
    if mfiles:
        total = sum(os.path.getsize(f) for f in mfiles)
        extra = ""
        if os.path.isfile(mm):
            with open(mm, "rb") as f:
                extra = ", MEMORY.md %d lines" % count_lines(f.read())
        out.append("auto-memory: %d files, %d bytes%s" % (len(mfiles), total, extra))
    else:
        out.append("auto-memory: none found in %s" % mdir)

    names, dangling, bodies = set(), [], {}
    for f in mfiles:
        bodies[f] = read(f)
        fm = re.match(r"---\r?\n(.*?)\r?\n---", bodies[f], re.S)
        if fm:
            m = re.search(r"(?m)^name:\s*(.+?)\s*$", fm.group(1))
            if m:
                names.add(m.group(1).strip("'\""))
    for f, body in bodies.items():
        for t in re.findall(r"\[\[([^\]]+)\]\]", body):
            if t.strip() not in names:
                dangling.append("%s: [[%s]]" % (os.path.basename(f), t))
    linkfiles = [(p, "docs/lessons/" + os.path.basename(p))
                 for p in sorted(glob.glob(os.path.join(c.root, "docs", "lessons", "*.md")))]
    if mm in bodies:
        linkfiles.append((mm, "MEMORY.md"))
    for path, label in linkfiles:
        body = bodies[path] if path in bodies else read(path)
        for t in re.findall(r"\]\(([^)\s]+)\)", body):
            t = t.strip("<>")
            if re.match(r"(?i)(https?:|mailto:)", t) or t.startswith("#"):
                continue
            t = t.split("#", 1)[0]
            if t and not os.path.exists(os.path.join(os.path.dirname(path), t)):
                dangling.append("%s: %s" % (label, t))
    out.append("dangling links: %d" % len(dangling))
    out.extend("  " + d for d in dangling)
    return "\n".join(out)


def cmd_hygiene(c, a):
    print(hygiene_text(c, a.memory_dir))
    return 0


def cmd_digest(c, a):
    if a.max_bytes < MIN_BYTES:
        die("dream: --max-bytes must be at least %d (got %d)" % (MIN_BYTES, a.max_bytes))
    wts = c.worktrees()
    roots = {norm(c.root)} | set(wts) | set(c.state["known_roots"]) | {norm(os.path.abspath(m)) for m in a.match}
    roots = sorted(r for r in roots if r)
    marks = markers(roots)
    newfiles = {k: dict(v) for k, v in c.state["files"].items()}
    read_n = hit_n = lines_n = bad_n = 0
    raw = {}
    for path in sorted(glob.glob(os.path.join(c.projects, "*", "*.jsonl"))):
        ent = newfiles.setdefault(os.path.abspath(path), {"offset": 0})
        off = ent.get("offset", 0)
        try:
            size = os.path.getsize(path)
        except OSError:
            continue
        if size < off:
            off = 0
        ent["offset"] = off
        if size == off:
            continue
        read_n += 1
        stem = os.path.splitext(os.path.basename(path))[0][:8]
        matched = False
        with open(path, "rb") as f:
            f.seek(off)
            for line in f:
                if not line.endswith(b"\n"):
                    break
                off += len(line)
                lines_n += 1
                low = line.lower()
                if not any(m in low for m in marks):
                    continue
                try:
                    obj = json.loads(line.decode("utf-8", errors="replace"))
                except ValueError:
                    bad_n += 1
                    continue
                if not isinstance(obj, dict) or not cwd_match(obj.get("cwd"), roots):
                    continue
                # System text, model-written compaction summaries and view-only lines are not human signal.
                if obj.get("isMeta") or obj.get("isCompactSummary") or obj.get("isVisibleInTranscriptOnly"):
                    continue
                for kind, text in extract(obj):
                    matched = True
                    k = (kind, text[:200].lower())
                    ts = str(obj.get("timestamp") or "")
                    br = obj.get("gitBranch") or "-"
                    cur = raw.get(k)
                    if cur is None:
                        raw[k] = {"kind": kind, "text": text, "ts": ts, "sess": stem, "branch": br, "n": 1}
                    else:
                        cur["n"] += 1
                        if ts >= cur["ts"]:
                            cur.update(text=text, ts=ts, sess=stem, branch=br)
        ent["offset"] = off
        if matched:
            hit_n += 1
            ent["m"] = True

    def render(s):
        n = " (x%d)" % s["n"] if s["n"] > 1 else ""
        d = s["ts"]
        return "[%s] %s %s %s %s: %s%s" % (s["kind"], d[:10], d[11:16], s["sess"], s["branch"], s["text"], n)

    ordered = sorted(raw.values(), key=lambda s: s["ts"], reverse=True)
    ordered.sort(key=lambda s: PRIORITY[s["kind"]])  # stable: newest first inside a group
    kept, used = [], 0
    for s in ordered:
        cost = len(("- s000 " + render(s)).encode("utf-8")) + 1
        if used + cost > a.max_bytes and kept:
            break
        used += cost
        kept.append(s)
    dropped = len(ordered) - len(kept)
    kept.sort(key=lambda s: s["ts"])

    nextstate = {"version": 1, "files": newfiles,
                 "known_roots": sorted(set(c.state["known_roots"]) | set(wts)),
                 "last_dream": c.state["last_dream"]}
    since = c.state["last_dream"] or "the first dream"
    nxt = c.sp("state.next.json")
    if not raw:
        write_json(c.sp("state.json"), nextstate)
        if os.path.exists(nxt):
            os.remove(nxt)
        print("dream: nothing to dream (no new signal since %s)" % since)
        return 3

    nextstate["signals"] = len(kept)
    sigs = ["- s%d %s" % (i + 1, render(s)) for i, s in enumerate(kept)]
    body = "\n".join([
        "# Dream digest",
        "generated: %s  repository: %s" % (iso(c.now), c.root),
        "since: %s" % since,
        "transcripts: %d with matches of %d read; new lines read: %d; malformed: %d" % (hit_n, read_n, lines_n, bad_n),
        "signals: %d kept, %d dropped by the %d byte cap" % (len(kept), dropped, a.max_bytes),
        "",
        "## Signals",
        "Kinds: C correction, D denied, H hook block, I interrupt, E failed tool call, U message, M mid-turn message.",
    ] + sigs + ["", "## Hygiene", hygiene_text(c), ""])
    ensure_dir(c.state_dir)
    dpath = c.sp("digest.md")
    with open(dpath, "w", encoding="utf-8", newline="\n") as f:
        f.write(body)
    write_json(nxt, nextstate)
    print("dream: digest %s: %d signals from %d sessions (%d bytes; %d new lines read; %d dropped by the cap)"
          % (dpath, len(kept), len({s["sess"] for s in kept}), os.path.getsize(dpath), lines_n, dropped))
    return 0


def cmd_done(c, a):
    nxt = c.sp("state.next.json")
    if not os.path.isfile(nxt):
        die("dream: run digest first")
    with open(nxt, encoding="utf-8") as f:
        s = json.load(f)
    n = s.pop("signals", 0)
    s["last_dream"] = iso(c.now)
    write_json(c.sp("state.json"), s)
    os.remove(nxt)
    if os.path.exists(c.sp("offered")):
        os.remove(c.sp("offered"))
    print("dream: done (%d signals, recorded in %s); the next dream reads transcripts after this point"
          % (n, c.sp("state.json")))
    return 0


def due_numbers(c):
    last = c.last()
    roots = {norm(c.root)} | set(c.worktrees()) | set(c.state["known_roots"])
    slugs = {slug(r).lower() for r in roots}
    app_prefix = slug(c.root).lower() + "--claude-worktrees-"

    def ours_folder(folder):
        # Exact names only: a prefix match would also take sibling folders such as Foo-bar for Foo.
        f = folder.lower()
        return f in slugs or f.startswith(app_prefix)

    sessions = 0
    seen = set()
    for path, ent in c.state["files"].items():
        seen.add(path)
        try:
            size = os.path.getsize(path)
        except OSError:
            continue
        if (ent.get("m") or ours_folder(os.path.basename(os.path.dirname(path)))) \
                and size > ent.get("offset", 0):
            sessions += 1
    try:
        folders = os.listdir(c.projects)
    except OSError:
        folders = []
    for fo in folders:
        if ours_folder(fo):
            for p in glob.glob(os.path.join(c.projects, fo, "*.jsonl")):
                if os.path.abspath(p) not in seen:
                    sessions += 1
    retros = 0
    for p in glob.glob(os.path.join(c.root, ".work", "done", "*.md")):
        try:
            m = dt.datetime.fromtimestamp(os.path.getmtime(p), dt.timezone.utc)
        except OSError:
            continue
        if m > last:
            retros += 1
    elapsed = (c.now - last) >= dt.timedelta(days=3)
    return sessions, retros, (sessions > 0 and (retros > 0 or elapsed))


def cmd_due(c, a):
    s, r, due = due_numbers(c)
    last = c.state["last_dream"]
    if not due:
        if not a.quiet:
            print("dream: not due (%d sessions with new activity, %d task retros, last dream %s)"
                  % (s, r, last[:10] if last else "never"))
        return 1
    if a.offer:
        fp = "%s:%d" % (c.now.strftime("%Y-%m-%d"), r)
        try:
            with open(c.sp("offered"), encoding="utf-8") as f:
                prev = f.read().strip()
        except OSError:
            prev = ""
        if prev == fp:
            if not a.quiet:
                print("dream: due, already offered today")
            return 1
        ensure_dir(c.state_dir)
        with open(c.sp("offered"), "w", encoding="utf-8", newline="\n") as f:
            f.write(fp + "\n")
    if not a.quiet:
        print("dream: due (%d sessions with new activity, %d task retros since the last dream)" % (s, r))
    return 0


def cmd_status(c, a):
    s, r, due = due_numbers(c)
    print("last dream: %s" % (c.state["last_dream"] or "never"))
    print("sessions with new activity: %d" % s)
    print("task retros since the last dream: %d" % r)
    print("due: %s" % ("yes" if due else "no"))
    print("digest: %s" % ("present" if os.path.isfile(c.sp("digest.md")) else "none"))
    print("state.next.json: %s" % ("present" if os.path.isfile(c.sp("state.next.json")) else "none"))
    return 0


def main():
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--projects-dir")
    common.add_argument("--root")
    common.add_argument("--state-dir")
    ap = argparse.ArgumentParser(prog="dream.py", description=__doc__.split("\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    d = sub.add_parser("digest", parents=[common])
    d.add_argument("--match", action="append", default=[])
    d.add_argument("--max-bytes", type=int, default=40000)
    sub.add_parser("done", parents=[common])
    u = sub.add_parser("due", parents=[common])
    u.add_argument("--offer", action="store_true")
    u.add_argument("--quiet", action="store_true")
    sub.add_parser("status", parents=[common])
    h = sub.add_parser("hygiene", parents=[common])
    h.add_argument("--memory-dir")
    a = ap.parse_args()
    c = Ctx(a)
    sys.exit({"digest": cmd_digest, "done": cmd_done, "due": cmd_due,
              "status": cmd_status, "hygiene": cmd_hygiene}[a.cmd](c, a))


if __name__ == "__main__":
    main()
