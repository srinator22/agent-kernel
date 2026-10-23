#!/usr/bin/env python3
"""PreToolUse hook: refuse shell commands that feed Python from stdin or use a here-document.

Purpose: `python -` with an empty or missing stdin starts an interactive REPL under some shell wrappers
(Git Bash on Windows in particular) that hangs or loops and can fill a disk with log output, and quoted
here-documents break on apostrophes in the shell wrapper. Both recur across agents because the habit is strong,
so a written rule is not enough: this hook refuses the command before it runs and tells the agent to write the
script or text to a file with the file-writing tool and run it by path.

Optional rule (off by default): `--check-pcbnew-getwidth`, or the environment variable
HOOK_CHECK_PCBNEW_GETWIDTH=1. It belongs to projects that script KiCad. When the command runs a .py file that
imports pcbnew, the hook reads the file and refuses it if any line calls a bare `.GetWidth()` unless that same
line also calls GetWidth with a layer argument (for example
`v.GetWidth(L) if isinstance(v, PCB_VIA) else t.GetWidth()`) or ends with the comment `# track-only` (the
author's statement that no via reaches the call). A bare call on a via raises a modal debug dialog on the
desktop and hangs the run until someone clicks it. A file-level "names PCB_VIA somewhere" rule is too weak: it
misses a script that compares a class name and still calls the bare form on the via.

Inputs: the hook JSON on stdin, shaped {"tool_name": ..., "tool_input": {"command": ...}, "cwd": ...}.
Outputs: exit 0 lets the call run; exit 2 refuses it with the reason on stderr (the harness shows it to the
agent). Malformed JSON never refuses (exit 0). `--self-test` checks the patterns: 0 pass, 1 fail.
Dependencies: Python 3 standard library only.
Assumptions: the command text is the whole shell command the harness is about to run; a here-document or a lone
`-` argument to a python interpreter is never needed because a file can be written first.
Validation source: ported from a hook that refused these two patterns more than twenty times in practice; the
patterns and their self-test cases are kept as they were.
"""
import json
import os
import re
import sys
import tempfile

ENV_SWITCH = "HOOK_CHECK_PCBNEW_GETWIDTH"
FLAG_SWITCH = "--check-pcbnew-getwidth"

# python, python3, python3.12, py, with or without .exe or a path, then optional flags, then a lone "-".
PY_STDIN = re.compile(
    r"(?:^|[\s;&|(`/\\])(?:py|python[0-9.]*)(?:\.exe)?((?:\s+-[A-Za-z0-9]+)*)\s+-(?=\s|$|[;&|<)])")
# <<WORD, << 'WORD', <<-"WORD"; not the <<< here-string.
HEREDOC = re.compile(r"(?<!<)<<(?!<)-?\s*([\"']?)[A-Za-z_][A-Za-z0-9_]*\1")

REASON = (
    "Refused by the shell-stdin hook: {what}. "
    "Write the script or text to a file with the file-writing tool (a scratch folder is fine) and run "
    "`python path/to/script.py`; for a commit message use -F with a file written the same way.")

# Only the script a python interpreter is asked to run: python[.exe] (possibly quoted, with a path), optional
# flags, then the .py path. Reading or searching a script (cat, grep, sed) is not judged.
SCRIPT_PATH = re.compile(
    r"(?:py|python[0-9.]*)(?:\.exe)?[\"']?\s+(?:-[A-Za-z]+\s+)*"
    r"(?:\"([^\"]+?\.py)\"|'([^']+?\.py)'|([^\s\"';&|()<>]+?\.py))(?=$|[\s;&|)])")
CD_DIR = re.compile(r"(?:^|[;&|(]\s*)cd\s+(?:\"([^\"]+)\"|'([^']+)'|([^\s;&|]+))")
BARE_GETWIDTH = re.compile(r"\.GetWidth\(\s*\)")
LAYER_GETWIDTH = re.compile(r"\.GetWidth\(\s*[^\s)]")
TRACK_ONLY = re.compile(r"#\s*track-only\b")
# A real import statement, not the word: this hook's own file names pcbnew and GetWidth in its tests.
IMPORTS_PCBNEW = re.compile(r"^\s*(?:import\s+pcbnew\b|from\s+pcbnew\s+import\b)", re.MULTILINE)

VIA_REASON = (
    "Refused by the shell-stdin hook: {path} imports pcbnew and line {line} calls a bare .GetWidth(). "
    "On a via that raises a modal debug dialog on the desktop and hangs the run. Write it on one line as "
    "`w = t.GetWidth(pcbnew.F_Cu) if isinstance(t, pcbnew.PCB_VIA) else t.GetWidth()`, or end the line with "
    "`# track-only` if no via can reach it.")


def _script_paths(command: str, cwd: str):
    bases = [cwd] if cwd else []
    for m in CD_DIR.finditer(command):
        d = next(g for g in m.groups() if g)
        bases.append(d if os.path.isabs(d) else os.path.join(cwd or "", d))
    for m in SCRIPT_PATH.finditer(command):
        p = next(g for g in m.groups() if g)
        candidates = [p] if os.path.isabs(p) else [os.path.join(b, p) for b in bases] + [p]
        for c in candidates:
            if os.path.isfile(c):
                yield c
                break


def pcbnew_verdict(command: str, cwd: str = ""):
    """(path, line number) of the first bare GetWidth in a pcbnew script the command runs, else None."""
    for path in _script_paths(command, cwd):
        try:
            with open(path, encoding="utf-8", errors="replace") as fh:
                text = fh.read()
        except OSError:
            continue
        if not IMPORTS_PCBNEW.search(text):
            continue
        for number, line in enumerate(text.splitlines(), 1):
            if BARE_GETWIDTH.search(line) and not LAYER_GETWIDTH.search(line) and not TRACK_ONLY.search(line):
                return path, number
    return None


def verdict(command: str):
    """What is wrong with the command, or None when it may run."""
    if PY_STDIN.search(command):
        return "python reading its program from stdin (`python -`)"
    if HEREDOC.search(command):
        return "a shell here-document (<<WORD)"
    return None


def _pcbnew_self_test():
    """Scripts in a temporary folder: (file text, refuse?)."""
    cases = {
        "bad.py": ("import pcbnew\nfor t in b.GetTracks():\n    print(t.GetWidth())\n", True),
        "guarded.py": ("import pcbnew\nw = t.GetWidth(pcbnew.F_Cu) if isinstance(t, pcbnew.PCB_VIA) "
                       "else t.GetWidth()\n", False),
        "layer.py": ("import pcbnew\nprint(v.GetWidth(pcbnew.F_Cu))\n", False),
        "getclass.py": ("import pcbnew\nkind = 'via' if t.GetClass() == 'PCB_VIA' else 'track'\n"
                        "print(kind, t.GetWidth())\n", True),
        "trackonly.py": ("import pcbnew\nw = t.GetWidth()  # track-only\n", False),
        "nopcbnew.py": ("class A:\n    def GetWidth(self): return 1\nprint(A().GetWidth())\n", False),
    }
    wrong = []
    with tempfile.TemporaryDirectory() as d:
        os.makedirs(os.path.join(d, "sub"))
        for name, (text, _) in cases.items():
            with open(os.path.join(d, "sub", name), "w", encoding="utf-8") as fh:
                fh.write(text)
        for name, (_, refuse) in cases.items():
            forms = [f'"C:/Program Files/KiCad/bin/python.exe" sub/{name}',
                     f"cd sub && python {name} --x 1",
                     f"& 'C:\\KiCad\\bin\\python.exe' '{os.path.join(d, 'sub', name)}'"]
            for form in forms:
                if bool(pcbnew_verdict(form, d)) != refuse:
                    wrong.append(form)
        if pcbnew_verdict("python missing.py", d):
            wrong.append("python missing.py")
        # Reading or searching a script is not running it.
        for form in ("cat sub/bad.py", "grep -n GetWidth sub/bad.py", "sed -n 1,5p sub/bad.py | head",
                     "python tools/x.py --input sub/bad.py"):
            if pcbnew_verdict(form, d):
                wrong.append(form)
    # This hook's own file mentions pcbnew and GetWidth only inside strings: it must not refuse itself.
    if pcbnew_verdict(f'python "{os.path.abspath(__file__)}" --self-test', ""):
        wrong.append("the hook refuses its own file")
    return wrong


def self_test() -> int:
    refuse = [
        "python - <<'EOF'\nprint(1)\nEOF",
        "cd x && python -",
        "echo x | python3 -",
        "py -3 - < a.py",
        "/usr/bin/python3.12 -I -",
        "C:\\Python\\python.exe - ",
        "cat > f.py <<EOF\nx\nEOF",
        "cat <<-\"END\"\nx\nEND",
        "git commit -F - << 'MSG'\nm\nMSG",
    ]
    allow = [
        "python tools/check_thing.py",
        "python -c \"print(1)\"",
        "python -m pytest -q",
        "python -I script.py --x -",
        "grep -n x file | head -5",
        "cat <<< \"here string\"",
        "git log --oneline -3",
        "ls -la",
    ]
    bad = [c for c in refuse if not verdict(c)] + [c for c in allow if verdict(c)]
    bad += _pcbnew_self_test()
    for c in bad:
        print("WRONG:", repr(c))
    print("self-test:", "FAIL" if bad else "PASS",
          f"({len(refuse)} refuse, {len(allow)} allow, pcbnew rule cases)")
    return 1 if bad else 0


def pcbnew_rule_enabled(argv) -> bool:
    return FLAG_SWITCH in argv or os.environ.get(ENV_SWITCH, "").strip() not in ("", "0")


def main(argv=None) -> int:
    argv = list(sys.argv[1:] if argv is None else argv)
    if "--help" in argv or "-h" in argv:
        print(__doc__)
        return 0
    if "--self-test" in argv:
        return self_test()
    try:
        data = json.load(sys.stdin)
    except ValueError:
        return 0
    if not isinstance(data, dict):
        return 0
    tool_input = data.get("tool_input")
    command = (tool_input.get("command") if isinstance(tool_input, dict) else None) or ""
    if not isinstance(command, str):
        return 0
    what = verdict(command)
    if what:
        print(REASON.format(what=what), file=sys.stderr)
        return 2
    if pcbnew_rule_enabled(argv):
        found = pcbnew_verdict(command, data.get("cwd") or "")
        if found:
            print(VIA_REASON.format(path=found[0], line=found[1]), file=sys.stderr)
            return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
