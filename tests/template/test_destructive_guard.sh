#!/usr/bin/env bash
# destructive-guard.sh: forbidden removal targets and destructive git forms,
# fed hook payloads from both shells the harness offers (Bash and PowerShell),
# plus the settings wiring (matcher covers both shells, command runs the script).
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" || { echo "$0: cannot load lib.sh; stopped before writing anything" >&2; exit 2; }

GUARD="$T_ROOT/scripts/destructive-guard.sh"
SETTINGS="$T_ROOT/.claude/settings.json"
PREFIX="BLOCKED by scripts/destructive-guard.sh"

# Fixed identity so results never depend on the machine running the tests.
G_HOME='/c/Users/tester'
G_UP='C:\Users\tester'
G_PROJ='C:\dev\proj'

# guard_ctx TOOL COMMAND CWD HOME USERPROFILE PROJECT_DIR: feed a PreToolUse
# payload for TOOL running COMMAND. COMMAND and CWD are already JSON-escaped
# where they need to be (\n, \", \\); an empty CWD omits the cwd field.
guard_ctx() {
  local payload
  if [[ -n "$3" ]]; then
    payload="$(printf '{"tool_name":"%s","tool_input":{"command":"%s"},"cwd":"%s"}' "$1" "$2" "$3")"
  else
    payload="$(printf '{"tool_name":"%s","tool_input":{"command":"%s"}}' "$1" "$2")"
  fi
  OUT="$(printf '%s' "$payload" | env HOME="$4" USERPROFILE="$5" CLAUDE_PROJECT_DIR="$6" bash "$GUARD" 2>&1)"
  RC=$?
}
# guard TOOL COMMAND: no cwd in the payload, the fixed identity above.
guard() { guard_ctx "$1" "$2" "" "$G_HOME" "$G_UP" "$G_PROJ"; }

# blocked SHELL NAME COMMAND / allowed SHELL NAME COMMAND
blocked() {
  guard "$1" "$3"
  assert_rc "$1: $2" 2
  assert_contains "$1: $2 (names the guard)" "$PREFIX"
}
allowed() {
  guard "$1" "$3"
  assert_rc "$1: $2" 0
}
# blocked_in / allowed_in SHELL NAME COMMAND CWD: same, with a payload cwd and
# the fixed identity (workspace C:\dev\proj, home C:\Users\tester).
blocked_in() {
  guard_ctx "$1" "$3" "$4" "$G_HOME" "$G_UP" "$G_PROJ"
  assert_rc "$1: $2" 2
  assert_contains "$1: $2 (names the guard)" "$PREFIX"
}
allowed_in() {
  guard_ctx "$1" "$3" "$4" "$G_HOME" "$G_UP" "$G_PROJ"
  assert_rc "$1: $2" 0
}

for shell in Bash PowerShell; do
  # Removal family: always-forbidden targets, any flags.
  blocked "$shell" "rm -rf / is blocked" 'rm -rf /'
  blocked "$shell" "rm -rf /* is blocked" 'rm -rf /*'
  blocked "$shell" "rm -rf ~ is blocked" 'rm -rf ~'
  blocked "$shell" "rm -fr ~ is blocked" 'rm -fr ~'
  blocked "$shell" "rm -rf ~/ is blocked" 'rm -rf ~/'
  blocked "$shell" "rm -rf ~/* is blocked" 'rm -rf ~/*'
  blocked "$shell" "rm -rf . is blocked" 'rm -rf .'
  blocked "$shell" "rm -rf ./ is blocked" 'rm -rf ./'
  blocked "$shell" "rm -rf ./* is blocked" 'rm -rf ./*'
  blocked "$shell" "rm -rf .. is blocked" 'rm -rf ..'
  blocked "$shell" "rm -rf ../ is blocked" 'rm -rf ../'
  blocked "$shell" "rm -rf * is blocked" 'rm -rf *'
  blocked "$shell" "rm -rf .* is blocked" 'rm -rf .*'
  blocked "$shell" "rm -rf \$HOME is blocked" 'rm -rf $HOME'
  blocked "$shell" "rm -rf \${HOME} is blocked" 'rm -rf ${HOME}'
  blocked "$shell" "Remove-Item \$env:USERPROFILE is blocked" 'Remove-Item -Recurse -Force $env:USERPROFILE'
  blocked "$shell" "Remove-Item \$env:userprofile (any case) is blocked" 'Remove-Item -Recurse -Force $env:userprofile'
  blocked "$shell" "rd %USERPROFILE% is blocked" 'rd /s /q %USERPROFILE%'
  blocked "$shell" "rm / without recursion is still blocked" 'rm /'
  blocked "$shell" "rm * without recursion is still blocked" 'rm *'
  blocked "$shell" "rm --recursive --force / is blocked" 'rm --recursive --force /'
  blocked "$shell" "sudo rm -rf / is blocked" 'sudo rm -rf /'
  blocked "$shell" "env FOO=1 rm -rf / is blocked" 'env FOO=1 rm -rf /'
  blocked "$shell" "xargs rm -rf / is blocked" 'ls | xargs rm -rf /'
  blocked "$shell" "/bin/rm -rf / is blocked" '/bin/rm -rf /'
  blocked "$shell" "rm.exe -rf / is blocked" 'rm.exe -rf /'
  blocked "$shell" "RM -RF / is blocked" 'RM -RF /'
  # Drive roots.
  blocked "$shell" "rd /s /q C:\\ is blocked" 'rd /s /q C:\\'
  blocked "$shell" "rd /s /q C: is blocked" 'rd /s /q C:'
  blocked "$shell" "rd /s /q C:/ is blocked" 'rd /s /q C:/'
  blocked "$shell" "del /s /q C:\\* is blocked" 'del /s /q C:\\*'
  blocked "$shell" "rm -rf C:/* is blocked" 'rm -rf C:/*'
  blocked "$shell" "Remove-Item -Recurse C:\\ is blocked" 'Remove-Item -Recurse -Force C:\\'
  blocked "$shell" "Remove-Item -Path C:\\ is blocked" 'Remove-Item -Path C:\\ -Recurse'
  blocked "$shell" "rm -rf /c is blocked" 'rm -rf /c'
  blocked "$shell" "rm -rf /c/ is blocked" 'rm -rf /c/'
  blocked "$shell" "rm -rf /c/* is blocked" 'rm -rf /c/*'
  # Recursive plus unresolved variable.
  blocked "$shell" "rm -rf \"\$BUILD_DIR\"/* is blocked" 'rm -rf \"$BUILD_DIR\"/*'
  blocked "$shell" "rm -rf \$DIR is blocked" 'rm -rf $DIR'
  blocked "$shell" "Remove-Item -Recurse \$dir is blocked" 'Remove-Item -Recurse -Force $dir\\build'
  blocked "$shell" "rd /s /q %TEMP%\\x is blocked" 'rd /s /q %TEMP%\\x'
  # Recursive plus top-level directory.
  blocked "$shell" "rm -rf /usr is blocked" 'rm -rf /usr'
  blocked "$shell" "rm -rf /tmp/ is blocked" 'rm -rf /tmp/'
  blocked "$shell" "rm -rf /c/Users is blocked" 'rm -rf /c/Users'
  blocked "$shell" "Remove-Item -Recurse C:\\Users is blocked" 'Remove-Item -Recurse -Force C:\\Users'
  # A \\n in the payload is a backslash then n, never a line break.
  blocked "$shell" "Remove-Item -Recurse C:\\new (top level) is blocked" 'Remove-Item -Recurse -Force C:\\new'
  blocked "$shell" "rd /s /q C:\\Windows\\ is blocked" 'rd /s /q C:\\Windows\\'
  blocked "$shell" "Remove-Item -rec C:\\Users is blocked (-rec prefix)" 'Remove-Item -rec C:\\Users'
  blocked "$shell" "Remove-Item -R C:\\Users is blocked (-R prefix)" 'Remove-Item -R C:\\Users'
  blocked "$shell" "ri -Recurse C:\\Users is blocked" 'ri -Recurse C:\\Users'
  blocked "$shell" "rm -Rf /usr is blocked" 'rm -Rf /usr'
  blocked "$shell" "rm -rfv /usr is blocked" 'rm -rfv /usr'
  # Multi-line and chained.
  blocked "$shell" "rm -rf / on the second line is blocked" 'cd x\nrm -rf /'
  blocked "$shell" "rm -rf / after CRLF is blocked" 'cd x\r\nrm -rf /'
  blocked "$shell" "rm -rf / after && is blocked" 'cd x && rm -rf /'
  blocked "$shell" "rm -rf / after ; is blocked" 'cd x; rm -rf /'
  blocked "$shell" "rm -rf / after || is blocked" 'false || rm -rf /'

  # Removal family: allowed.
  allowed "$shell" "rm file.txt is allowed" 'rm file.txt'
  allowed "$shell" "rm -rf build is allowed" 'rm -rf build'
  allowed "$shell" "rm -rf /tmp/x/y is allowed" 'rm -rf /tmp/x/y'
  allowed "$shell" "rm -rf ./build is allowed" 'rm -rf ./build'
  allowed "$shell" "rm -rf /tmp/x is allowed (two levels)" 'rm -rf /tmp/x'
  allowed "$shell" "Remove-Item -Recurse -Force .\\build is allowed" 'Remove-Item -Recurse -Force .\\build'
  allowed "$shell" "rm -rf ~/projects/old is allowed" 'rm -rf ~/projects/old'
  allowed "$shell" "rmdir emptydir is allowed" 'rmdir emptydir'
  allowed "$shell" "rmdir /s /q build is allowed" 'rmdir /s /q build'
  allowed "$shell" "rm \$HOME/x (not recursive) is allowed" 'rm $HOME/x'
  allowed "$shell" "Remove-Item -Recurse -Force C:\\new\\dir is allowed (not a line break, not top level)" 'Remove-Item -Recurse -Force C:\\new\\dir'
  allowed "$shell" "rd /s /q C:\\dev\\x is allowed" 'rd /s /q C:\\dev\\x'
  allowed "$shell" "Remove-Item -Force file.txt is allowed" 'Remove-Item -Force file.txt'
  allowed "$shell" "ls -la is allowed" 'ls -la'
  allowed "$shell" "the gauntlet is allowed" './scripts/check.sh'
  allowed "$shell" "echo rm -rf / is allowed (echo is not a removal)" 'echo rm -rf /'

  # git: blocked.
  blocked "$shell" "git commit --no-verify is blocked" 'git commit --no-verify -m x'
  blocked "$shell" "git commit -nm is blocked" 'git commit -nm x'
  blocked "$shell" "git commit -n is blocked" 'git commit -n -m x'
  blocked "$shell" "git push --no-verify is blocked" 'git push --no-verify origin x'
  blocked "$shell" "git push --force is blocked" 'git push --force origin x'
  blocked "$shell" "git push -f is blocked" 'git push -f origin x'
  blocked "$shell" "git push --force-with-lease is blocked" 'git push --force-with-lease origin x'
  blocked "$shell" "git push --force-with-lease=ref is blocked" 'git push --force-with-lease=main origin x'
  blocked "$shell" "git push --force-if-includes is blocked" 'git push --force-if-includes origin x'
  blocked "$shell" "git push --delete is blocked" 'git push origin --delete x'
  blocked "$shell" "git push -d is blocked" 'git push -d origin x'
  blocked "$shell" "git push --mirror is blocked" 'git push --mirror'
  blocked "$shell" "git push --prune is blocked" 'git push --prune origin'
  blocked "$shell" "git push +ref is blocked" 'git push origin +main'
  blocked "$shell" "git push :ref is blocked" 'git push origin :old'
  blocked "$shell" "git -C repo push --force is blocked" 'git -C repo push --force'
  blocked "$shell" "git -c k=v push -f is blocked" 'git -c k=v push -f'
  blocked "$shell" "git.exe push -f is blocked" 'git.exe push -f'
  blocked "$shell" "Git.exe PUSH -f is blocked" 'Git.exe PUSH -f'
  blocked "$shell" "quoted git.exe path push -f is blocked" '& \"C:\\Program Files\\Git\\cmd\\git.exe\" push -f'
  blocked "$shell" "git reset --hard is blocked" 'git reset --hard'
  blocked "$shell" "git reset --hard HEAD~1 is blocked" 'git reset --hard HEAD~1'
  blocked "$shell" "chained make && git reset --hard is blocked" 'make && git reset --hard'
  blocked "$shell" "git clean -f is blocked" 'git clean -f'
  blocked "$shell" "git clean -fd is blocked" 'git clean -fd'
  blocked "$shell" "git clean -fdx is blocked" 'git clean -fdx'
  blocked "$shell" "git clean --force is blocked" 'git clean --force -d'
  blocked "$shell" "git branch -D is blocked" 'git branch -D x'
  blocked "$shell" "git branch -d -f is blocked" 'git branch -d -f x'
  blocked "$shell" "git branch --delete --force is blocked" 'git branch --delete --force x'
  blocked "$shell" "git branch -df is blocked" 'git branch -df x'
  blocked "$shell" "git checkout -f is blocked" 'git checkout -f main'
  blocked "$shell" "git checkout --force is blocked" 'git checkout --force main'
  blocked "$shell" "git checkout . is blocked" 'git checkout .'
  blocked "$shell" "git checkout -- . is blocked" 'git checkout -- .'
  blocked "$shell" "git checkout ./ is blocked" 'git checkout ./'
  blocked "$shell" "git checkout * is blocked" 'git checkout *'
  blocked "$shell" "git checkout :/ is blocked" 'git checkout :/'
  blocked "$shell" "git restore . is blocked" 'git restore .'
  blocked "$shell" "git restore --worktree . is blocked" 'git restore --worktree .'
  blocked "$shell" "git restore --staged --worktree . is blocked" 'git restore --staged --worktree .'
  blocked "$shell" "git restore -S -W . is blocked" 'git restore -S -W .'
  blocked "$shell" "git restore :/ is blocked" 'git restore :/'
  blocked "$shell" "git stash drop is blocked" 'git stash drop'
  blocked "$shell" "git stash clear is blocked" 'git stash clear'
  blocked "$shell" "git stash drop stash@{0} is blocked" 'git stash drop stash@{0}'

  # git: allowed.
  allowed "$shell" "git status is allowed" 'git status'
  allowed "$shell" "git log is allowed" 'git log --oneline -5'
  allowed "$shell" "git diff is allowed" 'git diff --cached'
  allowed "$shell" "git add is allowed" 'git add -A'
  allowed "$shell" "git commit -m x is allowed" 'git commit -m x'
  allowed "$shell" "git commit -am x is allowed" 'git commit -am x'
  allowed "$shell" "git push origin x is allowed" 'git push origin x'
  allowed "$shell" "git push -u origin x is allowed" 'git push -u origin x'
  allowed "$shell" "git reset --soft HEAD~1 is allowed" 'git reset --soft HEAD~1'
  allowed "$shell" "git reset HEAD file is allowed" 'git reset HEAD file.txt'
  allowed "$shell" "git clean -n is allowed" 'git clean -n'
  allowed "$shell" "git clean -nd is allowed" 'git clean -nd'
  allowed "$shell" "git clean -fn is allowed (dry run)" 'git clean -fn'
  allowed "$shell" "git clean --dry-run -f is allowed" 'git clean --dry-run -f'
  allowed "$shell" "git branch -d x is allowed" 'git branch -d x'
  allowed "$shell" "git branch -a is allowed" 'git branch -a'
  allowed "$shell" "git checkout -- file.txt is allowed" 'git checkout -- file.txt'
  allowed "$shell" "git checkout -b x is allowed" 'git checkout -b x'
  allowed "$shell" "git checkout main is allowed" 'git checkout main'
  allowed "$shell" "git restore file.txt is allowed" 'git restore file.txt'
  allowed "$shell" "git restore --staged . is allowed" 'git restore --staged .'
  allowed "$shell" "git restore -S . is allowed" 'git restore -S .'
  allowed "$shell" "git stash is allowed" 'git stash'
  allowed "$shell" "git stash pop is allowed" 'git stash pop'
  allowed "$shell" "git stash list is allowed" 'git stash list'
  allowed "$shell" "git -C repo status is allowed" 'git -C repo status'
  allowed "$shell" "git -C quoted path status is allowed" 'git -C \"C:\\my repo\" status'
  allowed "$shell" "git status then log on two lines is allowed" 'git status\ngit log --oneline'
  allowed "$shell" "git commit -m with parentheses is allowed" 'git commit -m \"fix (x)\"'
  allowed "$shell" "a quoted message that names --no-verify is allowed" 'git commit -m \"docs: ban --no-verify and -n\"'
  blocked "$shell" "rm -rf of a quoted top-level path with a space is blocked" 'rm -rf \"C:\\Program Files\"'
  allowed "$shell" "rm -rf of a quoted narrow path with a space is allowed" 'rm -rf \"C:\\my stuff\\old build\"'

  # Glob under an unresolved variable, with or without recursion.
  blocked "$shell" "rm \"\$BUILD_DIR\"/* (no -r) is blocked" 'rm \"$BUILD_DIR\"/*'
  blocked "$shell" "rm \$X/* is blocked" 'rm $X/*'
  blocked "$shell" "rm \$X/? is blocked" 'rm $X/?'
  blocked "$shell" "del %TMP%\\* is blocked" 'del %TMP%\\*'
  blocked "$shell" "del /q %TMP%\\*.log is blocked" 'del /q %TMP%\\*.log'
  blocked "$shell" "Remove-Item \$env:X\\* is blocked" 'Remove-Item $env:X\\*'
  blocked "$shell" "Remove-Item -Force \$env:X\\*.tmp is blocked" 'Remove-Item -Force $env:X\\*.tmp'
  allowed "$shell" "rm \"\$TMPFILE\" (variable, no glob, not recursive) is allowed" 'rm \"$TMPFILE\"'
  allowed "$shell" "rm \$TMPFILE is allowed" 'rm $TMPFILE'
  allowed "$shell" "Remove-Item \$env:TMPFILE is allowed" 'Remove-Item $env:TMPFILE'
  allowed "$shell" "del %TMP%\\x.log is allowed" 'del %TMP%\\x.log'
  allowed "$shell" "rm build/*.o (glob, no variable) is allowed" 'rm build/*.o'
  guard "$shell" 'rm $X/*'
  assert_contains "$shell: the glob-under-variable reason is stated" "removal of a glob under an unresolved variable (pass the literal path)"

  # Home and workspace by literal path (workspace C:\dev\proj, home C:\Users\tester).
  blocked "$shell" "workspace as /c/dev/proj is blocked" 'rm -rf /c/dev/proj'
  blocked "$shell" "workspace as /c/dev/proj/ (trailing slash) is blocked" 'rm -rf /c/dev/proj/'
  blocked "$shell" "workspace as C:\\dev\\proj is blocked" 'rm -rf C:\\dev\\proj'
  blocked "$shell" "workspace as C:\\dev\\proj\\ (trailing backslash) is blocked" 'rd /s /q C:\\dev\\proj\\'
  blocked "$shell" "workspace as C:/dev/proj is blocked" 'rm -rf C:/dev/proj'
  blocked "$shell" "workspace in mixed case is blocked" 'rm -rf /C/Dev/PROJ'
  blocked "$shell" "workspace with repeated slashes is blocked" 'rm -rf /c//dev///proj'
  blocked "$shell" "workspace through . and .. is blocked" 'rm -rf /c/dev/other/../proj/.'
  blocked "$shell" "workspace contents /c/dev/proj/* is blocked" 'rm -rf /c/dev/proj/*'
  blocked "$shell" "Remove-Item -Recurse -Force workspace is blocked" 'Remove-Item -Recurse -Force C:\\dev\\proj'
  blocked "$shell" "non-recursive rm of the workspace path is blocked" 'rm /c/dev/proj'
  blocked "$shell" "home as /c/Users/tester is blocked" 'rm -rf /c/Users/tester'
  blocked "$shell" "home as C:\\Users\\tester is blocked" 'Remove-Item -Recurse -Force C:\\Users\\tester'
  blocked "$shell" "home as rd /s /q C:\\Users\\tester is blocked" 'rd /s /q C:\\Users\\tester'
  blocked "$shell" "home as C:/Users/Tester (any case) is blocked" 'rm -rf C:/Users/Tester'
  blocked "$shell" "home as ~/. is blocked" 'rm -rf ~/.'
  blocked "$shell" "ancestor of the workspace /c/dev is blocked" 'rm -rf /c/dev'
  blocked "$shell" "ancestor of the workspace C:\\dev\\ is blocked" 'rd /s /q C:\\dev\\'
  blocked "$shell" "ancestor of home /c/Users is blocked" 'rm -rf /c/Users'
  blocked "$shell" "ancestor of the workspace via .. in a path is blocked" 'rm -rf /c/dev/proj/..'
  allowed "$shell" "rm -rf /c/dev/proj/build (inside the workspace) is allowed" 'rm -rf /c/dev/proj/build'
  allowed "$shell" "rm -rf C:\\dev\\proj\\build\\ is allowed" 'rm -rf C:\\dev\\proj\\build\\'
  allowed "$shell" "sibling of the workspace /c/dev/other is allowed" 'rm -rf /c/dev/other'
  allowed "$shell" "sibling whose name starts like the workspace /c/dev/proj2 is allowed" 'rm -rf /c/dev/proj2'
  allowed "$shell" "child of home /c/Users/tester/.cache/x is allowed" 'rm -rf /c/Users/tester/.cache/x'
  allowed "$shell" "another user's folder /c/Users/other/x is allowed" 'rm -rf /c/Users/other/x'
  allowed "$shell" "rm of a file in the workspace is allowed" 'rm /c/dev/proj/notes.txt'
  # A deeper workspace and home, so the ancestor rule is not masked by the top-level rule.
  guard_ctx "$shell" 'rm -rf /c/src/team' "" "" "" 'C:\src\team\proj'
  assert_rc "$shell: ancestor /c/src/team of a deep workspace is blocked" 2
  guard_ctx "$shell" 'rm -rf C:\\src\\team\\' "" "" "" 'C:\src\team\proj'
  assert_rc "$shell: ancestor C:\\src\\team\\ of a deep workspace is blocked" 2
  guard_ctx "$shell" 'rm -rf /c/src/team/other' "" "" "" 'C:\src\team\proj'
  assert_rc "$shell: sibling /c/src/team/other of a deep workspace is allowed" 0
  guard_ctx "$shell" 'rm -rf /c/src/team/proj/build' "" "" "" 'C:\src\team\proj'
  assert_rc "$shell: child of a deep workspace is allowed" 0

  # Relative targets resolve against the payload cwd.
  blocked_in "$shell" "cwd inside the workspace: rm -rf ../.. (ancestor) is blocked" 'rm -rf ../..' 'C:\\dev\\proj\\sub'
  blocked_in "$shell" "cwd inside the workspace: rm -rf ../../ is blocked" 'rm -rf ../../' 'C:\\dev\\proj\\sub'
  blocked_in "$shell" "cwd inside the workspace: Remove-Item -Recurse ..\\.. is blocked" 'Remove-Item -Recurse -Force ..\\..' 'C:\\dev\\proj\\sub'
  blocked_in "$shell" "cwd inside the workspace: rm -rf ../../proj (the workspace) is blocked" 'rm -rf ../../proj' 'C:\\dev\\proj\\sub'
  blocked_in "$shell" "cwd inside the workspace: rm -rf ../sub (the cwd) is blocked" 'rm -rf ../sub' 'C:\\dev\\proj\\sub'
  blocked_in "$shell" "cwd is the workspace: rm -rf ../proj is blocked" 'rm -rf ../proj' 'C:\\dev\\proj'
  allowed_in "$shell" "cwd inside the workspace: rm -rf build is allowed" 'rm -rf build' 'C:\\dev\\proj\\sub'
  allowed_in "$shell" "cwd inside the workspace: rm -rf ../build is allowed" 'rm -rf ../build' 'C:\\dev\\proj\\sub'
  allowed_in "$shell" "cwd inside the workspace: rm -rf ./out/x is allowed" 'rm -rf ./out/x' 'C:\\dev\\proj\\sub'
  allowed_in "$shell" "cwd inside the workspace: rm -rf ../../other is allowed" 'rm -rf ../../other' 'C:\\dev\\proj\\sub'
  allowed "$shell" "no cwd: a relative path is skipped by the path check" 'rm -rf ../../x'
  # The payload cwd is the workspace even when CLAUDE_PROJECT_DIR is unset.
  guard_ctx "$shell" 'rm -rf /c/work/app' 'C:\\work\\app' "" "" ""
  assert_rc "$shell: cwd alone protects the workspace" 2
  guard_ctx "$shell" 'rm -rf /c/work' 'C:\\work\\app' "" "" ""
  assert_rc "$shell: cwd alone protects the workspace's ancestors" 2
  guard_ctx "$shell" 'rm -rf /c/work/app/build' 'C:\\work\\app' "" "" ""
  assert_rc "$shell: cwd alone allows a child of the workspace" 0
  # Other machines' home spellings.
  guard_ctx "$shell" 'rm -rf /home/someone' "" "/home/someone" "" ""
  assert_rc "$shell: home /home/someone is blocked" 2
  guard_ctx "$shell" 'rm -rf /Users/someone' "" "/Users/someone" "" ""
  assert_rc "$shell: home /Users/someone is blocked" 2
  guard_ctx "$shell" 'rm -rf /home/someone/old' "" "/home/someone" "" ""
  assert_rc "$shell: a child of /home/someone is allowed" 0
  guard_ctx "$shell" 'rm -rf ~/projects/old' "" "/home/someone" "" ""
  assert_rc "$shell: ~/projects/old is allowed" 0
  guard_ctx "$shell" 'rm -rf ~/projects/..' "" "/home/someone" "" ""
  assert_rc "$shell: ~/projects/.. (home) is blocked" 2
  guard_ctx "$shell" 'rm -rf /home/org' "" "/home/org/someone" "" ""
  assert_rc "$shell: /home/org (ancestor of a deeper home) is blocked" 2
  guard_ctx "$shell" 'rm -rf /c/Users/tester' "" "" 'C:\Users\tester' ""
  assert_rc "$shell: home given only as USERPROFILE is blocked" 2
  guard_ctx "$shell" 'rm -rf /c/Users/tester' "" "" "" ""
  assert_rc "$shell: no home or workspace known, only the top-level rules apply" 0
  guard "$shell" 'rm -rf /c/dev/proj'
  assert_contains "$shell: the home/workspace reason is stated" "recursive removal of the home directory, the workspace, or a folder containing one"

  # Interpreter wrappers: the inner command is checked.
  blocked "$shell" "bash -c git push --force is blocked" 'bash -c \"git push --force\"'
  blocked "$shell" "bash -c single quotes is blocked" "bash -c 'git push --force origin x'"
  blocked "$shell" "sh -c is blocked" 'sh -c \"git reset --hard\"'
  blocked "$shell" "zsh -c is blocked" 'zsh -c \"rm -rf /\"'
  blocked "$shell" "dash -c is blocked" 'dash -c \"rm -rf ~\"'
  blocked "$shell" "ksh -c is blocked" 'ksh -c \"git clean -fdx\"'
  blocked "$shell" "bash -lc is blocked" 'bash -lc \"git push -f\"'
  blocked "$shell" "bash -ec is blocked" 'bash -ec \"git commit --no-verify -m x\"'
  blocked "$shell" "/bin/bash -c is blocked" '/bin/bash -c \"git stash clear\"'
  blocked "$shell" "bash --norc -c is blocked" 'bash --norc -c \"git push --force\"'
  blocked "$shell" "bash -o pipefail -c is blocked" 'bash -o pipefail -c \"git push --force\"'
  blocked "$shell" "sudo bash -c is blocked" 'sudo bash -c \"rm -rf /\"'
  blocked "$shell" "bash -c with a variable path is blocked" 'bash -c \"rm -rf $DIR\"'
  blocked "$shell" "bash -c with a glob under a variable is blocked" 'bash -c \"rm $DIR/*\"'
  blocked "$shell" "bash -c with a workspace path is blocked" 'bash -c \"rm -rf /c/dev/proj\"'
  blocked "$shell" "bash -c chained inner command is blocked" 'bash -c \"cd x && git push --force\"'
  blocked "$shell" "powershell -Command is blocked" 'powershell -Command \"Remove-Item -Recurse -Force C:\\\"'
  blocked "$shell" "powershell -Command git push is blocked" 'powershell -Command \"git push --force\"'
  blocked "$shell" "powershell -c is blocked" 'powershell -c \"git reset --hard\"'
  blocked "$shell" "powershell -com is blocked" 'powershell -com \"git reset --hard\"'
  blocked "$shell" "powershell -COMMAND (any case) is blocked" 'powershell -COMMAND \"git reset --hard\"'
  blocked "$shell" "pwsh -c is blocked" 'pwsh -c \"git push -f\"'
  blocked "$shell" "pwsh -Command unquoted tokens is blocked" 'pwsh -Command git push --force origin x'
  blocked "$shell" "powershell.exe -NoProfile -Command is blocked" 'powershell.exe -NoProfile -Command \"Remove-Item -Recurse -Force C:\\\"'
  blocked "$shell" "powershell -ExecutionPolicy Bypass -Command is blocked" 'powershell -ExecutionPolicy Bypass -Command \"git clean -fd\"'
  blocked "$shell" "full-path powershell.exe -Command is blocked" 'C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe -Command \"rm -rf /\"'
  blocked "$shell" "powershell -EncodedCommand is blocked" 'powershell -EncodedCommand ZwBpAHQA'
  blocked "$shell" "powershell -enc is blocked" 'powershell -NoProfile -enc ZwBpAHQA'
  blocked "$shell" "powershell -e is blocked" 'powershell -e ZwBpAHQA'
  blocked "$shell" "pwsh -ec is blocked" 'pwsh -ec ZwBpAHQA'
  blocked "$shell" "cmd /c rd /s /q C:\\ is blocked" 'cmd /c rd /s /q C:\\'
  blocked "$shell" "cmd.exe /k is blocked" 'cmd.exe /k rd /s /q C:\\'
  blocked "$shell" "CMD /C (any case) is blocked" 'CMD /C rd /s /q C:\\'
  blocked "$shell" "cmd /d /c is blocked" 'cmd /d /c rd /s /q C:\\'
  blocked "$shell" "cmd /c git push --force is blocked" 'cmd /c git push --force'
  blocked "$shell" "cmd /c quoted is blocked" 'cmd /c \"del /s /q C:\\*\"'
  blocked "$shell" "cmd //c from Git Bash is blocked" 'cmd //c rd /s /q C:\\'
  blocked "$shell" "two wrappers deep is blocked" 'bash -c \"sh -c '"'"'git push --force'"'"'\"'
  blocked "$shell" "three wrappers deep is blocked" 'bash -c \"sh -c '"'"'cmd /c rd /s /q C:\\'"'"'\"'
  blocked "$shell" "four wrappers deep is refused as too deep" 'bash -c \"sh -c '"'"'cmd /c powershell -c dir'"'"'\"'
  allowed "$shell" "bash -c ls -la is allowed" 'bash -c \"ls -la\"'
  allowed "$shell" "bash -lc make is allowed" 'bash -lc \"make test\"'
  allowed "$shell" "bash script.sh is allowed" 'bash scripts/check.sh'
  allowed "$shell" "bash script.sh -c arg is allowed (the -c belongs to the script)" 'bash scripts/check.sh -c x'
  allowed "$shell" "sh -c git status is allowed" "sh -c 'git status'"
  allowed "$shell" "powershell -Command Get-ChildItem is allowed" 'powershell -Command \"Get-ChildItem\"'
  allowed "$shell" "powershell -NoProfile -c git status is allowed" 'powershell -NoProfile -c \"git status\"'
  allowed "$shell" "powershell -ExecutionPolicy Bypass -File is allowed" 'powershell -ExecutionPolicy Bypass -File build.ps1'
  allowed "$shell" "pwsh -Command Remove-Item narrow path is allowed" 'pwsh -Command \"Remove-Item -Recurse -Force C:\\dev\\x\"'
  allowed "$shell" "cmd /c dir is allowed" 'cmd /c dir'
  allowed "$shell" "cmd /c del file.txt is allowed" 'cmd /c del file.txt'
  allowed "$shell" "three wrappers of harmless nesting is allowed" 'bash -c \"sh -c '"'"'cmd /c dir'"'"'\"'
  guard "$shell" 'bash -c \"sh -c '"'"'cmd /c powershell -c dir'"'"'\"'
  assert_contains "$shell: the nesting reason is stated" "command nested too deeply to check"
  guard "$shell" 'powershell -enc ZwBpAHQA'
  assert_contains "$shell: the encoded-command reason is stated" "encoded PowerShell command cannot be checked"

  # Shell syntax must not hide the command name.
  blocked "$shell" "if/then hides git reset --hard" 'if true; then git reset --hard; fi'
  blocked "$shell" "for/do hides rm -rf /" 'for d in a b; do rm -rf /; done'
  blocked "$shell" "while/do hides git clean -fdx" 'while true; do git clean -fdx; done'
  blocked "$shell" "elif hides git reset --hard" 'if false; then ls; elif true; then git reset --hard; fi'
  blocked "$shell" "else hides git reset --hard" 'if false; then ls; else git reset --hard; fi'
  blocked "$shell" "until/do hides rm -rf /" 'until false; do rm -rf /; done'
  blocked "$shell" "a brace block hides git push --force" '{ git push --force; }'
  blocked "$shell" "a subshell hides rm -rf ~" '(rm -rf ~)'
  blocked "$shell" "a leading ! hides git reset --hard" '! git reset --hard'
  blocked "$shell" "a case arm hides rm -rf /" 'case x in a) rm -rf / ;; esac'
  blocked "$shell" "\$(...) hides rm -rf /" '$(rm -rf /)'
  blocked "$shell" "\$(...) inside an argument hides rm -rf /" 'echo $(rm -rf /)'
  blocked "$shell" "backticks hide rm -rf /" '`rm -rf /`'
  blocked "$shell" "a function body hides rm -rf /" 'f() { rm -rf /; }; f'
  blocked "$shell" "PowerShell if block hides a Remove-Item of the workspace" 'if (Test-Path x) { Remove-Item -Recurse -Force C:\\dev\\proj }'
  blocked "$shell" "PowerShell if block hides a Remove-Item of home" 'if (Test-Path x) { Remove-Item -Recurse -Force C:\\Users\\tester }'
  blocked "$shell" "PowerShell foreach block hides a recursive Remove-Item of a variable" 'foreach ($d in $dirs) { Remove-Item -Recurse -Force $d }'
  guard_ctx "$shell" 'if (Test-Path x) { Remove-Item -Recurse -Force C:\\Users\\someone }' "" "/c/Users/someone" 'C:\Users\someone' ""
  assert_rc "$shell: PowerShell if block hides a Remove-Item of the home C:\\Users\\someone" 2
  blocked "$shell" "rm -rf \${BUILD_DIR:?}/x (quoted, recursive) is blocked" 'rm -rf \"${BUILD_DIR:?}/x\"'
  blocked "$shell" "rm -rf \${BUILD_DIR}/x is blocked" 'rm -rf ${BUILD_DIR}/x'
  blocked "$shell" "rm -rf \"\${HOME}/x\" is blocked" 'rm -rf \"${HOME}/x\"'
  blocked "$shell" "rm \${HOME} (not recursive) is still a forbidden target" 'rm ${HOME}'
  blocked "$shell" "rm -rf \$(pwd) is blocked" 'rm -rf $(pwd)'
  blocked "$shell" "brace expansion to / is blocked" 'rm -rf /{usr,etc}'
  allowed "$shell" "git commit -m with a parenthesised scope is allowed" 'git commit -m \"fix (scope): text\"'
  allowed "$shell" "git log --format with parentheses is allowed" 'git log --format=\"%H (%an)\"'
  allowed "$shell" "echo \$(date) is allowed" 'echo $(date)'
  allowed "$shell" "an if/then/fi with a test is allowed" 'if [ -f x ]; then echo ok; fi'
  allowed "$shell" "a for loop over globs is allowed" 'for f in *.md; do wc -l \"$f\"; done'
  allowed "$shell" "powershell -Command with a script block is allowed" 'powershell -Command \"Get-ChildItem | ForEach-Object { $_.Name }\"'
  allowed "$shell" "a PowerShell foreach that only reads is allowed" 'foreach ($d in $dirs) { Get-Item $d }'
  allowed "$shell" "a loop removing a narrow literal path is allowed" 'for d in a b; do rm -rf build/out; done'
  guard "$shell" 'if true; then git reset --hard; fi'
  assert_contains "$shell: the hidden command's reason is stated" "git reset --hard discards work"

  # Recursive removal of a .git directory.
  blocked "$shell" "rm -rf .git is blocked" 'rm -rf .git'
  blocked "$shell" "rm -rf .git/ is blocked" 'rm -rf .git/'
  blocked "$shell" "rm -rf ./.git is blocked" 'rm -rf ./.git'
  blocked "$shell" "rm -rf sub/.git/ is blocked" 'rm -rf sub/.git/'
  blocked "$shell" "rm -rf /tmp/x/y/.git is blocked" 'rm -rf /tmp/x/y/.git'
  blocked "$shell" "rm -rf .GIT (any case) is blocked" 'rm -rf .GIT'
  blocked "$shell" "rm -rf .git/* is blocked" 'rm -rf .git/*'
  blocked "$shell" "rm -rf sub/../.git is blocked" 'rm -rf sub/../.git'
  blocked "$shell" "Remove-Item -Recurse -Force .git is blocked" 'Remove-Item -Recurse -Force .git'
  blocked "$shell" "Remove-Item -Recurse -Force sub\\.git\\ is blocked" 'Remove-Item -Recurse -Force sub\\.git\\'
  blocked "$shell" "rd /s /q .git is blocked" 'rd /s /q .git'
  blocked "$shell" "a quoted path to .git is blocked" 'rm -rf \"my repo/.git\"'
  allowed "$shell" "rm -rf .github is allowed" 'rm -rf .github'
  allowed "$shell" "rm -rf .gitignore-old is allowed" 'rm -rf .gitignore-old'
  allowed "$shell" "rm -rf foo.git is allowed" 'rm -rf foo.git'
  allowed "$shell" "rm -f .git/index.lock (not recursive) is allowed" 'rm -f .git/index.lock'
  allowed "$shell" "rm .git (not recursive) is allowed" 'rm .git'
  allowed "$shell" "rm -rf .git/hooks/old is allowed" 'rm -rf .git/hooks/old'
  guard "$shell" 'rm -rf .git'
  assert_contains "$shell: the .git reason is stated" "recursive removal of a .git directory destroys history"

  # A cd earlier in the command moves where relative targets point.
  CDWS='C:\\dev\\proj'
  blocked_in "$shell" "cd .. then rm -rf of the workspace folder is blocked" 'cd .. && rm -rf proj' "$CDWS"
  blocked_in "$shell" "cd .. then rm -rf of the quoted workspace folder is blocked" 'cd .. && rm -rf \"proj\"' "$CDWS"
  blocked_in "$shell" "cd /c/dev then rm -rf of the workspace folder is blocked" 'cd /c/dev && rm -rf proj' "$CDWS"
  blocked_in "$shell" "cd /c then rm -rf of an ancestor is blocked" 'cd /c && rm -rf dev' "$CDWS"
  blocked_in "$shell" "cd C:\\dev then rm -rf of the workspace folder is blocked" 'cd C:\\dev && rm -rf proj' "$CDWS"
  blocked_in "$shell" "cd .. ; cd .. then rm -rf proj is blocked" 'cd ..; cd ..; rm -rf proj' 'C:\\dev\\proj\\sub'
  blocked_in "$shell" "Set-Location .. then Remove-Item of the workspace folder is blocked" 'Set-Location ..; Remove-Item -Recurse -Force proj' "$CDWS"
  blocked_in "$shell" "sl .. then Remove-Item of the workspace folder is blocked" 'sl ..; Remove-Item -Recurse -Force proj' "$CDWS"
  blocked_in "$shell" "pushd .. then rm -rf of the workspace folder is blocked" 'pushd ..; rm -rf proj' "$CDWS"
  blocked_in "$shell" "chdir .. then rm -rf of the workspace folder is blocked" 'chdir .. && rm -rf proj' "$CDWS"
  blocked_in "$shell" "cmd cd /d then rm of the workspace folder is blocked" 'cd /d C:\\dev && rm -rf proj' "$CDWS"
  blocked_in "$shell" "cd ~/.. then rm -rf of home is blocked" 'cd ~/.. && rm -rf tester' "$CDWS"
  blocked_in "$shell" "cd sub then rm -rf ../.. (the workspace's parent) is blocked" 'cd sub && rm -rf ../..' "$CDWS"
  blocked_in "$shell" "cd inside a subshell persists: (cd ..) then rm -rf proj is blocked" '(cd ..) && rm -rf proj' "$CDWS"
  # The subshell cd does not persist in a real shell: the target is also
  # resolved against the payload cwd, so ../.. from a workspace subfolder is refused.
  blocked_in "$shell" "a subshell cd elsewhere does not hide ../.. from the workspace cwd" '(cd /tmp/a/b/c); rm -rf ../..' 'C:\\dev\\proj\\sub'
  allowed_in "$shell" "a subshell cd elsewhere still allows a narrow sibling inside the workspace" '(cd /tmp/a/b/c); rm -rf ../x' 'C:\\dev\\proj\\sub'
  blocked_in "$shell" "cd inside bash -c is inherited by the inner rm" 'bash -c \"cd .. && rm -rf proj\"' "$CDWS"
  blocked_in "$shell" "cd inside sh -c with single quotes is inherited" "sh -c 'cd .. && rm -rf proj'" "$CDWS"
  blocked_in "$shell" "cd inside powershell -Command is inherited" 'powershell -Command \"Set-Location ..; Remove-Item -Recurse -Force proj\"' "$CDWS"
  guard_ctx "$shell" 'cd .. && rm -rf \"New Project\"' 'C:\\dev\\work\\New Project' "$G_HOME" "$G_UP" 'C:\dev\work\New Project'
  assert_rc "$shell: cd .. then rm -rf \"New Project\" from the workspace is blocked" 2
  # A backslash-escaped space (Git Bash tab completion) or a PowerShell
  # backtick-escaped space keeps the workspace name in one word.
  guard_ctx "$shell" 'cd .. && rm -rf New\\ Project' 'C:\\dev\\work\\New Project' "$G_HOME" "$G_UP" 'C:\dev\work\New Project'
  assert_rc "$shell: cd .. then rm -rf New\\ Project (escaped space) is blocked" 2
  guard_ctx "$shell" 'rm -rf /c/dev/work/New\\ Project' 'C:\\dev\\work\\New Project' "$G_HOME" "$G_UP" 'C:\dev\work\New Project'
  assert_rc "$shell: rm -rf of the workspace by an escaped-space path is blocked" 2
  guard_ctx "$shell" 'Remove-Item -Recurse -Force C:\\dev\\work\\New` Project' 'C:\\dev\\work\\New Project' "$G_HOME" "$G_UP" 'C:\dev\work\New Project'
  assert_rc "$shell: Remove-Item of the workspace by a backtick-escaped space is blocked" 2
  guard_ctx "$shell" 'rm -rf build/New\\ Folder' 'C:\\dev\\work\\New Project' "$G_HOME" "$G_UP" 'C:\dev\work\New Project'
  assert_rc "$shell: an escaped-space folder inside the workspace is allowed" 0
  guard_ctx "$shell" 'cmd /c rd /s /q \"C:\\dev\\work\\New Project\"' 'C:\\dev\\work\\New Project' "$G_HOME" "$G_UP" 'C:\dev\work\New Project'
  assert_rc "$shell: cmd /c rd /s /q of the quoted workspace is blocked" 2
  guard_ctx "$shell" 'cmd //c rd /s /q \"C:\\dev\\work\\New Project\"' 'C:\\dev\\work\\New Project' "$G_HOME" "$G_UP" 'C:\dev\work\New Project'
  assert_rc "$shell: cmd //c rd /s /q of the quoted workspace is blocked" 2
  guard_ctx "$shell" 'pwsh -Command Remove-Item -Recurse -Force \"C:\\dev\\work\\New Project\"' 'C:\\dev\\work\\New Project' "$G_HOME" "$G_UP" 'C:\dev\work\New Project'
  assert_rc "$shell: pwsh -Command Remove-Item of the quoted workspace is blocked" 2
  guard_ctx "$shell" 'bash -c \"rm -rf \\\"/c/dev/work/New Project\\\"\"' 'C:\\dev\\work\\New Project' "$G_HOME" "$G_UP" 'C:\dev\work\New Project'
  assert_rc "$shell: bash -c with an escaped-quote workspace path is blocked" 2
  guard_ctx "$shell" 'cmd /c rd /s /q \"C:\\dev\\work\\New Project\\build out\"' 'C:\\dev\\work\\New Project' "$G_HOME" "$G_UP" 'C:\dev\work\New Project'
  assert_rc "$shell: cmd /c rd of a quoted narrow folder with a space is allowed" 0
  guard_ctx "$shell" 'bash -c \"rm -rf \\\"/c/dev/work/New Project/build out\\\"\"' 'C:\\dev\\work\\New Project' "$G_HOME" "$G_UP" 'C:\dev\work\New Project'
  assert_rc "$shell: bash -c with an escaped-quote narrow path is allowed" 0
  guard_ctx "$shell" 'cmd /c rd /s /q \"C:\\\"' 'C:\\dev\\work\\New Project' "$G_HOME" "$G_UP" 'C:\dev\work\New Project'
  assert_rc "$shell: rd /s /q of a quoted drive root ending in a backslash is still blocked" 2
  # A cd the guard cannot resolve refuses a recursive relative removal.
  blocked_in "$shell" "cd \$X then rm -rf out is blocked" 'cd $X && rm -rf out' "$CDWS"
  blocked_in "$shell" "cd \"\$(dirname x)\" then rm -rf out is blocked" 'cd \"$(dirname x)\" && rm -rf out' "$CDWS"
  blocked_in "$shell" "cd %X% then rd /s /q out is blocked" 'cd %X% && rd /s /q out' "$CDWS"
  blocked_in "$shell" "cd - then rm -rf out is blocked" 'cd - && rm -rf out' "$CDWS"
  blocked_in "$shell" "popd then rm -rf out is blocked" 'popd; rm -rf out' "$CDWS"
  blocked_in "$shell" "Pop-Location then Remove-Item out is blocked" 'Pop-Location; Remove-Item -Recurse -Force out' "$CDWS"
  blocked_in "$shell" "pushd with no argument then rm -rf out is blocked" 'pushd; rm -rf out' "$CDWS"
  blocked_in "$shell" "cd ~user then rm -rf out is blocked" 'cd ~root && rm -rf out' "$CDWS"
  blocked_in "$shell" "an unresolved cd persists across segments" 'cd - ; ls ; rm -rf out' "$CDWS"
  blocked "$shell" "no cwd and a relative cd: cd sub then rm -rf out is blocked" 'cd sub && rm -rf out'
  guard_ctx "$shell" 'cd $X && rm -rf out' 'C:\\dev\\proj' "$G_HOME" "$G_UP" "$G_PROJ"
  assert_contains "$shell: the unresolved-cd reason is stated" "recursive removal of a relative path after a cd the guard cannot resolve (use an absolute path)"
  guard "$shell" 'cd sub && rm -rf out'
  assert_contains "$shell: the no-cwd relative-cd reason is stated" "recursive removal of a relative path after a cd the guard cannot resolve (use an absolute path)"
  # cd keeps ordinary commands working.
  allowed_in "$shell" "cd build then rm -rf out is allowed" 'cd build && rm -rf out' "$CDWS"
  allowed_in "$shell" "cd /c/dev/proj/sub then rm -rf ../tmp is allowed (inside the workspace)" 'cd /c/dev/proj/sub && rm -rf ../tmp' "$CDWS"
  allowed "$shell" "an absolute cd with no cwd then rm -rf ../tmp is allowed" 'cd /c/dev/proj/sub && rm -rf ../tmp'
  allowed_in "$shell" "pushd build; rm -rf out; popd is allowed" 'pushd build; rm -rf out; popd' "$CDWS"
  allowed_in "$shell" "Set-Location build; Remove-Item out is allowed" 'Set-Location build; Remove-Item -Recurse -Force out' "$CDWS"
  allowed_in "$shell" "cd .. then rm -rf of a sibling is allowed" 'cd .. && rm -rf other' "$CDWS"
  allowed_in "$shell" "cd ~ then rm -rf of a child of home is allowed" 'cd ~ && rm -rf .cache/x' "$CDWS"
  allowed_in "$shell" "cd with a quoted path with a space is allowed" 'cd \"my dir\" && rm -rf out' "$CDWS"
  allowed_in "$shell" "an unresolved cd without recursion is allowed" 'cd - && rm file.txt' "$CDWS"
  allowed_in "$shell" "an unresolved cd then an absolute narrow path is allowed" 'cd - && rm -rf /tmp/x/y' "$CDWS"
  allowed "$shell" "no cwd and no cd: rm -rf out stays allowed" 'rm -rf out'
  allowed "$shell" "no cwd: an absolute cd then rm -rf out is allowed" 'cd /tmp/x && rm -rf out'
  allowed "$shell" "cd alone is allowed" 'cd sub'
done

# Payload shape: command extraction versus whole-text fallback.
OUT="$(printf '{"tool_name":"Bash","tool_input":{"command":"ls","description":"rm -rf /"}}' | bash "$GUARD" 2>&1)"; RC=$?
assert_rc "a description that mentions rm -rf / is allowed when the command is ls" 0
OUT="$(printf '{"tool_name":"Bash","tool_input":{"description":"x","command":"ls -la"}}' | bash "$GUARD" 2>&1)"; RC=$?
assert_rc "a command key after the description is read" 0
OUT="$(printf '{"tool_name":"Bash","tool_input":{"description":"x","command":"rm -rf /"}}' | bash "$GUARD" 2>&1)"; RC=$?
assert_rc "a command key after the description is still scanned" 2
OUT="$(printf '{"tool_name":"Bash","tool_input":{"command"  :  "rm -rf /"}}' | bash "$GUARD" 2>&1)"; RC=$?
assert_rc "whitespace around the command colon is tolerated" 2
OUT="$(printf '{"tool_name":"Bash","tool_input":{"cmd":"rm -rf /"}}' | bash "$GUARD" 2>&1)"; RC=$?
assert_rc "a payload with no command key falls back to a whole-text scan" 2
assert_contains "the fallback block names the guard" "$PREFIX"
OUT="$(printf '{"tool_name":"Bash","tool_input":{"cmd":"ls"}}' | bash "$GUARD" 2>&1)"; RC=$?
assert_rc "a payload with no command key and nothing dangerous is allowed" 0
OUT="$(printf '' | bash "$GUARD" 2>&1)"; RC=$?
assert_rc "an empty payload is allowed" 0
OUT="$(printf '{"tool_name":"Bash","tool_input":{"command":""}}' | bash "$GUARD" 2>&1)"; RC=$?
assert_rc "an empty command is allowed" 0

# The block message carries the reason, the matched segment, and the hand-off.
guard Bash 'cd x && rm -rf /'
assert_contains "the block names the kernel rules and the doc" "(kernel rules 6 and 11, docs/rules/destructive-actions.md)"
assert_contains "the block quotes the matched segment" "Matched: rm -rf /."
assert_contains "the block tells the agent to hand off to the human" "ask them to run it themselves"

# Backslash-escaped inner quotes in a commit message are one quoted word.
for shell in Bash PowerShell; do
  allowed "$shell" "git commit -m with backslash-escaped inner quotes is allowed" 'git commit -m \"fix \\\"x\\\" thing\"'
  allowed "$shell" "git commit -m with escaped inner quotes then a flag is allowed" 'git commit -m \"note \\\"x\\\" done\" --amend'
done

# Process kills by image name hit every process of that name, not only the
# ones this session started.
for shell in Bash PowerShell; do
  blocked "$shell" "taskkill /IM is blocked" 'taskkill /IM node.exe'
  blocked "$shell" "taskkill /F /IM is blocked" 'taskkill /F /IM node.exe'
  blocked "$shell" "taskkill /im (any case) is blocked" 'taskkill /f /im Node.exe'
  blocked "$shell" "taskkill //IM (Git Bash spelling) is blocked" 'taskkill //F //IM node.exe'
  blocked "$shell" "taskkill -im is blocked" 'taskkill -f -im node.exe'
  blocked "$shell" "taskkill /FI imagename filter is blocked" 'taskkill /FI \"IMAGENAME eq node.exe\"'
  blocked "$shell" "taskkill.exe /IM is blocked" 'taskkill.exe /IM node.exe'
  blocked "$shell" "cmd /c taskkill /IM is blocked" 'cmd /c taskkill /IM node.exe'
  blocked "$shell" "Stop-Process -Name is blocked" 'Stop-Process -Name node'
  blocked "$shell" "Stop-Process -Name -Force is blocked" 'Stop-Process -Name node -Force'
  blocked "$shell" "Stop-Process -ProcessName is blocked" 'Stop-Process -ProcessName node'
  blocked "$shell" "Stop-Process -Na (abbreviation) is blocked" 'Stop-Process -Na node'
  blocked "$shell" "spps -Name is blocked" 'spps -Name node'
  blocked "$shell" "pwsh -Command Stop-Process -Name is blocked" 'pwsh -Command \"Stop-Process -Name node\"'
  blocked "$shell" "pkill is blocked" 'pkill node'
  blocked "$shell" "pkill -f is blocked" 'pkill -f server.js'
  blocked "$shell" "killall is blocked" 'killall node'
  blocked "$shell" "sudo killall is blocked" 'sudo killall -9 node'
  allowed "$shell" "taskkill /PID is allowed" 'taskkill /PID 1234 /F'
  allowed "$shell" "Stop-Process -Id is allowed" 'Stop-Process -Id 1234'
  allowed "$shell" "kill by pid is allowed" 'kill 1234'
  allowed "$shell" "kill -9 by pid is allowed" 'kill -9 1234'
  allowed "$shell" "a commit message that names pkill is allowed" 'git commit -m \"docs: ban pkill and taskkill /IM\"'
done

# git -c core.hooksPath= swaps the hooks away, the same as --no-verify.
for shell in Bash PowerShell; do
  blocked "$shell" "git -c core.hooksPath=/dev/null commit is blocked" 'git -c core.hooksPath=/dev/null commit -m x'
  blocked "$shell" "git -c core.hookspath= (any case) is blocked" 'git -c core.hookspath= push'
  allowed "$shell" "git -c user.name=x commit is allowed" 'git -c user.name=x commit -m y'
done

# A shell command over about 4 KB is checked and prints nothing: a stderr
# warning on an allowed command is shown only in the user's verbose view.
long_arg="$(printf 'a%.0s' $(seq 1 4200))"
guard Bash "echo $long_arg"
assert_rc "a command over 4 KB that is harmless is allowed" 0
assert_eq "a command over 4 KB that is harmless prints nothing" "" "$OUT"
guard Bash "echo $long_arg && rm -rf /"
assert_rc "a command over 4 KB is still checked" 2

# git global options that take their value as the next word must not hide the
# subcommand (or the hooksPath setting) behind that value.
for shell in Bash PowerShell; do
  blocked "$shell" "git --config-env core.hooksPath=HP (two words) is blocked" 'git --config-env core.hooksPath=HP commit -m x'
  blocked "$shell" "git --config-env=core.hooksPath=HP is blocked" 'git --config-env=core.hooksPath=HP commit -m x'
  blocked "$shell" "git --git-dir .git push --force is blocked" 'git --git-dir .git push --force origin main'
  blocked "$shell" "git --work-tree . reset --hard is blocked" 'git --work-tree . reset --hard'
  blocked "$shell" "git --namespace x push --force is blocked" 'git --namespace x push --force origin main'
  allowed "$shell" "git --config-env=user.name=NAME commit is allowed" 'git --config-env=user.name=NAME commit -m x'
  allowed "$shell" "git --git-dir .git status is allowed" 'git --git-dir .git status'
done

# Case folding covers every letter the locale knows on bash 4+: an accented
# home folder spelled in another case is still the home folder.
U_UP="$(printf '\303\211')"
U_LO="$(printf '\303\251')"
payload="$(printf '{"tool_name":"Bash","tool_input":{"command":"rm -rf c:/users/%smile"}}' "$U_LO")"
OUT="$(printf '%s' "$payload" | env LC_ALL=C.UTF-8 HOME="C:\\Users\\${U_UP}mile" USERPROFILE="" CLAUDE_PROJECT_DIR="$G_PROJ" bash "$GUARD" 2>&1)"; RC=$?
assert_rc "a non-ASCII home spelled in another case is blocked (LC_ALL=C.UTF-8)" 2
assert_contains "the non-ASCII home block names the guard" "$PREFIX"

# An unexpected bash error inside the guard must block, not exit 1 (which the
# harness treats as a non-blocking error and runs the command).
GFIX="$(mktemp -d)"
cp "$GUARD" "$GFIX/guard.sh"
sed -i.bak '/^trap /a\
: "${GUARD_TEST_UNSET_VARIABLE}"' "$GFIX/guard.sh" && rm -f "$GFIX/guard.sh.bak"
OUT="$(printf '{"tool_name":"Bash","tool_input":{"command":"ls"}}' | env -u GUARD_TEST_UNSET_VARIABLE bash "$GFIX/guard.sh" 2>&1)"; RC=$?
assert_rc "an unexpected error inside the guard blocks" 2
assert_contains "the unexpected-error block says the guard failed" "guard failed"
assert_contains "the unexpected-error block names the guard" "$PREFIX"
cp "$GUARD" "$GFIX/guard.sh"
OUT="$(printf '{"tool_name":"Bash","tool_input":{"command":"ls"}}' | bash "$GFIX/guard.sh" 2>&1)"; RC=$?
assert_rc "the unmodified guard allows the same harmless command" 0
rm -rf "$GFIX"

# Documented under-block: the segment split is quote-unaware, so a protected
# path holding a separator is cut in two and neither half names it.
guard_ctx Bash 'rm -rf \"C:\\x\\R&D\\proj\"' "" "$G_HOME" "$G_UP" 'C:\x\R&D\proj'
assert_rc "KNOWN LIMIT: a workspace whose path holds & is not recognised when quoted" 0

# Wiring: the settings hook covers both shells and runs this script.
assert_file "the guard script exists" "$GUARD"
assert_file_has "settings.json declares a PreToolUse hook" "$SETTINGS" '"PreToolUse"'
assert_file_has "the hook matcher covers Bash and PowerShell" "$SETTINGS" '"matcher": "Bash|PowerShell"'
assert_file_has "the hook runs the guard script" "$SETTINGS" 'scripts/destructive-guard.sh'
mode="$(cd "$T_ROOT" && git ls-files -s scripts/destructive-guard.sh | awk '{print $1}')"
if [[ -n "$mode" ]]; then
  assert_eq "the guard script is executable in the index" "100755" "$mode"
fi

t_finish
