#!/usr/bin/env bash
# push-scan hook: scripts/push-scan.sh, wired into .claude/settings.json
# (matcher Bash|PowerShell) and .codex/hooks.json. Covers the forms it
# refuses and allows (see the lists below), the scan target of `git -C`, the
# no-subprocess fast path for commands that are not pushes (a fake
# private-terms.sh records every call), the malformed-payload policy, and the
# wiring. The Codex command strings are also pinned in test_codex_hooks.sh.
#
# Refused: git push (plain, with options, with remote and ref, after
#   cd DIR &&, as git -C DIR push, git.exe, env/sudo-wrapped, inside
#   bash -c "...") when the repository's private-terms check fails: a planted
#   term in a staged file or in an unpushed commit.
# Allowed: a clean push; no terms file; no scripts/private-terms.sh in the
#   target; git push --help and -h; git status, commit, log, fetch and pull;
#   echo and grep mentioning push; commit messages mentioning push.
# Malformed payload (no "command" field): parsed as a command, with a warning
#   on stderr; allowed unless the text is a push whose scan fails.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" || { echo "$0: cannot load lib.sh; stopped before writing anything" >&2; exit 2; }

HOOK="$T_ROOT/scripts/push-scan.sh"
TERM_WORD="zorpglax"

# mk_repo DIR REALSCRIPT: repository with a clean first commit, a terms file
# naming TERM_WORD, and either the real private-terms.sh (1) or a fake that
# records its calls into DIR/calls.log and exits with the number in DIR/fake-rc (0).
mk_repo() {
  local d="$1" real="$2"
  mkdir -p "$d/scripts" "$d/.work"
  if [[ "$real" == 1 ]]; then
    cp "$T_ROOT/scripts/private-terms.sh" "$d/scripts/private-terms.sh"
  else
    cat > "$d/scripts/private-terms.sh" <<'EOF'
#!/usr/bin/env bash
echo "called $*" >> "$(dirname "$0")/../calls.log"
echo "fake scan output"
read -r rc < "$(dirname "$0")/../fake-rc" 2>/dev/null || rc=0
exit "$rc"
EOF
  fi
  chmod +x "$d/scripts/private-terms.sh"
  printf '%s\n' "$TERM_WORD" > "$d/.work/private-terms.txt"
  echo clean > "$d/a.txt"
  git -C "$d" init -q . >/dev/null 2>&1
  git -C "$d" config user.email selftest@example.invalid
  git -C "$d" config user.name selftest
  git -C "$d" config core.autocrlf false
  git -C "$d" config maintenance.auto false
  printf '/.work/\n/calls.log\n/fake-rc\n' > "$d/.gitignore"
  git -C "$d" add -A >/dev/null 2>&1
  git -C "$d" commit -q -m fixture >/dev/null 2>&1
}

# esc TEXT -> ESC: JSON-escape backslashes and double quotes.
esc() { local s="$1"; s=${s//\\/\\\\}; ESC=${s//\"/\\\"}; }

# hook CMD [CWD]: feed a Bash PreToolUse payload; sets OUT and RC.
hook() {
  local payload
  esc "$1"
  if [[ -n "${2:-}" ]]; then
    local c="$2"; esc_cwd=${c//\\/\\\\}
    payload="{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"$ESC\"},\"cwd\":\"$esc_cwd\"}"
  else
    payload="{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"$ESC\"}}"
  fi
  OUT="$(printf '%s' "$payload" | bash "$HOOK" 2>&1)"; RC=$?
}

make_fixture
REAL="$FIX/real"; FAKE="$FIX/fake"; OTHER="$FIX/other"
mk_repo "$REAL" 1
mk_repo "$FAKE" 0
mk_repo "$OTHER" 1

# ---- clean repository: every push form allows ----
for cmd in "git push" "git push origin main" "git push -u origin HEAD" "git -c user.name=x push" "git.exe push" "env GIT_TRACE=0 git push" "sudo git push" "bash -c \"git push origin main\"" "git status && git push"; do
  hook "$cmd" "$REAL"
  assert_rc "clean repo allows: $cmd" 0
done

# ---- planted term in a staged file ----
echo "this has $TERM_WORD in it" > "$REAL/leak.txt"
git -C "$REAL" add leak.txt >/dev/null 2>&1
for cmd in "git push" "git push origin main" "git push --force-with-lease" "git -c user.name=x push" "git.exe push" "env GIT_TRACE=0 git push" "sudo git push origin" "bash -c \"git push origin main\"" "git status && git push" "cd $REAL && git push" "true; git push"; do
  hook "$cmd" "$REAL"
  assert_rc "staged term blocks: $cmd" 2
  assert_contains "staged term: $cmd names the hook" "BLOCKED by scripts/push-scan.sh"
  assert_contains "staged term: $cmd shows the private-terms output" "leak.txt"
  assert_not_contains "staged term: $cmd never prints the term" "$TERM_WORD"
done

# ---- not pushes: allowed while the same term is staged ----
for cmd in "git push --help" "git push -h origin" "git status" "git log --oneline" "git fetch origin" "git pull" "git commit -m \"push the button\"" "echo git push" "grep push README.md" "git diff push-branch" "git stash push" "git help push"; do
  hook "$cmd" "$REAL"
  assert_rc "not a push allows: $cmd" 0
done
git -C "$REAL" reset -q leak.txt >/dev/null 2>&1; rm -f "$REAL/leak.txt"

# ---- planted term in an unpushed commit ----
echo "committed $TERM_WORD" > "$REAL/leak2.txt"
git -C "$REAL" add leak2.txt >/dev/null 2>&1
git -C "$REAL" commit -q -m "add leak" >/dev/null 2>&1
hook "git push" "$REAL"
assert_rc "unpushed commit with a term blocks" 2
assert_contains "unpushed commit: block line" "BLOCKED by scripts/push-scan.sh"
assert_not_contains "unpushed commit: the term is masked" "$TERM_WORD"

# ---- git -C DIR targets that directory, not the cwd ----
hook "git -C $REAL push" "$OTHER"
assert_rc "git -C <leaky repo> push from a clean cwd blocks" 2
hook "git -C $OTHER push" "$REAL"
assert_rc "git -C <clean repo> push from a leaky cwd allows" 0
hook "git push" "$OTHER"
assert_rc "plain push in the clean repo allows" 0
hook "cd $REAL && git push" "$OTHER"
assert_rc "cd <leaky repo> && git push blocks" 2
hook "cd $REAL; cd $OTHER; git push" "$OTHER"
assert_rc "cd back to the clean repo allows" 0
hook "git -C $OTHER push; git -C $REAL push" "$OTHER"
assert_rc "two pushes: the leaky target blocks" 2
mkdir -p "$FIX/parent"
git -C "$FIX" init -q parent >/dev/null 2>&1
hook "git -C ../real push" "$OTHER"
assert_rc "git -C with a relative path resolves against the cwd" 2

# ---- no terms file: allowed ----
mv "$REAL/.work/private-terms.txt" "$REAL/.work/private-terms.off"
hook "git push" "$REAL"
assert_rc "no terms file allows" 0
mv "$REAL/.work/private-terms.off" "$REAL/.work/private-terms.txt"

# ---- target without the script, or not a repository: allowed with a note ----
NOSCRIPT="$FIX/noscript"; mkdir -p "$NOSCRIPT"; git -C "$NOSCRIPT" init -q . >/dev/null 2>&1
hook "git push" "$NOSCRIPT"
assert_rc "repository without private-terms.sh allows" 0
assert_contains "repository without private-terms.sh: says nothing to scan" "nothing to scan"
NOREPO="$FIX/norepo"; mkdir -p "$NOREPO"
GIT_CEILING_DIRECTORIES="$FIX" hook "git push" "$NOREPO"
assert_rc "directory outside any repository allows" 0
assert_contains "outside a repository: says nothing to scan" "nothing to scan"

# ---- fast path and call recording with the fake script ----
rm -f "$FAKE/calls.log"
for cmd in "git status" "git commit -m done" "ls -la" "echo hello" "git log" "git push --help" "git push -h"; do
  hook "$cmd" "$FAKE"
  assert_rc "fake: not a push allows: $cmd" 0
done
assert_no_file "non-push commands never ran the scan" "$FAKE/calls.log"
hook "git push origin main" "$FAKE"
assert_rc "fake: a push with a passing scan allows" 0
assert_file_has "fake: the push ran the scan once with check" "$FAKE/calls.log" "called check"
assert_eq "fake: exactly one scan call" "1" "$(grep -c called "$FAKE/calls.log")"
echo 1 > "$FAKE/fake-rc"
hook "git push" "$FAKE"
assert_rc "fake: a push with a failing scan blocks" 2
assert_contains "fake: block reason carries the scan output" "fake scan output"
assert_contains "fake: block reason carries the exit status" "exit 1"
echo 0 > "$FAKE/fake-rc"

# ---- non-push commands run no subprocess: a PATH with no git, no external tool ----
EMPTYBIN="$FIX/emptybin"; mkdir -p "$EMPTYBIN"
OUT="$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git status"}}' | PATH="$EMPTYBIN" "$BASH" "$HOOK" 2>&1)"; RC=$?
assert_rc "git status runs with nothing on PATH (builtins only)" 0
assert_eq "git status prints nothing" "" "$OUT"

# ---- malformed payloads (policy: parse the whole text; warn; allow unless a failing push) ----
OUT="$(printf '%s' 'not json at all' | bash "$HOOK" 2>&1)"; RC=$?
assert_rc "malformed payload without push allows" 0
OUT="$(printf '' | bash "$HOOK" 2>&1)"; RC=$?
assert_rc "empty payload allows" 0
OUT="$(cd "$FAKE" && printf '%s' 'git push origin' | bash "$HOOK" 2>&1)"; RC=$?
assert_rc "payload with no command field naming a passing push allows" 0
assert_contains "payload with no command field warns" "no \"command\" field"
OUT="$(cd "$REAL" && printf '%s' 'git push origin' | bash "$HOOK" 2>&1)"; RC=$?
assert_rc "payload with no command field naming a failing push blocks" 2
OUT="$(cd "$FAKE" && printf '%s' '{"tool_name":"Bash","tool_input":{}}' | bash "$HOOK" 2>&1)"; RC=$?
assert_rc "payload with a tool_input but no command allows" 0

# ---- the real hook stays fast (the hook timeout is 60 seconds) ----
START=$SECONDS
hook "git push" "$OTHER"
ELAPSED=$((SECONDS - START))
if (( ELAPSED < 30 )); then t_ok "a push scan in a small repository takes $ELAPSED s (limit 30)"; else t_bad "a push scan took $ELAPSED s (limit 30)"; fi

# ---- wiring ----
SETTINGS="$T_ROOT/.claude/settings.json"
CODEX="$T_ROOT/.codex/hooks.json"
assert_file "the script exists" "$HOOK"
assert_file_has "settings.json runs push-scan.sh" "$SETTINGS" 'scripts/push-scan.sh'
assert_file_has "hooks.json runs push-scan.sh" "$CODEX" 'scripts/push-scan.sh'
assert_file_has "hooks.json routes push-scan through the launcher" "$CODEX" 'codex-hook.cmd\" push-scan'
assert_file_has "the launcher accepts push-scan" "$T_ROOT/scripts/codex-hook.cmd" 'push-scan'
. "$T_ROOT/scripts/find-python.sh"
if [[ -n "$PY" ]]; then
  run "$PY" -I -B -c '
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
n = 0
for g in d["hooks"]["PreToolUse"]:
    for h in g["hooks"]:
        if "push-scan.sh" in h["command"]:
            n += 1
            print(g["matcher"], h.get("timeout", "none"))
print("count", n)
' "$SETTINGS"
  assert_contains "settings.json: push-scan.sh sits under Bash|PowerShell" "Bash|PowerShell 60"
  assert_contains "settings.json: push-scan.sh appears once" "count 1"
else
  t_na "settings.json structure: python not found (CI checks it)"
fi

t_finish
