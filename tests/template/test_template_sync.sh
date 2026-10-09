#!/usr/bin/env bash
# template-sync.sh: the three-way comparison on a fixture template (two tagged
# versions) and a fixture project last synced to v1. Covers: --help, the
# template read from AGENTS.md, the clean-tree and branch guard, the exact core
# set, header-only lessons files, adopted profiles and ci.yml as DIFF only, the
# KERNEL and Rules index diffs from AGENTS.md, conflicts reported on every run
# until merged and never recorded as synced, and the exit codes (0 clean or
# applied, 1 conflicts or kernel change pending, 2 usage or guard failure).
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

make_fixture
TPL="$FIX/template"
PRJ="$FIX/project"
export TEMPLATE_SYNC_TODAY=2026-10-09

commit_all() { git add -A >/dev/null 2>&1 && git commit -q -m "$1" >/dev/null 2>&1; }
proj_commit() { git add -A -- . ':!.work/template-sync' >/dev/null 2>&1 && git commit -q -m "$1" >/dev/null 2>&1; }
put() { # file content
  mkdir -p "$(dirname "$1")"
  printf '%s\n' "$2" > "$1"
}
put_agents() { # kernel-text rules-text
  cat > AGENTS.md <<AG
# Agents

<!-- KERNEL:BEGIN -->
1. $1
<!-- KERNEL:END -->

## Rules index (triggered)
- $2

## Project decisions
- Template: $TPL v1
- Profiles: software
AG
}
put_lessons() { # first-line data1 data2: a 12-line format header, then two data lines
  mkdir -p docs/lessons
  printf '%s\n' "$1" l2 l3 l4 l5 l6 l7 l8 l9 l10 l11 l12 "$2" "$3" > docs/lessons/INDEX.md
}

# ---- the template, version v1 ----
mkdir -p "$TPL" && cd "$TPL" || exit 1
git init -q . >/dev/null 2>&1
git config user.email t@example.invalid; git config user.name t; git config core.autocrlf false
mkdir -p scripts
cp "$T_ROOT/scripts/kernel-hash.sh" "$T_ROOT/scripts/template-sync.sh" scripts/
put scripts/a.sh "echo a v1"
put scripts/obsolete.sh "echo obsolete"
put tests/template/t.sh "echo t v1"
put docs/rules/r.md "rule r"
put docs/procedures/p.md "procedure p v1"
put docs/profiles/README.md "profiles readme v1"
put docs/profiles/software/PROFILE.md "software v1"
put docs/profiles/embedded/PROFILE.md "embedded v1"
put docs/profiles/scientific/PROFILE.md "scientific v1"
put CONTRIBUTING.md "contributing v1"
put manifest.md "manifest v1"
put CLAUDE.md "@AGENTS.md"
put cliff.toml "cliff v1"
put .github/workflows/ci.yml "ci v1"
put_lessons "# Lessons index v1" "template data 1" "template data 2"
put README.md "template readme v1"
put BACKLOG.md "template backlog v1"
put docs/decisions/0001.md "adr v1"
put .work/TASK.md "template task v1"
put_agents "Kernel v1." "rule index v1"
commit_all v1 && git tag v1

# ---- version v2 ----
put scripts/a.sh "echo a v2"
git rm -q scripts/obsolete.sh
put docs/rules/new.md "a new rule"
put docs/procedures/p.md "procedure p v2"
put docs/profiles/software/PROFILE.md "software v2"
put docs/profiles/embedded/PROFILE.md "embedded v2"
put manifest.md "manifest v2"
put .github/workflows/ci.yml "ci v2"
put_lessons "# Lessons index v2" "template data 1" "template data 2"
put README.md "template readme v2"
put BACKLOG.md "template backlog v2"
put docs/decisions/0001.md "adr v2"
put_agents "Kernel v2." "rule index v2"
commit_all v2 && git tag v2

# ---- the project: v1 files, its own truth files, last synced to v1 ----
mkdir -p "$PRJ" && cd "$PRJ" || exit 1
git init -q . >/dev/null 2>&1
git config user.email p@example.invalid; git config user.name p; git config core.autocrlf false
git -C "$TPL" archive --format=tar v1 | tar -x -C "$PRJ"
rm -f README.md BACKLOG.md
rm -rf docs/profiles/scientific
put_agents "Kernel v1." "rule index v1"
put README.md "project readme"
put BACKLOG.md "project backlog"
put docs/procedures/p.md "procedure p v1 edited by the project"
put docs/profiles/embedded/PROFILE.md "embedded v1 edited by the project"
put .github/workflows/ci.yml "ci v1 edited by the project"
put_lessons "# Lessons index v1" "project data 1" "project data 2"
put docs/lessons/MAINTENANCE.log "template-sync: v1 2026-09-01"
chmod +x scripts/*.sh
./scripts/kernel-hash.sh --update >/dev/null
proj_commit "project at v1"
git checkout -q -B main
cp AGENTS.md "$FIX/agents.before"; cp README.md "$FIX/readme.before"
cp .kernel.hash "$FIX/hash.before"
cp docs/lessons/MAINTENANCE.log "$FIX/log.before"

# ---- (a) help ----
run ./scripts/template-sync.sh --help
assert_rc "--help exits 0" 0
assert_contains "--help prints the usage" "usage: scripts/template-sync.sh"
run ./scripts/template-sync.sh -h
assert_rc "-h exits 0" 0
assert_contains "-h prints the usage" "--dry-run"

# ---- dry run on main (allowed) ----
run ./scripts/template-sync.sh --template "$TPL" --ref v2 --dry-run
assert_rc "dry run with conflicts and a kernel change exits 1" 1
assert_contains "previous sync detected" "previous sync v1"
assert_contains "untouched script is an UPDATE" "UPDATE    scripts/a.sh"
assert_contains "untouched manifest is an UPDATE" "UPDATE    manifest.md"
assert_contains "lessons header change is an UPDATE" "UPDATE    docs/lessons/INDEX.md"
assert_contains "edited procedure is a CONFLICT" "CONFLICT  docs/procedures/p.md"
assert_contains "conflict shows a diff" "=== diff: docs/procedures/p.md"
assert_file "conflict diff is written to .work" .work/template-sync/docs/procedures/p.md.diff
assert_contains "carried non-adopted profile is synced as a conflict" "CONFLICT  docs/profiles/embedded/PROFILE.md"
assert_contains "new file is an ADD" "ADD       docs/rules/new.md"
assert_contains "upstream removal is listed" "REMOVED   scripts/obsolete.sh"
assert_not_contains "never lists README.md" "README.md"
assert_not_contains "never lists BACKLOG.md" "BACKLOG.md"
assert_not_contains "never lists decisions" "docs/decisions"
assert_not_contains "never lists .work as a path" "  .work/"
assert_not_contains "a profile the project does not carry is skipped" "scientific"
assert_contains "summary counts" "update=3 add=1 conflict=2 diff=2"
assert_contains "dry run says nothing changed" "dry run; nothing was changed"
assert_eq "dry run left a.sh alone" "echo a v1" "$(cat scripts/a.sh)"
assert_no_file "dry run added nothing" docs/rules/new.md
assert_eq "dry run did not record a sync" "$(cat "$FIX/log.before")" "$(cat docs/lessons/MAINTENANCE.log)"

# ---- (e) adopted profiles and ci.yml are DIFF only ----
assert_contains "adopted profile is a DIFF" "DIFF      docs/profiles/software/PROFILE.md"
assert_not_contains "adopted profile is never an UPDATE" "UPDATE    docs/profiles/software"
assert_contains "ci.yml is a DIFF" "DIFF      .github/workflows/ci.yml"
assert_file "profile diff is written" .work/template-sync/docs/profiles/software/PROFILE.md.diff
assert_file_has "profile diff holds the template text" .work/template-sync/docs/profiles/software/PROFILE.md.diff "+software v2"
assert_file "ci diff is written" .work/template-sync/.github/workflows/ci.yml.diff
assert_file_has "ci diff holds the template text" .work/template-sync/.github/workflows/ci.yml.diff "+ci v2"

# ---- (f) AGENTS.md: kernel and rules index diffs, never applied ----
assert_contains "kernel change is announced" "KERNEL CHANGE: needs owner approval and scripts/kernel-hash.sh --update"
assert_file "kernel diff is written" .work/template-sync/AGENTS.kernel.diff
assert_file_has "kernel diff holds the template kernel" .work/template-sync/AGENTS.kernel.diff "+1. Kernel v2."
assert_file "rules index diff is written" .work/template-sync/AGENTS.rules-index.diff
assert_file_has "rules index diff holds the template line" .work/template-sync/AGENTS.rules-index.diff "+- rule index v2"
assert_eq "AGENTS.md untouched by a dry run" "$(cat "$FIX/agents.before")" "$(cat AGENTS.md)"

# ---- (c) guard: a real apply refuses on main and on a dirty tree ----
run ./scripts/template-sync.sh --template "$TPL" --ref v2
assert_rc "apply on main is refused" 2
assert_contains "branch guard is explained" "not main or master"
assert_eq "refused apply changed nothing" "echo a v1" "$(cat scripts/a.sh)"
git checkout -q -b sync-work
echo "stray" > stray.txt
run ./scripts/template-sync.sh --template "$TPL" --ref v2
assert_rc "apply on a dirty tree is refused" 2
assert_contains "dirty guard is explained" "working tree is not clean"
assert_eq "refused dirty apply changed nothing" "echo a v1" "$(cat scripts/a.sh)"
run ./scripts/template-sync.sh --template "$TPL" --ref v2 --dry-run
assert_rc "dry run on a dirty tree is allowed (conflicts pending)" 1
rm -f stray.txt

# ---- real run on a branch: updates applied, conflicts kept and not recorded ----
run ./scripts/template-sync.sh --template "$TPL" --ref v2
assert_rc "apply with conflicts exits 1" 1
assert_eq "untouched script updated" "echo a v2" "$(cat scripts/a.sh)"
assert_eq "manifest updated" "manifest v2" "$(cat manifest.md)"
assert_eq "new file added" "a new rule" "$(cat docs/rules/new.md)"
assert_eq "adopted profile never applied" "software v1" "$(cat docs/profiles/software/PROFILE.md)"
assert_eq "ci.yml never applied" "ci v1 edited by the project" "$(cat .github/workflows/ci.yml)"
assert_eq "conflicting file keeps the project version" "procedure p v1 edited by the project" "$(cat docs/procedures/p.md)"
assert_eq "carried profile conflict keeps the project version" "embedded v1 edited by the project" "$(cat docs/profiles/embedded/PROFILE.md)"
assert_file "upstream-removed file is not deleted" scripts/obsolete.sh
assert_eq "AGENTS.md never applied" "$(cat "$FIX/agents.before")" "$(cat AGENTS.md)"
assert_eq "README.md untouched" "$(cat "$FIX/readme.before")" "$(cat README.md)"
assert_eq ".kernel.hash untouched" "$(cat "$FIX/hash.before")" "$(cat .kernel.hash)"
assert_contains "kernel re-verified" "kernel-hash: OK"
assert_file_has "lessons header updated" docs/lessons/INDEX.md "# Lessons index v2"
assert_file_has "lessons project data kept (1)" docs/lessons/INDEX.md "project data 1"
assert_file_has "lessons project data kept (2)" docs/lessons/INDEX.md "project data 2"
assert_file_lacks "template lessons data not copied" docs/lessons/INDEX.md "template data 1"
assert_contains "unrecorded sync is announced" "sync NOT recorded"
assert_eq "conflicts are not recorded as synced" "$(cat "$FIX/log.before")" "$(cat docs/lessons/MAINTENANCE.log)"

# ---- (g) conflicts are reported on every run until resolved ----
proj_commit "after first sync"
run ./scripts/template-sync.sh --template "$TPL" --ref v2
assert_rc "second apply still exits 1" 1
assert_contains "conflict reported again" "CONFLICT  docs/procedures/p.md"
assert_contains "second conflict reported again" "CONFLICT  docs/profiles/embedded/PROFILE.md"
assert_eq "still not recorded" "$(cat "$FIX/log.before")" "$(cat docs/lessons/MAINTENANCE.log)"
assert_contains "the way out is named" "rerun with --resolved"

# ---- (h) a hand merge that keeps project lines is attested with --resolved ----
# The project merges p.md by hand and keeps its own line, so the file differs
# from both the old and the new template: without --resolved it stays a
# conflict forever and the sync is never recorded.
git branch -q keep-before-h
put docs/procedures/p.md "procedure p v2 plus a project line"
put docs/profiles/embedded/PROFILE.md "embedded v2"
put_agents "Kernel v2." "rule index v2"
./scripts/kernel-hash.sh --update >/dev/null
proj_commit "hand merge keeping a project line"
run ./scripts/template-sync.sh --template "$TPL" --ref v2 --dry-run
assert_rc "a hand merge that keeps project lines is still a conflict" 1
assert_contains "the hand-merged file is reported as a conflict" "CONFLICT  docs/procedures/p.md"
run ./scripts/template-sync.sh --template "$TPL" --ref v2 --resolved
assert_rc "--resolved records the sync with the conflicts attested" 0
assert_contains "the attested file is listed as resolved" "RESOLVED  docs/procedures/p.md"
assert_not_contains "nothing is reported as a conflict" "CONFLICT"
assert_file_has "the project line survives --resolved" docs/procedures/p.md "plus a project line"
assert_file_has "the sync is recorded" docs/lessons/MAINTENANCE.log "template-sync: v2 2026-10-09"
git reset -q --hard keep-before-h && git clean -qfd -e .work/template-sync >/dev/null 2>&1

# ---- resolve by hand: conflicts and kernel merged ----
put docs/procedures/p.md "procedure p v2"
put docs/profiles/embedded/PROFILE.md "embedded v2"
put_agents "Kernel v2." "rule index v2"
./scripts/kernel-hash.sh --update >/dev/null
proj_commit "merged by hand"
run ./scripts/template-sync.sh --template "$TPL" --ref v2
assert_rc "clean apply exits 0 (DIFF entries do not fail it)" 0
assert_contains "DIFF still reported" "DIFF      docs/profiles/software/PROFILE.md"
assert_not_contains "no conflict left" "CONFLICT"
assert_not_contains "no kernel change left" "KERNEL CHANGE"
assert_file_has "sync recorded with ref and date" docs/lessons/MAINTENANCE.log "template-sync: v2 2026-10-09"
assert_file_has "earlier log line kept" docs/lessons/MAINTENANCE.log "template-sync: v1 2026-09-01"
proj_commit "synced to v2"

# ---- run again: now synced to v2, nothing to bring ----
run ./scripts/template-sync.sh --template "$TPL" --ref v2 --dry-run
assert_rc "second dry run exits 0" 0
assert_contains "second run sees v2 as previous" "previous sync v2"
assert_contains "nothing left to apply" "update=0 add=0 conflict=0"

# ---- (b) the template and the default ref come from AGENTS.md ----
run ./scripts/template-sync.sh --dry-run
assert_contains "template read from AGENTS.md" "template and default ref taken from AGENTS.md"
assert_contains "template url and tag from AGENTS.md" "template $TPL at v1"
run ./scripts/template-sync.sh --ref v2 --dry-run
assert_rc "--template is optional" 0
assert_contains "--ref overrides the AGENTS.md tag" "template $TPL at v2"
cp AGENTS.md "$FIX/agents.keep"
sed -i.bak '/^- Template:/d' AGENTS.md && rm -f AGENTS.md.bak
run ./scripts/template-sync.sh --dry-run
assert_rc "no template anywhere is a usage error" 2
assert_contains "the missing Template line is explained" "- Template: <url> <tag>"
cp "$FIX/agents.keep" AGENTS.md

# ---- no previous sync recorded: only missing files are applied ----
rm -f docs/lessons/MAINTENANCE.log
put scripts/a.sh "echo a project edit"
rm -f docs/rules/new.md
run ./scripts/template-sync.sh --template "$TPL" --ref v2 --dry-run
assert_contains "no previous version is stated" "no previous sync recorded"
assert_contains "differing file cannot be proven untouched" "CONFLICT  scripts/a.sh"
assert_contains "missing file is added" "ADD       docs/rules/new.md"

# ---- usage ----
run ./scripts/template-sync.sh --bogus
assert_rc "an unknown flag is a usage error" 2
run ./scripts/template-sync.sh --template "$FIX/does-not-exist" --dry-run
assert_rc "an unreachable template fails" 1
run ./scripts/template-sync.sh --template "$TPL" --ref no-such-ref --dry-run
assert_rc "an unknown ref fails" 1

t_finish
