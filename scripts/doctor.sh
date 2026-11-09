#!/usr/bin/env bash
# doctor.sh - checks that every tool the template uses is present and works.
# Purpose: a missing or broken tool otherwise degrades silently ("skipped
#   locally"); this names each one and prints the install command.
# Usage: bash scripts/doctor.sh [--quiet] [--list] [--required]
#   --quiet     print only problems
#   --list      print the tool names, one per line, and stop
#   --required  check only git, bash and Python 3 (either mode)
# Input: PATH; .start-done at the repo root (project mode); test hook
#   DOCTOR_BASH_VERSION (major.minor, replaces the running bash version).
# Output: one line per problem, "<tool> (required|recommended): <reason> -
#   install: <command>", then a summary unless --quiet. Exit 0 when every
#   required tool for the mode works (recommended gaps are warnings), 1
#   otherwise, 2 on a usage error.
# Dependencies: bash 3.2+, scripts/find-python.sh, uname. Each tool is RUN, not
#   looked up. uvx and pipx run only --version; nothing is ever installed or
#   downloaded, and no network command runs.
# Assumptions: required in template mode only: ruff 0.16.10 on PATH at exactly
#   that version, or uvx, or pipx (check.sh step 5k fails without one).
# Install ids: winget ids checked with winget show --id <id> --exact; brew
#   names checked on formulae.brew.sh.

RUFF_PIN="0.16.10"
QUIET=0
LIST=0
REQ_ONLY=0
for arg in "$@"; do
  case "$arg" in
    --quiet) QUIET=1 ;;
    --list) LIST=1 ;;
    --required) REQ_ONLY=1 ;;
    *) echo "doctor.sh: unknown argument: $arg (usage: doctor.sh [--quiet] [--list] [--required])" >&2; exit 2 ;;
  esac
done

if (( LIST )); then
  echo git; echo bash; echo python
  if (( ! REQ_ONLY )); then echo gh; echo gitleaks; echo git-cliff; echo "git grep"; echo ruff; fi
  exit 0
fi

ROOT="$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)"
cd "$ROOT" || exit 2

case "$(uname -s 2>/dev/null)" in
  MINGW*|MSYS*|CYGWIN*) OS=windows ;;
  Darwin*) OS=mac ;;
  *) OS=linux ;;
esac

# install_cmd TOOL: the install command for the detected system.
install_cmd() {
  case "$1:$OS" in
    git:windows) echo "winget install --id Git.Git --exact" ;;
    git:mac) echo "brew install git" ;;
    git:linux) echo "sudo apt install git" ;;
    bash:windows) echo "winget install --id Git.Git --exact (Git Bash)" ;;
    bash:mac) echo "brew install bash" ;;
    bash:linux) echo "sudo apt install bash" ;;
    python:windows) echo "winget install --id Python.Python.3.13 --exact" ;;
    python:mac) echo "brew install python@3.13" ;;
    python:linux) echo "sudo apt install python3" ;;
    gh:windows) echo "winget install --id GitHub.cli --exact" ;;
    gh:mac) echo "brew install gh" ;;
    gh:linux) echo "sudo apt install gh (or https://github.com/cli/cli/blob/trunk/docs/install_linux.md)" ;;
    gitleaks:windows) echo "winget install --id Gitleaks.Gitleaks --exact" ;;
    gitleaks:mac) echo "brew install gitleaks" ;;
    gitleaks:linux) echo "https://github.com/gitleaks/gitleaks#installing" ;;
    git-cliff:windows) echo "winget install --id orhun.git-cliff --exact" ;;
    git-cliff:mac) echo "brew install git-cliff" ;;
    git-cliff:linux) echo "https://git-cliff.org/docs/installation" ;;
    grep:windows) echo "winget install --id Git.Git --exact (Git for Windows is built with PCRE)" ;;
    grep:mac) echo "brew install git" ;;
    grep:linux) echo "sudo apt install git (the Debian and Ubuntu build includes PCRE)" ;;
    ruff:windows) echo "winget install --id astral-sh.uv --exact (uvx runs ruff $RUFF_PIN), or winget install --id astral-sh.ruff --exact --version $RUFF_PIN" ;;
    ruff:mac) echo "brew install uv (uvx runs ruff $RUFF_PIN), or brew install pipx" ;;
    ruff:linux) echo "https://docs.astral.sh/uv/getting-started/installation/ (uvx runs ruff $RUFF_PIN), or sudo apt install pipx" ;;
  esac
}

REQ_FAIL=0
FIRST_RUN_OUT=""
# say LINE: print unless --quiet.
say() { if (( ! QUIET )); then printf '%s\n' "$1"; fi; }
good() { say "  ok   $1"; }
# problem NAME KIND REASON: one line with the install command.
problem() {
  printf '%s (%s): %s - install: %s\n' "$1" "$2" "$3" "$(install_cmd "$4")"
  if [[ "$2" == required ]]; then REQ_FAIL=$((REQ_FAIL + 1)); fi
}
# probe CMD ARGS...: sets PROBE_RC (127 when CMD does not exist) and PROBE_OUT
# (first output line).
probe() {
  PROBE_OUT=""
  if ! command -v "$1" >/dev/null 2>&1; then PROBE_RC=127; return 0; fi
  PROBE_OUT="$("$@" 2>&1)"; PROBE_RC=$?
  PROBE_OUT="${PROBE_OUT%%$'\n'*}"
  return 0
}
# check_tool NAME KIND INSTALLKEY CMD ARGS...
check_tool() {
  local name="$1" kind="$2" key="$3"
  shift 3
  probe "$@"
  if (( PROBE_RC == 127 )); then
    problem "$name" "$kind" "not found" "$key"
  elif (( PROBE_RC != 0 )); then
    problem "$name" "$kind" "found but fails to run (exit $PROBE_RC)" "$key"
  else
    good "$name ${PROBE_OUT:+- $PROBE_OUT}"
  fi
}

check_tool git required git git --version
GIT_OK=0
if (( PROBE_RC == 0 )); then GIT_OK=1; fi

# bash 3.2 or newer.
bv="${DOCTOR_BASH_VERSION:-${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]}}"
bmaj="${bv%%.*}"; bmin="${bv#*.}"; bmin="${bmin%%.*}"
if (( bmaj > 3 || (bmaj == 3 && bmin >= 2) )); then
  good "bash - $bv"
else
  problem bash required "version $bv is older than 3.2" bash
fi

# Python 3, through the shared probe.
# shellcheck source=find-python.sh
PY=""
. "$ROOT/scripts/find-python.sh"
if [[ -n "$PY" ]]; then
  pyv="$("$PY" --version 2>&1)"; pyv="${pyv%%$'\n'*}"
  good "python - $PY, $pyv"
else
  stub=""; seen=0
  for c in python3 python; do
    p="$(command -v "$c" 2>/dev/null || true)"; [[ -n "$p" ]] && seen=1
    case "$p" in
      */WindowsApps/*|*/windowsapps/*|*\\WindowsApps\\*) stub="$c"; break ;;
    esac
  done
  if [[ -n "$stub" ]]; then
    printf 'python (required): %s resolves to the Microsoft Store App Execution Alias and fails to run\n' "$stub"
    printf '  fix 1: turn off the python.exe and python3.exe App execution aliases (Settings > Apps > Advanced app settings > App execution aliases)\n'
    printf '  fix 2: install Python (%s) and put it first on PATH\n' "$(install_cmd python)"
    REQ_FAIL=$((REQ_FAIL + 1))
  elif (( seen )); then
    problem python required "found but fails to run as Python 3" python
  else
    problem python required "not found" python
  fi
fi

if (( ! REQ_ONLY )); then
  check_tool gh recommended gh gh --version
  check_tool gitleaks recommended gitleaks gitleaks version
  check_tool git-cliff recommended git-cliff git-cliff --version

  # git grep -P: the no-dash scan needs git built with PCRE. The lookahead
  # exists only in PCRE; doctor.sh itself holds the text it matches.
  if (( GIT_OK )); then
    if git grep --no-index -P -q 'doct(?=or)' -- "$ROOT/scripts/doctor.sh" >/dev/null 2>&1; then
      good "git grep -P - PCRE available"
    else
      problem "git grep -P" recommended "git is not built with PCRE (the dash and character scans fall back to CI)" grep
    fi
  fi

  # ruff: template mode only. Present only at exactly RUFF_PIN; uvx and pipx
  # are checked with --version and never asked to fetch anything.
  if [[ ! -f .start-done ]]; then
    runner=""
    probe ruff --version
    if (( PROBE_RC == 0 )) && [[ "$PROBE_OUT" == "ruff $RUFF_PIN" ]]; then
      runner="ruff on PATH, $PROBE_OUT"
    else
      probe uvx --version
      if (( PROBE_RC == 0 )); then
        runner="uvx, $PROBE_OUT"
      else
        probe pipx --version
        if (( PROBE_RC == 0 )); then runner="pipx, $PROBE_OUT"; fi
      fi
    fi
    if [[ -n "$runner" ]]; then
      good "ruff $RUFF_PIN - $runner"
    else
      problem "ruff $RUFF_PIN" required "needs ruff $RUFF_PIN on PATH at exactly that version, or uvx, or pipx; none works" ruff
    fi
  fi
fi

if (( REQ_FAIL > 0 )); then
  say "doctor: $REQ_FAIL required problem(s); install the tools above and run it again"
  exit 1
fi
say "doctor: every required tool works"
exit 0
