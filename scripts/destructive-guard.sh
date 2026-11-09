#!/usr/bin/env bash
# destructive-guard.sh - PreToolUse hook body for every session (main agent and
# subagents), matcher Bash|PowerShell. Mechanizes kernel rules 6 and 11 and
# docs/rules/destructive-actions.md: forbidden removal targets and destructive
# or hook-skipping git forms are refused before they run.
# Input: the hook payload (JSON) on stdin, e.g.
#   {"tool_name":"Bash","tool_input":{"command":"rm -rf /"},"cwd":"C:\\dev\\x"}
# The "command" string is extracted and JSON-unescaped, so a description that
# merely mentions a dangerous command is not matched. If no "command" key is
# found, the whole payload text is scanned instead. The optional "cwd" field is
# the workspace; with it, relative removal targets are resolved before checking.
# Parsing: the command is split into segments on newlines, ; & | ( ) { } and
# backticks (so $(...), subshells, blocks and PowerShell script blocks expose
# the command inside), ${NAME} is read as $NAME, each segment is tokenised on
# whitespace outside quotes (quote characters are dropped), and leading
# wrappers (sudo, command, nohup, time, exec, xargs, env, the PowerShell call
# operator &, NAME=value prefixes and their options) and shell keywords (if,
# then, else, elif, do, while, until, !) are dropped. The command name is the
# lowercased basename without .exe.
# Directory tracking: the current directory starts at the payload cwd; cd,
# pushd, chdir, Set-Location, sl and Push-Location change it for the segments
# after them (no argument: HOME; ~ and ~/x from HOME; other paths resolved
# against the current directory). A target that is - or +N, holds a $ or %NAME%,
# is ~user, or any popd, leaves the directory UNKNOWN, as does a relative cd
# when no cwd is known. Relative removal targets resolve against the current
# directory; a recursive removal of a relative path while it is UNKNOWN is
# refused. A cd inside parentheses, braces or a wrapper (bash -c "cd x") is
# treated as persisting for what follows.
# Interpreter wrappers are unwrapped and the inner text is checked the same
# way, to a nesting depth of 3 (deeper is refused): bash/sh/zsh/dash/ksh -c
# (clusters such as -lc too), powershell/pwsh -Command (any prefix of at least
# -c; -EncodedCommand cannot be read and is refused), cmd /c and /k.
# Blocks:
#   rm, rmdir, rd, del, erase, ri, remove-item
#     - any flags: a filesystem/drive/home/workspace root or a broad glob
#       (/, ~, ., .., *, C:\, /c, $HOME, %USERPROFILE%, ...); a glob under an
#       unresolved variable ($X/*, %X%\*, $env:X\*); the home directory
#       (HOME, USERPROFILE) or the workspace (CLAUDE_PROJECT_DIR, payload cwd)
#       given by literal path
#     - recursive flags (-r -rf -fr --recursive -Recurse, /s): a target with an
#       unresolved variable ($X, %X%), a top-level directory (/usr, C:\Users),
#       or a folder that is, or contains, the home directory or the workspace
#       (paths are compared after backslash/drive/case/dot normalisation, so
#       C:\Users\a, C:/Users/a and /c/Users/a are the same folder)
#     - recursive flags: a .git directory (.git, x/.git, .git/, .git/*)
#   git: --no-verify; commit -n; push --force/--force-with-lease/--delete/
#     --mirror/--prune/-f/-d or a +ref or :ref refspec; reset --hard;
#     clean -f (unless a dry run); branch -D or -d with -f; checkout -f or a
#     whole-tree target; restore of the whole tree (unless --staged only);
#     stash drop and stash clear; -c core.hooksPath= (or --config-env of it).
#   taskkill /IM (or a /FI imagename filter), Stop-Process/spps/kill -Name or
#     -ProcessName, pkill, killall: a kill by image name can end processes this
#     session did not start; kill by PID. Any command over about 4 KB only
#     warns on stderr (exit stays 0), because long literal commands can fail
#     with a quote error before any hook runs.
# Escaped spaces (bash \ and PowerShell ` before a space) stay inside the word,
# and wrapper arguments are re-quoted when the inner command is rebuilt.
# Limits: the segment split is quote-unaware, so a separator or bracket
# (; & | ( ) { } backtick) inside a quoted string splits it too and a commit
# message containing "; git push --force" is refused (accepted over-blocking).
# The same split under-blocks: a protected path that holds one of those
# characters (a workspace under C:/x/R&D/proj) is cut in two even when quoted,
# and neither half names the workspace, so a quoted removal of it is allowed.
# Rare forms are also not read: a backtick substitution or PowerShell
# expression as a target, ~+ and ~- as a path, a partial glob such as New*, a
# PowerShell -Path:<value>, shortened git long options (--forc), and a kill
# fed through a pipe (Get-Process -Name x | Stop-Process). ADR 0006 records
# these as limits, not defects.
# Not parsed: eval, scripts run from files, aliases or functions defined
# earlier in the shell, and targets fed through a pipe such as
# Get-ChildItem ~ | Remove-Item -Recurse. A cd in a subshell or wrapper is
# treated as persisting, so a relative target is also resolved against the
# payload cwd and either resolution can refuse it. A relative target is skipped by the home/workspace
# check when the payload carries no cwd and no cd happened.
# Over-blocking is acceptable on purpose: a false block costs one human-run
# command, a false allow can destroy work that git cannot recover. There is no
# bypass flag or environment variable.
# Exit: 0 allow; 2 block, with the reason on stderr for the agent to read.
# Needs bash 3.2 or newer (macOS /bin/bash works; Git for Windows ships 5):
# no ${x,,}, no associative arrays, no mapfile, no $'..' inside "${..}", and
# every array expansion is guarded for an empty array under set -u.
set -uo pipefail

if (( BASH_VERSINFO[0] < 3 || (BASH_VERSINFO[0] == 3 && BASH_VERSINFO[1] < 2) )); then
  echo "BLOCKED by scripts/destructive-guard.sh: needs bash 3.2 or newer (found ${BASH_VERSION}); install a newer bash or ask the human to run the command themselves." >&2
  exit 2
fi

NL=$'\n'

# lc STRING -> LC. Lowercase with builtins only: ${x,,} needs bash 4, and a
# fork per call is too slow for a hook that runs on every command.
lc() {
  LC="$1"
  case "$LC" in
    *[A-Z]*)
      LC=${LC//A/a}; LC=${LC//B/b}; LC=${LC//C/c}; LC=${LC//D/d}; LC=${LC//E/e}
      LC=${LC//F/f}; LC=${LC//G/g}; LC=${LC//H/h}; LC=${LC//I/i}; LC=${LC//J/j}
      LC=${LC//K/k}; LC=${LC//L/l}; LC=${LC//M/m}; LC=${LC//N/n}; LC=${LC//O/o}
      LC=${LC//P/p}; LC=${LC//Q/q}; LC=${LC//R/r}; LC=${LC//S/s}; LC=${LC//T/t}
      LC=${LC//U/u}; LC=${LC//V/v}; LC=${LC//W/w}; LC=${LC//X/x}; LC=${LC//Y/y}
      LC=${LC//Z/z}
      ;;
  esac
}

block() { # reason segment
  echo "BLOCKED by scripts/destructive-guard.sh (kernel rules 6 and 11, docs/rules/destructive-actions.md): $1. Matched: $2. If the human explicitly asked for this with a verified target, ask them to run it themselves." >&2
  exit 2
}

# json_unescape STRING -> UNESC. Backslash pairs go first (to a placeholder) so
# that C:\new is a path and not a newline; the placeholder becomes one
# backslash last. Patterns are built from variables, not quoted literals,
# because bash 3.2 and 4+ differ on quotes inside ${..//..}.
json_unescape() {
  local s="$1" ph=$'\x01' bs='\' dq='"' sl='/'
  s=${s//"$bs$bs"/$ph}
  s=${s//"${bs}n"/$NL}
  s=${s//"${bs}r"/$NL}
  s=${s//"${bs}t"/ }
  s=${s//"$bs$dq"/$dq}
  s=${s//"$bs$sl"/$sl}
  UNESC=${s//$ph/$bs}
}

payload="$(cat)"
text="$payload"
fallback=0
re_cmd='"command"[[:space:]]*:[[:space:]]*"((\\.|[^"\\])*)"'
re_cwd='"cwd"[[:space:]]*:[[:space:]]*"((\\.|[^"\\])*)"'
if [[ "$payload" =~ $re_cmd ]]; then
  text="${BASH_REMATCH[1]}"
else
  fallback=1
fi
cwd_raw=""
if [[ "$payload" =~ $re_cwd ]]; then
  json_unescape "${BASH_REMATCH[1]}"
  cwd_raw="$UNESC"
fi
json_unescape "$text"
text="$UNESC"
# A very long literal command can fail in the harness with a quote error before
# any hook sees it. Warn only; the checks below still run.
if (( ${#text} > 4096 )); then
  echo "WARNING from scripts/destructive-guard.sh: the command is ${#text} characters (over about 4 KB); long literal commands can fail with a quote error. Write it to a script file and run that instead." >&2
fi

re_assign='^[A-Za-z_][A-Za-z0-9_]*='
re_pct='%[^%[:space:]]+%'
re_top_posix='^/[^/]+/?$'
re_top_gitbash='^/[a-zA-Z]/[^/]+/?$'
re_top_win='^[A-Za-z]:[\\/][^\\/]+[\\/]?$'
re_drive='^([a-z]):(/.*)?$'
re_flagcluster='^-[a-z]{1,4}$'

# norm_path PATH -> NP. One spelling for every path: forward slashes, no
# repeated or trailing slash, lowercase, drive x:/rest as /x/rest, ~ expanded
# from HOME, . and .. resolved, a relative path joined to the base directory
# NBASE (the payload cwd, then the directory a cd moved to).
# Returns 1 when the path cannot be made absolute (relative with no base).
NHOME=""
NCWD=""
NBASE=""
CURUNK=0
norm_path() {
  local p="${1//\\//}" seg IFS=/
  local -a parts=() out=()
  while [[ "$p" == *//* ]]; do p="${p//\/\///}"; done
  lc "$p"; p="$LC"
  if [[ "$p" =~ $re_drive ]]; then
    p="/${BASH_REMATCH[1]}${BASH_REMATCH[2]}"
  elif [[ "$p" == '~' || "$p" == '~/'* ]]; then
    [[ -n "$NHOME" ]] || return 1
    p="$NHOME${p#\~}"
  elif [[ "$p" != /* ]]; then
    [[ -n "$NBASE" ]] || return 1
    p="$NBASE/$p"
  fi
  set -f
  parts=($p)
  set +f
  for seg in ${parts[@]+"${parts[@]}"}; do
    case "$seg" in
      '' | .) ;;
      ..) (( ${#out[@]} )) && unset "out[${#out[@]}-1]" ;;
      *) out+=("$seg") ;;
    esac
  done
  NP="/${out[*]+"${out[*]}"}"
  return 0
}

# Protected folders: home and workspace. Normalised once.
PROT=()
for hv in "${HOME:-}" "${USERPROFILE:-}"; do
  if [[ -n "$hv" && -z "$NHOME" ]] && norm_path "$hv"; then NHOME="$NP"; fi
done
if [[ -n "$cwd_raw" ]] && norm_path "$cwd_raw"; then NCWD="$NP"; fi
NBASE="$NCWD"
for pv in "${HOME:-}" "${USERPROFILE:-}" "${CLAUDE_PROJECT_DIR:-}" "$cwd_raw"; do
  if [[ -n "$pv" ]] && norm_path "$pv"; then PROT+=("$NP"); fi
done

has_var() { [[ "$1" == *'$'* || "$1" =~ $re_pct ]]; }

# Always-forbidden removal target, any flags. $1 is lowercased by the caller.
forbidden_target() {
  case "$1" in
    / | '/*' | '~' | '~/' | '~/*' | . | ./ | './*' | .. | ../ | '*' | '.*') return 0 ;;
    '\' | '.\' | '.\*' | '..\') return 0 ;;
    [a-z]: | [a-z]:\\ | [a-z]:/ | [a-z]:\\\* | [a-z]:/\*) return 0 ;;
    /[a-z] | /[a-z]/ | /[a-z]/\*) return 0 ;;
    '$home' | '${home}' | '$env:userprofile' | '%userprofile%') return 0 ;;
  esac
  return 1
}

# check_protected TARGET RECURSIVE: the target is, or (recursive) contains, the
# home directory or the workspace. A trailing /* or /.* means the folder itself.
check_protected() {
  local tgt pp
  norm_path "$1" || return 0
  tgt="$NP"
  if [[ "$tgt" == */'*' || "$tgt" == */'.*' ]]; then
    tgt="${tgt%/*}"
    [[ -n "$tgt" ]] || tgt="/"
  fi
  for pp in ${PROT[@]+"${PROT[@]}"}; do
    if [[ "$tgt" == "$pp" ]]; then
      if (( $2 )); then
        block "recursive removal of the home directory, the workspace, or a folder containing one" "$SEG"
      fi
      block "removal of the home directory or the workspace itself" "$SEG"
    fi
    if (( $2 )) && [[ "$pp" == "${tgt%/}/"* ]]; then
      block "recursive removal of the home directory, the workspace, or a folder containing one" "$SEG"
    fi
  done
  return 0
}

re_winabs='^[A-Za-z]:'
is_relative() { [[ "$1" != /* && "$1" != \\* && "$1" != '~'* && ! "$1" =~ $re_winabs ]]; }

git_dir_form() { # PATH (slashes forward, lowercase) -> 0 when it names .git
  local g="$1"
  while [[ "$g" == */ || "$g" == */. ]]; do g="${g%?}"; done
  if [[ "$g" == */'*' || "$g" == */'.*' ]]; then g="${g%/*}"; fi
  [[ "$g" == .git || "$g" == */.git ]]
}
# is_git_dir TARGET: the target is a .git directory (or its direct contents
# via a trailing /* or /.*), by its spelling or, when it resolves, by its path.
is_git_dir() {
  local g="${1//\\//}"
  lc "$g"; g="$LC"
  git_dir_form "$g" && return 0
  if norm_path "$1"; then git_dir_form "$NP" && return 0; fi
  return 1
}

check_removal() { # name; arguments in ARGS
  local name="$1" win=0 rec=0 a la lf t lt
  local -a targets=()
  case "$name" in rd | rmdir | del | erase) win=1 ;; esac
  for a in ${ARGS[@]+"${ARGS[@]}"}; do
    lc "$a"; la="$LC"
    if [[ "$a" == -* ]]; then
      lf="${la%%:*}"
      if [[ "$lf" == --recursive ]]; then
        rec=1
      elif [[ "$lf" != --* && ${#lf} -ge 2 && "-recurse" == "$lf"* ]]; then
        rec=1
      elif [[ "$lf" =~ $re_flagcluster && "$lf" == *r* ]]; then
        rec=1
      fi
    elif (( win )) && [[ "$la" =~ ^/[sqf]$ ]]; then
      [[ "$la" == /s ]] && rec=1
    else
      targets+=("$a")
    fi
  done
  for t in ${targets[@]+"${targets[@]}"}; do
    lc "$t"; lt="$LC"
    if forbidden_target "$lt"; then
      block "refused removal target (root, home, workspace root or broad glob; pass a literal narrow absolute path)" "$SEG"
    fi
    if (( rec )) && is_git_dir "$t"; then
      block "recursive removal of a .git directory destroys history" "$SEG"
    fi
    if has_var "$t"; then
      if [[ "$t" == *[*?]* ]]; then
        block "removal of a glob under an unresolved variable (pass the literal path)" "$SEG"
      fi
      if (( rec )); then
        block "recursive removal with an unresolved variable in the target (pass the literal absolute path)" "$SEG"
      fi
      continue
    fi
    if (( rec && CURUNK )) && is_relative "$t"; then
      block "recursive removal of a relative path after a cd the guard cannot resolve (use an absolute path)" "$SEG"
    fi
    check_protected "$t" "$rec"
    # A cd inside a subshell does not persist in the real shell, but this
    # parser treats it as persisting; so a relative target is also resolved
    # against the payload cwd, and either resolution can refuse it.
    if is_relative "$t" && [[ -n "$NCWD" && "$NBASE" != "$NCWD" ]]; then
      local saved_base="$NBASE"
      NBASE="$NCWD"
      check_protected "$t" "$rec"
      NBASE="$saved_base"
    fi
    (( rec )) || continue
    if [[ "$t" =~ $re_top_posix || "$t" =~ $re_top_gitbash || "$t" =~ $re_top_win ]]; then
      block "recursive removal of a top-level directory" "$SEG"
    fi
  done
}

# Helpers over GARGS (git arguments after the subcommand).
g_exact() { local x a; for x in "$@"; do for a in ${GARGS[@]+"${GARGS[@]}"}; do [[ "$a" == "$x" ]] && return 0; done; done; return 1; }
g_prefix() { local x a; for x in "$@"; do for a in ${GARGS[@]+"${GARGS[@]}"}; do [[ "$a" == "$x"* ]] && return 0; done; done; return 1; }
g_cluster() { local a; for a in ${GARGS[@]+"${GARGS[@]}"}; do [[ "$a" =~ ^-[a-zA-Z]+$ && "$a" == *"$1"* ]] && return 0; done; return 1; }
g_first() { [[ "${#GARGS[@]}" -gt 0 && "${GARGS[0]}" == "$1" ]]; }
g_whole_tree() { g_exact . ./ '*' :/; }

check_git() { # arguments in ARGS
  local i=0 n=${#ARGS[@]} a sub=""
  while (( i < n )); do
    a="${ARGS[i]}"
    if [[ "$a" == -* ]]; then
      # git -c core.hooksPath=... points the hooks elsewhere: --no-verify by
      # another route (kernel rule 6).
      lc "$a"
      if [[ "$LC" == --config-env=core.hookspath* ]]; then
        block "git --config-env core.hooksPath replaces the hooks (kernel rule 6)" "$SEG"
      fi
      if [[ "$a" == -c ]] && (( i + 1 < n )); then
        lc "${ARGS[i+1]}"
        if [[ "$LC" == core.hookspath* ]]; then
          block "git -c core.hooksPath replaces the hooks (kernel rule 6)" "$SEG"
        fi
      fi
      if [[ "$a" == -C || "$a" == -c ]]; then i=$((i + 2)); else i=$((i + 1)); fi
    else
      lc "$a"; sub="$LC"
      i=$((i + 1))
      break
    fi
  done
  GARGS=()
  (( i < n )) && GARGS=("${ARGS[@]:i}")

  if g_exact --no-verify; then
    block "git --no-verify skips the hooks (kernel rule 6)" "$SEG"
  fi
  case "$sub" in
    commit)
      g_cluster n && block "git commit -n is --no-verify (kernel rule 6)" "$SEG"
      ;;
    push)
      if g_exact --force --delete --mirror --prune || g_prefix --force-with-lease --force-if-includes \
        || g_cluster f || g_cluster d || g_prefix '+' ':'; then
        block "git push with force, delete, mirror, prune or a +ref/:ref refspec is destructive (kernel rule 6)" "$SEG"
      fi
      ;;
    reset)
      g_exact --hard && block "git reset --hard discards work (kernel rule 6)" "$SEG"
      ;;
    clean)
      if g_exact --force || g_cluster f; then
        if ! g_exact --dry-run && ! g_cluster n; then
          block "git clean -f deletes untracked files (kernel rule 6); dry-run first with -n" "$SEG"
        fi
      fi
      ;;
    branch)
      g_cluster D && block "git branch -D force-deletes a branch (kernel rule 6)" "$SEG"
      if { g_exact --delete || g_cluster d; } && { g_exact --force || g_cluster f; }; then
        block "git branch delete with force (kernel rule 6)" "$SEG"
      fi
      ;;
    checkout)
      if g_exact --force || g_cluster f; then
        block "git checkout -f discards local changes (kernel rule 6)" "$SEG"
      fi
      g_whole_tree && block "git checkout of the whole tree discards local changes (kernel rule 6)" "$SEG"
      ;;
    restore)
      if g_whole_tree; then
        if ! { { g_exact --staged -S; } && ! g_exact --worktree -W; }; then
          block "git restore of the whole tree discards local changes (kernel rule 6)" "$SEG"
        fi
      fi
      ;;
    stash)
      if g_first drop || g_first clear; then
        block "git stash drop/clear destroys stashed work (kernel rule 6)" "$SEG"
      fi
      ;;
  esac
}

# tokenize SEGMENT: split on whitespace outside quotes into toks[]; the quote
# characters are dropped, so "C:\Program Files\Git\cmd\git.exe" is one token
# and a quoted commit message cannot smuggle flag-like words into the checks.
ESC_SP=$'\x02'
tokenize() {
  toks=()
  local s="$1" cur="" q="" c i
  for (( i = 0; i < ${#s}; i++ )); do
    c="${s:i:1}"
    if [[ "$c" == "$ESC_SP" ]]; then
      cur+=" "
    elif (( ESC_READ )) && [[ "$q" == '"' && "$c" == '\' && "${s:i+1:1}" == '"' ]]; then
      cur+='"'
      i=$((i + 1))
    elif [[ -n "$q" ]]; then
      if [[ "$c" == "$q" ]]; then q=""; else cur+="$c"; fi
    elif [[ "$c" == '"' || "$c" == "'" ]]; then
      q="$c"
    elif [[ "$c" == [[:space:]] ]]; then
      [[ -n "$cur" ]] && toks+=("$cur")
      cur=""
    else
      cur+="$c"
    fi
  done
  [[ -n "$cur" ]] && toks+=("$cur")
}

# Interpreter wrappers: each finds the inner command text in ARGS and checks it
# with check_text one level deeper. $1 is the current depth.
check_posix_shell() { # bash/sh/zsh/dash/ksh: the argument after -c (or -lc, -ec, ...)
  local j=0 m=${#ARGS[@]} a
  while (( j < m )); do
    a="${ARGS[j]}"
    if [[ "$a" == -o || "$a" == +o || "$a" == -O || "$a" == +O ]]; then
      j=$((j + 2))
    elif [[ "$a" =~ ^-[a-zA-Z]+$ && "$a" == *c* ]]; then
      (( j + 1 < m )) && check_text "${ARGS[j+1]}" $(($1 + 1))
      return 0
    elif [[ "$a" == -* || "$a" == +* ]]; then
      j=$((j + 1))
    else
      return 0
    fi
  done
  return 0
}

# join_args FROM -> JOINED: ARGS[FROM..] joined by spaces, a word that holds
# whitespace re-quoted (tokenize dropped its quotes), so the inner check sees
# "C:\dev\work\New Project" as one path again.
join_args() {
  local k a out=""
  # One argument is the whole inner command (powershell -Command "..."):
  # pass it through as written. Re-quote only words of a multi-word command.
  if (( $1 + 1 == ${#ARGS[@]} )); then
    JOINED="${ARGS[$1]}"
    return 0
  fi
  for (( k = $1; k < ${#ARGS[@]}; k++ )); do
    a="${ARGS[k]}"
    if [[ "$a" == *[[:space:]]* ]]; then
      if [[ "$a" == *'"'* ]]; then a="'$a'"; else a="\"$a\""; fi
    fi
    out+="${out:+ }$a"
  done
  JOINED="$out"
}
check_powershell() { # powershell/pwsh: tokens after -Command (any prefix >= -c); -EncodedCommand refused
  local j=0 m=${#ARGS[@]} a lf IFS=' '
  while (( j < m )); do
    a="${ARGS[j]}"
    if [[ "$a" == -* ]]; then
      lc "$a"; a="$LC"
      lf="${a%%:*}"
      if [[ "$lf" == -ec ]] || { (( ${#lf} >= 2 )) && [[ "-encodedcommand" == "$lf"* ]]; }; then
        block "encoded PowerShell command cannot be checked" "$SEG"
      fi
      if (( ${#lf} >= 2 )) && [[ "-command" == "$lf"* ]]; then
        join_args $((j + 1))
        check_text "$JOINED" $(($1 + 1))
        return 0
      fi
    fi
    j=$((j + 1))
  done
  return 0
}

check_cmd() { # cmd: tokens after /c or /k
  local j=0 m=${#ARGS[@]} a IFS=' '
  while (( j < m )); do
    a="${ARGS[j]}"
    lc "$a"; a="$LC"
    if [[ "$a" == /c || "$a" == /k || "$a" == //c || "$a" == //k ]]; then
      join_args $((j + 1))
      check_text "$JOINED" $(($1 + 1))
      return 0
    fi
    j=$((j + 1))
  done
  return 0
}

# check_kill NAME: a process kill by image name hits every process of that
# name, including ones this session did not start. Kill by PID instead.
check_kill() {
  local name="$1" a lf min=2
  case "$name" in
    pkill | killall) block "process kill by name ($name) can end unrelated processes (kill the PID you started)" "$SEG" ;;
  esac
  # PowerShell's kill alias takes -Name too; bash kill has -n SIGNUM, so a
  # bare -n there is not a name.
  [[ "$name" == kill ]] && min=3
  for a in ${ARGS[@]+"${ARGS[@]}"}; do
    lc "$a"
    case "$name" in
      taskkill)
        case "$LC" in
          /im | -im | //im | /im:* | -im:*) block "taskkill by image name can end unrelated processes (use /PID of a process you started)" "$SEG" ;;
          *imagename*) block "taskkill filtered by image name can end unrelated processes (use /PID of a process you started)" "$SEG" ;;
        esac
        ;;
      *)
        if [[ "$LC" == -* ]]; then
          lf="${LC%%:*}"
          if { (( ${#lf} >= min )) && [[ "-name" == "$lf"* ]]; } \
            || { (( ${#lf} >= 3 )) && [[ "-processname" == "$lf"* ]]; }; then
            block "Stop-Process by name can end unrelated processes (use -Id of a process you started)" "$SEG"
          fi
        fi
        ;;
    esac
  done
}

cd_unknown() { NBASE=""; CURUNK=1; }

# change_dir NAME: apply a cd-like command (arguments in ARGS) to NBASE/CURUNK.
# The directory state is global on purpose: a recursive call (bash -c "cd x")
# starts from the caller's directory and leaves its change behind.
change_dir() {
  local name="$1" j=0 n=${#ARGS[@]} a t="" found=0
  case "$name" in popd | pop-location) cd_unknown; return 0 ;; esac
  while (( j < n )); do
    a="${ARGS[j]}"
    if [[ "$a" == - ]]; then
      t="-"; found=1; break
    elif lc "$a"; [[ "$LC" == /d ]] && (( j + 1 < n )); then
      j=$((j + 1))
    elif [[ "$a" == -* ]]; then
      j=$((j + 1))
    else
      t="$a"; found=1; break
    fi
  done
  if (( ! found )); then
    # pushd without an argument swaps the top two directories; cd goes home.
    case "$name" in pushd | push-location) cd_unknown; return 0 ;; esac
    t="~"
  fi
  t="${t//\\//}"
  if [[ "$t" == - || "$t" == +[0-9]* || "$t" == '~'?* && "$t" != '~/'* ]] || has_var "$t"; then
    cd_unknown
  elif norm_path "$t"; then
    NBASE="$NP"
    CURUNK=0
  else
    cd_unknown
  fi
  return 0
}

# check_text TEXT DEPTH: split TEXT into segments and check each; wrappers
# recurse. The state tokenize/check_* share is local so recursion cannot
# clobber the caller's segment.
check_text() {
  local in="$1" depth="$2" SEG w name n i m r
  local -a toks=() ARGS=() GARGS=()
  local re_brace='\$\{([A-Za-z_][A-Za-z0-9_]*)\}'
  if (( depth > 3 )); then
    block "command nested too deeply to check" "$in"
  fi
  # ${NAME} is $NAME (so ${HOME} still hits the forbidden targets); any other
  # ${...} falls apart at the brace split below into a bare $ fragment.
  while [[ "$in" =~ $re_brace ]]; do
    m="${BASH_REMATCH[0]}"
    r='$'"${BASH_REMATCH[1]}"
    in=${in/"$m"/$r}
  done
  # An escaped space (bash New\ Project, PowerShell New` Project) is part of
  # the word in the second reading (ESC_READ=1): mark it before the backtick
  # split, tokenize reads it as a space.
  if (( ESC_READ )); then
    in="${in//\\ /$ESC_SP}"
    in="${in//\` /$ESC_SP}"
  fi
  # Segment split, quote-unaware on purpose. && and || fall out of the
  # single-character replacements.
  in=${in//&/$NL}
  in=${in//|/$NL}
  in=${in//;/$NL}
  in=${in//\(/$NL}
  in=${in//\)/$NL}
  in=${in//\{/$NL}
  in=${in//\}/$NL}
  in=${in//\`/$NL}
  if (( fallback && depth == 0 )); then
    # No command field to extract: also cut at JSON punctuation so a command
    # buried in the payload still starts its own segment.
    in=${in//\"/$NL}
    in=${in//,/$NL}
  fi
  while IFS= read -r SEG; do
    SEG="${SEG#"${SEG%%[![:space:]]*}"}"
    SEG="${SEG%"${SEG##*[![:space:]]}"}"
    tokenize "$SEG"
    n=${#toks[@]}
    i=0
    while (( i < n )); do
      w="${toks[i]##*[/\\]}"
      lc "$w"; w="$LC"
      case "$w" in
        sudo | command | nohup | time | exec | xargs)
          i=$((i + 1))
          while (( i < n )) && [[ "${toks[i]}" == -* ]]; do i=$((i + 1)); done
          ;;
        '&' | if | then | else | elif | do | while | until | '!')
          i=$((i + 1))
          ;;
        env)
          i=$((i + 1))
          while (( i < n )) && [[ "${toks[i]}" == -* || "${toks[i]}" =~ $re_assign ]]; do i=$((i + 1)); done
          ;;
        *)
          if [[ "${toks[i]}" =~ $re_assign ]]; then i=$((i + 1)); else break; fi
          ;;
      esac
    done
    (( i < n )) || continue
    name="${toks[i]##*[/\\]}"
    lc "$name"; name="$LC"
    name="${name%.exe}"
    ARGS=()
    (( i + 1 < n )) && ARGS=("${toks[@]:i+1}")
    case "$name" in
      rm | rmdir | rd | del | erase | ri | remove-item) check_removal "$name" ;;
      git) check_git ;;
      cd | pushd | popd | chdir | set-location | sl | push-location | pop-location) change_dir "$name" ;;
      bash | sh | zsh | dash | ksh) check_posix_shell "$depth" ;;
      powershell | pwsh) check_powershell "$depth" ;;
      cmd) check_cmd "$depth" ;;
      taskkill | stop-process | spps | kill | pkill | killall) check_kill "$name" ;;
    esac
  done <<< "$in"
}

# A backslash before a space or a double quote, or a backtick before a space,
# is ambiguous: a bash or PowerShell
# escaped space (New\ Project) or a Windows path ending in a separator
# (C:\ -Recurse). Check both readings; either one can refuse. The cd state
# starts over for the second reading.
ESC_READ=0
check_text "$text" 0
if [[ "$text" == *"\\ "* || "$text" == *'` '* || "$text" == *'\"'* ]]; then
  ESC_READ=1
  NBASE="$NCWD"
  CURUNK=0
  check_text "$text" 0
fi
exit 0
