#!/usr/bin/env bash
# ci-watch.sh: expected workflows are derived from the commit's changed files
# and each workflow's push filters (printed, with reasons), the root commit
# falls back to "expect all" and says so, a SHA that is not local is reported
# as underivable, --expect and --base override, GitHub's "?" means zero or one
# of the preceding character, and the watch loop does not wait for a
# path-filtered workflow that cannot run. A failure prints the failing job's
# log tail even while its workflow run is still in progress. The watch
# loop runs against a fake gh on PATH and a local bare remote; no network.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

put() { mkdir -p "$(dirname "$1")"; printf '%s\n' "${@:2}" > "$1"; }
W=.github/workflows

make_fixture
git checkout -q -b work
cp_script ci-watch.sh
put $W/ci.yml "name: ci" "on:" "  push:" "    branches: [\"**\"]" "    tags: [\"v*\"]" "  pull_request:" "jobs: {}"
put $W/docs.yml "on:" "  push:" "    paths:" "      - 'docs/**'" "jobs: {}"
put $W/src.yml "on:" "  push:" "    paths:" "    - \"src/**\"  # same-indent list" "jobs: {}"
put $W/ignore.yml "on:" "  push:" "    paths-ignore: ['**.md', 'docs/**']" "jobs: {}"
put $W/tags.yml "on:" "  push:" "    tags: [v*]" "jobs: {}"
put $W/pr.yml "on: pull_request" "jobs: {}"
put $W/neg.yml "on:" "  push:" "    paths: ['src/**', '!src/gen/**']" "jobs: {}"
put $W/inline.yml "on: [push, pull_request]" "jobs: {}"
put $W/branch.yml "on:" "  push:" "    branches:" "      - main" "jobs: {}"
git add -A && git commit -q -m root
ROOT_SHA="$(git rev-parse HEAD)"

# ---- the root commit cannot be diffed: expect all, and say so ----
run ./scripts/ci-watch.sh --plan
assert_rc "--plan exits 0 on the root commit" 0
assert_contains "the root commit falls back to expect all" "cannot derive the expected workflows"
assert_contains "the fallback says how many it expects" "expecting all 9"

# ---- a docs-only commit ----
put docs/guide.md "guide"
git add -A && git commit -q -m docs
run ./scripts/ci-watch.sh --plan
assert_rc "--plan exits 0 on a docs commit" 0
assert_not_contains "branch.yml is not expected on branch work" "workflows (from 1 changed files): $W/branch.yml"
assert_contains "branch filter reason" "$W/branch.yml not expected: branch work is not in its branches filter"
assert_contains "ci.yml is expected" " $W/ci.yml"
assert_contains "docs.yml is expected for a docs change" " $W/docs.yml"
assert_contains "src.yml is not expected for a docs change" "$W/src.yml not expected: no changed file matches its paths filter"
assert_contains "ignore.yml is not expected when every file is ignored" "$W/ignore.yml not expected: every changed file matches its paths-ignore filter"
assert_contains "a tag-only workflow is not expected" "$W/tags.yml not expected: runs on tag pushes only"
assert_contains "a pull_request-only workflow is not expected" "$W/pr.yml not expected: no push trigger"
assert_contains "a negated filter is expected and explained" "$W/neg.yml expected: cannot decide its push filter (negated pattern '!src/gen/**')"
assert_contains "an inline push trigger is expected" " $W/inline.yml"
line="$(printf '%s\n' "$OUT" | grep 'expected workflows (from')"
assert_eq "the docs commit expects exactly these" \
  "ci-watch: expected workflows (from 1 changed files): $W/ci.yml $W/docs.yml $W/inline.yml $W/neg.yml" "$line"

# ---- a source commit ----
put src/a.c "int a;"
git add -A && git commit -q -m src
run ./scripts/ci-watch.sh --plan
line="$(printf '%s\n' "$OUT" | grep 'expected workflows (from')"
assert_eq "the source commit expects exactly these" \
  "ci-watch: expected workflows (from 1 changed files): $W/ci.yml $W/ignore.yml $W/inline.yml $W/neg.yml $W/src.yml" "$line"
assert_contains "docs.yml is not expected for a source change" "$W/docs.yml not expected: no changed file matches its paths filter"
run ./scripts/ci-watch.sh --plan --base "$ROOT_SHA"
line="$(printf '%s\n' "$OUT" | grep 'expected workflows (from')"
assert_eq "--base diffs every commit since the base" \
  "ci-watch: expected workflows (from 2 changed files): $W/ci.yml $W/docs.yml $W/ignore.yml $W/inline.yml $W/neg.yml $W/src.yml" "$line"
run ./scripts/ci-watch.sh --plan --base no-such-ref
assert_rc "a --base that is not a commit is a usage error" 2
run ./scripts/ci-watch.sh --plan 0123456789abcdef0123456789abcdef01234567
assert_contains "a SHA that is not local cannot be derived, and says so" "cannot derive the expected workflows (0123456789abcdef0123456789abcdef01234567 is not in the local repository)"

# ---- --expect overrides, and refuses a name that is not a workflow ----
run ./scripts/ci-watch.sh --plan --expect docs.yml
assert_rc "--expect with a real workflow exits 0" 0
assert_contains "--expect replaces the derived set" "expected workflows (--expect): $W/docs.yml"
assert_not_contains "--expect skips derivation" "not expected:"
run ./scripts/ci-watch.sh --plan --expect all
assert_contains "--expect all expects every workflow" "(--expect): $W/branch.yml $W/ci.yml"
run ./scripts/ci-watch.sh --plan --expect nope.yml
assert_rc "--expect with an unknown workflow is a usage error" 2
assert_contains "the unknown name is reported" "--expect names $W/nope.yml, which is not a workflow file"
run ./scripts/ci-watch.sh --plan --bogus
assert_rc "an unknown flag is a usage error" 2

# ---- the watch loop, against a fake gh and a local bare remote ----
# The fake gh behaves like gh 2.90: "run view" (with or without --job) refuses
# while any run is in progress; the jobs logs endpoint answers at once.
fake_gh() { # set up the fake gh and a bare origin for the current fixture
  FAKE="$FIX/.git/fake"
  mkdir -p "$FAKE/bin"
  put "$FAKE/bin/gh" '#!/usr/bin/env bash' 'case "$*" in' \
    '  *check-runs*) cat "$CI_FAKE/check-runs.txt" 2>/dev/null ;;' \
    '  *actions/runs*) cat "$CI_FAKE/runs.txt" 2>/dev/null ;;' \
    '  *actions/jobs/*/logs*) cat "$CI_FAKE/log.txt"; echo "fake gh args: $*" ;;' \
    '  "run view"*) if grep -q in_progress "$CI_FAKE/runs.txt" 2>/dev/null; then echo "run is still in progress; logs will be available when it is complete" >&2; exit 1; fi' \
    '    cat "$CI_FAKE/log.txt"; echo "fake gh args: $*" ;;' 'esac'
  chmod +x "$FAKE/bin/gh"
  : > "$FAKE/check-runs.txt"; : > "$FAKE/runs.txt"
  export CI_FAKE="$FAKE" CI_WATCH_POLL=0 CI_WATCH_GRACE=0 PATH="$FAKE/bin:$PATH"
  git init -q --bare "$FIX/.git/remote.git"
  git remote add origin "$FIX/.git/remote.git"
  git push -q origin work 2>/dev/null
}
fake_gh
HEAD_SHA="$(git rev-parse HEAD)"
tab=$'\t'
runs_ok() { # workflow files with a completed, successful run
  local w
  : > "$FAKE/runs.txt"
  for w in "$@"; do echo "$W/$w${tab}completed${tab}success${tab}1${tab}https://ci.invalid/1" >> "$FAKE/runs.txt"; done
}

echo "check${tab}completed${tab}success${tab}https://ci.invalid/c${tab}55" > "$FAKE/check-runs.txt"
runs_ok ci.yml ignore.yml inline.yml neg.yml src.yml
run ./scripts/ci-watch.sh --timeout 0
assert_rc "success when every expected workflow and check succeeded" 0
assert_contains "success is reported for the SHA" "all 1 checks reached terminal success for $HEAD_SHA"

runs_ok ci.yml inline.yml neg.yml src.yml
run ./scripts/ci-watch.sh --timeout 0
assert_rc "an expected workflow with no run yet is not success" 3
assert_contains "the timeout names the missing workflow" "expected workflows without a successful run yet: $W/ignore.yml"
assert_contains "the timeout says to re-run" "Re-run the same command"

runs_ok ci.yml ignore.yml inline.yml neg.yml src.yml
run ./scripts/ci-watch.sh --timeout 0 --expect docs.yml
assert_rc "--expect makes the watch wait for docs.yml" 3
assert_contains "the missing --expect workflow is named" "without a successful run yet: $W/docs.yml"

echo "check${tab}in_progress${tab}-${tab}https://ci.invalid/c${tab}55" > "$FAKE/check-runs.txt"
run ./scripts/ci-watch.sh --timeout 0
assert_rc "a check still in progress at the timeout exits 3" 3
assert_contains "the timeout is not success" "TIMEOUT after 0s with 0/1 checks completed"

: > "$FAKE/log.txt"
for i in $(seq 1 60); do echo "log line $i end" >> "$FAKE/log.txt"; done
echo "check${tab}completed${tab}failure${tab}https://ci.invalid/c${tab}55" > "$FAKE/check-runs.txt"
runs_ok inline.yml
echo "$W/ci.yml${tab}completed${tab}failure${tab}77${tab}https://ci.invalid/77" >> "$FAKE/runs.txt"
run ./scripts/ci-watch.sh --timeout 0
assert_rc "a failed job and run fail the watch" 1
assert_contains "the failure names the job and URL" "check -> failure  https://ci.invalid/c"
assert_contains "the failure names the workflow and URL" "workflow $W/ci.yml -> failure  https://ci.invalid/77"
assert_contains "the failing job's log tail is printed" "failing log tail, job 55 (last 40 lines, verbatim)"
assert_contains "the job log is fetched by job id" "fake gh args: api repos/{owner}/{repo}/actions/jobs/55/logs"
assert_not_contains "the run log is not repeated when a job log exists" "failing log tail, run 77"
assert_contains "the tail ends with the last log line" "log line 60 end"
assert_contains "the tail is the last 40 lines" "log line 22 end"
assert_not_contains "the tail is only 40 lines" "log line 21 end"

echo "$W/ci.yml${tab}in_progress${tab}-${tab}77${tab}https://ci.invalid/77" > "$FAKE/runs.txt"
run ./scripts/ci-watch.sh --timeout 0
assert_rc "a failed job fails the watch while its run is still in progress" 1
assert_contains "the job's log tail is printed while the run is in progress" "failing log tail, job 55 (last 40 lines, verbatim)"
assert_contains "the tail is the job log, not a refusal" "log line 60 end"
assert_not_contains "no log-not-available fallback" "log not available"

echo "check${tab}completed${tab}success${tab}https://ci.invalid/c${tab}55" > "$FAKE/check-runs.txt"
echo "$W/ci.yml${tab}completed${tab}startup_failure${tab}77${tab}https://ci.invalid/77" > "$FAKE/runs.txt"
run ./scripts/ci-watch.sh --timeout 0
assert_rc "a failed run with no failed job fails the watch" 1
assert_contains "the run's log tail is printed when no job failed" "failing log tail, run 77 (last 40 lines, verbatim)"
assert_contains "the run log is fetched by run id" "fake gh args: run view 77 --log-failed"

put src/b.c "int b;"
git add -A && git commit -q -m unpushed
run ./scripts/ci-watch.sh --timeout 0
assert_rc "an unpushed SHA is unverifiable" 1
assert_contains "the local SHA is printed" "local SHA asked for: $(git rev-parse HEAD)"
assert_contains "the remote SHA is printed" "remote origin/work: $HEAD_SHA"

# ---- "?" is zero or one of the preceding character (GitHub's *.jsx? example) ----
put $W/js.yml "on:" "  push:" "    paths: ['**.jsx?']" "jobs: {}"
git add -A && git commit -q -m js-workflow
put web/page.js "page"
git add -A && git commit -q -m js
run ./scripts/ci-watch.sh --plan
assert_contains "*.jsx? matches page.js" "(from 1 changed files): $W/ci.yml $W/ignore.yml $W/inline.yml $W/js.yml"
put web/page.jsx "page"
git add -A && git commit -q -m jsx
run ./scripts/ci-watch.sh --plan
assert_contains "*.jsx? matches page.jsx" " $W/js.yml"
put web/page.json "{}"
git add -A && git commit -q -m json
run ./scripts/ci-watch.sh --plan
assert_contains "*.jsx? does not match page.json" "$W/js.yml not expected: no changed file matches its paths filter"

# ---- quoted events in an inline list or scalar ----
put $W/quoted.yml 'on: ["push", pull_request]' "jobs: {}"
put $W/scalar.yml "on: 'push'" "jobs: {}"
put $W/prquoted.yml "on: ['pull_request', \"workflow_dispatch\"]" "jobs: {}"
git add -A && git commit -q -m quoted-events
run ./scripts/ci-watch.sh --plan
assert_contains "quoted non-push events are not a push trigger" "$W/prquoted.yml not expected: no push trigger"
assert_not_contains "a quoted push in an inline list is not skipped" "$W/quoted.yml not expected"
assert_not_contains "a quoted push scalar is not skipped" "$W/scalar.yml not expected"
OUT="$(printf '%s\n' "$OUT" | grep 'expected workflows (from')"
assert_contains "a quoted push in an inline list is expected" " $W/quoted.yml"
assert_contains "a quoted push scalar is expected" " $W/scalar.yml"

# ---- "nothing to watch" exits 0 only after a confident derivation ----
t_cleanup
make_fixture
git checkout -q -b work
cp_script ci-watch.sh
put $W/docs.yml "on:" "  push:" "    paths: ['docs/**']" "jobs: {}"
git add -A && git commit -q -m root
put src/a.c "int a;"
git add -A && git commit -q -m src
fake_gh
run ./scripts/ci-watch.sh --timeout 0
assert_rc "a confident derivation with nothing expected and no checks exits 0" 0
assert_contains "it says there is nothing to watch" "no workflow is expected for $(git rev-parse HEAD) and no check reported within 0s; nothing to watch"
cp "$FAKE/bin/gh" "$FAKE/gh.good"
put "$FAKE/bin/gh" '#!/usr/bin/env bash' 'echo "please run: gh auth login" >&2' 'exit 4'
run ./scripts/ci-watch.sh --timeout 0
assert_rc "a failing gh is unverified, never nothing-to-watch" 1
assert_not_contains "a failing gh does not claim nothing to watch" "nothing to watch"
assert_contains "the gh failure is reported" "could NOT be verified: gh query failed: check-runs: please run: gh auth login"
cp "$FAKE/gh.good" "$FAKE/bin/gh"
echo "$W/pr.yml${tab}queued${tab}-${tab}91${tab}https://ci.invalid/91" > "$FAKE/runs.txt"
run ./scripts/ci-watch.sh --timeout 0
assert_rc "a queued run with no check run yet blocks the nothing-to-watch exit" 3
assert_contains "the open run is reported" "workflow runs not yet completed: 1"
echo "check${tab}completed${tab}success${tab}https://ci.invalid/c${tab}55" > "$FAKE/check-runs.txt"
echo "$W/pr.yml${tab}pending${tab}-${tab}91${tab}https://ci.invalid/91" > "$FAKE/runs.txt"
run ./scripts/ci-watch.sh --timeout 0
assert_rc "a pending run blocks success even when every check run succeeded" 3
: > "$FAKE/check-runs.txt"; : > "$FAKE/runs.txt"
put "docs/caf$(printf '\xc3\xa9').md" "non-ASCII name"
git add -A && git commit -q -m nonascii
run ./scripts/ci-watch.sh --plan
assert_contains "a non-ASCII changed path still matches its paths filter" "(from 1 changed files): $W/docs.yml"
git push -q origin work 2>/dev/null
git rm -q -r .github && git commit -q -m no-workflows && git push -q origin work 2>/dev/null
run ./scripts/ci-watch.sh --timeout 0
assert_rc "with no workflow files there is no confident derivation, so no checks is a timeout" 3
assert_not_contains "nothing-to-watch is not claimed without a derivation" "nothing to watch"

t_finish
