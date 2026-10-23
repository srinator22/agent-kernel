#!/usr/bin/env bash
# ci-watch.sh - a push is not done until every required check for the exact
# pushed SHA reaches terminal success (kernel rule 5). This script mechanizes
# that: it verifies the remote branch points at the SHA, works out which
# workflows the commit can trigger, then polls the checks and workflow runs for
# that SHA until each is terminal, printing transitions.
# Usage: scripts/ci-watch.sh [SHA] [--timeout SECONDS] [--expect LIST] [--base REF] [--plan]
#   --timeout SECONDS  stop waiting after this long (default 1800); exit 3
#   --expect LIST      comma-separated workflow files to wait for (ci.yml or
#                      .github/workflows/ci.yml), or "all"; overrides derivation
#   --base REF         diff REF..SHA instead of SHA's own commit; pass the
#                      remote SHA from before the push when one push carried
#                      several commits (GitHub filters on all of them)
#   --plan             print the expected workflows for SHA and exit 0; needs
#                      neither gh nor the remote
# Expected workflows: a path-filtered workflow never runs for a commit that
# touches none of its paths, so waiting for it can only time out. The workflows
# under .github/workflows/ at SHA are read and each one's push trigger is
# matched against the branch and the files SHA changes against its first
# parent (or --base): expected, not expected (with the reason), or expected
# because its filter cannot be decided here (negated patterns, flow mappings).
# A root commit has no diff, so every workflow is expected and the script says
# so. A SHA that is not in the local repository cannot be derived at all: the
# script says so and waits for whatever checks GitHub reports. Only a confident
# derivation may conclude that nothing is expected (after CI_WATCH_GRACE).
# Exit: 0 all terminal-success; 1 failure, or unverifiable (no gh, remote SHA
# mismatch); 2 usage error; 3 timeout while checks are still in progress (re-run
# the same command to keep watching).
# Test hooks: CI_WATCH_POLL (seconds between polls, default 15), CI_WATCH_GRACE
# (seconds to wait for a first check when no workflow is expected, default 60).
set -euo pipefail

SHA=""
TIMEOUT=1800
EXPECT=""
PLAN=0
BASE=""
POLL="${CI_WATCH_POLL:-15}"
GRACE="${CI_WATCH_GRACE:-60}"
LOG_TAIL=40
WF_DIR=".github/workflows"

while (( $# )); do
  case "$1" in
    --timeout) TIMEOUT="${2:?--timeout needs a value}"; shift 2 ;;
    --expect) EXPECT="${2:?--expect needs a value}"; shift 2 ;;
    --base) BASE="${2:?--base needs a value}"; shift 2 ;;
    --plan) PLAN=1; shift ;;
    -*) echo "ci-watch: unknown flag $1 (supported: --timeout, --expect, --base, --plan)" >&2; exit 2 ;;
    *) SHA="$1"; shift ;;
  esac
done
[[ "$TIMEOUT" =~ ^[0-9]+$ ]] || { echo "ci-watch: --timeout must be a whole number of seconds" >&2; exit 2; }
[[ -n "$SHA" ]] || SHA="$(git rev-parse HEAD)"
if full="$(git rev-parse --verify --quiet "$SHA^{commit}" 2>/dev/null)"; then SHA="$full"; fi
branch="$(git rev-parse --abbrev-ref HEAD)"

# glob_re PATTERN: the anchored ERE for a GitHub Actions filter pattern.
# "**/" is zero or more directories, "**" anything, "*" anything but "/";
# "?" (zero or one of the preceding character), "+" (one or more) and [...]
# keep their regex meaning, as in GitHub's filter syntax; the rest is literal.
glob_re() {
  local p="$1" out="" c i=0 n=${#1}
  while (( i < n )); do
    c="${p:i:1}"
    if [[ "${p:i:3}" == "**/" ]]; then out+="(.*/)?"; i=$((i + 3)); continue; fi
    if [[ "${p:i:2}" == "**" ]]; then out+=".*"; i=$((i + 2)); continue; fi
    case "$c" in
      "*") out+="[^/]*" ;;
      "?") out+="?" ;;
      "+") out+="+" ;;
      "[") out+="[" ;;
      "]") out+="]" ;;
      "."|"("|")"|"{"|"}"|"^"|"$"|"|"|"\\") out+="\\$c" ;;
      *) out+="$c" ;;
    esac
    i=$((i + 1))
  done
  printf '^%s$' "$out"
}

# matches_any TEXT PATTERN...: TEXT matches at least one glob.
matches_any() {
  local text="$1" p re
  shift
  for p in "$@"; do
    re="$(glob_re "$p")"
    if [[ "$text" =~ $re ]]; then return 0; fi
  done
  return 1
}

# push_filters FILE: the push trigger of one workflow as lines "KEY<TAB>VALUE":
# TRIGGER push|none, a line per pattern under branches, branches-ignore, tags,
# tags-ignore, paths and paths-ignore, or UNKNOWN <reason>.
push_filters() {
  awk '
    function indent(s) { match(s, /^ */); return RLENGTH }
    function unq(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); gsub(/^["\047]|["\047]$/, "", s); return s }
    function flow(key, v,   n, i, parts) {
      if (v !~ /^\[.*\]$/) { print "UNKNOWN\t" key " is not a list"; return }
      v = substr(v, 2, length(v) - 2)
      n = split(v, parts, ",")
      for (i = 1; i <= n; i++) if (unq(parts[i]) != "") print key "\t" unq(parts[i])
    }
    { sub(/\r$/, ""); line = $0; sub(/[ \t]+#.*$/, "", line); if (line ~ /^[ \t]*#/) line = "" }
    line ~ /^[ \t]*$/ { next }
    {
      ind = indent(line); body = substr(line, ind + 1)
      if (ind == 0) {
        inon = 0
        if (body ~ /^["\047]?on["\047]?:/) {
          found = 1; v = body; sub(/^[^:]*:[ \t]*/, "", v)
          if (v == "") { inon = 1; ci = -1; next }
          if (v ~ /^\{/) { print "UNKNOWN\ton: is a flow mapping"; next }
          gsub(/[\[\]]/, "", v)
          print (("," v ",") ~ /,[ \t]*push[ \t]*,/) ? "TRIGGER\tpush" : "TRIGGER\tnone"
          trig = 1
        }
        next
      }
      if (!inon) next
      if (ci < 0) ci = ind
      if (ind == ci) {
        inpush = 0; key = ""
        if (body ~ /^- /) { if (unq(substr(body, 3)) == "push") pushseen = 1; listform = 1; next }
        if (body ~ /^["\047]?push["\047]?:/) {
          pushseen = 1; v = body; sub(/^[^:]*:[ \t]*/, "", v)
          if (v != "" && v != "{}" && v != "null" && v != "~") print "UNKNOWN\tpush: has an inline value"
          inpush = 1; pi = -1
        }
        next
      }
      if (!inpush) next
      if (pi < 0) pi = ind
      if (key != "" && body ~ /^- /) { print key "\t" unq(substr(body, 3)); next }
      if (ind == pi) {
        key = ""
        if (body ~ /^(branches|branches-ignore|tags|tags-ignore|paths|paths-ignore):/) {
          key = body; sub(/:.*$/, "", key)
          v = body; sub(/^[^:]*:[ \t]*/, "", v)
          print "HAS\t" key
          if (v != "") { flow(key, v); key = "" }
        }
        next
      }
    }
    END {
      if (!found) { print "UNKNOWN\tno on: key found"; exit }
      if (!trig) print (pushseen ? "TRIGGER\tpush" : "TRIGGER\tnone")
    }' "$1"
}

# decide FILE CHANGED_FILE...: prints "expected", "skip <reason>" or
# "unknown <reason>" for one workflow.
decide() {
  local file="$1" k v unknown="" trigger="" has=" "
  shift
  local -a br=() bri=() tg=() tgi=() pa=() pai=()
  while IFS=$'\t' read -r k v; do
    case "$k" in
      TRIGGER) trigger="$v" ;;
      UNKNOWN) unknown="${unknown:+$unknown; }$v" ;;
      HAS) has+="$v " ;;
      branches) br+=("$v") ;;
      branches-ignore) bri+=("$v") ;;
      tags) tg+=("$v") ;;
      tags-ignore) tgi+=("$v") ;;
      paths) pa+=("$v") ;;
      paths-ignore) pai+=("$v") ;;
    esac
  done < <(push_filters "$file")
  if [[ -n "$unknown" ]]; then echo "unknown $unknown"; return; fi
  if [[ "$trigger" != push ]]; then echo "skip no push trigger"; return; fi
  local p
  for p in "${br[@]}" "${bri[@]}" "${pa[@]}" "${pai[@]}"; do
    if [[ "$p" == '!'* ]]; then echo "unknown negated pattern '$p'"; return; fi
  done
  if [[ "$has" == *" branches "* || "$has" == *" branches-ignore "* ]]; then
    if [[ "$has" == *" branches "* ]] && ! matches_any "$branch" "${br[@]}"; then
      echo "skip branch $branch is not in its branches filter"; return
    fi
    if [[ "$has" == *" branches-ignore "* ]] && matches_any "$branch" "${bri[@]}"; then
      echo "skip branch $branch is in its branches-ignore filter"; return
    fi
  elif [[ "$has" == *" tags "* || "$has" == *" tags-ignore "* ]]; then
    echo "skip runs on tag pushes only"; return
  fi
  if [[ "$has" == *" paths "* && "$has" == *" paths-ignore "* ]]; then
    echo "unknown both paths and paths-ignore"; return
  fi
  if (( $# == 0 )) && [[ "$has" == *" paths"* ]]; then
    echo "unknown the commit changes no files"; return
  fi
  local f
  if [[ "$has" == *" paths "* ]]; then
    for f in "$@"; do
      if matches_any "$f" "${pa[@]}"; then echo "expected"; return; fi
    done
    echo "skip no changed file matches its paths filter"; return
  fi
  if [[ "$has" == *" paths-ignore "* ]]; then
    for f in "$@"; do
      if ! matches_any "$f" "${pai[@]}"; then echo "expected"; return; fi
    done
    echo "skip every changed file matches its paths-ignore filter"; return
  fi
  echo "expected"
}

# Workflow files at SHA, then the expected set.
# core.quotePath=false: git quotes non-ASCII paths otherwise, and a quoted path
# never matches a filter.
mapfile -t ALL_WF < <(git -c core.quotePath=false ls-tree --name-only "$SHA" "$WF_DIR/" 2>/dev/null | grep -E '\.ya?ml$' || true)
EXPECTED=()
DERIVED=0
if [[ -n "$BASE" ]] && ! git rev-parse --verify --quiet "$BASE^{commit}" >/dev/null 2>&1; then
  echo "ci-watch: --base $BASE is not a commit in the local repository" >&2
  exit 2
fi
if [[ -n "$EXPECT" ]]; then
  if [[ "$EXPECT" == all ]]; then
    EXPECTED=("${ALL_WF[@]}")
  else
    IFS=',' read -r -a want <<< "$EXPECT"
    for w in "${want[@]}"; do
      w="${w// /}"
      [[ -n "$w" ]] || continue
      [[ "$w" == */* ]] || w="$WF_DIR/$w"
      if ! printf '%s\n' "${ALL_WF[@]}" | grep -qxF -- "$w"; then
        echo "ci-watch: --expect names $w, which is not a workflow file at $SHA" >&2
        exit 2
      fi
      EXPECTED+=("$w")
    done
  fi
  echo "ci-watch: expected workflows (--expect): ${EXPECTED[*]:-none}"
elif ! git cat-file -e "$SHA^{commit}" 2>/dev/null; then
  echo "ci-watch: cannot derive the expected workflows ($SHA is not in the local repository); waiting for whatever checks GitHub reports"
elif (( ${#ALL_WF[@]} == 0 )); then
  echo "ci-watch: no workflow files under $WF_DIR/ at $SHA; watching whatever checks report"
elif [[ -z "$BASE" ]] && ! git rev-parse --verify --quiet "$SHA^1" >/dev/null 2>&1; then
  EXPECTED=("${ALL_WF[@]}")
  echo "ci-watch: cannot derive the expected workflows ($SHA has no parent to diff against); expecting all ${#ALL_WF[@]}: ${EXPECTED[*]}"
else
  DERIVED=1
  mapfile -t CHANGED < <(git -c core.quotePath=false diff --name-only "${BASE:-$SHA^1}" "$SHA")
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  for wf in "${ALL_WF[@]}"; do
    git show "$SHA:$wf" > "$tmp/wf.yml"
    verdict="$(decide "$tmp/wf.yml" "${CHANGED[@]}")"
    case "$verdict" in
      expected) EXPECTED+=("$wf") ;;
      unknown*) EXPECTED+=("$wf"); echo "ci-watch: $wf expected: cannot decide its push filter (${verdict#unknown })" ;;
      skip*) echo "ci-watch: $wf not expected: ${verdict#skip }" ;;
    esac
  done
  echo "ci-watch: expected workflows (from ${#CHANGED[@]} changed files): ${EXPECTED[*]:-none}"
fi

if (( PLAN )); then exit 0; fi

if ! command -v gh >/dev/null 2>&1; then
  echo "ci-watch: gh CLI not found, so the checks for $SHA could NOT be verified." >&2
  echo "Unverified is not success (kernel rule 14). Install gh, or watch the CI UI and record the result." >&2
  exit 1
fi

remote_sha="$(git ls-remote origin "refs/heads/$branch" | awk '{print $1}')"
if [[ "$remote_sha" != "$SHA" ]]; then
  echo "ci-watch: SHA mismatch on branch '$branch':" >&2
  echo "  local SHA asked for: $SHA" >&2
  echo "  remote origin/$branch: ${remote_sha:-nothing}" >&2
  echo "Push first; watch what is actually on the remote." >&2
  exit 1
fi

echo "ci-watch: watching checks for $SHA (timeout ${TIMEOUT}s)"
# A failed gh query (not logged in, expired token, rate limit, network) is
# not an empty answer: it blocks both success exits, and if it is still
# failing at the timeout the SHA is reported unverified (exit 1).
errf="$(mktemp)"
trap 'rm -rf "${tmp:-}" "$errf"' EXIT
start=$SECONDS
prev_total=-1
declare -A last_state

while :; do
  gh_err=""
  runs="$(gh api "repos/{owner}/{repo}/commits/$SHA/check-runs" --paginate \
    --jq '.check_runs[] | "\(.name)\t\(.status)\t\(.conclusion // "-")\t\(.html_url)\t\(.id)"' \
    2>"$errf")" || gh_err="check-runs: $(tail -n 3 "$errf" | tr '\n' ' ')"
  wfruns="$(gh api "repos/{owner}/{repo}/actions/runs?head_sha=$SHA" --paginate \
    --jq '.workflow_runs[] | "\(.path)\t\(.status)\t\(.conclusion // "-")\t\(.id)\t\(.html_url)"' \
    2>"$errf")" || gh_err="${gh_err:+$gh_err; }workflow runs: $(tail -n 3 "$errf" | tr '\n' ' ')"
  if [[ -n "$gh_err" ]]; then echo "  [$(date -u +%H:%M:%S)] gh query failed: $gh_err"; fi

  total=0; completed=0; failed=0; failures=""; failed_jobs=()
  while IFS=$'\t' read -r name status conclusion url jobid; do
    [[ -n "$name" ]] || continue
    total=$((total + 1))
    state="$status/$conclusion"
    if [[ "${last_state[$name]:-}" != "$state" ]]; then
      echo "  [$(date -u +%H:%M:%S)] $name: $state"
      last_state[$name]="$state"
    fi
    if [[ "$status" == "completed" ]]; then
      completed=$((completed + 1))
      case "$conclusion" in
        success|neutral|skipped) ;;
        *) failed=$((failed + 1)); failures+="  $name -> $conclusion  $url"$'\n'; failed_jobs+=(${jobid:+"$jobid"}) ;;
      esac
    fi
  done <<< "$runs"

  # Workflow runs: a failed run fails the watch; an expected workflow is done
  # only when it has a completed, non-failing run; any run not yet completed
  # (queued, pending, waiting, in progress) blocks success, expected or not,
  # since a run held before its first job has no check run to watch.
  failed_ids=(); done_wf=" "; open_runs=0
  while IFS=$'\t' read -r path status conclusion id url; do
    [[ -n "$path" ]] || continue
    path="${path%%@*}"
    if [[ "$status" == "completed" ]]; then
      case "$conclusion" in
        success|neutral|skipped) done_wf+="$path " ;;
        *) failed_ids+=("$id"); failures+="  workflow $path -> $conclusion  $url"$'\n'; failed=$((failed + 1)) ;;
      esac
    else
      open_runs=$((open_runs + 1))
    fi
  done <<< "$wfruns"
  missing=()
  for wf in "${EXPECTED[@]}"; do
    [[ "$done_wf" == *" $wf "* ]] || missing+=("$wf")
  done

  if (( total != prev_total )); then
    if (( total == 0 )); then
      echo "  (no checks reported yet for $SHA)"
    fi
    prev_total=$total
  fi

  if (( failed > 0 )); then
    echo "ci-watch: FAILURE for $SHA" >&2
    printf '%s' "$failures" >&2
    # A failed check run is a job. "gh run view --job" refuses while the rest
    # of the run is still in progress, so the job log comes from the jobs logs
    # endpoint, which serves it as soon as the job ends. A failed run with no
    # failed job (a startup failure) gets the run's log instead.
    for id in "${failed_jobs[@]}"; do
      echo "---- failing log tail, job $id (last $LOG_TAIL lines, verbatim) ----" >&2
      gh api "repos/{owner}/{repo}/actions/jobs/$id/logs" 2>&1 | tail -n "$LOG_TAIL" >&2 || echo "(log not available: gh api .../actions/jobs/$id/logs failed)" >&2
    done
    if (( ${#failed_jobs[@]} == 0 )); then
      for id in "${failed_ids[@]}"; do
        echo "---- failing log tail, run $id (last $LOG_TAIL lines, verbatim) ----" >&2
        gh run view "$id" --log-failed 2>&1 | tail -n "$LOG_TAIL" >&2 || echo "(log not available: gh run view $id --log-failed failed)" >&2
      done
    fi
    echo "Inspect the logs above, fix the root cause, verify locally, push the replacement, and watch the replacement SHA." >&2
    exit 1
  fi
  if [[ -z "$gh_err" ]] && (( completed == total && ${#missing[@]} == 0 && open_runs == 0 )); then
    if (( total > 0 )); then
      echo "ci-watch: all $total checks reached terminal success for $SHA"
      exit 0
    fi
    if (( DERIVED && ${#EXPECTED[@]} == 0 && SECONDS - start >= GRACE )); then
      echo "ci-watch: no workflow is expected for $SHA and no check reported within ${GRACE}s; nothing to watch"
      exit 0
    fi
  fi
  if (( SECONDS - start >= TIMEOUT )) && [[ -n "$gh_err" ]]; then
    echo "ci-watch: the checks for $SHA could NOT be verified: gh query failed: $gh_err" >&2
    echo "Unverified is not success (kernel rule 14). Fix gh (gh auth status), then run the same command again." >&2
    exit 1
  fi
  if (( SECONDS - start >= TIMEOUT )); then
    echo "ci-watch: TIMEOUT after ${TIMEOUT}s with $completed/$total checks completed for $SHA." >&2
    if (( ${#missing[@]} )); then echo "  expected workflows without a successful run yet: ${missing[*]}" >&2; fi
    if (( open_runs )); then echo "  workflow runs not yet completed: $open_runs" >&2; fi
    echo "This is not success. Re-run the same command to keep watching (exit 3)." >&2
    exit 3
  fi
  sleep "$POLL"
done
