#!/usr/bin/env bash
# worker-git-guard.sh - PreToolUse hook body for the worker agent: workers never
# commit or push (kernel rule 16). .claude/agents/worker.md runs it for every
# shell the harness offers (matcher Bash|PowerShell), so a commit cannot slip
# through the shell that was not matched.
# Input: the hook payload (JSON) on stdin. The whole payload is matched, not a
# parsed command field, so the check needs no JSON parser and cannot be dodged
# by the payload's shape; this over-blocks on purpose (a description that
# names "git push" is refused too).
# Blocks: "git commit" and "git push", with any options between git and the
# subcommand ("git -C dir commit"), and git.exe on Windows, anywhere in a
# multi-line command: inside the JSON payload a line break is the two
# characters \n (or \r\n), so an escaped \n, \r or \t also counts as the
# boundary before git. A quoted exe path (PowerShell: & "C:\...\git.exe" commit)
# and quoted option arguments with spaces (git -C "my repo" push) are covered;
# inside the payload a double quote arrives JSON-escaped as \".
# Case-insensitive, because Windows runs GIT.EXE and Git.exe just the same.
# Exit: 0 allow; 2 block, with the reason on stderr for the agent to read.
set -uo pipefail
shopt -s nocasematch

payload="$(cat)"
q="'"
arg='([^-[:space:]\\'"$q"'][^[:space:]]*|\\"([^"\\]|\\[^"])*\\"|'"$q"'[^'"$q"']*'"$q"')'
opt='[[:space:]]+-[^[:space:]]+([[:space:]]+'"$arg"')?'
re='(^|[^[:alnum:]_.-]|\\[nrt])git(\.exe)?(\\"|'"$q"')?('"$opt"')*[[:space:]]+(commit|push)([^[:alnum:]_-]|$)'

if [[ "$payload" =~ $re ]]; then
  echo "BLOCKED: workers never commit or push (kernel rule 16); return the work to the advisor. Matched: ${BASH_REMATCH[0]}" >&2
  exit 2
fi
exit 0
