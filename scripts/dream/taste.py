"""taste.py - learn the owner's tastes from every local project, for a personal
profile the owner approves line by line.

Purpose: the taste pass of a dream (docs/procedures/dream.md). A model-free
digest reduces every project's Claude Code transcripts, and the feedback notes
in every project's auto-memory, to the owner's own preference signals; a
read-only agent proposes numbered profile lines from it; "apply" writes only
the numbers the owner approved.

Inputs: <projects>/<dir>/<session>.jsonl (top level only) under the default
projects folder and every --projects-dir; <projects>/<dir>/memory/*.md notes
whose type is feedback or user. A message counts only when dream.is_human says
it holds the owner's own words.
Outputs, all user-level and never inside a repository (apply and sync refuse
a taste folder inside a git work tree):
  <home>/.claude/taste/<area>.md   the profile: "# Title", a purpose line,
                                   then "- [Tnnn] <line>" items
  <home>/.claude/CLAUDE.md         a managed block of @taste/<area>.md imports
  <codex>/AGENTS.md                a managed block holding the profile text
  <home>/.claude/taste/.dream/     state.json (offsets, notes read, the
                                   evidence pool, last pass), state.next.json
                                   (pending until done), ledger.json (next id,
                                   used signals, applied report numbers),
                                   digest.md, reports/
<home> is TASTE_HOME or the home folder; <codex> is <home>/.codex when
TASTE_HOME is set, else CODEX_HOME or ~/.codex; the default projects folder is
DREAM_PROJECTS_DIR or <home>/.claude/projects. DREAM_NOW pins "now".
Signal kinds: P stated preference, O own words in a question answer,
C correction, D a rejected action and the owner's next message, A a picked
option, R a short reaction with the reply it answers, T a taste-topic
sentence, F an auto-memory feedback or user note (model-written, so it never
counts as a session of evidence). Ids are "t" plus hex of a hash of the kind
and text, so the same signal keeps its id in every run.
Evidence rule (apply): a proposal cites a P or O signal, or non-F signals
from two or more sessions. Caps: a profile line holds at most 160 characters
after its id; all area files together hold at most 6000 bytes.
Exit codes: 0 ok; 1 refused (validation, caps, check problems); 2 usage, a
state or ledger of a newer format, a taste folder inside a git work tree, or a
broken managed block; 3 the digest stopped early (too few fresh signals, or
under --min-days since the last pass), after saving what it read to the pool.
Dependencies: Python 3 standard library, git (work-tree guard; without git the
guard cannot see a repository), dream.py beside this file. Assumption: a
transcript line is complete only when it ends in a newline.
"""
import argparse
import datetime as dt
import glob
import hashlib
import json
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
import dream as D  # noqa: E402  (shared helpers; the folder is not on sys.path under -I)

FORMAT = 1
LINE_MAX = 160
PROFILE_MAX = 6000
PRUNE_DAYS = 180
SENT_LIMIT = 300
RE_LIMIT = 160
REACTION_MAX = 120
MAX_P, MAX_T = 8, 3
PRIORITY = {"P": 0, "O": 0, "C": 1, "D": 1, "A": 2, "R": 2, "T": 3, "F": 3}
EXPLICIT = ("P", "O")
AREAS = [
    ("communication", "Communication", "How to talk to me: tone, length, structure, what to lead with."),
    ("writing", "Writing", "How I like text written: wording, style, punctuation."),
    ("design", "Design", "Visual and interface design taste."),
    ("art", "Art", "Art taste: styles, palettes, composition."),
    ("code", "Code", "How I like code written and organised, beyond each repository's own rules."),
    ("working", "Working style", "How to work with me: when to ask, how much autonomy, how much process."),
]
BEGIN = "<!-- taste:begin - managed by scripts/dream.sh taste; edit the files in ~/.claude/taste -->"
BEGIN_KEY = "<!-- taste:begin"
END = "<!-- taste:end -->"
KIND_ORDER = "POCDARTF"
KINDS = ("Kinds: P stated preference, O own words in an answer, C correction, D rejected action and "
         "the next message, A picked option, R reaction (re: the reply), T taste topic, "
         "F memory note (model-written).")

STRONG = re.compile(
    r"\b(i (really |strongly |much |also )?(like|love|hate|dislike|enjoy)|"
    r"i (do not|don't|dont) (like|love|want|need|care for)|i'?d rather|i would rather|"
    r"prefer\w*|favou?rite|"
    r"(always|never) (use|do|say|write|put|add|make|lead|start|end|ask|show|give|include|leave|keep|run)|"
    r"(do not|don't|dont|stop|avoid) (use|using|add|adding|say|saying|write|writing|put|putting|"
    r"making|asking|showing|including)|"
    r"too (long|short|verbose|wordy|busy|much|many|dense|small|big|large|technical|formal|casual|"
    r"bright|dark|cluttered|plain|tight|cramped|loud|complex|complicated)|"
    r"shorter|simpler|cleaner|calmer|plainer|more concise|"
    r"(less|more) (verbose|detail|jargon|text|words|colou?r|whitespace|spacing|formal|casual|concise|visual)|"
    r"(looks|feels|reads|sounds) (great|good|nice|clean|cluttered|busy|off|wrong|cheap|generic|"
    r"amateur|professional|dated|modern)|"
    r"ugly|beautiful|gorgeous|elegant|tacky|bland|boring)\b", re.I)
TOPIC = re.compile(
    r"\b(tone|fonts?|typefaces?|typography|colou?rs?|palettes?|layouts?|spacing|whitespace|margins?|"
    r"padding|styles?|styling|wording|phrasing|jargon|emojis?|dash(es)?|bullets?|headings?|concise|"
    r"verbose|minimal(ist)?|aesthetics?|vibe|look and feel|naming|readab\w*|animations?|icons?)\b", re.I)
REACTION = re.compile(
    r"^((i )?(love|like) (it|this|that)|perfect|great|nice|looks (good|great|nice|amazing|perfect|better)|"
    r"beautiful|awesome|amazing|excellent|exactly|much better|better|brilliant|wow|ugly|"
    r"hate (it|this|that)|meh|not (great|good)|worse|terrible|horrible|yuck)\b", re.I)
TAG_BLOCK = re.compile(r"<([A-Za-z][\w-]*)(\s[^>]*)?>.*?</\1\s*>", re.S)
IMAGE = re.compile(r"\[Image[^\]]*\]")
SENT_SPLIT = re.compile(r"(?<=[.!?])\s+|\n+")
ID_LINE = re.compile(r"^- \[(T\d{3,})\] (.*)$")
ITEM = re.compile(r"^(\d+)\.\s+(.*\S)\s*$")
ADD = re.compile(r"^add\s+([a-z][a-z0-9-]{0,23}):\s+(.+)$")
REVISE = re.compile(r"^revise\s+(T\d{3,})\s+([a-z][a-z0-9-]{0,23}):\s+(.+)$")
REMOVE = re.compile(r"^remove\s+(T\d{3,})(:.*)?$")
SIG_ID = re.compile(r"\bt[0-9a-f]{6,12}\b")


def die(msg, code=2):
    print(msg, file=sys.stderr)
    sys.exit(code)


class Ctx:
    def __init__(self, a):
        th = os.environ.get("TASTE_HOME")
        self.home = os.path.abspath(th) if th else os.path.expanduser("~")
        self.taste = os.path.join(self.home, ".claude", "taste")
        self.state_dir = os.path.join(self.taste, ".dream")
        self.claude_md = os.path.join(self.home, ".claude", "CLAUDE.md")
        codex = os.path.join(self.home, ".codex") if th else (
            os.environ.get("CODEX_HOME") or os.path.join(self.home, ".codex"))
        self.codex_md = os.path.join(codex, "AGENTS.md")
        default = os.environ.get("DREAM_PROJECTS_DIR") or os.path.join(self.home, ".claude", "projects")
        self.projects = []
        for p in [default] + list(getattr(a, "projects_dir", None) or []):
            p = os.path.abspath(p)
            if p not in self.projects:
                self.projects.append(p)
        self.now = D.now_utc()

    def sp(self, name):
        return os.path.join(self.state_dir, name)


def load_json(path, defaults):
    try:
        with open(path, encoding="utf-8") as f:
            s = json.load(f)
    except FileNotFoundError:
        s = {}
    except (ValueError, OSError) as e:
        die("taste: unreadable %s: %s" % (path, e))
    if not isinstance(s, dict):
        die("taste: %s is not a JSON object" % path)
    fmt = s.get("format", FORMAT)
    if not isinstance(fmt, int) or fmt > FORMAT:
        die("taste: %s has format %s, newer than this script's format %d; update the template "
            "(scripts/template-sync.sh) before the taste pass" % (path, fmt, FORMAT))
    s["format"] = FORMAT
    for k, v in defaults.items():
        s.setdefault(k, v() if callable(v) else v)
    return s


def load_state(c, name="state.json"):
    return load_json(c.sp(name), {"files": dict, "memory": dict, "pool": dict, "last_pass": None,
                                  "passes": list, "history_seen": 0})


def load_ledger(c):
    return load_json(c.sp("ledger.json"), {"next_id": 1, "used": dict, "applied": list,
                                           "history": list, "seen": dict})


def pending_or_state(c):
    nxt = c.sp("state.next.json")
    return load_state(c, "state.next.json") if os.path.isfile(nxt) else load_state(c)


def git_env():
    # A git hook exports GIT_DIR and friends; they would make every folder look like that repository.
    return {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}


def inside_git(path):
    p = os.path.abspath(path)
    while not os.path.isdir(p):
        parent = os.path.dirname(p)
        if parent == p:
            return False
        p = parent
    try:
        r = subprocess.run(["git", "-C", p, "rev-parse", "--is-inside-work-tree"],
                           capture_output=True, text=True, timeout=10, env=git_env())
    except (OSError, subprocess.SubprocessError):
        return False
    return r.returncode == 0 and r.stdout.strip() == "true"


def guard_git(c):
    if inside_git(c.taste):
        die("taste: %s is inside a git work tree; the profile must stay outside every repository "
            "(set TASTE_HOME to a folder outside it)" % c.taste)


# ---------------------------------------------------------------- signals

def own_text(s):
    s = TAG_BLOCK.sub(" ", s)
    s = IMAGE.sub(" ", s)
    return s.strip()


def message_signals(raw, last_reply, rejected):
    """Signals from one owner message, and the rejection flag after it."""
    s = own_text(raw)
    if not s or s.startswith("<") or s.startswith("[Request interrupted"):
        return [], rejected
    flat = " ".join(s.split()).replace("\u2019", "'")
    if not rejected and len(flat) <= REACTION_MAX and REACTION.match(flat):
        return [("R", D.clean(flat, SENT_LIMIT), last_reply)], False
    sents = [" ".join(x.split()) for x in SENT_SPLIT.split(s)]
    sents = [x for x in sents if len(x) >= 8]
    ps = [x for x in sents if STRONG.search(x.replace("\u2019", "'"))][:MAX_P]
    if ps:
        return [("P", D.clean(x, SENT_LIMIT), "") for x in ps], False
    if rejected:
        return [("D", D.clean(flat, SENT_LIMIT), "")], False
    if D.is_correction(flat):
        return [("C", D.clean(flat, SENT_LIMIT), "")], False
    ts = [x for x in sents if TOPIC.search(x)][:MAX_T]
    return [("T", D.clean(x, SENT_LIMIT), "") for x in ts], False


def answer_signals(tur):
    labels = {}
    for q in tur.get("questions") or []:
        if isinstance(q, dict) and isinstance(q.get("question"), str):
            labels[q["question"]] = [o.get("label") for o in q.get("options") or [] if isinstance(o, dict)]
    out = []
    answers = tur.get("answers")
    if isinstance(answers, dict):
        for q, a in answers.items():
            qd = D.clean(str(q), 150)
            # "[User did not answer ...]" and similar are the client's placeholders, not an answer.
            picks = [p for p in (a if isinstance(a, list) else [a])
                     if isinstance(p, str) and p.strip() and not p.strip().startswith("[")]
            known = [p for p in picks if p in labels.get(q, [])]
            if known:
                rec = any("(recommended)" in p.lower() for p in known)
                names = ", ".join(re.sub(r"\s*\(recommended\)", "", p, flags=re.I).strip() for p in known)
                out.append(("A", "Q: %s -> %s%s" % (qd, names, " (recommended)" if rec else ""), ""))
            for p in picks:
                if p not in labels.get(q, []):
                    out.append(("O", "Q: %s -> own words: %s" % (qd, D.clean(p, 200)), ""))
    notes = tur.get("annotations")
    if isinstance(notes, dict):
        for q, v in notes.items():
            n = v.get("notes") if isinstance(v, dict) else None
            if isinstance(n, str) and n.strip():
                out.append(("O", "Q: %s -> note: %s" % (D.clean(str(q), 150), D.clean(n, 200)), ""))
    return out


def norm_text(s):
    return " ".join(s.lower().split())[:200]


def sig_key(kind, text, re_):
    return "%s\0%s\0%s" % (kind, norm_text(text), norm_text(re_)[:80] if kind == "R" else "")


def add_signal(pool, kind, text, re_, sess, proj, ts):
    key = sig_key(kind, text, re_)
    h = hashlib.sha1(key.encode("utf-8")).hexdigest()
    n = 6
    while True:
        sid = "t" + h[:n]
        e = pool.get(sid)
        if e is None or sig_key(e["kind"], e["text"], e.get("re", "")) == key:
            break
        n += 2
    if e is None:
        pool[sid] = {"kind": kind, "text": text, "re": re_, "sessions": [sess], "projects": [proj],
                     "first": ts, "last": ts, "at": [proj, sess], "n": 1, "shown": 0, "n_shown": 0}
        return
    e["n"] += 1
    if sess not in e["sessions"]:
        e["sessions"].append(sess)
    if proj not in e["projects"]:
        e["projects"].append(proj)
    if ts and (not e["first"] or ts < e["first"]):
        e["first"] = ts
    if ts >= (e["last"] or ""):
        e.update(last=ts, text=text, re=re_, at=[proj, sess])


def has_type(line, value):
    return (b'"type":"' + value + b'"') in line or (b'"type": "' + value + b'"') in line


def project_name(cwd, folder):
    """The repository a session belongs to: its start folder's name, with an
    app worktree (<repo>/.claude/worktrees/<name>) counted as its repository."""
    if isinstance(cwd, str) and cwd.strip():
        p = cwd.replace("\\", "/").rstrip("/")
        p = re.split(r"/\.claude/worktrees/", p, flags=re.I)[0]
        name = p.split("/")[-1]
        if name:
            return name
    return folder


def scan_transcripts(c, files, pool, stats):
    for pdir in c.projects:
        for path in sorted(glob.glob(os.path.join(pdir, "*", "*.jsonl"))):
            ent = files.setdefault(os.path.abspath(path), {"offset": 0})
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
            stats["read"] += 1
            folder = os.path.basename(os.path.dirname(path))
            stem = os.path.splitext(os.path.basename(path))[0]
            last_reply, rejected, hit = "", False, False
            with open(path, "rb") as f:
                f.seek(off)
                for line in f:
                    if not line.endswith(b"\n"):
                        break
                    off += len(line)
                    stats["lines"] += 1
                    asst = has_type(line, b"assistant") and has_type(line, b"text")
                    if not (has_type(line, b"user") or asst or b"queued_command" in line):
                        continue
                    try:
                        obj = json.loads(line.decode("utf-8", errors="replace"))
                    except ValueError:
                        stats["bad"] += 1
                        continue
                    if not isinstance(obj, dict) or obj.get("isSidechain"):
                        continue
                    if obj.get("isMeta") or obj.get("isCompactSummary") or obj.get("isVisibleInTranscriptOnly"):
                        continue
                    if not ent.get("project") and isinstance(obj.get("cwd"), str) and obj["cwd"].strip():
                        # A session moves between subfolders; it belongs to the folder it started in.
                        ent["project"] = project_name(obj["cwd"], folder)
                    t = obj.get("type")
                    msg = obj.get("message")
                    content = msg.get("content") if isinstance(msg, dict) else None
                    if t == "assistant":
                        tx = " ".join(D.texts(content)).strip()
                        if tx:
                            last_reply = D.clean(tx, RE_LIMIT)
                        continue
                    sigs = []
                    if t == "attachment":
                        att = obj.get("attachment")
                        p = att.get("prompt") if isinstance(att, dict) and att.get("type") == "queued_command" else None
                        if isinstance(p, str) and D.is_human(att, p):
                            got, rejected = message_signals(p, last_reply, rejected)
                            sigs += got
                    elif t == "user":
                        tur = obj.get("toolUseResult")
                        if isinstance(tur, dict) and "answers" in tur:
                            sigs += answer_signals(tur)
                        if obj.get("toolDenialKind") == "user-rejected":
                            rejected = True
                        for i in content if isinstance(content, list) else []:
                            if isinstance(i, dict) and i.get("type") == "tool_result" and i.get("is_error"):
                                s = " ".join(D.texts(i.get("content")))
                                if "the user said:" in s:
                                    why = s.split("the user said:", 1)[1].strip()
                                    if why:
                                        sigs.append(("D", D.clean(why, SENT_LIMIT), ""))
                                elif "doesn't want to proceed" in s:
                                    rejected = True
                        for s in D.texts(content):
                            if D.is_human(obj, s):
                                got, rejected = message_signals(s, last_reply, rejected)
                                sigs += got
                    if sigs:
                        hit = True
                        proj = ent.get("project") or project_name(obj.get("cwd"), folder)
                        sess = str(obj.get("sessionId") or stem)[:8]
                        ts = str(obj.get("timestamp") or "")
                        for kind, text, re_ in sigs:
                            add_signal(pool, kind, text, re_, sess, proj, ts)
            ent["offset"] = off
            if hit:
                stats["hits"] += 1


def scan_notes(c, memory, pool, stats):
    for pdir in c.projects:
        for path in sorted(glob.glob(os.path.join(pdir, "*", "memory", "*.md"))):
            if os.path.basename(path).lower() == "memory.md":
                continue
            try:
                with open(path, "rb") as f:
                    raw = f.read()
            except OSError:
                continue
            h = hashlib.sha1(raw).hexdigest()
            key = os.path.abspath(path)
            if memory.get(key) == h:
                continue
            memory[key] = h
            m = re.match(r"---\r?\n(.*?)\r?\n---\r?\n?(.*)$", raw.decode("utf-8", errors="replace"), re.S)
            if not m:
                continue
            fm, body = m.groups()
            if not re.search(r"(?m)^\s*type:\s*['\"]?(feedback|user)['\"]?\s*$", fm):
                continue
            dm = re.search(r"(?m)^description:\s*(.+?)\s*$", fm)
            desc = dm.group(1).strip("'\"") if dm else ""
            text = D.clean((desc + " - " if desc else "") + " ".join(body.split()), SENT_LIMIT)
            sm = re.search(r"(?m)^\s*originSessionId:\s*(\S+)", fm)
            tm = re.search(r"(?m)^\s*modified:\s*(\S+)", fm)
            ts = tm.group(1).strip("'\"") if tm else D.iso(
                dt.datetime.fromtimestamp(os.path.getmtime(path), dt.timezone.utc))
            folder = os.path.basename(os.path.dirname(os.path.dirname(path)))
            add_signal(pool, "F", text, "", sm.group(1)[:8] if sm else "memory", folder, ts)
            stats["notes"] += 1


def fresh(e):
    return e.get("shown", 0) == 0 or e.get("n", 0) > e.get("n_shown", 0)


def render(sid, e):
    parts = []
    if e["n"] > 1:
        parts.append("x%d" % e["n"])
    if len(e["sessions"]) > 1:
        parts.append("%d sessions" % len(e["sessions"]))
    if len(e["projects"]) > 1:
        parts.append("%d projects" % len(e["projects"]))
    suffix = " (%s)" % ", ".join(parts) if parts else ""
    ctx = " re: " + e["re"] if e.get("re") else ""
    proj, sess = e["at"]
    return "- %s [%s] %s %s %s: %s%s%s" % (sid, e["kind"], (e["last"] or "")[:10], proj, sess,
                                            e["text"], suffix, ctx)


def ordered(items):
    out = sorted(items, key=lambda x: x[1]["last"] or "", reverse=True)
    out.sort(key=lambda x: PRIORITY[x[1]["kind"]])  # stable: newest first inside a kind group
    return out


# ---------------------------------------------------------------- profile

def area_meta(area):
    for slug, title, purpose in AREAS:
        if slug == area:
            return title, purpose
    return area.replace("-", " ").capitalize(), "Learned preferences: %s." % area.replace("-", " ")


def area_order(areas):
    known = [a for a, _, _ in AREAS if a in areas]
    return known + sorted(a for a in areas if a not in known)


def load_profile(c):
    prof = {}
    for p in glob.glob(os.path.join(c.taste, "*.md")):
        with open(p, encoding="utf-8", errors="replace") as f:
            prof[os.path.splitext(os.path.basename(p))[0]] = f.read().splitlines()
    return prof


def items(lines):
    return [line for line in lines if line.startswith("- ")]


def profile_ids(prof):
    ids = []
    for area, lines in prof.items():
        for i, line in enumerate(lines):
            m = ID_LINE.match(line)
            if m:
                ids.append((m.group(1), area, i))
    return ids


def profile_bytes(prof):
    return sum(len(("\n".join(lines) + "\n").encode("utf-8")) for lines in prof.values())


def next_id(prof, ledger):
    top = max([int(t[1:]) for t, _, _ in profile_ids(prof)] or [0])
    return max(ledger.get("next_id", 1), top + 1)


def cap_problems(prof):
    probs = []
    for area in area_order(prof):
        for i, line in enumerate(prof[area], 1):
            if line.startswith("- "):
                m = ID_LINE.match(line)
                text = m.group(2) if m else line[2:]
                if len(text) > LINE_MAX:
                    probs.append("taste: %s.md:%d: line is %d characters (max %d characters)"
                                 % (area, i, len(text), LINE_MAX))
    total = profile_bytes(prof)
    if total > PROFILE_MAX:
        probs.append("taste: the profile is %d bytes (max %d); merge or remove lines" % (total, PROFILE_MAX))
    return probs


def import_block(prof):
    return BEGIN + "\n" + "".join("@taste/%s.md\n" % a for a in area_order(prof)) + END + "\n"


def codex_block(prof):
    body = "\n\n".join("\n".join(prof[a]).rstrip("\n") for a in area_order(prof))
    return BEGIN + "\n# Personal taste profile\n\n" + (body + "\n" if body else "") + END + "\n"


def with_block(path, block):
    """The file's text with the managed block replaced or appended, and its old text (None if absent)."""
    try:
        with open(path, encoding="utf-8", newline="") as f:
            old = f.read()
    except FileNotFoundError:
        return block, None
    b, e = old.count(BEGIN_KEY), old.count(END)
    if b == 0 and e == 0:
        if not old:
            return block, old
        return old + ("" if old.endswith("\n") else "\n") + "\n" + block, old
    if b != 1 or e != 1 or old.index(END) < old.index(BEGIN_KEY):
        die("taste: %s has a broken taste block (%d begin, %d end markers); fix it by hand" % (path, b, e))
    i = old.index(BEGIN_KEY)
    j = old.index(END, i) + len(END)
    if old.startswith("\r\n", j):
        j += 2
    elif old.startswith("\n", j):
        j += 1
    return old[:i] + block + old[j:], old


def write_text(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8", newline="") as f:
        f.write(text)
    os.replace(tmp, path)


def sync_blocks(c, prof):
    changed = []
    for path, block in ((c.claude_md, import_block(prof)), (c.codex_md, codex_block(prof))):
        new, old = with_block(path, block)
        if new != old:
            write_text(path, new)
            changed.append(path)
    return changed


def write_profile(c, before, after):
    for area in set(before) | set(after):
        path = os.path.join(c.taste, area + ".md")
        if area not in after:
            if os.path.exists(path):
                os.remove(path)
        elif after[area] != before.get(area):
            write_text(path, "\n".join(after[area]) + "\n")


# ---------------------------------------------------------------- impact and outcome

VERB = {"add": "added", "revise": "revised", "remove": "removed"}


def change_text(h):
    return "%s %s (%s)" % (h["id"], VERB[h["op"]], h["area"])


def kind_counts(entries):
    out = {}
    for _, e in entries:
        out[e["kind"]] = out.get(e["kind"], 0) + 1
    return out


def snapshot(prof):
    return {"lines": sum(len(items(v)) for v in prof.values()), "bytes": profile_bytes(prof),
            "areas": len(prof)}


def impact_lines(state, ledger, prof, new):
    """What changed since the last pass, from data already kept; candidates only, the agent judges."""
    out = ["", "## Impact since the last pass"]
    hist = ledger["history"][state.get("history_seen", 0):]
    out.append("profile changes: " + ("; ".join(change_text(h) for h in hist) if hist
                                      else "none since the last pass"))
    ids = {t for t, _, _ in profile_ids(prof)}
    again = {}
    for sid, tids in ledger["used"].items():
        e, base = state["pool"].get(sid), ledger["seen"].get(sid)
        if e and base is not None and e["n"] > base:
            for t in tids:
                if t in ids:
                    again.setdefault(t, []).append("%s +%d" % (sid, e["n"] - base))
    for t in sorted(again):
        out.append("%s seen again since applied: %s" % (t, ", ".join(again[t])))
    for t, area, i in sorted(profile_ids(prof)):
        w = D.words(ID_LINE.match(prof[area][i]).group(2))
        hits = []
        for sid, e in new:
            common = w & D.words(e["text"])
            if len(common) >= 2:
                hits.append("%s (%s)" % (sid, " ".join(sorted(common))))
        if hits:
            out.append("%s shares words with %s" % (t, ", ".join(hits[:3])))
    out.append("trend, fresh signals by kind per pass:")
    for p in state.get("passes", [])[-10:]:
        out.append("  %s: %s" % (p["date"][:10], D.fmt_counts(p["counts"], KIND_ORDER)))
    out.append("  this pass: %s" % D.fmt_counts(kind_counts(new), KIND_ORDER))
    return out


def outcome_text(c, report, ledger, before):
    props = parse_report(report)
    rid = os.path.basename(report)
    applied = sorted(int(k.rsplit("#", 1)[1]) for k in ledger["applied"] if k.rsplit("#", 1)[0] == rid)
    declined = sorted(n for n in props if n not in applied)
    hist = [h for h in ledger["history"] if h.get("report") == rid]
    files = sorted({os.path.join(c.taste, h["area"] + ".md") for h in hist})
    after = snapshot(load_profile(c))
    before = before or {}
    return "\n".join([
        "", "## Outcome %s" % c.now.strftime("%Y-%m-%d"),
        "Applied: %s" % (", ".join(map(str, applied)) or "none"),
        "Declined: %s" % (", ".join(map(str, declined)) or "none"),
        "Changes: %s" % ("; ".join(change_text(h) for h in hist) or "none"),
        "Files: %s" % (", ".join(files) or "none"),
        "Profile: %s -> %d lines, %s -> %d of %d bytes, %s -> %d areas"
        % (before.get("lines", "?"), after["lines"], before.get("bytes", "?"), after["bytes"], PROFILE_MAX,
           before.get("areas", "?"), after["areas"]),
        ""])


# ---------------------------------------------------------------- commands

def cmd_digest(c, a):
    if a.max_bytes < D.MIN_BYTES:
        die("taste: --max-bytes must be at least %d (got %d)" % (D.MIN_BYTES, a.max_bytes))
    state = load_state(c)
    ledger = load_ledger(c)
    stats = {"read": 0, "lines": 0, "bad": 0, "hits": 0, "notes": 0}
    scan_transcripts(c, state["files"], state["pool"], stats)
    scan_notes(c, state["memory"], state["pool"], stats)
    pool, used = state["pool"], set(ledger["used"])
    cand = [(sid, e) for sid, e in pool.items() if sid not in used]
    new = ordered([x for x in cand if fresh(x[1])])
    old = ordered([x for x in cand if not fresh(x[1])])
    last = D.parse_iso(state["last_pass"] or "")
    reason = None
    if len(new) < a.min_signals:
        reason = "not enough new signal (%d fresh, need %d)" % (len(new), a.min_signals)
    elif last and not a.force and c.now - last < dt.timedelta(days=a.min_days):
        reason = "the last taste pass (%s) was under %d days ago" % (state["last_pass"][:10], a.min_days)
    nxt = c.sp("state.next.json")
    if reason:
        D.write_json(c.sp("state.json"), state)
        if os.path.exists(nxt):
            os.remove(nxt)
        print("taste: %s; %d fresh signals kept in the pool%s"
              % (reason, len(new), "; --force runs it now" if "days" in reason else ""))
        return 3

    kept_new, kept_old, used_b = [], [], 0
    full = False
    for group, kept in ((new, kept_new), (old, kept_old)):
        for sid, e in group:
            cost = len(render(sid, e).encode("utf-8")) + 1
            if used_b + cost > a.max_bytes and (kept_new or kept_old):
                full = True
                break
            used_b += cost
            kept.append((sid, e))
        if full:
            break
    dropped = len(new) + len(old) - len(kept_new) - len(kept_old)
    for sid, e in kept_new + kept_old:
        e["shown"] = e.get("shown", 0) + 1
        e["n_shown"] = e["n"]

    prof = load_profile(c)
    shown = kept_new + kept_old
    lines = [
        "# Taste digest",
        "generated: %s  sources: %s" % (D.iso(c.now), "; ".join(c.projects)),
        "since: %s" % (state["last_pass"] or "the first taste pass"),
        "transcripts: %d with signals of %d read; new lines read: %d; malformed: %d; notes read: %d"
        % (stats["hits"], stats["read"], stats["lines"], stats["bad"], stats["notes"]),
        "signals: %d fresh and %d earlier shown of %d unused in the pool; %d dropped by the %d byte cap"
        % (len(kept_new), len(kept_old), len(cand), dropped, a.max_bytes),
        "profile: %d of %d bytes; next id T%03d" % (profile_bytes(prof), PROFILE_MAX, next_id(prof, ledger)),
    ] + impact_lines(state, ledger, prof, new) + [
        "",
        "## Fresh signals",
        KINDS,
    ] + [render(sid, e) for sid, e in kept_new]
    if kept_old:
        lines += ["", "## Earlier signals, not yet used"] + [render(sid, e) for sid, e in kept_old]
    D.ensure_dir(c.state_dir)
    dpath = c.sp("digest.md")
    with open(dpath, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")
    state["history_seen"] = len(ledger["history"])
    state["this_pass"] = {"date": D.iso(c.now), "counts": kind_counts(new)}
    state["snapshot"] = snapshot(prof)
    D.write_json(nxt, state)
    report = os.path.join(c.state_dir, "reports", "%s-report.md" % c.now.strftime("%Y-%m-%d"))
    print("taste: digest %s: %d signals (%d fresh, %d earlier) from %d sessions in %d projects; "
          "%d bytes; %d new lines read; %d dropped by the cap"
          % (dpath, len(shown), len(kept_new), len(kept_old),
             len({s for _, e in shown for s in e["sessions"]}),
             len({p for _, e in shown for p in e["projects"]}),
             os.path.getsize(dpath), stats["lines"], dropped))
    print("taste: save the agent's report as %s" % report)
    return 0


def cmd_done(c, a):
    nxt = c.sp("state.next.json")
    if not os.path.isfile(nxt):
        die("taste: run digest first")
    s = load_state(c, "state.next.json")
    used = set(load_ledger(c)["used"])
    cutoff = c.now - dt.timedelta(days=PRUNE_DAYS)
    gone = []
    for sid, e in s["pool"].items():
        last = D.parse_iso(e.get("last") or "")
        if e.get("shown", 0) and not fresh(e) and sid not in used and last and last < cutoff:
            gone.append(sid)
    for sid in gone:
        del s["pool"][sid]
    s["last_pass"] = D.iso(c.now)
    if s.get("this_pass"):
        s["passes"] = (s["passes"] + [s["this_pass"]])[-10:]
    s.pop("this_pass", None)
    before = s.pop("snapshot", None)
    if a.report:
        text = outcome_text(c, a.report, load_ledger(c), before)
        with open(a.report, "a", encoding="utf-8", newline="\n") as f:
            f.write(text)
        print("taste: outcome appended to %s" % a.report)
    D.write_json(c.sp("state.json"), s)
    os.remove(nxt)
    print("taste: done (pool %d signals, %d pruned); the next pass reads transcripts after this point"
          % (len(s["pool"]), len(gone)))
    return 0


def parse_report(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            lines = f.read().splitlines()
    except OSError as e:
        die("taste: cannot read the report %s: %s" % (path, e))
    props, cur, inside = {}, None, False
    for line in lines:
        if line.startswith("## "):
            inside = line.strip().lower() == "## proposals"
            cur = None
            continue
        if not inside:
            continue
        m = ITEM.match(line)
        if m:
            head = m.group(2)
            cur = {"head": head, "evidence": []}
            ma, mr, mx = ADD.match(head), REVISE.match(head), REMOVE.match(head)
            if ma:
                cur.update(op="add", area=ma.group(1), text=ma.group(2).strip())
            elif mr:
                cur.update(op="revise", id=mr.group(1), area=mr.group(2), text=mr.group(3).strip())
            elif mx:
                cur.update(op="remove", id=mx.group(1))
            else:
                cur["op"] = None
            props[int(m.group(1))] = cur
        elif cur is not None and line[:1] in (" ", "\t"):
            ev = re.match(r"\s+Evidence:\s*(.*)$", line)
            if ev:
                cur["evidence"] += SIG_ID.findall(ev.group(1))
    return props


def evidence_problem(num, p, pool):
    ids = p["evidence"]
    missing = [i for i in ids if i not in pool]
    if missing:
        return "taste: proposal %d cites signals not in the pool: %s" % (num, ", ".join(missing))
    if p["op"] == "remove":
        return None
    if not ids:
        return "taste: proposal %d cites no evidence" % num
    es = [pool[i] for i in ids]
    if any(e["kind"] in EXPLICIT for e in es):
        return None
    sessions = {s for e in es if e["kind"] != "F" for s in e["sessions"]}
    if len(sessions) < 2:
        return ("taste: proposal %d is an inferred preference; it needs signals from two or more sessions "
                "(cited: %d) or one stated preference" % (num, len(sessions)))
    return None


def cmd_apply(c, a):
    guard_git(c)
    ledger = load_ledger(c)
    pool = pending_or_state(c)["pool"]
    props = parse_report(a.report)
    rid = os.path.basename(a.report)
    before = load_profile(c)
    prof = {k: list(v) for k, v in before.items()}
    nid = next_id(prof, ledger)
    problems, notes, uses, done_keys, hist = [], [], {}, [], []
    for num in a.numbers:
        key = "%s#%d" % (rid, num)
        p = props.get(num)
        if p is None:
            problems.append("taste: the report has no proposal %d" % num)
            continue
        if key in ledger["applied"]:
            notes.append("taste: proposal %d of %s already applied" % (num, rid))
            continue
        if not p["op"]:
            problems.append("taste: proposal %d is malformed: %s (expected 'add <area>: <line>', "
                            "'revise Tnnn <area>: <line>' or 'remove Tnnn: <reason>')" % (num, p["head"]))
            continue
        why = evidence_problem(num, p, pool)
        if why:
            problems.append(why)
            continue
        where = {t: (ar, i) for t, ar, i in profile_ids(prof)}
        if p["op"] in ("revise", "remove") and p["id"] not in where:
            problems.append("taste: proposal %d: %s is not in the profile" % (num, p["id"]))
            continue
        if p["op"] == "revise" and where[p["id"]][0] == p["area"]:
            ar, i = where[p["id"]]
            prof[ar][i] = "- [%s] %s" % (p["id"], p["text"])
            notes.append("taste: %s revised in %s" % (p["id"], ar))
            hist.append({"report": rid, "num": num, "op": "revise", "id": p["id"], "area": ar})
            for sid in p["evidence"]:
                uses.setdefault(sid, set()).add(p["id"])
            done_keys.append(key)
            continue
        if p["op"] in ("revise", "remove"):
            ar, i = where[p["id"]]
            del prof[ar][i]
            if not items(prof[ar]):
                del prof[ar]
        if p["op"] == "remove":
            notes.append("taste: %s removed" % p["id"])
            hist.append({"report": rid, "num": num, "op": "remove", "id": p["id"], "area": ar})
        else:
            tid = p["id"] if p["op"] == "revise" else "T%03d" % nid
            if p["op"] == "add":
                nid += 1
            if p["area"] not in prof:
                title, purpose = area_meta(p["area"])
                prof[p["area"]] = ["# " + title, purpose, ""]
            prof[p["area"]].append("- [%s] %s" % (tid, p["text"]))
            notes.append("taste: %s %s in %s" % (tid, "added" if p["op"] == "add" else "revised", p["area"]))
            hist.append({"report": rid, "num": num, "op": p["op"], "id": tid, "area": p["area"]})
            for sid in p["evidence"]:
                uses.setdefault(sid, set()).add(tid)
        done_keys.append(key)
    problems += cap_problems(prof) if done_keys else []
    if problems:
        for m in problems:
            print(m, file=sys.stderr)
        print("taste: nothing written", file=sys.stderr)
        return 1
    if done_keys:
        write_profile(c, before, prof)
        for sid, tids in uses.items():
            ledger["used"][sid] = sorted(set(ledger["used"].get(sid, [])) | tids)
        ledger["next_id"] = nid
        ledger["applied"] += done_keys
        ledger["history"] += [dict(h, date=D.iso(c.now)) for h in hist]
        for sid in uses:
            ledger["seen"][sid] = pool[sid]["n"]
        D.write_json(c.sp("ledger.json"), ledger)
        sync_blocks(c, prof)
    for m in notes:
        print(m)
    print("taste: profile %d of %d bytes in %d areas; imports in %s; Codex copy in %s"
          % (profile_bytes(prof), PROFILE_MAX, len(prof), c.claude_md, c.codex_md))
    return 0


def cmd_sync(c, a):
    guard_git(c)
    prof = load_profile(c)
    probs = cap_problems(prof)
    if probs:
        for m in probs:
            print(m, file=sys.stderr)
        return 1
    changed = sync_blocks(c, prof)
    print("taste: synced %d areas (%s)" % (len(prof), ", ".join(changed) if changed else "already current"))
    return 0


def cmd_check(c, a):
    problems = []
    load_state(c)
    load_ledger(c)
    if inside_git(c.taste):
        problems.append("taste: %s is inside a git work tree; the profile must stay outside every repository"
                        % c.taste)
    prof = load_profile(c)
    problems += cap_problems(prof)
    seen = {}
    for t, area, i in profile_ids(prof):
        if t in seen:
            problems.append("taste: %s appears twice (%s.md and %s.md)" % (t, seen[t], area))
        seen[t] = area
    for path, block in ((c.claude_md, import_block(prof)), (c.codex_md, codex_block(prof))):
        try:
            with open(path, encoding="utf-8", newline="") as f:
                current = f.read()
        except FileNotFoundError:
            current = ""
        if not prof and BEGIN_KEY not in current:
            continue  # no profile yet and no block: nothing to keep current
        if block not in current:
            problems.append("taste: %s: the taste block is out of date; run scripts/dream.sh taste sync" % path)
    if problems:
        for m in problems:
            print(m)
        return 1
    n = sum(len(items(v)) for v in prof.values())
    print("taste: OK (%d lines in %d areas, %d of %d bytes)" % (n, len(prof), profile_bytes(prof), PROFILE_MAX))
    return 0


def main():
    ap = argparse.ArgumentParser(prog="dream.sh taste", description=__doc__.split("\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    d = sub.add_parser("digest")
    d.add_argument("--projects-dir", action="append", default=[])
    d.add_argument("--max-bytes", type=int, default=40000)
    d.add_argument("--min-signals", type=int, default=5)
    d.add_argument("--min-days", type=int, default=7)
    d.add_argument("--force", action="store_true")
    dn = sub.add_parser("done")
    dn.add_argument("--report", help="append the outcome of this pass to the report")
    p = sub.add_parser("apply")
    p.add_argument("--report", required=True)
    p.add_argument("numbers", nargs="+", type=int)
    sub.add_parser("check")
    sub.add_parser("sync")
    a = ap.parse_args()
    c = Ctx(a)
    sys.exit({"digest": cmd_digest, "done": cmd_done, "apply": cmd_apply,
              "check": cmd_check, "sync": cmd_sync}[a.cmd](c, a))


if __name__ == "__main__":
    main()
