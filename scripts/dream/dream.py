"""dream.py - reduce Claude Code transcripts to a small signal digest for a dream.

Purpose: an offline, model-free pass over this repository's session transcripts.
It keeps only user-visible signal (corrections, messages, interrupts, denials,
hook blocks, failed tool calls; a message counts only when is_human says the
owner wrote it), reads each transcript line once ever, and
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
Impact and outcome: each digest opens an "Impact since the last dream"
section (signal counts by kind per dream, approved lessons with used: 0 whose
INDEX.md line is older than 45 days by git date, lessons sharing two or more
words with a new C, D, H, I or E signal; candidates only, the dreamer judges).
"done --report R --applied N..." appends an Outcome to the saved report:
applied and declined numbers, the files named in the applied Change lines that
changed since the digest (git against the commit the digest saw, with files
dirty at digest time compared by size and modification time, and the
auto-memory folder by the same stat), and the hygiene numbers at digest time
against now. The auto-memory folder is the one named after the main
checkout, also when the script runs in a linked worktree.
Scorecard: each digest, and the read-only "scorecard" command, carries the
owner's decisions read from the saved <date>-report.md files (per report, per
proposal kind) and the INDEX.md values and BACKLOG.md last cells now for the
lessons and rows that approved Change lines name; bounded to the last 10
reports and 20 lines each, so it stays small. Unusable reports are skipped
with a reason, never fatal.
State: <state-dir>/state.json {version, files{path: {offset, m}}, known_roots,
last_dream, dreams[{date, counts}] (the last 10)}; state.next.json also
carries this_dream, snapshot, head, dirty and memory for done; <state-dir>/offered holds the day:retro-count fingerprint of the
last offer. "done" commits state.next.json, so an unfinished dream loses nothing.
The per-file flag m marks transcripts that ever held lines for this repository,
so activity in unrelated projects never makes a dream due. Unseen transcripts
count for "due" only in folders named exactly after a root (the repository, a
git worktree, a saved root) or under <slug(root)>--claude-worktrees-; sibling
names such as Foo-bar for Foo never match.
Feedback: each digest also reads the owner's feedback log, <main checkout>/
.work/feedback/log.jsonl (written by scripts/dream/feedback.py, which this
module never imports), from the offset saved in state.json key "feedback"
{"offset": n}; lines must end in a newline, malformed lines are counted, a log
shorter than the offset is read again from 0. "## Feedback" lists lines of kind
deferral, correction, preference or approval (capped at 12000 bytes);
"## Repeats" lists word-overlap candidates between correction or preference
lines and the rules in docs/preferences/*.md (at most 40 lines). done commits
the offset, then rotates a log over 5 MB to log.1.jsonl (one kept) and resets
the offset to 0; the exit-3 digest, which commits offsets itself, rotates the
same way so a log of plain messages cannot grow without bound.
Exit codes: 0 ok (due: due); 1 not due; 2 usage error or ordering error;
3 digest found neither a new signal nor a new feedback line to show. Dependencies: Python 3 standard library, git
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
# Text that clients put in a user turn on someone else's behalf, in
# transcripts written before lines carried an origin.
MACHINE_PREFIXES = ("Task (from the session that started this one)",
                    "Background (from the session that started this one)",
                    "Another Claude session sent", "Base directory for this skill:",
                    "This session is being continued", "I hit my usage limit while you were working",
                    "The app was quit while you were working")
KIND_ORDER = "CDHIEUM"
MECHANIZE_KINDS = "CDHIE"
RETIRE_DAYS = 45
INDEX_REL = "docs/lessons/INDEX.md"
LESSON = re.compile(r"- \[(L\d+)\] (.*?)\s*\(used:\s*(\d+)\b")
FILE_RE = re.compile(r"(?<![\w/.-])((?:[\w.-]+/)*[\w-][\w.-]*\.(?:md|sh|py|toml|json|ya?ml|txt))\b")
# Scorecard: saved reports are exactly <date>-report.md; the later self-review
# pass and replay check start at these decided-proposal counts.
REPORT_NAME = re.compile(r"\d{4}-\d{2}-\d{2}-report\.md")
LESSON_ID = re.compile(r"\bL\d{3,}\b")
LAST = re.compile(r"last:\s*([^,)]+)")
SELF_REVIEW_AT, REPLAY_AT = 30, 50
CARD_REPORTS, CARD_LINES, CARD_CELL = 10, 20, 80
# Words too common to tie a lesson or a profile line to a signal.
STOP = {"about", "after", "again", "always", "never", "their", "there", "these", "those", "which",
        "while", "would", "should", "could", "where", "every", "other", "being", "prefer", "instead",
        "without", "using", "really", "think", "thing", "things", "something", "because", "before",
        "still", "first", "owner"}
# Feedback: kinds shown in the digest in priority order (plain messages already
# appear in Signals), the caps, and the log rotation size.
FEEDBACK_KINDS = ("deferral", "correction", "preference", "approval")
REPEAT_KINDS = ("correction", "preference")
FEEDBACK_BYTES, REPEAT_LINES, LOG_ROTATE = 12000, 40, 5 * 1024 * 1024
PREF_DIR = os.path.join("docs", "preferences")
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
        self.root = os.path.realpath(a.root) if a.root else os.path.dirname(os.path.dirname(here))
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
        s.setdefault("dreams", [])
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
        return [norm(ln[9:]) for ln in r.stdout.splitlines() if ln.startswith("worktree ")]

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


def memory_dir(c):
    """Claude Code keeps one auto-memory folder per repository, named after the
    main checkout, so a linked worktree reads that folder too."""
    return os.path.join(c.projects, slug(main_worktree(c.root)), "memory")


def stat_key(path):
    try:
        st = os.stat(path)
    except OSError:
        return [-1, 0]
    return [st.st_size, st.st_mtime_ns]


def git_z(root, *args):
    try:
        r = subprocess.run(["git", "-C", root] + list(args), capture_output=True, timeout=30)
    except (OSError, subprocess.SubprocessError):
        return None
    if r.returncode != 0:
        return None
    return [x for x in r.stdout.decode("utf-8", "replace").split("\0") if x]


def tree_state(root):
    """The commit the digest saw and the stat of every file dirty or untracked
    then, so done can tell a change made after the digest from one made before."""
    head = git_z(root, "rev-parse", "HEAD")
    st = git_z(root, "status", "--porcelain=v1", "-z", "-uall")
    if not head or st is None:
        return None, {}
    dirty, skip = {}, False
    for e in st:
        if skip:
            skip = False
            continue
        path = e[3:]
        if e[0] in "RC" or e[1] in "RC":
            skip = True
        dirty[path] = stat_key(os.path.join(root, path))
    return head[0].strip(), dirty


def memory_state(c):
    d = memory_dir(c)
    return {os.path.basename(f): stat_key(f) for f in glob.glob(os.path.join(d, "*.md"))}


def changed_since(c, s):
    """(paths, None): repository paths and memory note names changed since the
    digest; (None, reason) when that cannot be told. The diff is trusted only
    when this checkout's history holds the digest's commit, so done in another
    worktree on a diverged branch never claims the difference of two branches."""
    head = s.get("head")
    if not head:
        return None, "the digest recorded no commit"
    try:
        anc = subprocess.run(["git", "-C", c.root, "merge-base", "--is-ancestor", head, "HEAD"],
                             capture_output=True, timeout=30).returncode
    except (OSError, subprocess.SubprocessError):
        anc = 128
    if anc == 1:
        return None, "the digest's commit is not in this checkout's history"
    diff = git_z(c.root, "diff", "--name-only", "-z", head)
    new = git_z(c.root, "ls-files", "--others", "--exclude-standard", "-z")
    if anc != 0 or diff is None or new is None:
        return None, "git cannot compare against " + head[:12]
    dirty = s.get("dirty", {})
    out = set()
    for path in diff + new:
        if path in dirty and dirty[path] == stat_key(os.path.join(c.root, path)):
            continue
        out.add(path)
    was = s.get("memory", {})
    now = memory_state(c)
    out |= {n for n in set(was) | set(now) if was.get(n) != now.get(n)}
    return out, None


def names_path(named, path):
    """Matches by last components, so a bare README.md in a Change line counts
    when any README.md changed; a Change line names files loosely."""
    return path == named or path.endswith("/" + named) or named.endswith("/" + path)


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


def is_human(holder, text=""):
    """True when a user line (or a queued_command attachment) holds the owner's
    own words. Newer transcripts say so in origin.kind; another session's
    message is "peer", a background result "task-notification". Older lines
    have only turnOrigin, or nothing, so known machine-written openings decide."""
    o = holder.get("origin")
    if isinstance(o, dict) and o.get("kind"):
        return o.get("kind") == "human"
    t = holder.get("turnOrigin")
    if t:
        return t == "human"
    if holder.get("promptSource") == "system":
        return False
    return not text.lstrip().startswith(MACHINE_PREFIXES)


def extract(obj):
    """Yield (kind, text) signals from one parsed transcript line."""
    t = obj.get("type")
    if t == "user":
        msg = obj.get("message")
        content = msg.get("content") if isinstance(msg, dict) else None
        for s in texts(content):
            s = s.strip()
            if not s or s.startswith("<") or not is_human(obj, s):
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
            if isinstance(p, str) and p.strip() and not p.strip().startswith("<") and is_human(att, p):
                yield ("C" if is_correction(p) else "M"), clean(p, MSG_LIMIT)


def words(s):
    """Distinctive words (five letters or more, minus STOP) for overlap checks."""
    return {w for w in re.findall(r"[a-z]{5,}", s.lower()) if w not in STOP}


def fmt_counts(counts, order):
    return ", ".join("%s %d" % (k, counts[k]) for k in order if counts.get(k)) or "none"


def read_text(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            return f.read()
    except OSError:
        return ""


def approved_lessons(root):
    """(line number, id, text, used) for each approved lesson, counted the way
    scripts/lessons.sh does: fenced examples and the documented format line,
    whose text starts with a "<...>" placeholder, are not lessons."""
    out, fence = [], False
    for n, row in enumerate(read_text(os.path.join(root, INDEX_REL)).splitlines(), 1):
        if row.startswith("```"):
            fence = not fence
            continue
        m = re.match(r"- \[L\d+\] (.*)", row)
        if fence or not m or m.group(1).startswith("<"):
            continue
        f = LESSON.match(row)
        out.append((n, f.group(1) if f else row[3:7], f.group(2) if f else m.group(1),
                    int(f.group(3)) if f else None))
    return out


def git_line_dates(root, rel):
    """Committer date of each line of rel by git blame; None outside git or for
    an untracked file. Uncommitted lines carry the current time."""
    try:
        r = subprocess.run(["git", "-C", root, "blame", "--line-porcelain", "--", rel],
                           capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=30)
    except (OSError, subprocess.SubprocessError):
        return None
    if r.returncode != 0:
        return None
    out, cur = {}, None
    for row in r.stdout.splitlines():
        m = re.match(r"[0-9a-f]{40} \d+ (\d+)", row)
        if m:
            cur = int(m.group(1))
        elif row.startswith("committer-time ") and cur is not None:
            out[cur] = dt.datetime.fromtimestamp(int(row.split()[1]), dt.timezone.utc)
    return out


def impact_lines(c, sigs, counts):
    """What changed since the last dream, from data already kept; candidates only."""
    out = ["", "## Impact since the last dream", "trend, signals by kind per dream:"]
    dreams = c.state["dreams"][-10:]
    if not dreams:
        out.append("  no earlier dream")
    for d in dreams:
        out.append("  %s: %s" % (d["date"][:10], fmt_counts(d["counts"], KIND_ORDER)))
    out.append("  this dream: %s" % fmt_counts(counts, KIND_ORDER))
    lessons = approved_lessons(c.root)
    if lessons:
        dates = git_line_dates(c.root, INDEX_REL)
        if dates is None:
            out.append("retire candidates: N/A - %s has no git history here" % INDEX_REL)
        else:
            for n, lid, _, used in lessons:
                if used == 0 and n in dates and (c.now - dates[n]).days > RETIRE_DAYS:
                    out.append("%s unused for %d days (used: 0; its line was committed %s)"
                               % (lid, (c.now - dates[n]).days, dates[n].strftime("%Y-%m-%d")))
    for _, lid, text, _ in lessons:
        hits = ["%s (%s)" % (sid, " ".join(sorted(common))) for sid, common in lesson_hits(text, sigs)]
        if hits:
            out.append("%s shares words with %s" % (lid, ", ".join(hits[:3])))
    return out


def word_hits(text, items):
    """(id, shared words) for each (id, item text) pair sharing two or more
    distinctive words with text; the one matcher for Impact, the scorecard and
    Repeats."""
    w = words(text)
    out = []
    for iid, t in items:
        common = w & words(t)
        if len(common) >= 2:
            out.append((iid, common))
    return out


def lesson_hits(text, sigs):
    """(signal id, shared words) for each C, D, H, I or E signal sharing two or
    more words with a lesson."""
    return word_hits(text, [(sid, s["text"]) for sid, s in sigs if s["kind"] in MECHANIZE_KINDS])


def hygiene_numbers(text):
    """The top-level "label: value" lines of a hygiene report, in order."""
    out = {}
    for row in text.splitlines():
        if row and not row.startswith(" "):
            label, _, val = row.partition(": ")
            out[label] = val
    return out


class ReportError(Exception):
    """A saved report that cannot be used: msg for the scorecard's skipped
    line, fatal for dream.sh done, which stops on it."""

    def __init__(self, msg, fatal=None):
        super().__init__(msg)
        self.msg, self.fatal = msg, fatal or "dream: " + msg


def kind_name(tag):
    """A proposal's bracket tag lowercased, spaces around ":" normalised."""
    t = re.sub(r"\s+", " ", re.sub(r"\s*:\s*", ": ", tag.strip().lower())).strip()
    return t or "untagged"


def read_report(path):
    """({number: (kind, [Change texts])}, [rows of each Outcome section]) from a
    saved report; ReportError when it cannot be read or numbers a proposal twice."""
    try:
        with open(path, encoding="utf-8") as f:
            rows = f.read().splitlines()
    except (OSError, UnicodeDecodeError) as e:
        raise ReportError("cannot read it: %s" % e, "dream: cannot read the report %s: %s" % (path, e))
    props, outcomes, cur, section = {}, [], None, None
    for row in rows:
        if row.startswith("## "):
            head = row.strip()
            section = "p" if head == "## Proposals" else "o" if head.startswith("## Outcome") else None
            if section == "o":
                outcomes.append([])
            cur = None
            continue
        if section == "o":
            outcomes[-1].append(row.strip())
            continue
        if section != "p":
            continue
        m = re.match(r"(\d+)\. (.*)", row)
        if m:
            cur = int(m.group(1))
            if cur in props:
                raise ReportError("numbers proposal %d twice" % cur,
                                  "dream: %s numbers proposal %d twice; fix the report first" % (path, cur))
            tag = re.match(r"\[([^\]]*)\]", m.group(2).strip())
            props[cur] = (kind_name(tag.group(1) if tag else ""), [])
        elif cur is not None and row.strip().startswith("Change:"):
            props[cur][1].append(row.strip()[7:].strip())
    return props, outcomes


def parse_report(path):
    """{number: [Change texts]} from a saved dream report's Proposals section."""
    try:
        props, _ = read_report(path)
    except ReportError as e:
        die(e.fatal)
    return {n: changes for n, (_, changes) in props.items()}


def parse_outcome(rows, props):
    """(approved numbers, declined numbers) from one Outcome section's rows."""
    vals = {}
    for row in rows:
        for key in ("Applied", "Declined"):
            if row.startswith(key + ":"):
                vals[key] = row[len(key) + 1:].strip()
    out = []
    for key in ("Applied", "Declined"):
        if key not in vals:
            raise ReportError("Outcome lacks a%s %s line" % ("n" if key == "Applied" else "", key))
        parts = [] if vals[key].lower() == "none" else [p.strip() for p in vals[key].split(",")]
        if not all(p.isdigit() for p in parts):
            raise ReportError("Outcome %s is not a number list" % key)
        nums = {int(p) for p in parts}
        for n in sorted(nums):
            if n not in props:
                raise ReportError("Outcome names %d, which its Proposals lack" % n)
        out.append(nums)
    both = out[0] & out[1]
    if both:
        raise ReportError("Outcome puts %d in both Applied and Declined" % min(both))
    return out[0], out[1]


def cut(s, n=CARD_CELL):
    return s if len(s) <= n else s[:n - 3] + "..."


def cell_key(s):
    return re.sub(r"\s+", " ", s.replace("`", "")).strip().lower()


def table_cells(row):
    """Cells of a markdown table row: edge pipes stripped, split on unescaped
    pipes, "\\|" unescaped."""
    row = row.strip()
    if row.startswith("|"):
        row = row[1:]
    if row.endswith("|") and not row.endswith("\\|"):
        row = row[:-1]
    return [c.replace("\\|", "|").strip() for c in re.split(r"(?<!\\)\|", row)]


def backlog_status(root):
    """{first cell key: last cell} for each BACKLOG.md table row."""
    out = {}
    for row in read_text(os.path.join(root, "BACKLOG.md")).splitlines():
        if row.lstrip().startswith("|"):
            cells = table_cells(row)
            if len(cells) >= 2:
                out.setdefault(cell_key(cells[0]), cells[-1])
    return out


def index_values(root):
    """{lesson id: (text, used, last)} for the approved lessons in INDEX.md."""
    rows = read_text(os.path.join(root, INDEX_REL)).splitlines()
    out = {}
    for n, lid, text, used in approved_lessons(root):
        m = LAST.search(rows[n - 1])
        out[lid] = (text, "N/A" if used is None else used, m.group(1).strip() if m else "N/A")
    return out


def branch_label(root):
    try:
        r = subprocess.run(["git", "-C", root, "rev-parse", "--abbrev-ref", "HEAD"],
                           capture_output=True, text=True, timeout=10)
    except (OSError, subprocess.SubprocessError):
        return "N/A - not a git checkout"
    if r.returncode == 0:
        b = r.stdout.strip()
        return "detached" if b == "HEAD" else b
    # A repository with no commits yet has no HEAD to resolve, but its branch name.
    try:
        s = subprocess.run(["git", "-C", root, "symbolic-ref", "--short", "HEAD"],
                           capture_output=True, text=True, timeout=10)
    except (OSError, subprocess.SubprocessError):
        return "N/A - not a git checkout"
    return s.stdout.strip() if s.returncode == 0 and s.stdout.strip() else "N/A - not a git checkout"


def scorecard_lines(c, sigs=None):
    """The owner's recorded decisions on past proposals and what became of the
    lessons and BACKLOG rows the approved ones named. Read-only; sigs are this
    digest's (id, signal) pairs, or None outside a digest."""
    out = ["", "## Scorecard",
           "the owner's recorded decisions on past dream proposals, counted by script; "
           "now values read from %s (branch %s)" % (c.root, branch_label(c.root))]
    names = []
    if os.path.isdir(c.state_dir):
        names = sorted(n for n in os.listdir(c.state_dir) if REPORT_NAME.fullmatch(n))
    if not names:
        return out + ["no saved reports"]
    reports, skipped = [], []
    for name in names:
        try:
            props, outcomes = read_report(os.path.join(c.state_dir, name))
            dec = parse_outcome(outcomes[-1], props) if outcomes else None
        except ReportError as e:
            skipped.append(cut("skipped %s: %s" % (name, e.msg), 2 * CARD_CELL))
            continue
        reports.append((name[:10], props, dec))
    older, recent = reports[:-CARD_REPORTS], reports[-CARD_REPORTS:]
    out.append("reports (last %d, oldest first; approved means the owner approved it, not that it landed):"
               % CARD_REPORTS)
    if older:
        out.append("  older (%d reports): proposals %d, approved %d, declined %d, no Outcome %d" % (
            len(older), sum(len(p) for _, p, _ in older), sum(len(d[0]) for _, _, d in older if d),
            sum(len(d[1]) for _, _, d in older if d), sum(1 for _, _, d in older if d is None)))
    for date, props, dec in recent:
        if dec is None:
            out.append("  %s: proposals %d, no Outcome recorded" % (date, len(props)))
        else:
            out.append("  %s: proposals %d, approved %d, declined %d" % (date, len(props), len(dec[0]), len(dec[1])))
    out += skipped[:CARD_LINES]
    if len(skipped) > CARD_LINES:
        out.append("... %d more skipped reports not shown" % (len(skipped) - CARD_LINES))
    kinds = {}
    for _, props, dec in reports:
        for num, (kind, _) in props.items() if dec else ():
            k = kinds.setdefault(kind, [0, 0])
            k[0] += num in dec[0]
            k[1] += num in dec[1]
    out.append("by kind (every report with an Outcome):")
    for kind in sorted(kinds)[:CARD_LINES]:
        a, d = kinds[kind]
        out.append("  %s: approved %d, declined %d, rate %s"
                   % (cut(kind, 40), a, d, "%d%%" % round(100 * a / (a + d)) if a + d else "N/A - none decided"))
    if not kinds:
        out.append("  none")
    if len(kinds) > CARD_LINES:
        out.append("  ... %d more kinds not shown" % (len(kinds) - CARD_LINES))
    lessons, rows = [], []
    for _, props, dec in reversed(recent):
        for num in sorted(dec[0]) if dec else ():
            for ch in props[num][1]:
                for lid in LESSON_ID.findall(ch):
                    if lid not in lessons:
                        lessons.append(lid)
                if "BACKLOG.md" not in ch:
                    continue
                for q in re.findall(r'"([^"]*)"', ch):
                    first = q.split(" | ")[0].replace("\\|", "|").strip()
                    if " | " in q and cell_key(first) not in {cell_key(r) for r in rows}:
                        rows.append(first)
    idx = index_values(c.root)
    out.append("lessons named in approved changes, last %d reports (newest first; candidates: %s):" % (
        CARD_REPORTS, "this digest's C, D, H, I or E signals sharing two or more words, not proof"
        if sigs is not None else "N/A - no digest signals"))
    for lid in lessons[:CARD_LINES]:
        if lid not in idx:
            out.append("  %s: not in INDEX.md" % lid)
            continue
        text, used, last = idx[lid]
        out.append("  %s: used %s, last %s%s" % (lid, cut(str(used), 20), cut(last, 40), "" if sigs is None
                                                  else "; candidates %d" % len(lesson_hits(text, sigs))))
    if not lessons:
        out.append("  none")
    if len(lessons) > CARD_LINES:
        out.append("  ... %d more not shown" % (len(lessons) - CARD_LINES))
    status = backlog_status(c.root)
    out.append("BACKLOG rows named in approved changes, last %d reports (newest first; last cell now):" % CARD_REPORTS)
    for first in rows[:CARD_LINES]:
        now = status.get(cell_key(first))
        out.append("  %s: %s" % (cut(first), "not found" if now is None else cut(now)))
    if not rows:
        out.append("  none")
    if len(rows) > CARD_LINES:
        out.append("  ... %d more not shown" % (len(rows) - CARD_LINES))
    decided = sum(len(d[0]) + len(d[1]) for _, _, d in reports if d)
    out.append("decided: %d (self-review pass at %d, replay check at %d)" % (decided, SELF_REVIEW_AT, REPLAY_AT))
    return out


def outcome_text(c, path, applied, s):
    props = parse_report(path)
    for i, n in enumerate(applied):
        if n in applied[:i]:
            die("dream: proposal %d is approved twice" % n)
        if n not in props:
            die("dream: proposal %d is not in %s; approved numbers must match its numbered list" % (n, path))
    done = sorted(set(applied))
    files = []
    for n in done:
        for ch in props[n]:
            for f in FILE_RE.findall(ch):
                if f not in files:
                    files.append(f)
    changed, why = changed_since(c, s)
    if changed is None:
        files_line = "Files: %s (named in the Change lines; not checked: %s)" % (", ".join(files) or "none", why)
    else:
        files = [f for f in files if any(names_path(f, p) for p in changed)]
        files_line = "Files: %s" % (", ".join(files) or "none")
    after = hygiene_numbers(hygiene_text(c))
    before = s.get("snapshot") or {}
    changed = ["  %s: %s -> %s" % (k, before.get(k, "N/A"), v) for k, v in after.items() if before.get(k) != v]
    same = [k for k, v in after.items() if before.get(k) == v]
    return "\n".join(["", "## Outcome %s" % c.now.strftime("%Y-%m-%d"),
                      "Applied: %s" % (", ".join(map(str, done)) or "none"),
                      "Declined: %s" % (", ".join(str(n) for n in sorted(props) if n not in done) or "none"),
                      files_line,
                      "Hygiene, at the digest -> now:"] + (changed or ["  no change"])
                     + ["Unchanged: %s" % (", ".join(same) or "none"), ""])


def feedback_dir(root):
    """The folder feedback.py writes to: the main checkout's .work/feedback."""
    return os.path.join(main_worktree(root), ".work", "feedback")


def read_log_lines(path, off):
    """(entries, end offset, lines read, malformed) from byte off to the last
    complete line of one feedback log file; a partial last line waits."""
    entries, n, bad = [], 0, 0
    with open(path, "rb") as f:
        f.seek(off)
        for line in f:
            if not line.endswith(b"\n"):
                break
            off += len(line)
            if not line.strip():
                continue
            n += 1
            try:
                obj = json.loads(line.decode("utf-8", errors="replace"))
            except ValueError:
                bad += 1
                continue
            if not isinstance(obj, dict) or not isinstance(obj.get("kind"), str) \
                    or not isinstance(obj.get("text"), str):
                bad += 1
                continue
            entries.append(obj)
    return entries, off, n, bad


def read_feedback(c):
    """(entries, new offset, lines read, malformed, log exists) for the lines
    added to the feedback log since the saved offset. After a rotation the
    saved "carry" offset says where reading stopped in log.1.jsonl; those
    remaining lines come first, so lines logged during a dream are not lost."""
    folder = feedback_dir(c.root)
    saved = c.state.get("feedback") or {}
    entries, n, bad, exists = [], 0, 0, False
    carry = saved.get("carry")
    old = os.path.join(folder, "log.1.jsonl")
    if isinstance(carry, int) and carry >= 0:
        try:
            if carry <= os.path.getsize(old):
                e1, _, n1, b1 = read_log_lines(old, carry)
                entries, n, bad, exists = e1, n1, b1, True
        except OSError:
            pass
    path = os.path.join(folder, "log.jsonl")
    off = saved.get("offset", 0)
    try:
        size = os.path.getsize(path)
    except OSError:
        return entries, 0, n, bad, exists
    if not isinstance(off, int) or off < 0 or off > size:
        off = 0
    e2, off, n2, b2 = read_log_lines(path, off)
    return entries + e2, off, n + n2, bad + b2, True


def rotate_feedback(c, state):
    """Rename a log over 5 MB to log.1.jsonl (one kept) and reset the saved
    offset; called only after the offset was committed. The committed offset
    becomes the carry: lines the hook appended after the digest read the log
    stay in log.1.jsonl past it, and the next digest reads them first."""
    folder = feedback_dir(c.root)
    path = os.path.join(folder, "log.jsonl")
    try:
        if os.path.getsize(path) <= LOG_ROTATE:
            return
        os.replace(path, os.path.join(folder, "log.1.jsonl"))
    except OSError:
        return
    carry = (state.get("feedback") or {}).get("offset", 0)
    state["feedback"] = {"offset": 0, "carry": carry if isinstance(carry, int) else 0}
    write_json(c.sp("state.json"), state)


def feedback_line(i, e):
    files = e.get("files")
    files = ", ".join(x for x in files if isinstance(x, str)) if isinstance(files, list) else ""
    return "- f%d [%s] %s %s %s task %s: %s; files: %s" % (
        i, e["kind"], str(e.get("ts") or "")[:10], e.get("session") or "-", e.get("branch") or "-",
        e.get("task") or "-", clean(e["text"], MSG_LIMIT), files or "-")


def register_table_kind(cells):
    """'rules', 'rules-extra' (a rules header with columns other than an optional
    Repeats, which the register check reports), 'baselines' or None for a
    register table header row; the one header test for the register check
    (preferences.py) and the dream."""
    low = [c.lower() for c in cells]
    if len(low) >= 4 and low[0] == "id" and low[1] == "rule" and low[2].startswith("source") \
            and low[3].startswith("check"):
        if len(low) == 4 or (len(low) == 5 and low[4].startswith("repeats")):
            return "rules"
        return "rules-extra"
    if len(low) == 4 and low[:3] == ["kind", "reference", "owns"] and low[3].startswith("check"):
        return "baselines"
    return None


def register_rows(text):
    """(line number, table kind, cells) for each data row of a register's
    tables; fenced blocks are skipped and cells split on unescaped pipes."""
    fence, kind = False, None
    for n, row in enumerate(text.splitlines(), 1):
        if row.lstrip().startswith(("```", "~~~")):
            fence, kind = not fence, None
            continue
        if fence:
            continue
        if not row.lstrip().startswith("|"):
            kind = None
            continue
        cells = table_cells(row)
        head = register_table_kind(cells)
        if head:
            kind = head
        elif kind and cells and not all(set(x) <= set(":- ") for x in cells):
            yield n, kind, cells


def register_rules(root):
    """(area:rule ID, rule text) from the rules tables of docs/preferences/*.md;
    the area is the file name, since IDs are unique only within one file."""
    out = []
    for path in sorted(glob.glob(os.path.join(root, PREF_DIR, "*.md"))):
        area = os.path.splitext(os.path.basename(path))[0]
        if area.lower() == "readme":
            continue
        for _, kind, cells in register_rows(read_text(path)):
            if kind in ("rules", "rules-extra") and len(cells) >= 2 and cells[0]:
                out.append(("%s:%s" % (area, cells[0]), cells[1]))
    return out


def feedback_sections(c, entries, nread, bad, exists):
    """(lines of the Feedback and Repeats sections, number of entries of a shown kind)."""
    out = ["", "## Feedback"]
    if not exists:
        out.append("no feedback log yet")
    elif not nread:
        out.append("no new feedback lines")
    shown = [e for e in entries if e["kind"] in FEEDBACK_KINDS]
    shown.sort(key=lambda e: str(e.get("ts") or ""), reverse=True)
    shown.sort(key=lambda e: FEEDBACK_KINDS.index(e["kind"]))  # stable: newest first in a kind
    kept, used = [], 0
    for i, e in enumerate(shown, 1):
        line = feedback_line(i, e)
        cost = len(line.encode("utf-8")) + 1
        if used + cost > FEEDBACK_BYTES:
            break
        used += cost
        kept.append(line)
    if nread:
        out.append("log: %d new lines read, %d malformed; %d shown, %d dropped by the %d byte cap"
                   % (nread, bad, len(kept), len(shown) - len(kept), FEEDBACK_BYTES))
    out += kept
    out += ["", "## Repeats",
            "word-overlap candidates, not proof: a correction or preference sharing two or more words "
            "with a register rule in docs/preferences/*.md; each may be a repeat or a coincidence"]
    rules = register_rules(c.root)
    hits = []
    for i, e in enumerate(shown[:len(kept)], 1):
        if e["kind"] in REPEAT_KINDS:
            hits += ["%s <- f%d (%s)" % (rid, i, " ".join(sorted(common)))
                     for rid, common in word_hits(e["text"], rules)]
    if not hits:
        out.append("none" if rules else "no register rules")
    out += hits[:REPEAT_LINES]
    if len(hits) > REPEAT_LINES:
        out.append("... %d more not shown" % (len(hits) - REPEAT_LINES))
    return out, len(shown)


def count_lines(b):
    return b.count(b"\n") + (1 if b and not b.endswith(b"\n") else 0)


def hygiene_text(c, mem_override=None):
    out = []
    for rel in HYGIENE_FILES:
        p = os.path.join(c.root, rel)
        if os.path.isfile(p):
            with open(p, "rb") as f:
                b = f.read()
            out.append("%s: %d lines, %d bytes" % (rel, count_lines(b), len(b)))
        else:
            out.append("%s: missing" % rel)

    read = read_text
    appr = approved_lessons(c.root)
    unused = [x for x in appr if x[3] == 0]
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

    mdir = mem_override or memory_dir(c)
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

    fb_entries, fb_off, fb_n, fb_bad, fb_exists = read_feedback(c)
    fb_lines, fb_shown = feedback_sections(c, fb_entries, fb_n, fb_bad, fb_exists)
    nextstate = {"version": 1, "files": newfiles, "feedback": {"offset": fb_off},
                 "known_roots": sorted(set(c.state["known_roots"]) | set(wts)),
                 "last_dream": c.state["last_dream"], "dreams": c.state["dreams"]}
    since = c.state["last_dream"] or "the first dream"
    nxt = c.sp("state.next.json")
    if not raw and not fb_shown:
        write_json(c.sp("state.json"), nextstate)
        rotate_feedback(c, nextstate)
        if os.path.exists(nxt):
            os.remove(nxt)
        print("dream: nothing to dream (no new signal since %s)" % since)
        return 3

    counts = {}
    for s in raw.values():
        counts[s["kind"]] = counts.get(s["kind"], 0) + 1
    hyg = hygiene_text(c)
    nextstate["signals"] = len(kept)
    nextstate["this_dream"] = {"date": iso(c.now), "counts": counts}
    nextstate["snapshot"] = hygiene_numbers(hyg)
    nextstate["head"], nextstate["dirty"] = tree_state(c.root)
    nextstate["memory"] = memory_state(c)
    sigs = ["- s%d %s" % (i + 1, render(s)) for i, s in enumerate(kept)]
    pairs = [("s%d" % (i + 1), s) for i, s in enumerate(kept)]
    body = "\n".join([
        "# Dream digest",
        "generated: %s  repository: %s" % (iso(c.now), c.root),
        "since: %s" % since,
        "transcripts: %d with matches of %d read; new lines read: %d; malformed: %d" % (hit_n, read_n, lines_n, bad_n),
        "signals: %d kept, %d dropped by the %d byte cap" % (len(kept), dropped, a.max_bytes),
    ] + impact_lines(c, pairs, counts) + scorecard_lines(c, pairs) + fb_lines + [
        "",
        "## Signals",
        "Kinds: C correction, D denied, H hook block, I interrupt, E failed tool call, U message, M mid-turn message.",
    ] + sigs + ["", "## Hygiene", hyg, ""])
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
    if a.applied and not a.report:
        die("dream: --applied needs --report <the saved report>")
    with open(nxt, encoding="utf-8") as f:
        s = json.load(f)
    if a.report:
        text = outcome_text(c, a.report, a.applied, s)
        with open(a.report, "a", encoding="utf-8", newline="\n") as f:
            f.write(text)
        print("dream: outcome appended to %s" % a.report)
    n = s.pop("signals", 0)
    this = s.pop("this_dream", None)
    for k in ("snapshot", "head", "dirty", "memory"):
        s.pop(k, None)
    if this:
        s["dreams"] = (s.get("dreams", []) + [this])[-10:]
    s["last_dream"] = iso(c.now)
    write_json(c.sp("state.json"), s)
    rotate_feedback(c, s)
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


def cmd_scorecard(c, a):
    print("\n".join(scorecard_lines(c)[1:]))
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
    dn = sub.add_parser("done", parents=[common])
    dn.add_argument("--report", help="append the outcome of this dream to the saved report")
    dn.add_argument("--applied", type=int, nargs="+", default=[], help="the proposal numbers the human approved")
    u = sub.add_parser("due", parents=[common])
    u.add_argument("--offer", action="store_true")
    u.add_argument("--quiet", action="store_true")
    sub.add_parser("status", parents=[common])
    h = sub.add_parser("hygiene", parents=[common])
    h.add_argument("--memory-dir")
    sub.add_parser("scorecard", parents=[common])
    a = ap.parse_args()
    c = Ctx(a)
    sys.exit({"digest": cmd_digest, "done": cmd_done, "due": cmd_due, "status": cmd_status,
              "hygiene": cmd_hygiene, "scorecard": cmd_scorecard}[a.cmd](c, a))


if __name__ == "__main__":
    main()
