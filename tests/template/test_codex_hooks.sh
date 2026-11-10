#!/usr/bin/env bash
# codex-hooks: .codex/hooks.json wires the four hook scripts for Codex.
# Covers: the file's shape and exact command strings (A1); each Unix command run
# as `bash -c` with recorded Codex payloads on stdin from the root and from a
# subfolder (A2); on Windows each commandWindows string run through Python as one
# raw `%COMSPEC% /C "<string>"` command line, the form Codex uses, from the root
# and a subfolder of a repository whose path holds a space (A3); the launcher's
# unknown name, no Git Bash and no git cases (A4); CRLF on scripts/codex-hook.cmd
# and the file names in check.sh and the blueprint (A13).
# The payloads in tests/template/fixtures/codex/ were recorded from a live Codex
# session with every machine value replaced by a neutral one.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" || { echo "$0: cannot load lib.sh; stopped before writing anything" >&2; exit 2; }

HOOKS="$T_ROOT/.codex/hooks.json"
FXD="$T_ROOT/tests/template/fixtures/codex"
export TEMPLATE_UPDATE_CHECK=0

. "$T_ROOT/scripts/find-python.sh"
if [[ -z "$PY" ]]; then
  t_ok "python not found; codex hook tests skipped (CI runs them)"
  t_finish
fi

# ---- A1: the hooks file ----
# hook_field EVENT FIELD: matcher, count (command hooks), command, commandWindows
# or timeout ("none" when absent) of the one entry for EVENT.
hook_field() {
  "$PY" -I -B -c '
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
ev = d["hooks"][sys.argv[2]]
assert len(ev) == 1, "one matcher group"
g = ev[0]
h = g["hooks"]
f = sys.argv[3]
if f == "matcher": print(g.get("matcher", "none"), end="")
elif f == "count": print(len(h), end="")
elif f == "type": print(h[0]["type"], end="")
else: print(h[0].get(f, "none"), end="")
' "$HOOKS" "$1" "$2"
}
exp_unix() { # NAME TAIL
  printf '%s' "bash \"\$(git rev-parse --show-toplevel)/scripts/$1.sh\"$2"
}
exp_win() { # NAME N
  printf '%s' "git --version >nul 2>&1 || (echo codex-hook: git is not on PATH; run bash scripts/doctor.sh 1>&2 & exit $2) & for /f \"usebackq delims=\" %r in (\`git rev-parse --show-toplevel\`) do @call \"%r\\scripts\\codex-hook.cmd\" $1"
}

run "$PY" -I -B -c 'import json,sys; d=json.load(open(sys.argv[1],encoding="utf-8")); print(",".join(sorted(d)), ",".join(sorted(d["hooks"])))' "$HOOKS"
assert_rc "hooks.json is valid JSON" 0
assert_eq "hooks.json holds exactly the four events" "hooks PreToolUse,SessionStart,Stop,UserPromptSubmit" "$OUT"

# EVENT NAME TAIL N TIMEOUT MATCHER
check_event() {
  local ev="$1" name="$2" tail="$3" n="$4" to="$5" m="$6"
  assert_eq "$ev: one command hook" "1" "$(hook_field "$ev" count)"
  assert_eq "$ev: hook type is command" "command" "$(hook_field "$ev" type)"
  assert_eq "$ev: matcher" "$m" "$(hook_field "$ev" matcher)"
  assert_eq "$ev: Unix command" "$(exp_unix "$name" "$tail")" "$(hook_field "$ev" command)"
  assert_eq "$ev: Windows command" "$(exp_win "$name" "$n")" "$(hook_field "$ev" commandWindows)"
  assert_eq "$ev: timeout" "$to" "$(hook_field "$ev" timeout)"
}
check_event SessionStart session-context "" 0 none none
check_event UserPromptSubmit feedback-log "" 0 5 none
check_event PreToolUse destructive-guard " || exit 2" 2 none Bash
check_event Stop stop-gate "" 0 1200 none

# ---- fixtures: recorded payloads carry no machine values ----
for n in SessionStart UserPromptSubmit PreToolUse Stop; do
  assert_file "recorded payload $n.json exists" "$FXD/$n.json"
  assert_file_lacks "$n.json holds no home path" "$FXD/$n.json" 'Users'
done
assert_file_has "the recorded PreToolUse payload has the string command form" "$FXD/PreToolUse.json" '"tool_input":{"command":"git status --short ."}'
assert_file_has "the recorded PreToolUse payload names the Bash tool" "$FXD/PreToolUse.json" '"tool_name":"Bash"'

# ---- repositories ----
RMRF="rm -rf /"
PRE_ALLOW="$(cat "$FXD/PreToolUse.json")"
PRE_BLOCK="${PRE_ALLOW/git status --short ./$RMRF}"
SS="$(cat "$FXD/SessionStart.json")"
UP="$(cat "$FXD/UserPromptSubmit.json")"
STOP="$(cat "$FXD/Stop.json")"

# mk_repo DIR: a repository at DIR with the hook scripts and the launcher.
mk_repo() {
  local d="$1" s
  mkdir -p "$d/scripts" "$d/.codex" "$d/sub"
  for s in session-context.sh feedback-log.sh destructive-guard.sh stop-gate.sh find-python.sh codex-hook.cmd; do
    cp "$T_ROOT/scripts/$s" "$d/scripts/$s"
  done
  cp "$HOOKS" "$d/.codex/hooks.json"
  echo x > "$d/sub/f.txt"
  git -C "$d" init -q . >/dev/null 2>&1
  git -C "$d" add -A >/dev/null 2>&1
  git -C "$d" -c user.email=selftest@example.invalid -c user.name=selftest -c core.autocrlf=false commit -q -m fixture >/dev/null 2>&1
}

make_fixture
REPO="$FIX/repo"
mk_repo "$REPO"

# ---- A2: Unix commands, bash -c, payload on stdin ----
unix_hook() { # EVENT DIR PAYLOAD: run the Unix command of EVENT from DIR
  local cmd
  cmd="$(hook_field "$1" command)"
  OUT="$(cd "$2" && printf '%s' "$3" | bash -c "$cmd" 2>&1)"; RC=$?
}
for where in "" "sub"; do
  dir="$REPO${where:+/$where}"
  label="Unix, from ${where:-the root}"
  unix_hook PreToolUse "$dir" "$PRE_BLOCK"
  assert_rc "$label: guard blocks the root-removal payload" 2
  assert_contains "$label: guard prints its BLOCKED line" "BLOCKED by scripts/destructive-guard.sh"
  unix_hook PreToolUse "$dir" "$PRE_ALLOW"
  assert_rc "$label: guard passes git status" 0
  unix_hook SessionStart "$dir" "$SS"
  assert_rc "$label: session start exits 0" 0
  assert_contains "$label: session start prints context lines" "[session-context]"
  unix_hook UserPromptSubmit "$dir" "$UP"
  assert_rc "$label: feedback hook exits 0" 0
  unix_hook Stop "$dir" "$STOP"
  assert_rc "$label: stop gate allows with no live task" 0
done
# The guard command fails closed when git cannot name a root.
NOGIT="$FIX/nogit"; mkdir -p "$NOGIT"
unix_hook PreToolUse "$NOGIT" "$PRE_ALLOW"
assert_rc "Unix: the guard command exits 2 outside a repository" 2

# ---- A4/A13: the launcher file ----
LAUNCHER="$T_ROOT/scripts/codex-hook.cmd"
assert_file "the launcher exists" "$LAUNCHER"
lines="$(wc -l < "$LAUNCHER" | tr -d ' ')"
crlf="$(grep -c $'\r$' "$LAUNCHER")"
assert_eq "the launcher has CRLF line endings in the working tree" "$lines" "$crlf"
assert_file_has "the launcher keeps cmd's %%r loop variable in the file" "$LAUNCHER" 'for /f "usebackq delims=" %%r in'
assert_file_has "the launcher never looks in System32 for bash" "$LAUNCHER" '%ProgramFiles%\Git\bin\bash.exe'
assert_file_lacks "the launcher does not use System32 bash" "$LAUNCHER" 'System32'

# ---- A13: names in check.sh, the blueprint and the check.sh fixture ----
for f in .codex/hooks.json scripts/codex-hook.cmd tests/template/test_codex_hooks.sh; do
  assert_file_has "check.sh requires $f" "$T_ROOT/scripts/check.sh" "$f"
  assert_file_has "the blueprint names ${f##*/}" "$T_ROOT/docs/BLUEPRINT.md" "${f##*/}"
done
if [[ -f "$T_ROOT/tests/template/fixtures/check.sh" ]]; then
  if cmp -s "$T_ROOT/scripts/check.sh" "$T_ROOT/tests/template/fixtures/check.sh"; then t_ok "fixtures/check.sh is identical to scripts/check.sh"; else t_bad "fixtures/check.sh differs from scripts/check.sh"; fi
fi

# ---- A3 and A4: Windows, the form Codex uses ----
case "$(uname -s 2>/dev/null)" in MINGW*|MSYS*|CYGWIN*) IS_WIN=1 ;; *) IS_WIN=0 ;; esac
if (( ! IS_WIN )); then
  t_na "A3 Windows commandWindows strings through cmd.exe: needs Windows; covered by the Windows CI job"
  t_na "A4 launcher without Git Bash and without git: needs Windows; covered by the Windows CI job"
else
  # win_run CMDLINE DIR PAYLOAD [PATH [PROGRAMFILES]]: run
  # `%COMSPEC% /C "<CMDLINE>"` as one raw command line in DIR (a Windows path)
  # with PAYLOAD on stdin. Python builds the line because Git Bash mangles the
  # quotes of a cmd.exe call. The text goes in through stdin, so no path
  # conversion touches it. Sets OUT (stdout and stderr) and RC.
  win_run() {
    local res
    res="$(printf '%s\n%s\n%s\n%s\n%s' "$1" "$2" "${4:--}" "${5:--}" "$3" | "$PY" -I -B -c '
import os, subprocess, sys
raw = sys.stdin.buffer.read().decode("utf-8")
cmd, cwd, path, pf, payload = raw.split("\n", 4)
env = dict(os.environ)
if path != "-": env["PATH"] = path
# cmd.exe rebuilds %ProgramFiles% itself, so an environment override is ignored;
# a set command in front of the line is not.
if pf != "-": cmd = "set \"ProgramFiles=" + pf + "\" & " + cmd
r = subprocess.run(os.environ["COMSPEC"] + " /C \"" + cmd + "\"", input=payload.encode("utf-8"), cwd=cwd, env=env, capture_output=True)
sys.stdout.write((r.stdout + r.stderr).decode("utf-8", "replace").replace("\r", ""))
sys.stdout.write("\nRC=%d" % r.returncode)
' 2>&1)"
    RC="${res##*RC=}"
    OUT="${res%RC=*}"
  }
  win_hook() { # EVENT DIR PAYLOAD [PATH [PROGRAMFILES]]
    win_run "$(hook_field "$1" commandWindows)" "$(cygpath -w "$2")" "$3" "${4:-}" "${5:-}"
  }

  SP="$FIX/with space"
  mk_repo "$SP"
  for where in "" "sub"; do
    dir="$SP${where:+/$where}"
    label="Windows, from ${where:-the root} of a path with a space"
    win_hook PreToolUse "$dir" "$PRE_BLOCK"
    assert_rc "$label: guard blocks the root-removal payload" 2
    assert_contains "$label: guard prints its BLOCKED line" "BLOCKED by scripts/destructive-guard.sh"
    win_hook PreToolUse "$dir" "$PRE_ALLOW"
    assert_rc "$label: guard passes git status" 0
    win_hook SessionStart "$dir" "$SS"
    assert_rc "$label: session start exits 0" 0
    assert_contains "$label: session start prints context lines" "[session-context]"
    win_hook UserPromptSubmit "$dir" "$UP"
    assert_rc "$label: feedback hook exits 0" 0
    win_hook Stop "$dir" "$STOP"
    assert_rc "$label: stop gate allows with no live task" 0
  done

  # Unknown hook name: one stderr line, exit 0.
  win_run "\"$(cygpath -w "$SP")\\scripts\\codex-hook.cmd\" bogus" "$(cygpath -w "$SP")" "$PRE_ALLOW"
  assert_rc "launcher: an unknown name exits 0" 0
  assert_contains "launcher: an unknown name says so" "codex-hook: unknown hook name bogus"
  assert_eq "launcher: an unknown name prints one line" "1" "$(printf '%s\n' "$OUT" | grep -c .)"

  # No Git Bash: a git.cmd shim first on PATH whose --exec-path names a folder
  # without bash, and ProgramFiles set to an empty folder in the command line. The shim hands
  # every other call to the real git.
  SHIM="$FIX/shim"; EMPTYPF="$FIX/emptypf"; mkdir -p "$SHIM" "$EMPTYPF"
  REALGIT="$(cygpath -w "$(command -v git)")"
  printf '@echo off\r\nif "%%~1"=="--exec-path" (echo %%~dp0%s& exit /b 0)\r\n"%s" %%*\r\n' 'nobash\a\b\c' "$REALGIT" > "$SHIM/git.cmd"
  NOBASH_PATH="$(cygpath -w "$SHIM");C:\\Windows\\System32;C:\\Windows"
  for ev in SessionStart UserPromptSubmit PreToolUse Stop; do
    case "$ev" in
      SessionStart) pl="$SS"; want=0 ;;
      UserPromptSubmit) pl="$UP"; want=0 ;;
      PreToolUse) pl="$PRE_ALLOW"; want=2 ;;
      Stop) pl="$STOP"; want=0 ;;
    esac
    win_hook "$ev" "$SP/sub" "$pl" "$NOBASH_PATH" "$(cygpath -w "$EMPTYPF")"
    assert_rc "no Git Bash, $ev: exit $want" "$want"
    assert_contains "no Git Bash, $ev: the stderr line names doctor.sh" "scripts/doctor.sh"
    assert_contains "no Git Bash, $ev: the line says Git Bash was not found" "Git Bash not found"
    # No git on PATH: the commandWindows prefix answers before the launcher runs.
    win_hook "$ev" "$SP/sub" "$pl" 'C:\Windows\System32;C:\Windows' ""
    assert_rc "no git on PATH, $ev: exit $want" "$want"
    assert_contains "no git on PATH, $ev: the line names doctor.sh" "scripts/doctor.sh"
    assert_contains "no git on PATH, $ev: the line says git is missing" "git is not on PATH"
  done
fi

t_finish
