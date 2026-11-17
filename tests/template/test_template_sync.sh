#!/usr/bin/env bash
# template-sync.sh: the three-way comparison on a fixture template (two tagged
# versions) and a fixture project last synced to v1. Covers: --help, the
# template read from AGENTS.md, the clean-tree and branch guard, the exact core
# set, header-only lessons files, adopted profiles and ci.yml as DIFF only, the
# KERNEL and Rules index diffs from AGENTS.md, conflicts reported on every run
# until merged and never recorded as synced, and the exit codes (0 clean or
# applied, 1 conflicts, kernel change pending, skills cap exceeded or not
# counted, 2 usage or guard failure), and the skills cap reported after a sync.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" || { echo "$0: cannot load lib.sh; stopped before writing anything" >&2; exit 2; }

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
cp "$T_ROOT/scripts/kernel-hash.sh" "$T_ROOT/scripts/template-sync.sh" "$T_ROOT/scripts/profiles.sh" scripts/
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

# ---- kernel change pending: non-kernel files still sync; --accept-kernel is the owner's explicit step ----
# Conflicts merged by hand, kernel left at v1: the template kernel v2 is pending.
kbranch() { git reset -q --hard "$1" && git clean -qfd -e .work/template-sync >/dev/null 2>&1; }
put docs/procedures/p.md "procedure p v2"
put docs/profiles/embedded/PROFILE.md "embedded v2"
proj_commit "conflicts merged, kernel still v1"
git branch -q kbase
run ./scripts/template-sync.sh --template "$TPL" --ref v2
assert_rc "a pending kernel change exits 1" 1
assert_contains "the kernel change is announced" "KERNEL CHANGE"
assert_eq "non-kernel files are still applied" "echo a v2" "$(cat scripts/a.sh)"
assert_file_has "the kernel is left alone" AGENTS.md "Kernel v1."
assert_contains "the sync is not recorded while the kernel is pending" "sync NOT recorded"
assert_file_lacks "the log keeps the old ref as the base" docs/lessons/MAINTENANCE.log "v2"
kbranch kbase
run ./scripts/template-sync.sh --template "$TPL" --ref v2 --accept-kernel
assert_rc "--accept-kernel on an unmodified kernel exits 0" 0
assert_eq "exactly one acceptance line" "1" "$(printf '%s\n' "$OUT" | grep -c 'kernel accepted verbatim from v2 under --accept-kernel')"
assert_file_has "the template kernel is in AGENTS.md" AGENTS.md "Kernel v2."
assert_file_has "the rules index is not touched" AGENTS.md "rule index v1"
run ./scripts/kernel-hash.sh --verify
assert_rc "the kernel hash was updated" 0
assert_file_has "the sync is recorded" docs/lessons/MAINTENANCE.log "template-sync: v2 2026-10-09"
kbranch kbase
run ./scripts/template-sync.sh --template "$TPL" --ref v2 --accept-kernel --dry-run
assert_contains "a dry run never accepts" "KERNEL CHANGE"
assert_file_has "dry run left the kernel alone" AGENTS.md "Kernel v1."
# The three refusals: AGENTS.md keeps its kernel and the reason is named.
kstop() { # name reason-needle
  run ./scripts/template-sync.sh --template "$TPL" --ref v2 --accept-kernel
  assert_rc "$1: exits 1" 1
  assert_contains "$1: KERNEL CHANGE" "KERNEL CHANGE"
  assert_contains "$1: the reason is named" "$2"
  assert_file_lacks "$1: AGENTS.md is not changed" AGENTS.md "Kernel v2."
  kbranch kbase
}
git rm -q docs/lessons/MAINTENANCE.log && proj_commit "no log"
kstop "no recorded sync" "no recorded sync line"
put docs/lessons/MAINTENANCE.log "template-sync: nosuchref 2026-09-01" && proj_commit "unknown ref"
kstop "recorded ref missing" "missing from the template"
put_agents "Kernel custom." "rule index v1" && ./scripts/kernel-hash.sh --update >/dev/null && proj_commit "customized kernel"
kstop "customized kernel" "customized"
sed -i 's/$/\r/' AGENTS.md && proj_commit "CRLF checkout"
run ./scripts/template-sync.sh --template "$TPL" --ref v2 --accept-kernel
assert_rc "a CRLF-only difference counts as equal" 0
assert_file_has "the kernel is accepted into the CRLF file" AGENTS.md "Kernel v2."
assert_eq "the file keeps its CRLF line endings" "$(wc -l < AGENTS.md | tr -d ' ')" "$(grep -c $'\r' AGENTS.md)"
kbranch keep-before-h

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

# ---- (i) the Profiles line: names only, prose and notes ignored ----
# Real lines carry notes: a name list ended by a sentence, names followed by a
# bracketed note, a trailing period. Only the listed names that have a profile
# folder count as adopted; a profile named later in prose is not adopted.
cp AGENTS.md "$FIX/agents.profiles"
cp docs/profiles/embedded/PROFILE.md "$FIX/embedded.profiles"
set_profiles() { sed -i.bak "s|^- Profiles:.*|- Profiles: $1|" AGENTS.md && rm -f AGENTS.md.bak; }
put docs/profiles/embedded/PROFILE.md "embedded edited by the project"
set_profiles "software (tools/ and tests/), scientific (units: SI). embedded deferred until a board exists."
run ./scripts/template-sync.sh --template "$TPL" --ref v2 --dry-run
assert_contains "bracketed notes and a closing sentence leave the names" "never applied): software scientific"
assert_not_contains "a profile named in prose is not adopted" "deferred"
assert_contains "the unadopted carried profile still syncs" "CONFLICT  docs/profiles/embedded/PROFILE.md"
assert_not_contains "the unadopted carried profile is not a DIFF" "DIFF      docs/profiles/embedded"
cp "$FIX/embedded.profiles" docs/profiles/embedded/PROFILE.md
set_profiles "software, embedded."
run ./scripts/template-sync.sh --template "$TPL" --ref v2 --dry-run
assert_contains "a trailing period does not drop the last name" "never applied): software embedded"
set_profiles "software, nosuchprofile"
run ./scripts/template-sync.sh --template "$TPL" --ref v2 --dry-run
assert_contains "a listed name without a profile folder is ignored" "never applied): software"
assert_not_contains "the unknown name is not printed" "nosuchprofile"
cp "$FIX/agents.profiles" AGENTS.md

# ---- (j) the synced set is printed for other scripts and matches upstream.md ----
run ./scripts/template-sync.sh --list-set
assert_rc "--list-set exits 0" 0
assert_contains "--list-set prints core dirs" "core scripts/"
assert_contains "--list-set prints the catalogs" "catalog docs/library/"
assert_contains "--list-set prints AGENTS.md" "agents AGENTS.md"
# The procedure's core file set (backticked paths in its "## Core file set"
# section) names exactly the paths the script syncs.
doc_set="$(awk '/^## Core file set/{f=1; next} f && /^## /{exit} f' "$T_ROOT/docs/procedures/upstream.md" \
  | grep -o '`[^`]*`' | tr -d '`' | grep -E '^[A-Za-z.][A-Za-z0-9._/-]*$' | sed 's#/$##' | sort -u)"
script_set="$("$T_ROOT/scripts/template-sync.sh" --list-set | awk '{print $2}' | sed 's#/$##' | sort -u)"
assert_eq "upstream.md core file set matches --list-set" "$script_set" "$doc_set"

# ---- (k) library and roster sync only where the project carries them ----
cd "$TPL" || exit 1
put docs/library/item.md "library item v3"
put docs/roster/agent.md "roster agent v3"
put scripts/stack-check.sh "echo template stub"
put docs/preferences/README.md "preferences readme v3"
put docs/preferences/ui.md "template row that must never reach a project"
commit_all v3 && git tag v3
cd "$PRJ" || exit 1
run ./scripts/template-sync.sh --template "$TPL" --ref v3 --dry-run
assert_contains "an uncarried library is announced" "docs/library/ is not carried by this project"
assert_not_contains "an uncarried library is not added" "ADD       docs/library/item.md"
assert_not_contains "stack-check.sh is project-owned, never synced" "scripts/stack-check.sh"
mkdir -p docs/library
run ./scripts/template-sync.sh --template "$TPL" --ref v3 --dry-run
assert_contains "a carried library syncs" "ADD       docs/library/item.md"
assert_contains "an uncarried roster is still announced" "docs/roster/ is not carried"
rmdir docs/library

# ---- (k2) docs/preferences: only README.md is template-owned ----
put docs/preferences/ui.md "project register"
put docs/preferences/film.md "project film register"
run ./scripts/template-sync.sh --template "$TPL" --ref v3 --dry-run
assert_contains "docs/preferences/README.md is synced" "ADD       docs/preferences/README.md"
assert_not_contains "another docs/preferences file in the template is not offered" "docs/preferences/ui.md"
assert_not_contains "a project register is never listed" "docs/preferences/film.md"
assert_eq "a same-named project register is untouched" "project register" "$(cat docs/preferences/ui.md)"
./scripts/template-sync.sh --list-set > "$FIX/set.out"
assert_file_has "the core set lists the preferences README" "$FIX/set.out" "core docs/preferences/README.md"
assert_file_lacks "the core set does not list the whole folder" "$FIX/set.out" "docs/preferences/ "
rm -rf docs/preferences

# ---- (l) --baseline replaces the recorded previous version ----
put docs/lessons/MAINTENANCE.log "template-sync: v1 2026-09-01"
run ./scripts/template-sync.sh --template "$TPL" --ref v2 --baseline v2 --dry-run
assert_contains "--baseline is named as the previous version" "previous version v2 from --baseline"
assert_not_contains "--baseline overrides the log" "previous sync v1"
run ./scripts/template-sync.sh --template "$TPL" --ref v2 --baseline no-such-ref --dry-run
assert_rc "an unknown baseline exits 1" 1
assert_contains "the unknown baseline is named" "baseline 'no-such-ref' not found"

# ---- (m) --latest and --latest-tag use version order, not date ----
cd "$TPL" || exit 1
git tag template-v0.10.0 v1
git tag template-v0.9.0 v3
cd "$PRJ" || exit 1
run ./scripts/template-sync.sh --template "$TPL" --latest-tag
assert_rc "--latest-tag exits 0" 0
assert_eq "--latest-tag picks 0.10.0 over 0.9.0" "template-v0.10.0" "$OUT"
run ./scripts/template-sync.sh --template "$TPL" --latest --dry-run
assert_contains "--latest syncs to the newest tag" "template $TPL at template-v0.10.0"
run ./scripts/template-sync.sh --template "$TPL" --latest --ref v2 --dry-run
assert_rc "--latest with --ref is a usage error" 2
run ./scripts/template-sync.sh --template "$FIX/project" --latest-tag
assert_rc "no template-v* tag exits 1" 1
cd "$TPL" && git tag -d template-v0.10.0 template-v0.9.0 >/dev/null && cd "$PRJ" || exit 1

# ---- (n) --suggest-baseline ranks template commits by identical files ----
run ./scripts/template-sync.sh --template "$TPL" --suggest-baseline
assert_rc "--suggest-baseline exits 0" 0
assert_contains "--suggest-baseline lists candidates" "suggested baselines by identical core-set files"
assert_not_contains "unrelated histories give no merge-base" "merge-base"
cands="$(printf '%s\n' "$OUT" | grep -E '^  [0-9a-f]{7,} [0-9]{4}-[0-9]{2}-[0-9]{2} .* - [0-9]+ of [0-9]+ identical$' || true)"
assert_eq "three candidates are listed" "3" "$(printf '%s\n' "$cands" | grep -c .)"
cand() { printf '%s\n' "$cands" | sed -n "$1p"; }
count_of() { printf '%s\n' "$1" | sed 's/.* - \([0-9]*\) of .*/\1/'; }
# v2 and v3 differ only in folders the project does not carry and in the
# project-owned stack-check.sh, so they tie; the tie goes to the newest (v3).
# v1 matches fewer files and comes last.
assert_eq "the newest of the tied commits comes first" "$(git -C "$TPL" rev-parse --short v3)" "$(cand 1 | awk '{print $1}')"
assert_eq "the older tied commit comes second" "$(git -C "$TPL" rev-parse --short v2)" "$(cand 2 | awk '{print $1}')"
assert_eq "the weakest match comes last" "$(git -C "$TPL" rev-parse --short v1)" "$(cand 3 | awk '{print $1}')"
assert_eq "tied commits have equal counts" "$(count_of "$(cand 1)")" "$(count_of "$(cand 2)")"
if (( $(count_of "$(cand 2)") > $(count_of "$(cand 3)") )); then t_ok "the ranking is by identical files"; else t_bad "the ranking is by identical files ($(cand 2) / $(cand 3))"; fi
assert_no_file "--suggest-baseline writes no sync output" .work/template-sync/scripts
SHARED="$FIX/shared"
git clone -q -c core.autocrlf=false "$TPL" "$SHARED" >/dev/null 2>&1
(cd "$SHARED" && git checkout -q v1 2>/dev/null && ./scripts/template-sync.sh --template "$TPL" --suggest-baseline > "$FIX/shared.out" 2>&1)
assert_file_has "shared history prints the merge-base" "$FIX/shared.out" "shared git history; merge-base"
assert_file_has "the merge-base is the commit the project came from" "$FIX/shared.out" "$(git -C "$TPL" log -1 --format=%h v1)"
# A real apply with --baseline (the shared clone has no sync record) on a
# working branch: untouched files update and the sync is recorded normally.
# The kernel already matches v2 here: a pending kernel change would (rightly) leave the sync unrecorded.
(cd "$SHARED" && git checkout -q -b sync-base && sed -i 's/Kernel v1\./Kernel v2./' AGENTS.md && ./scripts/kernel-hash.sh --update >/dev/null   && git add -A -- . ":!.work" && git -c user.name=t -c user.email=t@example.invalid commit -q -m "kernel at v2" && ./scripts/template-sync.sh --template "$TPL" --ref v2 --baseline v1 > "$FIX/shared.apply" 2>&1)
assert_file_has "a real apply names the baseline" "$FIX/shared.apply" "previous version v1 from --baseline"
assert_file_has "an untouched file is updated against the baseline" "$SHARED/scripts/a.sh" "echo a v2"
assert_file_has "the sync is recorded normally after --baseline" "$SHARED/docs/lessons/MAINTENANCE.log" "template-sync: v2 2026-10-09"

# ---- (o) --status: the Template line names the last recorded sync ----
run ./scripts/template-sync.sh --status
assert_rc "--status in template mode exits 0" 0
assert_contains "template mode has nothing to check" "template mode"
touch .start-done
sed -i.bak "s|^- Template:.*|- Template: $TPL v1|" AGENTS.md && rm -f AGENTS.md.bak
run ./scripts/template-sync.sh --status
assert_rc "a matching Template line passes" 0
assert_contains "--status names the template" "status: template $TPL at v1"
put docs/lessons/MAINTENANCE.log "template-sync: v2 2026-10-09"
run ./scripts/template-sync.sh --status
assert_rc "a Template line behind the log fails" 1
assert_contains "the fix is named" "set '- Template: $TPL v2'"
sed -i.bak "s|^- Template:.*|- Template: $TPL v2 (synced by hand)|" AGENTS.md && rm -f AGENTS.md.bak
run ./scripts/template-sync.sh --status
assert_rc "prose after the ref fails" 1
assert_contains "the malformed line is explained" "malformed Template line"
sed -i.bak '/^- Template:/d' AGENTS.md && rm -f AGENTS.md.bak
run ./scripts/template-sync.sh --status
assert_rc "a missing Template line fails" 1
rm -f docs/lessons/MAINTENANCE.log
sed -i.bak "s|^- Profiles:|- Template: $TPL v2\n- Profiles:|" AGENTS.md && rm -f AGENTS.md.bak
run ./scripts/template-sync.sh --status
assert_rc "no recorded sync fails" 1
assert_contains "the missing record is explained" "no sync recorded"
rm -f .start-done
cp "$FIX/agents.profiles" AGENTS.md

# ---- (p) skills cap after a sync (kernel rule 10, scripts/lessons.sh skills) ----
# The template-v0.4.0 case: v2 adds the dream core skill to a project whose
# two project slots are full. The sync applies it, the core skill takes no
# project slot, and the cap result is reported; a third project skill is a
# breach and an action item.
TPL3="$FIX/template3"
PRJ3="$FIX/project3"
put_skill() { local d; for d in .claude/skills .agents/skills; do put "$d/$1/SKILL.md" "# $1"; done; }
mkdir -p "$TPL3" && cd "$TPL3" || exit 1
git init -q . >/dev/null 2>&1
git config user.email t@example.invalid; git config user.name t; git config core.autocrlf false
mkdir -p scripts
cp "$T_ROOT/scripts/kernel-hash.sh" "$T_ROOT/scripts/template-sync.sh" "$T_ROOT/scripts/lessons.sh" "$T_ROOT/scripts/profiles.sh" scripts/
put_agents "Kernel v1." "rule index v1"
sed -i.bak "s|^- Template:.*|- Template: $TPL3 v1|" AGENTS.md && rm -f AGENTS.md.bak
for s in adr maintain retro ship start template-update; do put_skill "$s"; done
commit_all v1 && git tag v1
put_skill dream
commit_all v2 && git tag v2
mkdir -p "$PRJ3" && cd "$PRJ3" || exit 1
git init -q . >/dev/null 2>&1
git config user.email p@example.invalid; git config user.name p; git config core.autocrlf false
git -C "$TPL3" archive --format=tar v1 | tar -x -C "$PRJ3"
put_skill own1
put_skill own2
put docs/lessons/MAINTENANCE.log "template-sync: v1 2026-09-01"
chmod +x scripts/*.sh
./scripts/kernel-hash.sh --update >/dev/null
proj_commit "project at v1"
git checkout -q -b sync-skills
run ./scripts/lessons.sh skills
assert_rc "before the sync the project is at its skills cap" 0
run ./scripts/template-sync.sh --template "$TPL3" --ref v2
assert_contains "the new core skill is applied" "ADD       .claude/skills/dream/SKILL.md"
assert_contains "the skills count is reported after the sync" "template-sync: skills: 9 (cap 9 = 7 core + 2 project"
assert_not_contains "a new core skill is no action item" "ACTION: skills cap"
assert_rc "a sync that adds a core skill to a full project exits 0" 0
proj_commit "sync to v2"
put_skill own3
proj_commit "a third project skill"
run ./scripts/template-sync.sh --template "$TPL3" --ref v2
assert_contains "a project over its cap gets an action item" "ACTION: skills cap: .claude/skills has 10 skills; the cap is 9"
assert_rc "a sync that leaves the project over its skills cap exits 1" 1
# A lessons.sh without the skills command (an older release) exits 2 with its
# usage; that is an unchecked cap, not a breach with no reason.
cd "$TPL3" || exit 1
put scripts/lessons.sh '#!/usr/bin/env bash
echo "usage: lessons.sh check" >&2
exit 2'
commit_all v3 && git tag v3
cd "$PRJ3" || exit 1
proj_commit "the over-cap sync"
run ./scripts/template-sync.sh --template "$TPL3" --ref v3
assert_not_contains "a lessons.sh without the skills command is no cap breach" "ACTION: skills cap"
assert_contains "a cap that could not be counted is reported" "template-sync: skills cap not checked: scripts/lessons.sh skills exited 2"
assert_rc "a sync whose cap could not be counted exits 1" 1
assert_not_contains "a lessons.sh with no CORE_SKILLS line retires nothing" "RETIRED CORE SKILL"
cd "$PRJ" || exit 1

# ---- (p2) a core skill a later release retires (ADR 0012 amendment) ----
# v2 drops template-update from CORE_SKILLS and removes its folders; the
# project keeps its folder, which now counts as a project skill and is named.
TPL4="$FIX/template4"
PRJ4="$FIX/project4"
mkdir -p "$TPL4" && cd "$TPL4" || exit 1
git init -q . >/dev/null 2>&1
git config user.email t@example.invalid; git config user.name t; git config core.autocrlf false
mkdir -p scripts
cp "$T_ROOT/scripts/kernel-hash.sh" "$T_ROOT/scripts/template-sync.sh" "$T_ROOT/scripts/lessons.sh" "$T_ROOT/scripts/profiles.sh" scripts/
put_agents "Kernel v1." "rule index v1"
sed -i.bak "s|^- Template:.*|- Template: $TPL4 v1|" AGENTS.md && rm -f AGENTS.md.bak
for s in adr dream maintain retro ship start template-update; do put_skill "$s"; done
commit_all v1 && git tag v1
sed -i.bak 's/^CORE_SKILLS=(.*)$/CORE_SKILLS=(adr dream maintain retro ship start)/' scripts/lessons.sh && rm -f scripts/lessons.sh.bak
git rm -q -r .claude/skills/template-update .agents/skills/template-update
commit_all v2 && git tag v2
mkdir -p "$PRJ4" && cd "$PRJ4" || exit 1
git init -q . >/dev/null 2>&1
git config user.email p@example.invalid; git config user.name p; git config core.autocrlf false
git -C "$TPL4" archive --format=tar v1 | tar -x -C "$PRJ4"
put_skill own1
put docs/lessons/MAINTENANCE.log "template-sync: v1 2026-09-01"
chmod +x scripts/*.sh
./scripts/kernel-hash.sh --update >/dev/null
proj_commit "project at v1"
git checkout -q -b sync-retired
run ./scripts/template-sync.sh --template "$TPL4" --ref v2 --dry-run
assert_contains "a dry run names the retired core skill the project keeps" "RETIRED CORE SKILL: template-update  (.claude/skills/template-update is kept but no longer a template core skill; it now counts as a project skill (ADR 0012)"
assert_contains "its template files are removed upstream, never deleted" "REMOVED   .claude/skills/template-update/SKILL.md"
assert_not_contains "a skill still in the core list is not retired" "RETIRED CORE SKILL: start"
run ./scripts/template-sync.sh --template "$TPL4" --ref v2
assert_contains "a real run names the retired core skill" "RETIRED CORE SKILL: template-update"
assert_contains "the retired skill counts as a project skill" "template-sync: skills: 8 (cap 8 = 6 core + 2 project"
assert_rc "a retired skill within the project slots exits 0" 0
assert_file_has "the retired skill folder is kept" .claude/skills/template-update/SKILL.md "# template-update"
proj_commit "sync to v2"
put_skill own2
proj_commit "a second project skill"
run ./scripts/template-sync.sh --template "$TPL4" --ref v2 --baseline v1
assert_contains "a full project with a retired skill is named and over its cap" "RETIRED CORE SKILL: template-update"
assert_contains "the cap breach is an action item" "ACTION: skills cap: .claude/skills has 9 skills; the cap is 8"
assert_rc "a retired skill that takes the project over its cap exits 1" 1
proj_commit "the over-cap sync"
# The project archived the retired skill: nothing to name. The project's own
# lessons.sh is v2's now and v2 is the baseline, so only the old list says it.
mkdir -p "$FIX/archive4/claude" "$FIX/archive4/agents"
mv .claude/skills/template-update "$FIX/archive4/claude/"
mv .agents/skills/template-update "$FIX/archive4/agents/"
proj_commit "archive the retired skill"
run ./scripts/template-sync.sh --template "$TPL4" --ref v2 --baseline v1 --dry-run
assert_not_contains "an archived retired skill is not named" "RETIRED CORE SKILL"
cd "$PRJ" || exit 1

# ---- (q) installed items: the ledger docs/installed.list ----
# Library, roster and profile items a project copied into its own folders sync
# from their template source under the same three-way rules, and the catalog
# folder itself need not be carried.
TPL5="$FIX/template5"
PRJ5="$FIX/project5"
mkdir -p "$TPL5" && cd "$TPL5" || exit 1
git init -q . >/dev/null 2>&1
git config user.email t@example.invalid; git config user.name t; git config core.autocrlf false
mkdir -p scripts
cp "$T_ROOT/scripts/kernel-hash.sh" "$T_ROOT/scripts/template-sync.sh" "$T_ROOT/scripts/profiles.sh" scripts/
put_agents "Kernel v1." "rule index v1"
sed -i.bak "s|^- Template:.*|- Template: $TPL5 v1|" AGENTS.md && rm -f AGENTS.md.bak
put docs/library/agents/x.md "x v1"
put docs/library/skills/s/SKILL.md "s v1"
put docs/roster/agents/r.md "r v1"
put docs/library/agents/gone.md "gone v1"
put docs/profiles/software/agents/p.md "p v1"
put .claude/agents/core.md "core v1"
commit_all v1 && git tag v1
put docs/library/agents/x.md "x v2"
put docs/library/skills/s/SKILL.md "s v2"
put docs/roster/agents/r.md "r v2"
git rm -q docs/library/agents/gone.md
put docs/library/agents/new.md "new v2"
put docs/profiles/software/agents/p.md "p v2"
commit_all v2 && git tag v2
mkdir -p "$PRJ5" && cd "$PRJ5" || exit 1
git init -q . >/dev/null 2>&1
git config user.email p@example.invalid; git config user.name p; git config core.autocrlf false
git -C "$TPL5" archive --format=tar v1 | tar -x -C "$PRJ5"
mv docs/library "$FIX/library5-not-carried"
mv docs/roster "$FIX/roster5-not-carried"
put .claude/agents/x.md "x v1"
put .claude/skills/s/SKILL.md "s v1 edited by the project"
put .claude/agents/r.md "r v2"
put .claude/agents/gone.md "gone v1"
put .codex/agents/p.md "p v1"
printf '%s\r\n' '# installed items: <project path> <template path>' '' \
  '.claude/agents/x.md docs/library/agents/x.md' \
  '.claude/skills/s/SKILL.md   docs/library/skills/s/SKILL.md  # edited here' \
  '.claude/agents/r.md docs/roster/agents/r.md' \
  '.claude/agents/gone.md docs/library/agents/gone.md' \
  '.claude/agents/new.md docs/library/agents/new.md' \
  '.codex/agents/p.md docs/profiles/software/agents/p.md' > docs/installed.list
put docs/lessons/MAINTENANCE.log "template-sync: v1 2026-09-01"
chmod +x scripts/*.sh
./scripts/kernel-hash.sh --update >/dev/null
proj_commit "project at v1"
git checkout -q -b sync-installed
run ./scripts/template-sync.sh --template "$TPL5" --ref v2 --dry-run
assert_contains "the ledger is read (CRLF, comments, blank lines)" "template-sync: 6 installed item(s) in docs/installed.list"
assert_contains "an untouched installed copy is an update from its source" "UPDATE    .claude/agents/x.md  (project copy untouched since v1; template changed) [installed from docs/library/agents/x.md]"
assert_contains "an edited installed copy is a conflict" "CONFLICT  .claude/skills/s/SKILL.md  (project edited and template differs; merge by hand, then rerun with --resolved) [installed from docs/library/skills/s/SKILL.md]"
assert_contains "a source removed upstream is listed, never deleted" "REMOVED   .claude/agents/gone.md  (no longer in the template; review, then archive if unused) [installed from docs/library/agents/gone.md]"
assert_contains "a source new in the template is added at the installed path" "ADD       .claude/agents/new.md  (new in the template) [installed from docs/library/agents/new.md]"
assert_contains "a profile item installed by start syncs too" "UPDATE    .codex/agents/p.md"
assert_not_contains "a copy equal to the new source is unchanged" ".claude/agents/r.md"
assert_contains "the conflict diff is written for the installed path" "=== diff: .claude/skills/s/SKILL.md (project -> template) ==="
assert_not_contains "the uncarried catalog itself is not synced" "docs/library/agents/x.md  ("
assert_rc "a dry run with a ledger conflict exits 1" 1
assert_file_has "a dry run applies nothing" .claude/agents/x.md "x v1"
run ./scripts/template-sync.sh --template "$TPL5" --ref v2
assert_file_has "the update is applied from the source" .claude/agents/x.md "x v2"
assert_file_has "the added item lands at its installed path" .claude/agents/new.md "new v2"
assert_file_has "the edited copy is kept" .claude/skills/s/SKILL.md "s v1 edited by the project"
assert_file_has "the removed item is kept" .claude/agents/gone.md "gone v1"
assert_no_file "the uncarried catalog is not created" docs/library
assert_contains "a ledger conflict leaves the sync unrecorded" "sync NOT recorded"
assert_rc "a real run with a ledger conflict exits 1" 1
# Malformed lines stop the run (exit 2) before anything is written; forms
# refused (L012), each alone in the ledger.
cp docs/installed.list "$FIX/ledger5"
bad_ledger() { # name line message
  printf '%s\n' "$2" > docs/installed.list
  run ./scripts/template-sync.sh --template "$TPL5" --ref v2 --dry-run
  assert_rc "ledger refuses $1" 2
  assert_contains "ledger names the line for $1" "template-sync: docs/installed.list:1: $3"
}
bad_ledger "one field" ".claude/agents/x.md" "want exactly"
bad_ledger "three fields" ".claude/agents/x.md docs/library/agents/x.md extra" "want exactly"
bad_ledger "an absolute path" "/etc/x docs/library/agents/x.md" "paths must be relative"
bad_ledger "a parent part" ".claude/../x.md docs/library/agents/x.md" "paths must be relative"
bad_ledger "a backslash path" '.claude\agents\x.md docs/library/agents/x.md' "paths must be relative"
bad_ledger "a source outside the catalogs and profiles" ".claude/agents/x.md scripts/a.sh" "the template path must be under"
bad_ledger "a project path inside a catalog" "docs/library/agents/x.md docs/library/agents/x.md" "the project path must be outside"
bad_ledger "AGENTS.md as the project path" "AGENTS.md docs/library/agents/x.md" "the project path is a file template-sync never applies"
bad_ledger "a lessons header file" "docs/lessons/INDEX.md docs/library/agents/x.md" "the project path is a file template-sync never applies"
bad_ledger "a core file" "CLAUDE.md docs/library/agents/x.md" "the project path is a template core file"
printf '%s\n' ".claude/agents/x.md docs/library/agents/x.md" ".claude/agents/x.md docs/roster/agents/r.md" > docs/installed.list
run ./scripts/template-sync.sh --template "$TPL5" --ref v2 --dry-run
assert_rc "ledger refuses a duplicate project path" 2
assert_contains "the duplicate is named on its line" "docs/installed.list:2: the project path is listed twice"
printf '%s' ".claude/agents/x.md docs/library/agents/x.md" > docs/installed.list
run ./scripts/template-sync.sh --template "$TPL5" --ref v2 --dry-run
assert_contains "a last line without a newline is read" "template-sync: 1 installed item(s)"
cp "$FIX/ledger5" docs/installed.list
cd "$PRJ" || exit 1

# ---- (r) a real run against a published tag: bare repo, URL transport ----
# The template is published as a bare repository reached by a file:// URL with
# annotated template-v* tags (what template-release.sh --tag creates), so the
# run takes the clone, ls-remote and tag-resolution paths a GitHub URL takes,
# without the network.
PUBDIR="$FIX/published.git"
# An annotated tag needs a committer identity; the bare repository has none configured.
git clone -q --bare "$TPL" "$PUBDIR" >/dev/null 2>&1
git -C "$PUBDIR" -c user.email=p@example.invalid -c user.name=p tag -a -m "release 0.2.0" template-v0.2.0 v1
git -C "$PUBDIR" -c user.email=p@example.invalid -c user.name=p tag -a -m "release 0.3.0" template-v0.3.0 v2
git -C "$PUBDIR" -c user.email=p@example.invalid -c user.name=p tag -a -m "release 0.10.0" template-v0.10.0 v2
# Git for Windows cannot open an MSYS path (/tmp/...) in a file:// URL; cygpath -m
# gives the C:/... form it can. Without cygpath the POSIX path is already right.
if command -v cygpath >/dev/null 2>&1; then
  PUB="file:///$(cygpath -m "$PUBDIR")"
else
  PUB="file://$PUBDIR"
fi
PRJ4="$FIX/project4"
mkdir -p "$PRJ4" && cd "$PRJ4" || exit 1
git init -q . >/dev/null 2>&1
git config user.email p@example.invalid; git config user.name p; git config core.autocrlf false
git -C "$TPL" archive --format=tar v1 | tar -x -C "$PRJ4"
sed -i.bak "s|^- Template:.*|- Template: $PUB template-v0.2.0|" AGENTS.md && rm -f AGENTS.md.bak
put docs/lessons/MAINTENANCE.log "template-sync: template-v0.2.0 2026-09-01"
chmod +x scripts/*.sh
# .start-done puts --status in project mode; without it the template-mode
# short-circuit would make the status assertions below check nothing.
touch .start-done
sed -i 's/Kernel v1\./Kernel v2./' AGENTS.md
./scripts/kernel-hash.sh --update >/dev/null
proj_commit "project at template-v0.2.0"
git checkout -q -b sync-real
run ./scripts/template-sync.sh --latest-tag
assert_eq "--latest-tag reads the published URL from AGENTS.md" "template-v0.10.0" "$OUT"
run ./scripts/template-sync.sh --status
assert_rc "--status is clean before the sync" 0
assert_contains "--status names the published URL and the recorded tag" "status: template $PUB at template-v0.2.0 (template-v0.2.0 2026-09-01)"
run ./scripts/template-sync.sh --latest
assert_contains "the run names the URL and the newest published tag" "template $PUB at template-v0.10.0"
assert_contains "the changed file is applied from the published tag" "UPDATE    scripts/a.sh"
assert_file_has "the applied file holds the published content" scripts/a.sh "echo a v2"
assert_file_has "the sync is recorded with the tag it reached" docs/lessons/MAINTENANCE.log "template-sync: template-v0.10.0 2026-10-09"
assert_file_has "the earlier record is kept" docs/lessons/MAINTENANCE.log "template-sync: template-v0.2.0 2026-09-01"
cd "$PRJ" || exit 1

# ---- usage ----
run ./scripts/template-sync.sh --bogus
assert_rc "an unknown flag is a usage error" 2
run ./scripts/template-sync.sh --template "$FIX/does-not-exist" --dry-run
assert_rc "an unreachable template fails" 1
run ./scripts/template-sync.sh --template "$TPL" --ref no-such-ref --dry-run
assert_rc "an unknown ref fails" 1

t_finish
