#!/usr/bin/env bash
# Exercises fixture-guard.sh against a throwaway git repository. Run: bash docs/library/tools/tests/test_fixture_guard.sh
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUARD="$HERE/../fixture-guard.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
cd "$work"
git init -q -b main
mkdir -p tests/golden src/core docs
ARGS=(--fixtures '^tests/golden/' --implementation '^src/core/')

fail() { echo "FIXTURE-GUARD TEST FAILED: $*" >&2; exit 1; }
expect() { # expect CODE DESCRIPTION -- command...
  local want="$1" what="$2"; shift 3
  local got=0
  "$@" >"$work/out.txt" 2>&1 || got=$?
  [[ "$got" == "$want" ]] || { cat "$work/out.txt" >&2; fail "$what: expected exit $want, got $got"; }
}

echo base > docs/readme.txt
git add -A && git commit -q -m "base"

# Fixture alone passes.
echo 1 > tests/golden/a.json && git add -A && git commit -q -m "fixture only"
expect 0 "fixture only" -- bash "$GUARD" "${ARGS[@]}"

# Implementation alone passes.
echo 1 > src/core/m.txt && git add -A && git commit -q -m "impl only"
expect 0 "implementation only" -- bash "$GUARD" "${ARGS[@]}"

# Both together without the marker fails and names the files.
echo 2 > tests/golden/a.json && echo 2 > src/core/m.txt && git add -A && git commit -q -m "both, no marker"
expect 1 "both without marker" -- bash "$GUARD" "${ARGS[@]}"
grep -q "tests/golden/a.json" "$work/out.txt" || fail "failure output does not name the fixture"
grep -q "src/core/m.txt" "$work/out.txt" || fail "failure output does not name the implementation file"

# Both together with the marker at the start of a body line passes.
echo 3 > tests/golden/a.json && echo 3 > src/core/m.txt && git add -A
git commit -q -m "both, with marker" -m "Reference-change: new tolerance agreed after review of run 12"
expect 0 "both with marker" -- bash "$GUARD" "${ARGS[@]}"

# The marker mid-line does not count.
echo 4 > tests/golden/a.json && echo 4 > src/core/m.txt && git add -A
git commit -q -m "both, marker buried" -m "note: Reference-change: not at line start"
expect 1 "marker mid-line" -- bash "$GUARD" "${ARGS[@]}"

# A custom marker is honoured, and the default no longer is.
echo 5 > tests/golden/a.json && echo 5 > src/core/m.txt && git add -A
git commit -q -m "both, custom marker" -m "Golden-change: updated"
expect 0 "custom marker" -- bash "$GUARD" "${ARGS[@]}" --marker "Golden-change:"
expect 1 "default marker absent" -- bash "$GUARD" "${ARGS[@]}"

# An explicit older commit argument is judged, not HEAD.
expect 0 "explicit commit" -- bash "$GUARD" "${ARGS[@]}" HEAD~2

# Could-not-run cases.
expect 2 "missing arguments" -- bash "$GUARD"
expect 2 "unknown commit" -- bash "$GUARD" "${ARGS[@]}" deadbeefdeadbeef
expect 2 "unknown option" -- bash "$GUARD" "${ARGS[@]}" --nope
expect 2 "not a repository" -- bash "$GUARD" "${ARGS[@]}" --root "$(mktemp -d)"
expect 0 "help" -- bash "$GUARD" --help

echo "fixture-guard-test: OK"
