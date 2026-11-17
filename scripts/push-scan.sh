#!/usr/bin/env bash
# push-scan.sh - PreToolUse hook body, matcher Bash|PowerShell: before a
# `git push` runs, scan the repository the push targets with
# `bash scripts/private-terms.sh check` and refuse the push when it fails.
# Why: CI has no private-terms list (it is gitignored), so only a local scan
# sees a private word; a push from a session that never ran the full gate
# once published private project names (docs/rules/security.md).
# Input: the hook payload (JSON) on stdin, as destructive-guard.sh reads it:
#   {"tool_name":"Bash","tool_input":{"command":"git -C x push"},"cwd":"/p"}
# The "command" string is extracted and JSON-unescaped; "cwd" is the start
# directory.
# Output: exit 0 allow (silent, or a one-line note on stderr); exit 2 block
# with the reason on stderr, followed by the private-terms output (terms are
# masked there). An internal error exits 1, a non-blocking error: this hook
# guards a habit with a local scan, it is not the destructive guard.
# Parsing: the command is split on ; & | ( ) newline and backtick outside
# quotes; quote characters are dropped. Per segment, NAME=value prefixes and
# the wrappers sudo, command, nohup, time, exec, env are skipped; the command
# must be git (basename, .exe dropped); git options are skipped (-C DIR and
# --git-dir/--work-tree/-c/--namespace take a value, other -x words do not);
# the first remaining word is the subcommand. Subcommand push is a push unless
# --help or -h follows. bash/sh/zsh/dash/ksh/pwsh/powershell/cmd segments are
# unwrapped: every later word that mentions push is parsed again (depth 3).
# The target directory starts at the payload cwd; `cd DIR` and `git -C DIR`
# (relative paths compose) move it; the repository is `git rev-parse
# --show-toplevel` of that directory. The scan runs the repository's own
# scripts/private-terms.sh; one without it, or a directory that is no
# repository, allows with a note (nothing to scan). No terms file: the script
# itself exits 0, so the push is allowed.
# Fast path: a command without the text "push" exits 0 using builtins only.
# Malformed payload (no "command" key, not JSON): the whole text is parsed as
# a command, as destructive-guard.sh does; a warning goes to stderr and the
# result is allow unless that text is a push whose scan fails.
# Limits: --git-dir and --work-tree are skipped, not followed; eval, aliases,
# scripts run from files, and a push inside a script the command runs are not
# read; a cd to a variable or - leaves the directory as it was.
# Assumptions: bash 3.2+ (no associative arrays, mapfile or ${x,,}).
set -euo pipefail

NL=$'\n'
SEP=$'\x01'
re_cmd='"command"[[:space:]]*:[[:space:]]*"((\\.|[^"\\])*)"'
re_cwd='"cwd"[[:space:]]*:[[:space:]]*"((\\.|[^"\\])*)"'
re_assign='^[A-Za-z_][A-Za-z0-9_]*='

json_unescape() {
  local s="$1" ph=$'\x02' bs='\' dq='"' sl='/'
  s=${s//"$bs$bs"/$ph}
  s=${s//"${bs}n"/$NL}
  s=${s//"${bs}r"/$NL}
  s=${s//"${bs}t"/ }
  s=${s//"$bs$dq"/$dq}
  s=${s//"$bs$sl"/$sl}
  UNESC=${s//$ph/$bs}
}

payload=""
IFS= read -r -d '' payload || true
case "$payload" in *push*) ;; *) exit 0 ;; esac

text="$payload"
if [[ "$payload" =~ $re_cmd ]]; then
  text="${BASH_REMATCH[1]}"
else
  echo "push-scan: the hook payload has no \"command\" field; parsing the whole text as a command" >&2
fi
CWD0=""
if [[ "$payload" =~ $re_cwd ]]; then
  json_unescape "${BASH_REMATCH[1]}"
  CWD0="$UNESC"
fi
json_unescape "$text"
text="$UNESC"
case "$text" in *push*) ;; *) exit 0 ;; esac
[[ -n "$CWD0" ]] || CWD0="$PWD"

# tokenize TEXT -> TOK (array); a separator outside quotes becomes a SEP word.
tokenize() {
  local s="$1" i n c q="" w="" have=0
  TOK=()
  n=${#s}
  for (( i = 0; i < n; i++ )); do
    c="${s:i:1}"
    if [[ -n "$q" ]]; then
      if [[ "$c" == "$q" ]]; then q=""; else w+="$c"; fi
      continue
    fi
    case "$c" in
      "'"|'"') q="$c"; have=1 ;;
      ' '|$'\t')
        if (( have )); then TOK+=("$w"); w=""; have=0; fi ;;
      ';'|'&'|'|'|'('|')'|'`'|"$NL"|'{'|'}')
        if (( have )); then TOK+=("$w"); w=""; have=0; fi
        TOK+=("$SEP") ;;
      *) w+="$c"; have=1 ;;
    esac
  done
  if (( have )); then TOK+=("$w"); fi
}

is_abs() { [[ "$1" == /* || "$1" == [A-Za-z]:* || "$1" == \\* ]]; }
join_dir() { # BASE REL -> JD
  if is_abs "$2"; then JD="$2"; else JD="${1%/}/$2"; fi
}

ROOTS=()
note_root() { # DIR: remember the repository root of DIR once
  local r x
  if ! r="$(git -C "$1" rev-parse --show-toplevel 2>/dev/null)" || [[ -z "$r" ]]; then
    echo "push-scan: $1 is not a git repository; nothing to scan" >&2
    return 0
  fi
  if (( ${#ROOTS[@]} )); then
    for x in "${ROOTS[@]}"; do [[ "$x" == "$r" ]] && return 0; done
  fi
  ROOTS+=("$r")
}

# scan_text TEXT DEPTH: find pushes in TEXT; cwd state lives in CUR.
scan_text() {
  local t="$1" depth="$2"
  local -a toks seg
  local tok i n base dir sub w j k is_push help
  (( depth <= 3 )) || return 0
  tokenize "$t"
  toks=("${TOK[@]+"${TOK[@]}"}")
  n=${#toks[@]}
  i=0
  while (( i < n )); do
    seg=()
    while (( i < n )) && [[ "${toks[i]}" != "$SEP" ]]; do seg+=("${toks[i]}"); i=$((i + 1)); done
    i=$((i + 1))
    (( ${#seg[@]} )) || continue
    # skip assignments and wrappers
    j=0
    while (( j < ${#seg[@]} )); do
      w="${seg[j]}"
      if [[ "$w" =~ $re_assign ]]; then j=$((j + 1)); continue; fi
      base="${w##*/}"; base="${base##*\\}"
      case "$base" in
        sudo|command|nohup|time|exec|env) j=$((j + 1)); continue ;;
      esac
      break
    done
    (( j < ${#seg[@]} )) || continue
    w="${seg[j]}"
    base="${w##*/}"; base="${base##*\\}"
    case "$base" in
      cd|pushd|chdir|Set-Location|sl|Push-Location)
        k=$((j + 1))
        # skip option-looking words such as -Path or -L
        while (( k < ${#seg[@]} )) && [[ "${seg[k]}" == -* && "${seg[k]}" != "-" ]]; do k=$((k + 1)); done
        if (( k < ${#seg[@]} )); then
          w="${seg[k]}"
          case "$w" in
            -|'$'*|'%'*|'~'*) ;;
            *) join_dir "$CUR" "$w"; CUR="$JD" ;;
          esac
        fi
        continue ;;
      bash|sh|zsh|dash|ksh|pwsh|powershell|cmd|bash.exe|sh.exe|pwsh.exe|powershell.exe|cmd.exe)
        for (( k = j + 1; k < ${#seg[@]}; k++ )); do
          case "${seg[k]}" in *push*) scan_text "${seg[k]}" $((depth + 1)) ;; esac
        done
        continue ;;
      git|git.exe) ;;
      *) continue ;;
    esac
    # git: skip options, find the subcommand
    dir="$CUR"
    k=$((j + 1))
    sub=""
    while (( k < ${#seg[@]} )); do
      w="${seg[k]}"
      case "$w" in
        -C) k=$((k + 1)); if (( k < ${#seg[@]} )); then join_dir "$dir" "${seg[k]}"; dir="$JD"; fi ;;
        -c|--git-dir|--work-tree|--namespace|--exec-path|--super-prefix|--config-env) k=$((k + 1)) ;;
        -*) ;;
        *) sub="$w"; break ;;
      esac
      k=$((k + 1))
    done
    [[ "$sub" == "push" ]] || continue
    is_push=1; help=0
    for (( k = k + 1; k < ${#seg[@]}; k++ )); do
      case "${seg[k]}" in --help|-h) help=1 ;; esac
    done
    (( help )) && is_push=0
    (( is_push )) && note_root "$dir"
  done
  return 0
}

CUR="$CWD0"
scan_text "$text" 0

(( ${#ROOTS[@]} )) || exit 0

for r in "${ROOTS[@]}"; do
  if [[ ! -f "$r/scripts/private-terms.sh" ]]; then
    echo "push-scan: $r has no scripts/private-terms.sh; nothing to scan" >&2
    continue
  fi
  rc=0
  out="$(cd "$r" && bash scripts/private-terms.sh check 2>&1)" || rc=$?
  if (( rc != 0 )); then
    {
      echo "BLOCKED by scripts/push-scan.sh: git push refused; scripts/private-terms.sh check failed in $r (exit $rc). Remove the private terms (amend or rewrite the unpushed commits, fix staged files) and push again. Output:"
      printf '%s\n' "$out"
    } >&2
    exit 2
  fi
done
exit 0
