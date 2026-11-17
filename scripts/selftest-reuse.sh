#!/usr/bin/env bash
# selftest-reuse.sh - skip the template self-tests when none of their inputs
# changed since the last green run (the "reuse a result when its inputs are
# unchanged, run more when they are unknown" rule). The inputs are the paths
# listed in tests/template/selftest-inputs.list.
#
# Usage: scripts/selftest-reuse.sh <subcommand>
#   key            print the sha256 key over the inputs and the tool identity.
#   check          exit 0 and print "selftest-reuse: inputs unchanged since
#                  <UTC date> (key <12 hex>)" when the record holds the current
#                  key; exit 1 with a one-line reason otherwise (no record, key
#                  changed, list missing, CI=true, CHECK_SELFTEST=full).
#   record         write "<key> <UTC date>" to the record.
#   verify-inputs  copy ONLY the declared inputs into a fresh temp git repository
#                  and run ./scripts/selftest.sh there; exit with its status. A
#                  test that reads an undeclared path fails there, so this proves
#                  the list is complete. CI runs it.
# Exit codes: 0 ok, 1 refusal or failure, 2 usage error.
#
# Key material, one line each, sorted by path: "<git hash-object of the working
# content> <path>" for every existing input file (a directory entry expands to
# its tracked and untracked-not-ignored files; ignored files never count), "exists
# <path>" for an "exists:" entry (presence only, content not hashed), then
# "bash $BASH_VERSION", "git --version", "uname -s", a format constant and the
# test-only SELFTEST_REUSE_ENV_EXTRA (appended so a test can change the tool
# identity; never set it outside tests). Digest: sha256sum, else shasum -a 256,
# else git hash-object --stdin of the same text (a sha1 blob id).
# Record: "$(git rev-parse --git-path selftest-pass)", inside the git dir, so it
# is never tracked, never synced and per worktree.
# Dependencies: bash 3.2+, git, tar, mktemp; sha256sum or shasum when present.
# verify-inputs empties every "exists:" file in its copy (presence kept), so a
# test reading that content fails there.
# Assumptions: run inside a git repository; paths contain no newline; the
# python and ruff versions the tests use are not part of the key (they come from
# the environment, a stale reuse after upgrading them is possible; set
# CHECK_SELFTEST=full to force a run).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

LIST="tests/template/selftest-inputs.list"
FORMAT_VERSION=1

die() { echo "selftest-reuse: $*" >&2; exit 1; }

# Parsed list: content_entries and exists_entries (bash 3.2: plain arrays).
content_entries=()
exists_entries=()
load_list() {
  local line
  [[ -f "$LIST" ]] || die "$LIST is missing; every self-test input must be declared there"
  content_entries=()
  exists_entries=()
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z "$line" || "$line" == \#* ]] && continue
    if [[ "$line" == exists:* ]]; then
      line="${line#exists:}"
      line="${line#"${line%%[![:space:]]*}"}"
      [[ -n "$line" ]] && exists_entries+=("$line")
    else
      content_entries+=("$line")
    fi
  done < "$LIST"
  (( ${#content_entries[@]} + ${#exists_entries[@]} > 0 )) || die "$LIST names no path"
}

# expand ENTRY...: the existing files under the entries, one per line, sorted.
# git decides what counts: tracked files and untracked files that are not
# ignored; a tracked file deleted from disk is dropped.
expand() {
  local p
  (( $# )) || return 0
  git -c core.quotepath=off ls-files -co --exclude-standard -- "$@" | LC_ALL=C sort -u | while IFS= read -r p || [[ -n "$p" ]]; do
    [[ -f "$p" ]] && printf '%s\n' "$p"
  done
  return 0
}

digest() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | awk '{print $1}'
  else
    git hash-object --stdin
  fi
}

key_material() {
  local paths hashes
  paths="$(expand ${content_entries[@]+"${content_entries[@]}"})"
  if [[ -n "$paths" ]]; then
    hashes="$(printf '%s\n' "$paths" | git hash-object --stdin-paths)"
    paste -d ' ' <(printf '%s\n' "$hashes") <(printf '%s\n' "$paths")
  fi
  paths="$(expand ${exists_entries[@]+"${exists_entries[@]}"})"
  if [[ -n "$paths" ]]; then
    printf '%s\n' "$paths" | sed 's/^/exists /'
  fi
  echo "bash ${BASH_VERSION:-unknown}"
  echo "git $(git --version)"
  echo "uname $(uname -s)"
  echo "format $FORMAT_VERSION"
  [[ -z "${SELFTEST_REUSE_ENV_EXTRA:-}" ]] || echo "extra ${SELFTEST_REUSE_ENV_EXTRA}"
}

compute_key() { load_list; key_material | digest; }

record_file() { git rev-parse --git-path selftest-pass; }

cmd_check() {
  local rec line rkey rdate key
  [[ "${CI:-}" != true ]] || die "CI is set; the self-tests always run in CI"
  [[ "${CHECK_SELFTEST:-}" != full ]] || die "CHECK_SELFTEST=full forces a run"
  [[ -f "$LIST" ]] || die "$LIST is missing; running the self-tests"
  rec="$(record_file)"
  [[ -f "$rec" ]] || die "no record of a passing run here; running the self-tests"
  line="$(sed -n 1p "$rec")"
  rkey="${line%% *}"
  rdate="${line#* }"
  key="$(compute_key)"
  [[ "$rkey" == "$key" ]] || die "inputs changed since the last passing run (key ${key:0:12}, recorded ${rkey:0:12}); running the self-tests"
  echo "selftest-reuse: inputs unchanged since $rdate (key ${key:0:12})"
}

cmd_record() {
  local key rec
  key="$(compute_key)"
  rec="$(record_file)"
  printf '%s %s\n' "$key" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$rec"
  echo "selftest-reuse: recorded key ${key:0:12}"
}

cmd_verify() {
  local tmp rc=0 p mode
  load_list
  # work is global: the EXIT trap runs after this function's locals are gone.
  work="$(mktemp -d "${TMPDIR:-/tmp}/selftest-verify.XXXXXX")" || die "cannot create a temp folder"
  trap 'case "$work" in */selftest-verify.*) rm -rf "$work" ;; esac' EXIT
  tmp="$work/repo"
  mkdir "$tmp"
  {
    expand ${content_entries[@]+"${content_entries[@]}"}
    expand ${exists_entries[@]+"${exists_entries[@]}"}
  } | LC_ALL=C sort -u > "$work/list"
  [[ -s "$work/list" ]] || die "no declared input exists in this repository"
  tr '\n' '\0' < "$work/list" | tar --null -T - -cf - | tar -xf - -C "$tmp"
  # An "exists:" entry is not hashed into the key, so no test may depend on its
  # content: the copy keeps the file (presence) but empty, and a test that reads
  # the content fails here.
  expand ${exists_entries[@]+"${exists_entries[@]}"} | while IFS= read -r p || [[ -n "$p" ]]; do
    : > "$tmp/$p"
  done
  (
    cd "$tmp"
    git init -q . >/dev/null 2>&1
    git config user.email "selftest-reuse@example.invalid"
    git config user.name "selftest-reuse"
    git config core.autocrlf false
    git add -A >/dev/null 2>&1
  ) || die "cannot prepare the temp repository"
  # Keep the source index's executable bits: where git does not track file
  # modes (Windows) a fresh add records 100644 and tests that check the bit fail.
  while IFS= read -r p || [[ -n "$p" ]]; do
    mode="$(git ls-files -s -- "$p" | awk '{print $1}')"
    [[ "$mode" == 100755 ]] && printf '%s\n' "$p"
  done < "$work/list" | (cd "$tmp" && tr '\n' '\0' | git update-index --chmod=+x -z --stdin) || true
  (
    cd "$tmp"
    git -c commit.gpgsign=false commit -q -m "declared self-test inputs" >/dev/null 2>&1
  ) || die "cannot commit the temp repository"
  echo "selftest-reuse: verify-inputs: running the self-tests on the declared inputs only ($(wc -l < "$work/list" | tr -d ' ') files)"
  (cd "$tmp" && ./scripts/selftest.sh) || rc=$?
  if (( rc )); then
    echo "selftest-reuse: verify-inputs FAILED (exit $rc): a test may read a path that $LIST does not declare" >&2
  else
    echo "selftest-reuse: verify-inputs: OK"
  fi
  return "$rc"
}

case "${1:-}" in
  key) compute_key ;;
  check) cmd_check ;;
  record) cmd_record ;;
  verify-inputs) cmd_verify ;;
  *) echo "usage: selftest-reuse.sh key|check|record|verify-inputs" >&2; exit 2 ;;
esac
