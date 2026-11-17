#!/usr/bin/env bash
# selftest-reuse.sh: the key, check, record and verify-inputs subcommands, on
# hermetic fixture repos. A fixture declares scripts/, tests/template/, docs/
# and (presence only) BACKLOG.md; src/app.py is deliberately not an input.
# SELFTEST_REUSE_ENV_EXTRA is the test-only hook that stands in for a changed
# bash, git or uname identity.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" || { echo "$0: cannot load lib.sh; stopped before writing anything" >&2; exit 2; }

REUSE="./scripts/selftest-reuse.sh"
# CI=true (every CI runner) and CHECK_SELFTEST refuse reuse by design; the cases
# below set them one at a time.
unset CI CHECK_SELFTEST SELFTEST_REUSE_ENV_EXTRA

write_list() {
  mkdir -p tests/template
  cat > tests/template/selftest-inputs.list <<'LS'
# fixture inputs
scripts
tests/template
docs

exists: BACKLOG.md
LS
}

reuse_fixture() {
  make_fixture
  cp_script selftest-reuse.sh
  cp_script find-python.sh
  write_list
  mkdir -p docs src
  printf 'doc a\n' > docs/a.md
  printf 'print(1)\n' > src/app.py
  printf 'backlog\n' > BACKLOG.md
  printf '#!/usr/bin/env bash\nexit 0\n' > scripts/tool.sh
  chmod +x scripts/tool.sh
  printf 'docs/ignored.tmp\n' > .gitignore
  git add -A >/dev/null 2>&1 && git commit -q -m fixture >/dev/null 2>&1
}

# ---- key ----
reuse_fixture
run $REUSE key
assert_rc "key succeeds" 0
if [[ "$OUT" =~ ^[0-9a-f]{64}$ ]]; then t_ok "the key is 64 hex characters"; else t_bad "the key is 64 hex characters (got: $OUT)"; fi
KEY1="$OUT"
run $REUSE key
assert_eq "the key is stable for unchanged inputs" "$KEY1" "$OUT"

# ---- check and record ----
run $REUSE check
assert_rc "no record: check refuses" 1
assert_contains "no record: the reason is one line naming it" "no record of a passing run"
run $REUSE record
assert_rc "record succeeds" 0
assert_file "the record sits in the git dir" "$(git rev-parse --git-path selftest-pass)"
assert_eq "the record is not part of the working tree" "" "$(git status --porcelain)"
run $REUSE check
assert_rc "unchanged inputs: reuse" 0
assert_contains "the reuse line names the date and the key" "selftest-reuse: inputs unchanged since "
assert_contains "the reuse line shows the first 12 hex of the key" "(key ${KEY1:0:12})"
# check.sh records the key it took before the run: record KEY writes exactly
# that key, never one computed later (an edit in between is never recorded).
GIVEN="0000000000000000000000000000000000000000000000000000000000000abc"
run $REUSE record "$GIVEN"
assert_rc "record KEY succeeds" 0
assert_eq "record KEY stores exactly the given key" "$GIVEN" "$(cut -d' ' -f1 "$(git rev-parse --git-path selftest-pass)")"
run $REUSE record "not-a-key"
assert_rc "record with a malformed key is refused" 1
run $REUSE record
assert_rc "record without a key computes it, as before" 0

# ---- a changed non-input path does not miss ----
echo "print(2)" >> src/app.py
printf 'new\n' > src/other.py
printf 'x\n' > docs/ignored.tmp
printf 'backlog changed\n' > BACKLOG.md
run $REUSE check
assert_rc "no miss after changing or adding paths outside the list, an ignored file, and an exists-only file's content" 0

# ---- an input edit, an added file, a deleted file each miss ----
echo "more" >> docs/a.md
run $REUSE check
assert_rc "editing an input file misses" 1
assert_contains "the miss says the inputs changed" "inputs changed since the last passing run"
git checkout -q -- docs/a.md
run $REUSE check
assert_rc "restoring the edited file hits again" 0
printf 'x\n' > docs/new.md
run $REUSE check
assert_rc "an untracked input file misses" 1
rm -f docs/new.md
run $REUSE check
assert_rc "removing it hits again" 0
printf 'x\n' > scripts/added.sh
run $REUSE check
assert_rc "a new file in an input directory misses" 1
rm -f scripts/added.sh
rm -f docs/a.md
run $REUSE check
assert_rc "deleting an input file misses" 1
git checkout -q -- docs/a.md
rm -f BACKLOG.md
run $REUSE check
assert_rc "deleting an exists-only file misses" 1
printf 'backlog\n' > BACKLOG.md
run $REUSE check
assert_rc "restoring it hits" 0

# ---- forced and CI runs ----
CHECK_SELFTEST=full run $REUSE check
assert_rc "CHECK_SELFTEST=full refuses reuse" 1
assert_contains "the reason names CHECK_SELFTEST=full" "CHECK_SELFTEST=full"
CI=true run $REUSE check
assert_rc "CI=true refuses reuse" 1
assert_contains "the reason names CI" "CI is set"

# ---- the tool identity is part of the key ----
SELFTEST_REUSE_ENV_EXTRA="bash 99" run $REUSE key
if [[ "$OUT" != "$KEY1" ]]; then t_ok "a changed identity changes the key"; else t_bad "a changed identity changes the key"; fi
SELFTEST_REUSE_ENV_EXTRA="uname Other" run $REUSE check
assert_rc "a changed identity misses" 1

# The python and ruff versions are part of the key: a fake python3 (and ruff)
# on PATH reports a version, and changing it changes the key and misses.
mkdir -p "$FIX/py1" "$FIX/py2"
printf '#!/usr/bin/env bash
[ "${1:-}" = --version ] && echo "Python 3.1.0"
exit 0
' > "$FIX/py1/python3"
printf '#!/usr/bin/env bash
[ "${1:-}" = --version ] && echo "Python 3.2.0"
exit 0
' > "$FIX/py2/python3"
printf '#!/usr/bin/env bash
echo "ruff 0.1.0"
' > "$FIX/py1/ruff"
printf '#!/usr/bin/env bash
echo "ruff 0.2.0"
' > "$FIX/py2/ruff"
chmod +x "$FIX"/py1/* "$FIX"/py2/*
run env PATH="$FIX/py1:$PATH" $REUSE key
PYKEY1="$OUT"
run env PATH="$FIX/py1:$PATH" $REUSE record
run env PATH="$FIX/py1:$PATH" $REUSE check
assert_rc "the same python and ruff reuse" 0
run env PATH="$FIX/py2:$PATH" $REUSE key
if [[ "$OUT" != "$PYKEY1" ]]; then t_ok "a changed python or ruff version changes the key"; else t_bad "a changed python or ruff version changes the key"; fi
run env PATH="$FIX/py2:$PATH" $REUSE check
assert_rc "a changed python identity misses" 1
run env PATH="$FIX/py1:$PATH" TEMPLATE_RUFF="$FIX/py2/ruff" $REUSE check
assert_rc "a changed TEMPLATE_RUFF version misses" 1

# ---- a missing record misses ----
rm -f "$(git rev-parse --git-path selftest-pass)"
run $REUSE check
assert_rc "a deleted record misses" 1
assert_contains "the missing record is named" "no record of a passing run"

# ---- a missing list is an error everywhere ----
run $REUSE record
mv tests/template/selftest-inputs.list "$FIX.list"
run $REUSE key
assert_rc "key without the list exits 1" 1
assert_contains "key names the list" "selftest-inputs.list is missing"
run $REUSE check
assert_rc "check without the list exits 1" 1
assert_contains "check names the list" "selftest-inputs.list is missing"
run $REUSE record
assert_rc "record without the list exits 1" 1
run $REUSE verify-inputs
assert_rc "verify-inputs without the list exits 1" 1
mv "$FIX.list" tests/template/selftest-inputs.list
run $REUSE bogus
assert_rc "an unknown subcommand is a usage error" 2
t_check_exec "reuse"

# ---- verify-inputs: a test that reads an undeclared file fails; declared, it passes ----
make_fixture
cp_script selftest-reuse.sh
mkdir -p tests/template docs
# A fake runner stands in for scripts/selftest.sh: it runs the one fake test.
printf '#!/usr/bin/env bash\nset -euo pipefail\ncd "$(dirname "$0")/.."\nbash tests/template/test_fake.sh\n' > scripts/selftest.sh
chmod +x scripts/selftest.sh
printf '#!/usr/bin/env bash\n[[ -f docs/secret.txt ]] || { echo "test_fake: cannot read docs/secret.txt"; exit 1; }\necho "fake test read docs/secret.txt"\n' > tests/template/test_fake.sh
chmod +x tests/template/test_fake.sh
printf 'secret\n' > docs/secret.txt
printf 'scripts\ntests/template\n' > tests/template/selftest-inputs.list
git add -A >/dev/null 2>&1 && git commit -q -m fixture >/dev/null 2>&1
VTMP="$FIX-tmp"
mkdir -p "$VTMP"
TMPDIR="$VTMP" run $REUSE verify-inputs
assert_rc "verify-inputs fails when the list omits a file a test reads" 1
assert_contains "the failing test's own message reaches the output" "cannot read docs/secret.txt"
assert_contains "the failure names the list" "selftest-inputs.list does not declare"
assert_eq "verify-inputs left no temp folder behind (failing run)" "" "$(ls -A "$VTMP")"
printf 'scripts\ntests/template\ndocs\n' > tests/template/selftest-inputs.list
TMPDIR="$VTMP" run $REUSE verify-inputs
assert_rc "verify-inputs passes once the file is declared" 0
assert_contains "the passing run says so" "verify-inputs: OK"
assert_eq "verify-inputs left no temp folder behind (passing run)" "" "$(ls -A "$VTMP")"
printf 'scripts\ntests/template\ndocs/secret.txt\n' > tests/template/selftest-inputs.list
TMPDIR="$VTMP" run $REUSE verify-inputs
assert_rc "a single declared file is enough" 0
# An "exists:" entry is not hashed, so verify-inputs must prove no test reads its
# content: the temp copy holds it empty.
printf 'backlog needle\n' > BACKLOG.md
printf '#!/usr/bin/env bash\ngrep -q needle BACKLOG.md || { echo "test_fake: BACKLOG.md content unreadable"; exit 1; }\n' > tests/template/test_fake.sh
printf 'scripts\ntests/template\nexists: BACKLOG.md\n' > tests/template/selftest-inputs.list
TMPDIR="$VTMP" run $REUSE verify-inputs
assert_rc "verify-inputs fails when a test reads the content of an exists: file" 1
assert_contains "the content read is what failed" "BACKLOG.md content unreadable"
printf '#!/usr/bin/env bash\n[[ -f BACKLOG.md ]] || { echo "test_fake: BACKLOG.md missing"; exit 1; }\n' > tests/template/test_fake.sh
TMPDIR="$VTMP" run $REUSE verify-inputs
assert_rc "verify-inputs passes when a test only checks an exists: file is present" 0
case "$VTMP" in */template-selftest.*-tmp) rm -rf "$VTMP" ;; esac
t_check_exec "verify-inputs"
t_cleanup

t_finish
