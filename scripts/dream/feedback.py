"""feedback.py - the UserPromptSubmit hook that logs the owner's own messages
with the situation they were sent in, so a dream can learn from them.

Purpose: scripts/feedback-log.sh runs this on every prompt. It appends one JSON
line per owner prompt to <main checkout>/.work/feedback/log.jsonl and prints at
most one context line (stdout becomes model context in Claude Code).
Inputs: the hook JSON on stdin (prompt, session_id, cwd, transcript_path); the
last 512 KB of the transcript; .work/TASK.md and the branch of this checkout.
Outputs: one log line with keys v, ts, session, branch, task, kind, text
(<= 2000), files (<= 5, newest first, repository-relative) and said (<= 300);
the folder holds a .gitignore of "*". The hook never rotates the log (only
`dream.sh done` does, after committing its offset), so no line is lost.
kind is a guess by word lists (classify), labelled as a guess in the context line.
Dependencies: Python 3 standard library, git (branch), dream.py beside this file
(is_human, is_correction, main_worktree, ensure_dir); dream.py never imports this.
Assumptions: every failure is swallowed, because a hook must never block or
delay a prompt; FEEDBACK_LOG=0 turns capture off.
"""
import datetime as dt
import json
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
import dream as D  # noqa: E402  (shared helpers; the folder is not on sys.path under -I)

TAIL_BYTES = 512 * 1024
TEXT_LIMIT = 2000
SAID_LIMIT = 300
FILES_MAX = 5
EDIT_TOOLS = {"Edit": "file_path", "Write": "file_path", "MultiEdit": "file_path",
              "NotebookEdit": "notebook_path"}

DEFERRAL = re.compile(
    r"\b(later|not now)\b|\bjust record\b|"
    r"\b(don't|do not)\s+(do|build|change|code)\b.*\b(yet|now|later)\b", re.I)
CORRECTION = re.compile(
    r"\b(wrong|hate|revert|undo|broke)\b|\bwhy did\b|\bnot what i\b|\bback to\b|"
    r"\bstill (not|wrong|broken)\b|\b(happened|doing it|is back) again\b", re.I)
PREFERENCE = re.compile(
    r"\b(always|never|from now on|i want|i prefer|i like|i don't like|make sure|every time)\b", re.I)
APPROVAL = re.compile(
    r"\b(perfect|exactly (right|what)|love (it|this|that)|looks (good|great)|"
    r"that's (it|great|perfect)|approved)\b", re.I)


def classify(text):
    """Guess the kind of an owner message; the first match wins."""
    t = " ".join(text.replace("\u2019", "'").split())
    if DEFERRAL.search(t):
        return "deferral"
    if re.match(r"^no,?\s+later\b", t, re.I):
        return "deferral"
    if D.is_correction(t) or CORRECTION.search(t):
        return "correction"
    if PREFERENCE.search(t):
        return "preference"
    if APPROVAL.search(t):
        return "approval"
    return "message"


def read_tail(path):
    """Complete lines from the last TAIL_BYTES of the transcript; [] on any problem."""
    try:
        with open(path, "rb") as f:
            size = f.seek(0, os.SEEK_END)
            start = max(0, size - TAIL_BYTES)
            f.seek(start)
            data = f.read()
    except (OSError, TypeError, ValueError):
        return []
    lines = data.split(b"\n")
    if start > 0:
        lines = lines[1:]  # the first line is cut mid-way
    return [ln for ln in lines if ln.strip()]


def rel_path(p, roots):
    if not isinstance(p, str) or not p:
        return None
    cands = {p.replace("\\", "/")}
    try:
        cands.add(os.path.realpath(p).replace("\\", "/"))
    except (OSError, ValueError):
        pass
    for c in cands:
        for r in roots:
            r = r.replace("\\", "/").rstrip("/")
            if c.lower().startswith(r.lower() + "/"):
                return c[len(r) + 1:]
    return None


def situation(lines, roots):
    """(files, said) from transcript lines: edited files newest first, and the
    last assistant text."""
    files, said = [], None
    for raw in reversed(lines):
        if len(files) >= FILES_MAX and said is not None:
            break
        try:
            obj = json.loads(raw)
        except ValueError:
            continue
        if not isinstance(obj, dict) or obj.get("type") != "assistant":
            continue
        msg = obj.get("message")
        content = msg.get("content") if isinstance(msg, dict) else None
        if not isinstance(content, list):
            continue
        for item in reversed(content):
            if not isinstance(item, dict):
                continue
            if item.get("type") == "text" and said is None and isinstance(item.get("text"), str):
                s = " ".join(item["text"].split())
                if s:
                    said = s[:SAID_LIMIT]
            elif item.get("type") == "tool_use" and item.get("name") in EDIT_TOOLS:
                inp = item.get("input")
                key = EDIT_TOOLS[item["name"]]
                p = rel_path(inp.get(key) if isinstance(inp, dict) else None, roots)
                if p and p not in files and len(files) < FILES_MAX:
                    files.append(p)
    return files, said or ""


def task_title(root):
    try:
        with open(os.path.join(root, ".work", "TASK.md"), encoding="utf-8") as f:
            first = f.readline().strip()
    except OSError:
        return "-"
    m = re.match(r"^#\s*Task:\s*(.*)$", first)
    title = m.group(1).strip() if m else ""
    if not title or "{{" in title:
        return "-"
    return title


def branch_of(root):
    # 1 s: the hook has a 5 s budget and a slow git must not push it past, which
    # would drop the line; "-" is the logged answer for a branch not known in time.
    try:
        r = subprocess.run(["git", "-C", root, "symbolic-ref", "--short", "HEAD"],
                           capture_output=True, text=True, timeout=1)
    except (OSError, subprocess.SubprocessError):
        return "-"
    return r.stdout.strip() if r.returncode == 0 and r.stdout.strip() else "-"


def append_line(folder, obj):
    D.ensure_dir(folder)
    data = (json.dumps(obj, ensure_ascii=False, separators=(",", ":")) + "\n").encode("utf-8")
    fd = os.open(os.path.join(folder, "log.jsonl"), os.O_WRONLY | os.O_APPEND | os.O_CREAT, 0o644)
    try:
        os.write(fd, data)
    finally:
        os.close(fd)


def run():
    if os.environ.get("FEEDBACK_LOG") == "0":
        return
    try:
        # Bytes, decoded as UTF-8: the hook JSON is UTF-8, and text-mode stdin uses
        # the locale code page on Windows, which garbles non-ASCII prompts.
        payload = json.loads(sys.stdin.buffer.read().decode("utf-8", "replace") or "null")
    except ValueError:
        return
    if not isinstance(payload, dict):
        return
    text = payload.get("prompt")
    if not isinstance(text, str):
        return
    text = text.strip()
    if not text or text.startswith(("/", "<")) or not D.is_human({}, text):
        return
    root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.realpath(__file__))))
    main = D.main_worktree(root)
    tp = payload.get("transcript_path")
    files, said = situation(read_tail(tp) if isinstance(tp, str) and tp else [],
                            [root] if main == root else [root, main])
    kind = classify(text)
    sid = payload.get("session_id")
    append_line(D.feedback_dir(root), {
        "v": 1,
        "ts": dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "session": sid[:8] if isinstance(sid, str) else "-",
        "branch": branch_of(root),
        "task": task_title(root),
        "kind": kind,
        "text": text[:TEXT_LIMIT],
        "files": files,
        "said": said,
    })
    if kind == "deferral":
        print("Owner deferral logged (script guess): if the owner put work off, record it as a note "
              "(BACKLOG.md or the plan) and do not start the work.")
    elif kind != "message":
        line = "Owner feedback logged (%s, script guess)." % kind
        if os.path.exists(os.path.join(root, ".start-done")):
            line += " If it states a lasting preference, follow docs/procedures/preferences.md."
        print(line)


def main():
    try:
        run()
    except Exception:  # noqa: BLE001  (a hook must never fail a prompt)
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
