"""taste.py - learn the owner's tastes from this project's own sessions, as
rows in the project's preference registers the owner approves line by line.

Purpose: the taste pass of a dream (docs/procedures/dream.md). A model-free
digest reduces this project's Claude Code transcripts and Codex sessions, and
the feedback notes in this project's auto-memory, to the owner's own
preference signals; a read-only agent proposes numbered register lines from
it; "apply" writes only the numbers the owner approved, through the one
register writer (preferences.write_rows).

Inputs: <projects>/<dir>/<session>.jsonl (top level only) under the default
projects folder and every --projects-dir, kept only when the session's first
cwd is this project (the root, its worktrees, the roots the project dream
remembers, this pass's own remembered roots and every --match path, matched
as dream.py matches them); <projects>/<main checkout slug>/memory/*.md notes
whose type is feedback or user (dream.memory_dir); this project's interactive
Codex threads through dream.codex_records (CODEX_HOME sessions, ADR 0014). A
message counts only when dream.is_human says it holds the owner's own words.
Outputs:
  <main checkout>/.work/dream/taste/   state.json (offsets, notes read, the
      evidence pool, known roots, last pass), state.next.json (pending until
      done), ledger.json (used signals, applied report numbers, the highest
      register number written per file), digest.md, reports/. The folder is
      gitignored and holds this computer's transcripts only.
  <root>/docs/preferences/<area>.md   rows written by apply: ID, the rule, a
      Source (the signal's date and the owner's quoted words from a cited P or
      O signal, else "YYYY-MM-DD: inferred from sessions <ids>"), Check Review.
Nothing is written under the home folder: not ~/.claude/taste, ~/.claude/CLAUDE.md
or ~/.codex/AGENTS.md. The default projects folder is DREAM_PROJECTS_DIR or
~/.claude/projects. DREAM_NOW pins "now".
Signal kinds: P stated preference, O own words in a question answer,
C correction, D a rejected action and the owner's next message, A a picked
option, R a short reaction with the reply it answers, T a taste-topic
sentence, F an auto-memory feedback or user note (model-written, so it never
counts as a session of evidence). Ids are "t" plus hex of a hash of the kind
and text, so the same signal keeps its id in every run.
Report format: "## Proposals", then "N. add <area>: <line>", "N. revise <area>
<ID>: <line>" or "N. remove <area> <ID>: <reason>", each with an indented
"Evidence:" line of signal ids.
Evidence rule (apply): a proposal cites a P or O signal, or non-F signals
from two or more sessions. Cap: a rule holds at most 160 characters. An add
whose rule text already exists in any register adds no row but counts as
applied. Apply refuses in template mode (no .start-done).
Profile size: the digest's "profile:" line is the registers' session-start
print (scripts/session-context.sh) against its 4000-byte cap, computed as the
header line per area plus " ID rule" per row; approximate, the reader decides.
Exit codes: 0 ok; 1 refused (validation, evidence, template mode, register
check problems); 2 usage, or a state or ledger of a newer format; 3 the digest
stopped early (too few fresh signals, or under --min-days since the last
pass), after saving what it read to the pool.
Dependencies: Python 3 standard library, git (worktrees, main checkout),
dream.py and preferences.py beside this file. Assumption: a transcript line is
complete only when it ends in a newline.
"""
import argparse
import datetime as dt
import glob
import hashlib
import json
import os
import re
import sys
from types import SimpleNamespace

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
import dream as D  # noqa: E402  (shared helpers; the folder is not on sys.path under -I)
import preferences as P  # noqa: E402  (the register writer and check)

FORMAT = 2
LINE_MAX = 160
PRINT_CAP = 4000
PRUNE_DAYS = 180
SENT_LIMIT = 300
RE_LIMIT = 160
REACTION_MAX = 120
CWD_SCAN_LINES = 200
MAX_P, MAX_T = 8, 3
PRIORITY = {"P": 0, "O": 0, "C": 1, "D": 1, "A": 2, "R": 2, "T": 3, "F": 3}
EXPLICIT = ("P", "O")
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
AREA = r"[a-z][a-z0-9-]{0,23}"
RULE_ID = r"\S+?-\d+"
ITEM = re.compile(r"^(\d+)\.\s+(.*\S)\s*$")
ADD = re.compile(r"^add\s+(%s):\s+(.+)$" % AREA)
REVISE = re.compile(r"^revise\s+(%s)\s+(%s):\s+(.+)$" % (AREA, RULE_ID))
REMOVE = re.compile(r"^remove\s+(%s)\s+(%s)(:.*)?$" % (AREA, RULE_ID))
SIG_ID = re.compile(r"\bt[0-9a-f]{6,12}\b")
CWD_RE = re.compile(rb'"cwd":\s*("(?:[^"\\]|\\.)*")')


def die(msg, code=2):
    print(msg, file=sys.stderr)
    sys.exit(code)


class Ctx:
    def __init__(self, a):
        here = os.path.dirname(os.path.realpath(__file__))
        self.root = os.path.realpath(a.root) if a.root else os.path.dirname(os.path.dirname(here))
        self.main = D.main_worktree(self.root)
        self.state_dir = os.path.join(self.main, ".work", "dream", "taste")
        default = os.environ.get("DREAM_PROJECTS_DIR") or os.path.join(os.path.expanduser("~"), ".claude", "projects")
        self.projects = []
        for p in [default] + list(getattr(a, "projects_dir", None) or []):
            p = os.path.abspath(p)
            if p not in self.projects:
                self.projects.append(p)
        self.match = [D.norm(os.path.abspath(m)) for m in getattr(a, "match", None) or []]
        self.now = D.now_utc()

    def sp(self, name):
        return os.path.join(self.state_dir, name)

    def dream_roots(self):
        """Roots the project dream remembers (its state.json), if it has any."""
        try:
            with open(os.path.join(self.main, ".work", "dream", "state.json"), encoding="utf-8") as f:
                roots = json.load(f).get("known_roots", [])
        except (OSError, ValueError, AttributeError):
            return []
        return [D.norm(r) for r in roots if isinstance(r, str)]


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
                                  "passes": list, "history_seen": 0, "known_roots": list})


def load_ledger(c):
    return load_json(c.sp("ledger.json"), {"used": dict, "applied": list, "history": list,
                                           "seen": dict, "high": dict})


def pending_or_state(c):
    nxt = c.sp("state.next.json")
    return load_state(c, "state.next.json") if os.path.isfile(nxt) else load_state(c)


def scope_roots(c, state):
    """This project's roots: the checkout, its worktrees, remembered roots, --match."""
    wts = D.Ctx.worktrees(SimpleNamespace(root=c.root))
    roots = {D.norm(c.root)} | set(wts) | set(state["known_roots"]) | set(c.dream_roots()) | set(c.match)
    # The same spellings the project dream accepts (a short ancestor such as
    # C:/Users/RUNNER~1 with a long rest), so both passes read the same sessions.
    return sorted(r for r in D.with_short_names(roots) if r), wts


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


def first_cwd(path):
    """The cwd of the first line that has one (a session belongs to the folder it started in)."""
    try:
        with open(path, "rb") as f:
            for n, line in enumerate(f):
                if n >= CWD_SCAN_LINES:
                    break
                m = CWD_RE.search(line)
                if m:
                    try:
                        v = json.loads(m.group(1).decode("utf-8", errors="replace"))
                    except ValueError:
                        continue
                    if isinstance(v, str) and v.strip():
                        return v
    except OSError:
        pass
    return None


def scan_transcripts(c, files, pool, stats, roots):
    for pdir in c.projects:
        for path in sorted(glob.glob(os.path.join(pdir, "*", "*.jsonl"))):
            key = os.path.abspath(path)
            ent = files.get(key)
            cwd = (ent or {}).get("cwd") or first_cwd(path)
            if not D.cwd_match(cwd, roots):
                continue  # another project's session: never read, never kept
            ent = files.setdefault(key, {"offset": 0})
            ent["cwd"] = cwd
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
    """Feedback and user notes from this project's auto-memory folder only."""
    for pdir in c.projects:
        mdir = D.memory_dir(SimpleNamespace(projects=pdir, root=c.root))
        for path in sorted(glob.glob(os.path.join(mdir, "*.md"))):
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

# ---------------------------------------------------------------- registers

def reg_rules(c):
    """[(area, ID, rule text)] of the project's registers, in file order."""
    out = []
    for key, text in D.register_rules(c.root):
        area, rid = key.split(":", 1)
        out.append((area, rid, text))
    return out


def print_bytes(rules):
    """Approximate size of the session-start print: a header line per area and
    " ID rule" per row, in bytes (scripts/session-context.sh is the reader)."""
    areas, total = [], 0
    for area, rid, text in rules:
        if area not in areas:
            areas.append(area)
            total += len(("[session-context] Preferences (%s):\n" % area).encode("utf-8"))
        total += len((" %s %s" % (rid, text)).encode("utf-8"))
    return total


def snapshot(c):
    r = reg_rules(c)
    return {"lines": len(r), "bytes": print_bytes(r), "areas": len({a for a, _, _ in r})}


def id_number(rid):
    _, n = P._id_parts(rid)
    return n or 0


# ---------------------------------------------------------------- impact and outcome

VERB = {"add": "added", "revise": "revised", "remove": "removed"}


def change_text(h):
    return "%s %s (%s)" % (h["id"], VERB[h["op"]], h["area"])


def kind_counts(entries):
    out = {}
    for _, e in entries:
        out[e["kind"]] = out.get(e["kind"], 0) + 1
    return out


def impact_lines(c, state, ledger, new):
    """What changed since the last pass, from data already kept; candidates only, the agent judges."""
    out = ["", "## Impact since the last pass"]
    hist = ledger["history"][state.get("history_seen", 0):]
    out.append("profile changes: " + ("; ".join(change_text(h) for h in hist) if hist
                                      else "none since the last pass"))
    rules = reg_rules(c)
    keys = {"%s:%s" % (a, i) for a, i, _ in rules}
    again = {}
    for sid, tids in ledger["used"].items():
        e, base = state["pool"].get(sid), ledger["seen"].get(sid)
        if e and base is not None and e["n"] > base:
            for t in tids:
                if t in keys:
                    again.setdefault(t, []).append("%s +%d" % (sid, e["n"] - base))
    for t in sorted(again):
        out.append("%s seen again since applied: %s" % (t, ", ".join(again[t])))
    for area, rid, text in sorted(rules):
        w = D.words(text)
        hits = []
        for sid, e in new:
            common = w & D.words(e["text"])
            if len(common) >= 2:
                hits.append("%s (%s)" % (sid, " ".join(sorted(common))))
        if hits:
            out.append("%s:%s shares words with %s" % (area, rid, ", ".join(hits[:3])))
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
    files = sorted({"docs/preferences/%s.md" % h["area"] for h in hist})
    after = snapshot(c)
    before = before or {}
    return "\n".join([
        "", "## Outcome %s" % c.now.strftime("%Y-%m-%d"),
        "Applied: %s" % (", ".join(map(str, applied)) or "none"),
        "Declined: %s" % (", ".join(map(str, declined)) or "none"),
        "Changes: %s" % ("; ".join(change_text(h) for h in hist) or "none"),
        "Files: %s" % (", ".join(files) or "none"),
        "Profile: %s -> %d rules, %s -> %d of %d bytes, %s -> %d areas"
        % (before.get("lines", "?"), after["lines"], before.get("bytes", "?"), after["bytes"], PRINT_CAP,
           before.get("areas", "?"), after["areas"]),
        ""])


# ---------------------------------------------------------------- commands

def scan_codex(c, files, pool, stats, roots):
    """Owner prompts of this project's Codex threads, through the same
    message_signals as a Claude transcript (the reader is dream.codex_records)."""
    cs = {"read": 0, "lines": 0, "bad": 0, "skipped": 0}
    last_reply, rejected, cur = "", False, None
    hits = set()
    for tid, ts, role, text in D.codex_records(c, files, roots, cs):
        if tid != cur:
            last_reply, rejected, cur = "", False, tid
        if role == "assistant":
            last_reply = D.clean(text, RE_LIMIT)
        elif role == "user":
            got, rejected = message_signals(text, last_reply, rejected)
            proj = project_name((files.get(D.CODEX_KEY + tid) or {}).get("cwd"), "codex")
            for kind, t, re_ in got:
                add_signal(pool, kind, t, re_, tid[:8], proj, ts)
                hits.add(tid)
    for k in ("read", "lines", "bad"):
        stats[k] += cs[k]
    stats["hits"] += len(hits)
    stats["skipped"] = stats.get("skipped", 0) + cs["skipped"]


def cmd_digest(c, a):
    if a.max_bytes < D.MIN_BYTES:
        die("taste: --max-bytes must be at least %d (got %d)" % (D.MIN_BYTES, a.max_bytes))
    state = load_state(c)
    ledger = load_ledger(c)
    roots, wts = scope_roots(c, state)
    state["known_roots"] = sorted(set(state["known_roots"]) | set(wts))
    stats = {"read": 0, "lines": 0, "bad": 0, "hits": 0, "notes": 0, "skipped": 0}
    scan_transcripts(c, state["files"], state["pool"], stats, roots)
    scan_codex(c, state["files"], state["pool"], stats, roots)
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

    snap = snapshot(c)
    shown = kept_new + kept_old
    lines = [
        "# Taste digest",
        "generated: %s  project: %s  sources: %s" % (D.iso(c.now), c.main, "; ".join(c.projects)),
        "since: %s" % (state["last_pass"] or "the first taste pass"),
        "transcripts: %d with signals of %d read; new lines read: %d; malformed: %d; notes read: %d"
        % (stats["hits"], stats["read"], stats["lines"], stats["bad"], stats["notes"]),
    ] + (["codex: %d compressed rollouts skipped (no zstd reader: install zstd or use Python 3.14)"
          % stats["skipped"]] if stats["skipped"] else []) + [
        "signals: %d fresh and %d earlier shown of %d unused in the pool; %d dropped by the %d byte cap"
        % (len(kept_new), len(kept_old), len(cand), dropped, a.max_bytes),
        "profile: %d of %d bytes in the session-start print; %d rules in %d areas"
        % (snap["bytes"], PRINT_CAP, snap["lines"], snap["areas"]),
    ] + impact_lines(c, state, ledger, new) + [
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
    state["snapshot"] = snap
    D.write_json(nxt, state)
    report = os.path.join(c.state_dir, "reports", "%s-report.md" % c.now.strftime("%Y-%m-%d"))
    print("taste: digest %s: %d signals (%d fresh, %d earlier) from %d sessions; "
          "%d bytes; %d new lines read; %d dropped by the cap"
          % (dpath, len(shown), len(kept_new), len(kept_old),
             len({s for _, e in shown for s in e["sessions"]}),
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
    props, cur, inside, part = {}, None, False, "head"
    for line in lines:
        if line.startswith("## "):
            inside = line.strip().lower() == "## proposals"
            cur = None
            continue
        if not inside:
            continue
        m = ITEM.match(line)
        if m:
            cur = {"head": m.group(2), "evidence": []}
            part = "head"
            num = int(m.group(1))
            if num in props:
                die("taste: %s numbers proposal %d twice; fix the report before applying" % (path, num))
            props[num] = cur
        elif cur is not None and line[:1] in (" ", "\t"):
            # An indented line continues the part above it: the head until the first
            # Evidence: or Why: line, then that part. A wrapped Evidence line adds its
            # signal ids; Why text is commentary and never reaches the rule.
            ev = re.match(r"\s+Evidence:\s*(.*)$", line)
            if ev:
                part = "evidence"
                cur["evidence"] += SIG_ID.findall(ev.group(1))
            elif re.match(r"\s+Why:", line):
                part = "why"
            elif not line.strip():
                continue
            elif part == "head":
                cur["head"] += " " + line.strip()
            elif part == "evidence":
                cur["evidence"] += SIG_ID.findall(line)
    for cur in props.values():
        head = cur["head"]
        ma, mr, mx = ADD.match(head), REVISE.match(head), REMOVE.match(head)
        if ma:
            cur.update(op="add", area=ma.group(1), text=ma.group(2).strip())
        elif mr:
            cur.update(op="revise", area=mr.group(1), id=mr.group(2), text=mr.group(3).strip())
        elif mx:
            cur.update(op="remove", area=mx.group(1), id=mx.group(2))
        else:
            cur["op"] = None
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


def owner_words(e):
    """The owner's own part of a P or O signal; an O signal also quotes the question."""
    t = e["text"]
    for marker in ("-> own words: ", "-> note: "):
        if marker in t:
            t = t.split(marker, 1)[1]
            break
    return " ".join(t.replace('"', "'").split())


def source_for(p, pool, now):
    """(date, owner words or None, source text) for the signals a proposal cites."""
    es = [pool[i] for i in p["evidence"]]
    explicit = [e for e in es if e["kind"] in EXPLICIT]
    if explicit:
        e = explicit[0]
        date = (e.get("last") or "")[:10] or now.strftime("%Y-%m-%d")
        words = owner_words(e)
        return date, words, '%s: "%s"' % (date, words)
    real = [e for e in es if e["kind"] != "F"]
    date = max([(e.get("last") or "")[:10] for e in real] or [""]) or now.strftime("%Y-%m-%d")
    sessions = sorted({s for e in real for s in e["sessions"]})
    inferred = "inferred from sessions %s" % ", ".join(sessions)
    return date, inferred, "%s: %s" % (date, inferred)


def snapshot_files(c, areas):
    """Bytes (or None when absent) of each register file an apply may touch."""
    out = {}
    for area in areas:
        path = os.path.join(c.root, "docs", "preferences", area + ".md")
        try:
            with open(path, "rb") as f:
                out[path] = f.read()
        except FileNotFoundError:
            out[path] = None
    return out


def restore_files(saved):
    for path, data in saved.items():
        if data is None:
            if os.path.exists(path):
                os.remove(path)
        else:
            with open(path, "wb") as f:
                f.write(data)


def cmd_apply(c, a):
    if not os.path.exists(os.path.join(c.root, ".start-done")):
        print("taste: template mode (no .start-done): register rows are written only in a started "
              "project; nothing written", file=sys.stderr)
        return 1
    ledger = load_ledger(c)
    pool = pending_or_state(c)["pool"]
    props = parse_report(a.report)
    rid = os.path.basename(a.report)
    problems, todo = [], []
    for i, num in enumerate(a.numbers):
        if num in a.numbers[:i]:
            problems.append("taste: proposal %d is approved twice" % num)
            continue
        key = "%s#%d" % (rid, num)
        p = props.get(num)
        if p is None:
            problems.append("taste: the report has no proposal %d" % num)
            continue
        if key in ledger["applied"]:
            print("taste: proposal %d of %s already applied" % (num, rid))
            continue
        if not p["op"]:
            problems.append("taste: proposal %d is malformed: %s (expected 'add <area>: <line>', "
                            "'revise <area> <ID>: <line>' or 'remove <area> <ID>: <reason>')" % (num, p["head"]))
            continue
        why = evidence_problem(num, p, pool)
        if why:
            problems.append(why)
            continue
        if p["op"] != "remove" and len(p["text"]) > LINE_MAX:
            problems.append("taste: proposal %d: the rule is %d characters (max %d characters)"
                            % (num, len(p["text"]), LINE_MAX))
            continue
        todo.append((num, key, p))
    if problems:
        for m in problems:
            print(m, file=sys.stderr)
        print("taste: nothing written", file=sys.stderr)
        return 1

    saved = snapshot_files(c, {p["area"] for _, _, p in todo})
    notes, uses, done_keys, hist = [], {}, [], []
    high = dict(ledger["high"])
    try:
        for num, key, p in todo:
            area = p["area"]
            warns = []
            if p["op"] == "add":
                date, _, source = source_for(p, pool, c.now)
                res = P.write_rows(c.root, area, [{"rule": p["text"], "source": source, "check": "Review"}],
                                   [], [], high.get(area, 0), warn=warns.append)
                if res["added"]:
                    tid = res["added"][0]
                    high[area] = max(high.get(area, 0), id_number(tid))
                    notes.append("taste: %s added in %s" % (tid, area))
                    hist.append({"report": rid, "num": num, "op": "add", "id": tid, "area": area})
                    use = "%s:%s" % (area, tid)
                else:
                    use = res["skipped"][0]["existing"]
                    notes.append("taste: proposal %d is already a rule (%s); no row added" % (num, use))
            elif p["op"] == "revise":
                date, words, _ = source_for(p, pool, c.now)
                P.write_rows(c.root, area, [], [{"id": p["id"], "rule": p["text"], "words": words, "date": date}],
                             [], high.get(area, 0), warn=warns.append)
                tid = p["id"]
                notes.append("taste: %s revised in %s" % (tid, area))
                hist.append({"report": rid, "num": num, "op": "revise", "id": tid, "area": area})
                use = "%s:%s" % (area, tid)
            else:
                P.write_rows(c.root, area, [], [], [{"id": p["id"]}], high.get(area, 0), warn=warns.append)
                # The removed number stays taken: a hand-written or ported top row
                # leaves no other trace, so a later add would get it again.
                high[area] = max(high.get(area, 0), id_number(p["id"]))
                notes.append("taste: %s removed from %s" % (p["id"], area))
                hist.append({"report": rid, "num": num, "op": "remove", "id": p["id"], "area": area})
                use = None
            notes += ["taste: warning: " + w for w in warns]
            if use:
                for sid in p["evidence"]:
                    uses.setdefault(sid, set()).add(use)
            done_keys.append(key)
    except P.PrefError as e:
        restore_files(saved)
        print("taste: %s" % e, file=sys.stderr)
        print("taste: nothing written", file=sys.stderr)
        return 1
    if done_keys:
        for sid, tids in uses.items():
            ledger["used"][sid] = sorted(set(ledger["used"].get(sid, [])) | tids)
            ledger["seen"][sid] = pool[sid]["n"]
        ledger["high"] = high
        ledger["applied"] += done_keys
        ledger["history"] += [dict(h, date=D.iso(c.now)) for h in hist]
        D.write_json(c.sp("ledger.json"), ledger)
    for m in notes:
        print(m)
    snap = snapshot(c)
    print("taste: %d rules in %d areas; %d of %d bytes in the session-start print"
          % (snap["lines"], snap["areas"], snap["bytes"], PRINT_CAP))
    return 0


def cmd_check(c, a):
    load_state(c)
    ledger = load_ledger(c)
    problems = []
    for area, n in ledger["high"].items():
        if not isinstance(n, int) or isinstance(n, bool) or n < 0:
            problems.append("taste: ledger.json: the highest number for %s is not a whole number" % area)
    if problems:
        for m in problems:
            print(m)
        return 1
    rc = P.main(["--root", c.root])
    if rc:
        return rc
    snap = snapshot(c)
    print("taste: OK (%d rules in %d areas, %d of %d bytes in the session-start print)"
          % (snap["lines"], snap["areas"], snap["bytes"], PRINT_CAP))
    return 0


def main():
    ap = argparse.ArgumentParser(prog="dream.sh taste", description=__doc__.split("\n")[0])
    ap.add_argument("--root", help="the project (default: the repository this script is in)")
    sub = ap.add_subparsers(dest="cmd", required=True)
    d = sub.add_parser("digest")
    d.add_argument("--projects-dir", action="append", default=[])
    d.add_argument("--match", action="append", default=[], help="count sessions started under this path")
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
    a = ap.parse_args()
    c = Ctx(a)
    sys.exit({"digest": cmd_digest, "done": cmd_done, "apply": cmd_apply,
              "check": cmd_check}[a.cmd](c, a))


if __name__ == "__main__":
    main()
