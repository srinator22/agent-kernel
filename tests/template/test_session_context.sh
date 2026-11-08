#!/usr/bin/env bash
# session-context.sh: the mode line, the rule-7 reminder, the git priming
# block (branch, capped status, last 10 commits), the in-progress task, and
# graceful output outside a git repository.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

make_fixture
cp_script session-context.sh
git add scripts && git commit -q -m "chore: scripts"
git checkout -q -b task/demo
for i in $(seq 1 12); do echo "$i" > "f$i.txt"; git add "f$i.txt"; git commit -q -m "feat: commit number $i"; done

run bash scripts/session-context.sh
assert_rc "exits 0" 0
assert_contains "template mode line" "TEMPLATE MODE"
assert_contains "rule 7 reminder" "Kernel rule 7"
assert_contains "branch line" "[session-context] Branch: task/demo"
assert_contains "clean tree is said so" "Working tree: clean"
assert_contains "last commits header" "Last commits"
assert_contains "the newest commit is listed" "feat: commit number 12"
assert_contains "the tenth newest commit is listed" "feat: commit number 3"
assert_not_contains "only ten commits are listed" "feat: commit number 2"

echo changed > f1.txt
for i in $(seq 1 25); do echo x > "new$i.txt"; done
run bash scripts/session-context.sh
assert_contains "changed-file count" "Working tree (26 changed or untracked):"
assert_contains "a modified file is listed" " M f1.txt"
assert_contains "the status list is capped" "... 6 more (git status --short)"

mkdir -p .work
echo "# Task: {{title}}" > .work/TASK.md
run bash scripts/session-context.sh
assert_not_contains "a pristine TASK.md is not printed" "In-progress task state"
printf '# Task: demo\nMode: standard\n' > .work/TASK.md
run bash scripts/session-context.sh
assert_contains "a live TASK.md is printed" "In-progress task state"
assert_contains "its content follows" "# Task: demo"
touch .start-done
run bash scripts/session-context.sh
assert_contains "project mode line after start" "Project mode (start has run)"
t_cleanup

# Outside a git repository: no git block, still exit 0.
FIX="$(mktemp -d "${TMPDIR:-/tmp}/template-selftest.XXXXXX")"
mkdir -p "$FIX/scripts" && cp "$T_ROOT/scripts/session-context.sh" "$FIX/scripts/"
run env GIT_CEILING_DIRECTORIES="$FIX" bash "$FIX/scripts/session-context.sh"
assert_rc "outside git it still exits 0" 0
assert_contains "outside git the reminder still prints" "Kernel rule 7"
assert_not_contains "outside git there is no branch line" "Branch:"
t_cleanup

# Template update awareness. The template URL is a local repo so no network
# is touched; TEMPLATE_UPDATE_SYNC=1 runs the cache refresh in the foreground.
make_fixture
cp_script session-context.sh template-sync.sh
TMPL="$FIX/tmpl"
mkdir -p "$TMPL/scripts" && git -C "$TMPL" init -q . && git -C "$TMPL" config user.email t@example.invalid && git -C "$TMPL" config user.name t
echo a > "$TMPL/scripts/a.sh"; echo "# t" > "$TMPL/AGENTS.md"
git -C "$TMPL" add . && git -C "$TMPL" commit -q -m "feat: a" && git -C "$TMPL" tag template-v0.9.0
echo b >> "$TMPL/scripts/a.sh"
git -C "$TMPL" commit -q -am "feat: b" && git -C "$TMPL" tag template-v0.10.0
SHA="$(git -C "$TMPL" rev-parse HEAD)"
mkdir -p docs/lessons
touch .start-done
set_synced() { # url ref [line-suffix]
  printf '# x
- Template: %s %s%s
' "$1" "$2" "${3:-}" > AGENTS.md
  printf 'template-sync: %s 2026-01-01
' "$2" > docs/lessons/MAINTENANCE.log
}
UPD="Template update available: template-v0.10.0"

set_synced "$TMPL" template-v0.9.0
rm -rf .work/template-sync
run env TEMPLATE_UPDATE_SYNC=1 bash scripts/session-context.sh
assert_rc "update check exits 0" 0
assert_contains "older synced tag gets the update line" "[session-context] $UPD (synced template-v0.9.0). Run /template-update."
assert_eq "the cache holds the newest tag" "template-v0.10.0" "$(cat .work/template-sync/latest-tag 2>/dev/null)"

set_synced "$TMPL" template-v0.10.0
run env TEMPLATE_UPDATE_SYNC=1 bash scripts/session-context.sh
assert_not_contains "synced to the newest tag prints no update line" "Template update available"

set_synced "$TMPL" "$SHA"
run env TEMPLATE_UPDATE_SYNC=1 bash scripts/session-context.sh
assert_contains "a sha sync gets the update line" "$UPD (synced $SHA)"

set_synced "$TMPL" template-v0.9.0 " (see notes)"
run env TEMPLATE_UPDATE_SYNC=1 bash scripts/session-context.sh
assert_not_contains "a Template line with prose prints nothing" "Template update available"

set_synced "$TMPL" template-v0.9.0
run env TEMPLATE_UPDATE_CHECK=0 TEMPLATE_UPDATE_SYNC=1 bash scripts/session-context.sh
assert_not_contains "TEMPLATE_UPDATE_CHECK=0 silences the block" "Template update available"
assert_contains "other lines still print with the check off" "Kernel rule 7"

echo template-v9.9.9 > .work/template-sync/latest-tag
run env TEMPLATE_UPDATE_SYNC=1 bash scripts/session-context.sh
assert_contains "a fresh cache is used without refresh" "Template update available: template-v9.9.9 (synced template-v0.9.0)"

set_synced "$TMPL/missing" template-v0.9.0
rm -rf .work/template-sync
run env TEMPLATE_UPDATE_SYNC=1 bash scripts/session-context.sh
assert_rc "unreachable template with no cache exits 0" 0
assert_not_contains "unreachable template prints no update line" "Template update available"
assert_contains "unreachable template keeps the other lines" "Kernel rule 7"
mkdir -p .work/template-sync && echo template-v0.10.0 > .work/template-sync/latest-tag
touch -d '3 days ago' .work/template-sync/latest-tag
run env TEMPLATE_UPDATE_SYNC=1 bash scripts/session-context.sh
assert_rc "unreachable template with a stale cache exits 0" 0
assert_contains "a failed refresh keeps the old cache" "$UPD (synced template-v0.9.0)"

# The real background refresh path (no TEMPLATE_UPDATE_SYNC) in project mode
# with no cache: the hook returns without waiting, prints its normal lines and
# no update line. The unreachable URL makes the detached job fail fast; its
# result is deliberately not awaited or asserted.
set_synced "$TMPL/missing" template-v0.9.0
rm -rf .work/template-sync
run bash scripts/session-context.sh
assert_rc "background refresh path exits 0" 0
assert_contains "background refresh path keeps the other lines" "Kernel rule 7"
assert_contains "background refresh path prints the project mode line" "Project mode (start has run)"
assert_not_contains "background refresh path prints no update line" "Template update available"

# Template mode: release pending count over the synced set only.
rm -f .start-done
rm -rf .work/template-sync
git add -A >/dev/null 2>&1; git commit -q -m "chore: fixture" 2>/dev/null
run bash scripts/session-context.sh
assert_not_contains "no template tag means no release line" "Template release pending"
git tag template-v0.1.0
echo n > notes.txt; git add notes.txt; git commit -q -m "docs: notes"
run bash scripts/session-context.sh
assert_not_contains "a non-synced file does not raise the count" "Template release pending"
echo "# c" >> scripts/session-context.sh; git commit -q -am "feat: touch a synced script"
run bash scripts/session-context.sh
assert_rc "a touched hook still exits 0" 0
assert_contains "a synced-set commit raises the count" "[session-context] Template release pending: 1 synced-set commits since template-v0.1.0. Cut one with scripts/template-release.sh."
assert_not_contains "a count-only line has no kernel sentence" "The kernel or rules index changed."

# Fresh tag with an AGENTS.md carrying a kernel block, rules index and Project
# decisions, plus a lessons file longer than its 12 synced header lines.
cat > AGENTS.md <<'EOF'
<!-- KERNEL:BEGIN -->
1. rule one
<!-- KERNEL:END -->
## Standards
- s
## Rules index (triggered)
- index one
## Project decisions
- Purpose: p
EOF
mkdir -p docs/lessons
seq 1 20 > docs/lessons/PENDING.md
git add -A; git commit -q -m "chore: agents and lessons"
git tag template-v0.2.0
run bash scripts/session-context.sh
assert_not_contains "a fresh tag clears the release line" "Template release pending"

sed -i '15s/.*/changed/' docs/lessons/PENDING.md
git commit -q -am "docs: lesson data below the header"
run bash scripts/session-context.sh
assert_not_contains "a lessons edit below line 12 does not raise the count" "Template release pending"

sed -i 's/^- Purpose: p/- Purpose: q/' AGENTS.md
git commit -q -am "docs: project decisions"
run bash scripts/session-context.sh
assert_not_contains "a Project decisions edit does not raise the count" "Template release pending"

sed -i 's/^- index one/- index two/' AGENTS.md
git commit -q -am "docs: rules index"
run bash scripts/session-context.sh
assert_rc "a rules index change exits 0" 0
assert_contains "a rules index change prints the line at count 0" "Template release pending: 0 synced-set commits since template-v0.2.0. Cut one with scripts/template-release.sh. The kernel or rules index changed."

t_finish
