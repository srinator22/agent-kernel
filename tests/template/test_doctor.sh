#!/usr/bin/env bash
# doctor.sh: each tool is checked by running it; a missing or broken tool gets
# one line with the install command for the detected system; nothing is ever
# installed or downloaded. Tools are PATH shims in a sandbox folder that is the
# whole PATH of the run, so no real winget, brew, apt, gh or curl is reached.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" || { echo "$0: cannot load lib.sh; stopped before writing anything" >&2; exit 2; }

SB=""
sb_clean() {
  case "$SB" in */template-selftest.sb.*) rm -rf "$SB" "$SB.gold" ;; esac
  SB=""
}
trap 'sb_clean; t_cleanup' EXIT

# mkshim NAME VERSION-TEXT: logs "NAME args" to $SB/log; exits with the number
# in $SB/rc.NAME when that file exists, else prints the version text.
mkshim() {
  cat > "$SB/$1" <<SHIM
#!$BASH
printf '%s\n' "$1 \$*" >> "$SB/log"
if [[ -f "$SB/rc.$1" ]]; then read -r rc < "$SB/rc.$1"; exit "\$rc"; fi
printf '%s\n' "$2"
SHIM
  chmod +x "$SB/$1"
}
mkgit() {
  cat > "$SB/git" <<SHIM
#!$BASH
printf '%s\n' "git \$*" >> "$SB/log"
if [[ "\$1" == grep ]]; then
  if [[ -f "$SB/rc.gitgrep" ]]; then read -r rc < "$SB/rc.gitgrep"; exit "\$rc"; fi
  exit 0
fi
if [[ -f "$SB/rc.git" ]]; then read -r rc < "$SB/rc.git"; exit "\$rc"; fi
echo "git version 2.50.0"
SHIM
  chmod +x "$SB/git"
}
set_uname() { printf '#!%s\necho "%s"\n' "$BASH" "$1" > "$SB/uname"; chmod +x "$SB/uname"; }
# new_sb: a sandbox where every tool works and the system is Linux.
new_sb() {
  if [[ -z "$SB" ]]; then
    SB="$(mktemp -d "${TMPDIR:-/tmp}/template-selftest.sb.XXXXXX")"
    set_uname Linux
    mkgit
    mkshim python3 "Python 3.12.1"
    mkshim gh "gh version 2.40.0"
    mkshim gitleaks "8.18.0"
    mkshim git-cliff "git-cliff 2.0.0"
    mkshim ruff "ruff 0.16.10"
    mkshim uvx "uv 0.5.0"
    mkshim pipx "1.4.0"
    # Installers and the network: present only to prove they are never called.
    mkshim winget "winget"; mkshim brew "brew"; mkshim apt "apt"; mkshim apt-get "apt-get"
    mkshim curl "curl"; mkshim sudo "sudo"
    mkdir "$SB.gold" && cp "$SB"/* "$SB.gold"/
  else
    # Restore the pristine shims: drop everything, copy the originals back.
    rm -rf "$SB/WindowsApps"
    rm -f "$SB"/* "$SB"/rc.* && cp "$SB.gold"/* "$SB"/
  fi
  : > "$SB/log"
  DPATH="$SB"
}
miss() { local t; for t in "$@"; do rm -f "$SB/$t"; done; }
broken() { echo "${2:-1}" > "$SB/rc.$1"; }
# drun ARGS...: doctor.sh with PATH = the sandbox only (DPATH).
drun() { run env PATH="$DPATH" "${DENV[@]}" "$BASH" scripts/doctor.sh "$@"; }
log_calls() { grep -c "^$1 " "$SB/log" || true; }
count_lines() { printf '%s\n' "$OUT" | grep -c . || true; }
words() { printf '%s\n' "$OUT" | tr '\n' ' ' | sed 's/ $//'; }

DENV=("X_UNUSED=1")
DPATH=""
make_fixture
cp_script doctor.sh find-python.sh
new_sb

# All tools work, template mode.
drun
assert_rc "template mode, everything works: exit 0" 0
assert_contains "git is reported" "git"
assert_contains "bash is reported" "bash"
assert_contains "python is reported" "python"
assert_not_contains "no problem line when everything works" "(required):"
assert_not_contains "no recommended gap when everything works" "(recommended):"
# Nothing is installed, downloaded or called over the network.
for t in winget brew apt apt-get curl sudo; do
  assert_eq "$t is never called by doctor" "0" "$(log_calls "$t")"
done
assert_eq "ruff at the pinned version: uvx stays unused" "0" "$(log_calls uvx)"
assert_eq "ruff at the pinned version: pipx stays unused" "0" "$(log_calls pipx)"

# Each required tool missing.
new_sb; miss git
drun
assert_rc "git missing: exit 1" 1
assert_contains "git missing is named" "git (required): not found"
new_sb; miss python3
drun
assert_rc "python missing: exit 1" 1
assert_contains "python missing is named" "python (required): not found"
# Each required tool broken.
new_sb; broken git 3
drun
assert_rc "git broken: exit 1" 1
assert_contains "git broken is named" "git (required): found but fails to run"
new_sb; broken python3 7
drun
assert_rc "python broken: exit 1" 1
assert_contains "python broken is named" "python (required): "
assert_contains "python broken says it fails" "fails to run"
new_sb
DENV=("DOCTOR_BASH_VERSION=3.1"); drun
assert_rc "bash 3.1: exit 1" 1
assert_contains "bash 3.1 is named" "bash (required): version 3.1"
DENV=("DOCTOR_BASH_VERSION=3.2"); drun
assert_rc "bash 3.2: exit 0" 0
DENV=("DOCTOR_BASH_VERSION=5.2"); drun
assert_rc "bash 5.2: exit 0" 0
DENV=("X_UNUSED=1")

# Recommended tools: a gap is a warning, exit stays 0.
for t in gh gitleaks git-cliff; do
  new_sb; miss "$t"
  drun
  assert_rc "$t missing: exit 0 (recommended)" 0
  assert_contains "$t missing is named as recommended" "$t (recommended): not found"
  new_sb; broken "$t" 2
  drun
  assert_rc "$t broken: exit 0 (recommended)" 0
  assert_contains "$t broken is named" "$t (recommended): found but fails to run"
done
new_sb; echo 128 > "$SB/rc.gitgrep"
drun
assert_rc "git grep -P unavailable: exit 0" 0
assert_contains "git grep -P gap is named" "git grep -P (recommended)"
assert_contains "git grep -P gap says PCRE" "PCRE"
new_sb
drun
if grep -q '^git grep .*-P' "$SB/log"; then t_ok "git grep -P is run, not looked up"; else t_bad "git grep -P is run, not looked up"; fi

# Install line per system: every tool missing at once, one run per system.
rm -f "$FIX/.start-done"
new_sb; miss git python3 gh gitleaks git-cliff ruff uvx pipx
set_uname MINGW64_NT-10.0-26300; drun
assert_rc "everything missing: exit 1" 1
assert_contains "Windows: git" "winget install --id Git.Git --exact"
assert_contains "Windows: python" "winget install --id Python.Python.3.13 --exact"
assert_contains "Windows: gh" "winget install --id GitHub.cli --exact"
assert_contains "Windows: gitleaks" "winget install --id Gitleaks.Gitleaks --exact"
assert_contains "Windows: git-cliff" "winget install --id orhun.git-cliff --exact"
assert_contains "Windows: ruff through uv" "winget install --id astral-sh.uv --exact"
assert_contains "the ruff gap is named" "ruff 0.16.10 (required)"
set_uname MSYS_NT-10.0; drun
assert_contains "MSYS counts as Windows" "winget install"
set_uname CYGWIN_NT-10.0; drun
assert_contains "CYGWIN counts as Windows" "winget install"
set_uname Darwin; drun
assert_contains "macOS: git" "brew install git"
assert_contains "macOS: python" "brew install python@3.13"
assert_contains "macOS: gh" "brew install gh"
assert_contains "macOS: gitleaks" "brew install gitleaks"
assert_contains "macOS: git-cliff" "brew install git-cliff"
assert_contains "macOS: ruff through uv" "brew install uv"
assert_not_contains "macOS: no winget" "winget"
set_uname Linux; drun
assert_contains "Linux: git" "sudo apt install git"
assert_contains "Linux: python" "sudo apt install python3"
assert_contains "Linux: gh" "sudo apt install gh"
assert_contains "Linux: gitleaks official page" "https://github.com/gitleaks/gitleaks"
assert_contains "Linux: git-cliff official page" "https://git-cliff.org/docs/installation"
assert_contains "Linux: ruff official page" "https://docs.astral.sh/uv/getting-started/installation/"
assert_not_contains "Linux: no winget" "winget"

# ruff, uvx, pipx: required in template mode only, uvx and pipx only --version.
new_sb; mkshim ruff "ruff 0.15.0"; miss uvx pipx
drun
assert_rc "ruff at another version, no uvx or pipx: exit 1" 1
new_sb; mkshim ruff "ruff 0.15.0"; miss pipx
drun
assert_rc "ruff at another version but uvx works: exit 0" 0
assert_eq "uvx is run, with --version only" "1 1" "$(log_calls uvx) $(grep -cx 'uvx --version' "$SB/log" || true)"
new_sb; miss ruff uvx
drun
assert_rc "no ruff or uvx but pipx works: exit 0" 0
assert_eq "pipx is run, with --version only" "1 1" "$(log_calls pipx) $(grep -cx 'pipx --version' "$SB/log" || true)"
new_sb; miss ruff pipx; broken uvx 5
drun
assert_rc "uvx broken and no other runner: exit 1" 1
# Project mode: none of the three is checked.
touch "$FIX/.start-done"
new_sb; miss ruff uvx pipx
drun
assert_rc "project mode, no ruff, uvx or pipx: exit 0" 0
assert_not_contains "project mode does not mention ruff" "ruff"
rm -f "$FIX/.start-done"

# Flags.
new_sb
drun --quiet
assert_rc "--quiet, everything works: exit 0" 0
assert_eq "--quiet, everything works: no output" "" "$OUT"
miss gh
drun --quiet
assert_rc "--quiet with a recommended gap: exit 0" 0
assert_eq "--quiet prints only the problem line" "1" "$(count_lines)"
assert_contains "--quiet problem names the tool" "gh (recommended)"
new_sb
drun --list
assert_rc "--list: exit 0" 0
assert_eq "--list prints the tool names" "git bash python gh gitleaks git-cliff git grep ruff" "$(words)"
drun --list --required
assert_eq "--list --required prints the required names" "git bash python" "$(words)"
miss gh gitleaks git-cliff ruff uvx pipx
drun --required
assert_rc "--required ignores recommended and ruff gaps: exit 0" 0
assert_not_contains "--required does not mention gh" "gh"
touch "$FIX/.start-done"; drun --required
assert_rc "--required in project mode: exit 0" 0
rm -f "$FIX/.start-done"
miss git
drun --required --quiet
assert_rc "--required with git missing: exit 1" 1
assert_eq "--required --quiet: one problem line" "1" "$(count_lines)"
drun --bogus
assert_rc "unknown flag: exit 2" 2
assert_contains "usage names the flags" "--required"
drun --quiet extra
assert_rc "stray argument: exit 2" 2

# A16: the Microsoft Store python stub.
for stub in python3 python; do
  new_sb; miss python3
  mkdir -p "$SB/WindowsApps"
  printf '#!%s\nexit 49\n' "$BASH" > "$SB/WindowsApps/$stub"; chmod +x "$SB/WindowsApps/$stub"
  set_uname MINGW64_NT-10.0-26300
  DPATH="$SB/WindowsApps:$SB"; drun
  assert_rc "$stub stub under WindowsApps: exit 1" 1
  assert_contains "$stub stub: named as the Store alias" "Microsoft Store App Execution Alias"
  assert_contains "$stub stub: names the stub" "$stub"
  assert_contains "$stub stub: fix one turns the aliases off" "App execution aliases"
  assert_contains "$stub stub: fix one names both aliases" "python.exe and python3.exe"
  assert_contains "$stub stub: fix two installs Python" "winget install --id Python.Python.3.13 --exact"
  assert_contains "$stub stub: fix two puts it first on PATH" "first on PATH"
done
# A working python after the stub: nothing to report.
new_sb; mkdir -p "$SB/WindowsApps"
printf '#!%s\nexit 49\n' "$BASH" > "$SB/WindowsApps/python3"; chmod +x "$SB/WindowsApps/python3"
mkshim python "Python 3.12.1"; miss python3
DPATH="$SB/WindowsApps:$SB"; drun
assert_rc "a stub python3 with a working python: exit 0" 0
assert_not_contains "no stub message when python works" "Microsoft Store"
# A broken python outside WindowsApps is not called a stub.
new_sb; broken python3 49
drun
assert_rc "a failing python outside WindowsApps: exit 1" 1
assert_not_contains "a failing python outside WindowsApps is not the Store stub" "Microsoft Store"

# A18: README names every tool doctor lists.
new_sb
OUT="$(cd "$FIX" && env PATH="$SB" "$BASH" scripts/doctor.sh --list 2>&1)"
while IFS= read -r name; do
  [[ -n "$name" ]] || continue
  if grep -qF -- "$name" "$T_ROOT/README.md"; then t_ok "README names $name"; else t_bad "README names $name"; fi
done <<< "$OUT"

sb_clean
t_finish
