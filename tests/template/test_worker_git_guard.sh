#!/usr/bin/env bash
# worker-git-guard.sh: the worker's commit and push block, fed hook payloads
# from both shells the harness offers (Bash and PowerShell), and the worker
# agent's hook wiring (matcher covers both shells, command runs the script).
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

GUARD="$T_ROOT/scripts/worker-git-guard.sh"
WORKER="$T_ROOT/.claude/agents/worker.md"

# guard TOOL COMMAND: feed a PreToolUse payload for TOOL running COMMAND.
guard() {
  OUT="$(printf '{"tool_name":"%s","tool_input":{"command":"%s"}}' "$1" "$2" | bash "$GUARD" 2>&1)"
  RC=$?
}

for shell in Bash PowerShell; do
  guard "$shell" "git commit -m fix"
  assert_rc "$shell: git commit is blocked" 2
  assert_contains "$shell: the block names the rule" "BLOCKED: workers never commit or push"
  guard "$shell" "git push origin task/x"
  assert_rc "$shell: git push is blocked" 2
  guard "$shell" "git -C /repo commit -am x"
  assert_rc "$shell: options before commit do not dodge the block" 2
  guard "$shell" "git -c user.name=x push"
  assert_rc "$shell: a -c option before push does not dodge the block" 2
  guard "$shell" "cd repo && git  commit"
  assert_rc "$shell: a chained commit with extra spaces is blocked" 2
  guard "$shell" "git.exe push"
  assert_rc "$shell: git.exe push is blocked" 2
  # JSON escapes a line break as the two characters \n; the guard sees those.
  guard "$shell" 'cd x\ngit commit -m y'
  assert_rc "$shell: a commit on the second line of a command is blocked" 2
  guard "$shell" 'git status\ngit push origin x'
  assert_rc "$shell: a push on the second line of a command is blocked" 2
  guard "$shell" 'cd x\r\ngit push'
  assert_rc "$shell: a push after a CRLF line break is blocked" 2
  guard "$shell" 'echo a\tgit commit'
  assert_rc "$shell: a commit after an escaped tab is blocked" 2
  # Payload text is JSON-escaped: \" is a quote, \\ a backslash.
  guard "$shell" '& \"C:\\Program Files\\Git\\cmd\\git.exe\" commit -m x'
  assert_rc "$shell: a quoted git.exe path does not dodge the block" 2
  guard "$shell" 'git -C \"C:\\my repo\" push'
  assert_rc "$shell: a double-quoted option argument with a space does not dodge the block" 2
  guard "$shell" "git -C 'a b' commit"
  assert_rc "$shell: a single-quoted option argument with a space does not dodge the block" 2
  guard "$shell" 'Git.exe PUSH'
  assert_rc "$shell: a differently cased git.exe push is blocked" 2
  guard "$shell" 'git -C \"C:\\my repo\" status'
  assert_rc "$shell: a quoted option argument before status is allowed" 0
  guard "$shell" 'git status\ngit log --oneline'
  assert_rc "$shell: a multi-line command without commit or push is allowed" 0
  guard "$shell" "git status --short"
  assert_rc "$shell: git status is allowed" 0
  guard "$shell" "git log --oneline -5"
  assert_rc "$shell: git log is allowed" 0
  guard "$shell" "git diff --cached"
  assert_rc "$shell: git diff is allowed" 0
  guard "$shell" "echo committed and pushed"
  assert_rc "$shell: prose without a git subcommand is allowed" 0
  guard "$shell" "./scripts/check.sh"
  assert_rc "$shell: the gauntlet is allowed" 0
done

OUT="$(printf '' | bash "$GUARD" 2>&1)"; RC=$?
assert_rc "an empty payload is allowed" 0

# Wiring: the worker agent's hook covers both shells and runs this script.
assert_file "the guard script exists" "$GUARD"
assert_file_has "the worker hook matcher covers Bash and PowerShell" "$WORKER" "matcher: Bash|PowerShell"
assert_file_has "the worker hook runs the guard script" "$WORKER" 'scripts/worker-git-guard.sh'
assert_file_lacks "the worker hook carries no inline copy of the logic" "$WORKER" 'case "$in"'
mode="$(cd "$T_ROOT" && git ls-files -s scripts/worker-git-guard.sh | awk '{print $1}')"
if [[ -n "$mode" ]]; then
  assert_eq "the guard script is executable in the index" "100755" "$mode"
fi

t_finish
