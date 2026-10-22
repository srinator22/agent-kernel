#!/usr/bin/env bash
# fixture-guard.sh - a golden fixture and the implementation it pins never change in the same commit unless
# the commit body carries a marker line stating the evidence and the decision.
#
# Purpose: a regression fixture exists to catch an implementation change. When both move in one commit, the
# test can no longer tell a fix from a drift. This guard makes the author say, in the commit body, why the
# reference moved (scientific profile rule SC-3; any project that pins golden numbers can use it).
# Usage: fixture-guard.sh --fixtures REGEX --implementation REGEX [--marker TEXT] [--root DIR] [COMMIT]
#   --fixtures        extended regex matched against each changed path (for example '^tests/golden/')
#   --implementation  extended regex for the code the fixtures pin (for example '^src/core/')
#   --marker          the body line prefix that permits a joint change (default 'Reference-change:')
#   --root            repository root (default: the git top level of the current directory)
#   COMMIT            the commit to judge (default HEAD)
# Output: one line saying OK or FAIL, and for FAIL the offending paths on stderr.
# Exit: 0 pass, 1 violation, 2 could not run (bad arguments, not a repository, unknown commit).
# Dependencies: bash, git, grep, sed.
# Assumptions: a merge commit lists no files in this form; its parents were checked when they were pushed.
# Validation source: ported from a project script run on every commit in CI; the behaviour is unchanged.
set -euo pipefail

usage() { sed -n '2,/^set -euo/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; }

FIXTURES=""
IMPLEMENTATION=""
MARKER="Reference-change:"
ROOT=""
COMMIT="HEAD"
while (( $# )); do
  case "$1" in
    --fixtures) [[ $# -ge 2 ]] || { echo "fixture-guard: --fixtures needs a value" >&2; exit 2; }; FIXTURES="$2"; shift 2 ;;
    --implementation) [[ $# -ge 2 ]] || { echo "fixture-guard: --implementation needs a value" >&2; exit 2; }; IMPLEMENTATION="$2"; shift 2 ;;
    --marker) [[ $# -ge 2 ]] || { echo "fixture-guard: --marker needs a value" >&2; exit 2; }; MARKER="$2"; shift 2 ;;
    --root) [[ $# -ge 2 ]] || { echo "fixture-guard: --root needs a value" >&2; exit 2; }; ROOT="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "fixture-guard: unknown option $1" >&2; exit 2 ;;
    *) COMMIT="$1"; shift ;;
  esac
done

if [[ -z "$FIXTURES" || -z "$IMPLEMENTATION" ]]; then
  echo "fixture-guard: --fixtures and --implementation are required (see --help)" >&2
  exit 2
fi

if [[ -z "$ROOT" ]]; then
  ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "fixture-guard: could not run, not inside a git repository" >&2; exit 2; }
fi
cd "$ROOT" 2>/dev/null || { echo "fixture-guard: could not run, cannot enter $ROOT" >&2; exit 2; }
git rev-parse --git-dir >/dev/null 2>&1 || { echo "fixture-guard: could not run, $ROOT is not a git repository" >&2; exit 2; }

if ! git rev-parse --verify --quiet "$COMMIT^{commit}" >/dev/null; then
  echo "fixture-guard: could not run, $COMMIT is not a commit" >&2
  exit 2
fi

files="$(git show --format= --name-only "$COMMIT" | sed '/^$/d')"
body="$(git show --format=%B --no-patch "$COMMIT")"

fixture_changed=0
impl_changed=0
if printf '%s\n' "$files" | grep -Eq -- "$FIXTURES"; then fixture_changed=1; fi
if printf '%s\n' "$files" | grep -Eq -- "$IMPLEMENTATION"; then impl_changed=1; fi

if (( fixture_changed && impl_changed )); then
  if printf '%s\n' "$body" | awk -v m="$MARKER" 'index($0, m) == 1 { found = 1 } END { exit found ? 0 : 1 }'; then
    echo "fixture-guard: OK ($COMMIT changes fixtures and implementation together with a $MARKER line)"
    exit 0
  fi
  echo "fixture-guard: FAIL: $COMMIT changes a fixture and its implementation in the same commit without a '$MARKER' line in the commit body. Split the change, or state the evidence and decision in the body." >&2
  printf '%s\n' "$files" | grep -E -- "$FIXTURES|$IMPLEMENTATION" | sed 's/^/  /' >&2
  exit 1
fi
echo "fixture-guard: OK ($COMMIT: fixtures changed=$fixture_changed, implementation changed=$impl_changed)"
