#!/usr/bin/env bash
# template-sync.sh - bring a project's template-owned files up to date with the
# template without clobbering what the project changed (docs/procedures/upstream.md).
# Usage: scripts/template-sync.sh [--template <git url or path>]
#          [--ref <tag> | --latest] [--baseline <ref>] [--dry-run] [--resolved]
#          [--accept-kernel]
#        scripts/template-sync.sh --suggest-baseline | --latest-tag | --status | --list-set
#        scripts/template-sync.sh --synced-commits <git range>
#        scripts/template-sync.sh --help | -h
#
# --template is optional: when omitted it is read from the project's AGENTS.md
# Project decisions line "- Template: <url> <tag>" (the url, and the tag as the
# default --ref). With neither, the script stops with exit 2.
# --latest syncs to the newest template-v* tag by version order (not with
# --ref). --baseline <ref> is the previous version instead of the last
# MAINTENANCE.log line, for a project whose record is missing or wrong.
# Read-only modes: --suggest-baseline (the merge-base when the project shares
# git history with the template, then the three template commits whose
# core-set files match the project's most often); --latest-tag (the newest
# template-v* tag via ls-remote, no clone); --status (offline: exit 1 unless
# the Template line is exactly "- Template: <url> <ref>" naming the last
# recorded sync; exit 0 in template mode); --synced-commits <range> (the
# commits of a range in this template repository that change the synced set,
# as "<sha> <kind>" with kind agents, core, header or catalog, for fleet.sh
# and template-release.sh); --list-set (the synced set as
# "<group> <path>" lines for other scripts).
#
# Guard: a real apply refuses (exit 2) unless "git status --porcelain" is empty
# (ignoring .work/template-sync/, which this script writes) and the current
# branch is not main or master. --dry-run is always allowed.
#
# Three-way comparison per file in the core set:
#   NEW  = the template at --ref (default: the template's HEAD)
#   OLD  = the template at the ref this project last synced to
#   PROJ = the project's copy
# "Previous version" detection: a real sync with no conflicts left appends one
# line to docs/lessons/MAINTENANCE.log of the form
#   template-sync: <ref> <date>
# The script reads the last such line and checks that ref out of the same
# template clone as OLD. With no such line, or a ref the template does not have,
# there is no OLD: a file is then applied only when missing from the project,
# and any differing file is listed for the human. A run that still has
# conflicts does not record the sync, so those conflicts are reported again on
# every run until the project copy is merged by hand.
#
# Core set (exactly): CLAUDE.md, CONTRIBUTING.md, manifest.md, cliff.toml,
# docs/BLUEPRINT.md, docs/DEFECT_MEMORY.md, docs/preferences/README.md,
# docs/procedures/, docs/rules/, docs/profiles/, scripts/, tests/template/,
# .claude/, .agents/, .codex/, .github/workflows/ci.yml, and the format
# headers (first 12 lines only) of docs/lessons/INDEX.md, PENDING.md,
# QUARANTINE.md and UPSTREAM.md; the rest of those four files is project
# data and is never touched. Catalogs, synced under the same rules only
# where the project carries the folder:
# docs/library/ and docs/roster/. Never touched at all: the project's own
# truth files, BACKLOG.md, docs/decisions/, the other docs/preferences/
# registers, .work/, the kernel hash, any *.local.* file, and
# scripts/stack-check.sh (the project's own stack steps).
#
# Outcomes (compared without regard to CR line endings):
#   PROJ == NEW                              unchanged
#   NEW == OLD                               project-owned, nothing to bring
#   PROJ == OLD, NEW differs                 UPDATE: applied (project never touched it)
#   PROJ differs from OLD, NEW differs       CONFLICT: listed as a diff, never applied
#   missing in project, absent from OLD      ADD: applied
#   missing in project, present in OLD       the project deleted it: listed, not restored
#   present in project, absent from NEW      removed upstream: listed, never deleted here
# Installed items: docs/installed.list (project-owned, never synced) lists the
# library, roster and profile files the project copied into its own folders,
# one "<project path> <template path>" line each (# comments allowed). Each
# entry is compared under the rules above with the template path as its NEW
# and OLD side, whether or not the project carries the catalog; its lines say
# "[installed from <template path>]". A malformed line exits 2 before anything
# is written.
#
# Retired core skills: a skill on the earlier CORE_SKILLS list (the previous
# version's scripts/lessons.sh and the project's own, read as text) that the
# new list drops, while .claude/skills/<name> stays in the project, prints
# "RETIRED CORE SKILL: <name>"; it now counts as a project skill (ADR 0012).
#
# Never applied, always reported as DIFF (the unified diff is written to
# .work/template-sync/<path>.diff): .github/workflows/ci.yml and every file of an
# adopted profile (docs/profiles/<name>/ for the names on the AGENTS.md
# "- Profiles:" line, parsed by scripts/profiles.sh). A DIFF is information, not a conflict: it does not change
# the exit code. A profile the project does not carry is skipped.
#
# AGENTS.md is never applied, except the kernel under --accept-kernel (below).
# The KERNEL block (KERNEL:BEGIN through KERNEL:END)
# and the "## Rules index" section of both versions are compared; when they
# differ the diffs are written to .work/template-sync/AGENTS.kernel.diff and
# AGENTS.rules-index.diff, a kernel difference prints "KERNEL CHANGE: needs owner
# approval and scripts/kernel-hash.sh --update", and the project's .kernel.hash
# is never touched. A kernel difference does not block the rest: every other
# file is applied, but the sync is NOT recorded in MAINTENANCE.log (exit 1), so
# the next run keeps the old ref as its base and still sees the kernel pending.
# --accept-kernel (a real apply only; the owner's explicit approval, ADR 0020)
# copies the template kernel block verbatim into AGENTS.md (the file's line
# endings kept) and runs scripts/kernel-hash.sh --update, but only when the
# project's kernel equals the kernel of the ref last recorded in MAINTENANCE.log
# (CRs ignored): a customized kernel, an unrecorded sync or a recorded ref the
# template lacks stops with KERNEL CHANGE and the reason. After applying, the script re-runs
# scripts/kernel-hash.sh --verify, then scripts/lessons.sh skills: a project
# over its kernel rule 10 skills cap gets an "ACTION: skills cap" line, and a
# cap that could not be counted is reported as not checked.
#
# Exit: 0 clean or applied, 1 conflicts or a kernel change pending (or a failed
# clone, ref or kernel verification, or the skills cap exceeded or not counted
# after the sync), 2 usage or guard failure or a malformed docs/installed.list.
#
# Test hook: TEMPLATE_SYNC_TODAY=YYYY-MM-DD overrides today's date.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG="docs/lessons/MAINTENANCE.log"
OUTDIR=".work/template-sync"
CORE_DIRS=(scripts docs/procedures docs/rules docs/profiles tests/template .claude .agents .codex)
CORE_FILES=(CLAUDE.md CONTRIBUTING.md manifest.md cliff.toml docs/BLUEPRINT.md docs/DEFECT_MEMORY.md docs/preferences/README.md .github/workflows/ci.yml)
HEADER_FILES=(docs/lessons/INDEX.md docs/lessons/PENDING.md docs/lessons/QUARANTINE.md docs/lessons/UPSTREAM.md)
HEADER_LINES=12
CATALOG_DIRS=(docs/library docs/roster)
EXCLUDE_RE='(^|/)[^/]*\.local\.[^/]*$'
# Project-owned even though it sits under scripts/: the project's own stack
# steps, which ./scripts/check.sh runs when present. Never synced.
PROJECT_OWNED_RE='^scripts/stack-check\.sh$'

# The synced set, one "<group> <path>" line each (a directory ends in "/"):
# core (applied under the three-way rules), header (only the first
# HEADER_LINES lines sync; the rest is project data), catalog (synced only
# where the project carries the folder) and agents (AGENTS.md: kernel block
# and rules index compared, never applied). scripts/template-release.sh,
# scripts/fleet.sh and scripts/session-context.sh get the set through
# --synced-commits (below) instead of keeping their own copy.
list_set() {
  local p
  for p in "${CORE_FILES[@]}"; do echo "core $p"; done
  for p in "${CORE_DIRS[@]}"; do echo "core $p/"; done
  for p in "${HEADER_FILES[@]}"; do echo "header $p"; done
  for p in "${CATALOG_DIRS[@]}"; do echo "catalog $p/"; done
  echo "agents AGENTS.md"
}

usage_text() {
  echo "usage: scripts/template-sync.sh [--template <git url or path>] [--ref <tag> | --latest]"
  echo "                                 [--baseline <ref>] [--dry-run] [--resolved] [--accept-kernel]"
  echo "       scripts/template-sync.sh [--template <url>] --suggest-baseline | --latest-tag"
  echo "       scripts/template-sync.sh --status | --list-set | --help"
  echo "       scripts/template-sync.sh --synced-commits <git range>"
  echo "  --template defaults to the '- Template: <url> <tag>' line of AGENTS.md (tag = default --ref)."
  echo "  A real apply needs a clean working tree and a branch other than main or master."
  echo "  --latest: sync to the newest template-v* tag (version order); not with --ref"
  echo "  --baseline <ref>: compare against this template version instead of the last recorded sync"
  echo "  --resolved: the conflicts reported by the previous run were merged by hand; record the sync with them"
  echo "  --accept-kernel: apply the template kernel verbatim and run kernel-hash.sh --update, only when the project kernel equals the last recorded release's"
  echo "  --suggest-baseline: candidate starting versions (merge-base, then best file matches); read-only"
  echo "  --latest-tag: print the newest template-v* tag at the template URL (ls-remote, no clone)"
  echo "  --status: offline check that the Template line names the last recorded sync"
  echo "  --list-set: print the synced set as '<group> <path>' lines"
  echo "  --synced-commits <range>: '<sha> <kind>' per commit of a git range here that changes what projects receive; kind is agents, core, header or catalog (offline)"
  echo "  exit: 0 clean or applied, 1 conflicts, kernel change pending, skills cap exceeded or not counted, 2 usage, guard failure or a malformed docs/installed.list"
}
usage() { usage_text >&2; exit 2; }

# The "- Profiles:" line is parsed by scripts/profiles.sh, the one parser
# lessons.sh shares, so both adopt the same set. The project's copy runs when
# present; a project that bootstrapped only this script uses the template's
# copy at the new ref. A name counts only when the template or the project has
# its profile folder.
adopted_profiles() {
  [[ -f AGENTS.md ]] || return 0
  local parser="scripts/profiles.sh" names item
  [[ -f "$parser" ]] || parser="$WORK/new/scripts/profiles.sh"
  if [[ ! -f "$parser" ]]; then
    echo "template-sync: neither the project nor the template has scripts/profiles.sh; cannot read the Profiles line" >&2
    return 1
  fi
  names="$(bash "$parser" adopted AGENTS.md)" || return 1
  while IFS= read -r item; do
    [[ -n "$item" ]] || continue
    if [[ -d "$WORK/new/docs/profiles/$item" || -d "docs/profiles/$item" ]]; then echo "$item"; fi
  done <<< "$names"
}

# "- Template: <url> <tag>" from AGENTS.md; prints "<url> <tag>" (tag may be empty).
agents_template() {
  [[ -f AGENTS.md ]] || return 0
  local line
  line="$(grep -m1 -E '^- Template:' AGENTS.md 2>/dev/null | tr -d '\r' || true)"
  line="${line#- Template:}"
  line="${line//\`/ }"
  [[ "$line" == *"{{"* ]] && return 0
  # shellcheck disable=SC2086
  set -- $line
  [[ -n "${1:-}" ]] && echo "$1 ${2:-}"
  return 0
}

is_header_file() {
  local h
  for h in "${HEADER_FILES[@]}"; do [[ "$1" == "$h" ]] && return 0; done
  return 1
}

# The adopted profile a path belongs to, when it is one.
adopted_profile_of() {
  local p="$1" a
  for a in $ADOPTED; do
    [[ "$p" == docs/profiles/"$a"/* ]] && return 0
  done
  return 1
}

never_apply() {
  [[ "$1" == ".github/workflows/ci.yml" ]] && return 0
  adopted_profile_of "$1"
}

# A profile directory the project does not carry (and does not adopt) is not synced.
uncarried_profile() {
  local p="$1" rest name
  [[ "$p" == docs/profiles/*/* ]] || return 1
  rest="${p#docs/profiles/}"; name="${rest%%/*}"
  [[ -d "docs/profiles/$name" ]] && return 1
  return 0
}

# Relative core-set paths present under a directory.
list_core() {
  local base="$1" d p
  for d in "${CORE_DIRS[@]}" "${CATALOG_DIRS[@]}"; do
    if [[ -d "$base/$d" ]]; then (cd "$base" && find "$d" -type f); fi
  done
  for p in "${CORE_FILES[@]}" "${HEADER_FILES[@]}"; do
    if [[ -f "$base/$p" ]]; then echo "$p"; fi
  done
}

# Equal ignoring CR (the repo is LF, but a Windows checkout may not be).
same() { cmp -s "$1" "$2" || cmp -s <(tr -d '\r' < "$1") <(tr -d '\r' < "$2"); }

# view SIDE SRC PATH: the file to compare. Whole file, except that the lessons
# files compare their format header only.
view() {
  if is_header_file "$3"; then
    mkdir -p "$WORK/v/$1/$(dirname "$3")"
    head -n "$HEADER_LINES" "$2" > "$WORK/v/$1/$3"
    echo "$WORK/v/$1/$3"
  else
    echo "$2"
  fi
}

resolve_ref() { # in the template clone; prints a commit id or nothing
  git -C "$TPL" rev-parse --verify -q "$1^{commit}" 2>/dev/null \
    || git -C "$TPL" rev-parse --verify -q "origin/$1^{commit}" 2>/dev/null || true
}

export_tree() { # commit dest
  mkdir -p "$2"
  git -C "$TPL" archive --format=tar "$1" | tar -x -C "$2"
}

# write_diff PATH FROM TO: unified diff into .work/template-sync/PATH.diff
write_diff() {
  mkdir -p "$(dirname "$OUTDIR/$1.diff")"
  diff -u --label "project/$1" --label "template/$1" "$2" "$3" > "$OUTDIR/$1.diff" || true
}

# core_skills_of LESSONS_SH: the names on its "CORE_SKILLS=(...)" line, one per
# line; read as text, never run, since the file may come from the template.
core_skills_of() {
  [[ -f "$1" ]] || return 0
  awk '{ sub(/\r$/, "") } /^CORE_SKILLS=\(.*\)[ \t]*$/ { sub(/^CORE_SKILLS=\(/, ""); sub(/\)[ \t]*$/, ""); print; exit }' "$1" \
    | tr -s ' \t' '\n\n' | grep -E '^[a-z0-9][a-z0-9-]*$' || true
}

kernel_block() { awk '/<!-- KERNEL:BEGIN -->/{f=1} f{print} /<!-- KERNEL:END -->/{exit}' "$1" | tr -d '\r'; }
rules_index() { awk '/^## Rules index/{f=1; print; next} f && /^## /{exit} f{print}' "$1" | tr -d '\r'; }

# A catalog path (docs/library/, docs/roster/) syncs only where the project
# carries that folder.
uncarried_catalog() {
  local d
  for d in "${CATALOG_DIRS[@]}"; do
    if [[ "$1" == "$d"/* ]]; then
      [[ -d "$d" ]] && return 1
      return 0
    fi
  done
  return 1
}

# The ledger of library, roster and profile items the project copied into its
# own folders (docs/procedures/upstream.md, "Installed items"): one
# "<project path> <template path>" line per file, # comments and blank lines
# ignored. Read into LED_DST / LED_SRC (indexed arrays: bash 3.2 has no
# associative ones). A malformed line stops the run: guessing what an entry
# meant could overwrite a file the project owns.
LEDGER="docs/installed.list"
LED_DST=()
LED_SRC=()

ledger_path_ok() { # a relative path with no empty, "." or ".." part
  [[ "$1" =~ ^[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)*$ ]] || return 1
  [[ "/$1/" != */./* && "/$1/" != */../* ]]
}

read_ledger() {
  LED_DST=(); LED_SRC=()
  [[ -f "$LEDGER" ]] || return 0
  local line n=0 dst src extra i bad
  while IFS= read -r line || [[ -n "$line" ]]; do
    n=$((n + 1))
    line="${line%$'\r'}"
    line="${line%%#*}"
    [[ -n "${line//[[:space:]]/}" ]] || continue
    dst=""; src=""; extra=""
    read -r dst src extra <<< "$line"
    bad=""
    if [[ -z "$src" || -n "$extra" ]]; then bad="want exactly '<project path> <template path>'"
    elif ! ledger_path_ok "$dst" || ! ledger_path_ok "$src"; then bad="paths must be relative, with no empty, '.' or '..' part"
    elif [[ "$src" != docs/library/* && "$src" != docs/roster/* && "$src" != docs/profiles/* ]]; then bad="the template path must be under docs/library/, docs/roster/ or docs/profiles/"
    elif [[ "$dst" == docs/library/* || "$dst" == docs/roster/* || "$dst" == docs/profiles/* ]]; then bad="the project path must be outside the catalogs and profiles, which sync on their own"
    elif [[ "$dst" == AGENTS.md ]] || [[ "$dst" =~ $PROJECT_OWNED_RE ]] || is_header_file "$dst"; then bad="the project path is a file template-sync never applies"
    else
      for i in "${CORE_FILES[@]}"; do [[ "$dst" == "$i" ]] && bad="the project path is a template core file"; done
      for i in ${LED_DST[@]+"${LED_DST[@]}"}; do [[ "$dst" == "$i" ]] && bad="the project path is listed twice"; done
    fi
    if [[ -n "$bad" ]]; then
      echo "template-sync: $LEDGER:$n: $bad: $line" >&2
      return 1
    fi
    LED_DST+=("$dst"); LED_SRC+=("$src")
  done < "$LEDGER"
  return 0
}

# tpl_path PATH: where PATH's template version lives (the ledger's source for
# an installed item, else PATH itself).
tpl_path() {
  local i
  for i in ${LED_DST[@]+"${!LED_DST[@]}"}; do
    if [[ "${LED_DST[$i]}" == "$1" ]]; then echo "${LED_SRC[$i]}"; return 0; fi
  done
  echo "$1"
}

# led_note PATH: " [installed from <source>]" for a ledger entry, else nothing.
led_note() {
  local t
  t="$(tpl_path "$1")"
  if [[ "$t" != "$1" ]]; then echo " [installed from $t]"; fi
  return 0
}

# --status: offline check that the "- Template:" line is exact and names the
# ref of the last recorded sync. Template mode has nothing to check.
status_check() {
  if [[ ! -f .start-done ]]; then
    echo "template-sync: status: template mode (start has not run); nothing to check"
    return 0
  fi
  local line rest last lastline
  line="$(grep -m1 -E '^- Template:' AGENTS.md 2>/dev/null | tr -d '\r' || true)"
  if [[ -z "$line" ]]; then
    echo "template-sync: status: AGENTS.md has no '- Template: <url> <ref>' line under Project decisions" >&2
    return 1
  fi
  rest="${line#- Template:}"
  # shellcheck disable=SC2086
  set -- $rest
  if (( $# != 2 )); then
    echo "template-sync: status: malformed Template line, want exactly '- Template: <url> <ref>': $line" >&2
    return 1
  fi
  lastline=""
  if [[ -f "$LOG" ]]; then lastline="$(grep '^template-sync: ' "$LOG" | tr -d '\r' | tail -n 1 || true)"; fi
  last="$(printf '%s\n' "$lastline" | awk '{print $2}')"
  if [[ -z "$last" ]]; then
    echo "template-sync: status: no sync recorded in $LOG; run a sync (with --baseline <ref> when the starting version is known)" >&2
    return 1
  fi
  if [[ "$last" != "$2" ]]; then
    echo "template-sync: status: the Template line names $2 but the last recorded sync is $last; set '- Template: $1 $last'" >&2
    return 1
  fi
  echo "template-sync: status: template $1 at $2 (${lastline#template-sync: })"
  return 0
}

# --latest-tag: the newest template-v* tag at the template URL, by version
# order, read with ls-remote (no clone).
latest_remote_tag() {
  local t
  t="$(git ls-remote --tags --refs -- "$1" 2>/dev/null | awk '{print $2}' \
        | sed -n 's#^refs/tags/\(template-v.*\)$#\1#p' | sort -V | tail -n 1 || true)"
  if [[ -z "$t" ]]; then
    echo "template-sync: no template-v* tag found at $1" >&2
    return 1
  fi
  echo "$t"
}

# --suggest-baseline: candidates for the template version a project started
# from, when its sync record is missing or wrong. First the merge-base when
# the project shares git history with the template, then the three template
# commits whose core-set files match the project's copies most often (ties to
# the newest). Writes only inside $WORK.
suggest_baseline() {
  local mb f total=0 hashes="$WORK/project.hashes"
  if git rev-parse -q --verify HEAD >/dev/null 2>&1 \
     && git -C "$TPL" fetch -q -- "$ROOT" HEAD >/dev/null 2>&1; then
    mb="$(git -C "$TPL" merge-base FETCH_HEAD HEAD 2>/dev/null || true)"
    if [[ -n "$mb" ]]; then
      echo "template-sync: shared git history; merge-base $(git -C "$TPL" log -1 --format='%h %cs %s' "$mb")"
    fi
  fi
  : > "$hashes"
  while IFS= read -r f; do
    [[ -n "$f" && -f "$f" ]] || continue
    is_header_file "$f" && continue
    printf '%s\t%s\n' "$(tr -d '\r' < "$f" | git -C "$TPL" hash-object --stdin)" "$f" >> "$hashes"
    total=$((total + 1))
  done < <(list_core "$ROOT" | grep -Ev "$EXCLUDE_RE" | grep -Ev "$PROJECT_OWNED_RE" || true)
  echo "template-sync: suggested baselines by identical core-set files (of $total), pass one with --baseline <ref>:"
  # Ties go to the newest commit: the position in topological order (children
  # before parents) breaks them, since commit times can share a second.
  local c n i=0
  while IFS= read -r c; do
    i=$((i + 1))
    n="$(git -C "$TPL" ls-tree -r "$c" | awk -F'\t' 'NR==FNR {want[$1 SUBSEP $2]=1; next} {split($1, a, " "); if ((a[3] SUBSEP $2) in want) n++} END {print n+0}' "$hashes" -)"
    printf '%s %s %s\n' "$n" "$i" "$(git -C "$TPL" log -1 --format='%h %cs %s' "$c")"
  done < <(git -C "$TPL" rev-list --all --topo-order) \
    | sort -k1,1nr -k2,2n | sed -n '1,3p' \
    | while read -r n _ h d s; do echo "  $h $d $s - $n of $total identical"; done
  return 0
}


# --synced-commits <range>: the commits of a git range in this repository (the
# template) that change what projects receive, one "<full sha> <kind>" line
# each, in git log order. One definition for fleet.sh (counts every line) and
# template-release.sh (agents, core and header are "synced"; catalog is the
# library section). A commit counts when it touches a core or catalog path; or
# a header file whose first HEADER_LINES lines differ from its parent (a file
# absent on one side differs); or AGENTS.md with a different KERNEL block or
# "## Rules index" section (CR stripped). The kind is the first that applies in
# the order agents, core, header, catalog, so a commit touching core and catalog
# is core, and one that also changes the AGENTS.md kernel or rules index is
# agents (agents first because session-context.sh prints its kernel sentence
# only for that kind). Edits below a lessons header and AGENTS.md Project
# decisions are project data and do not count.
agents_synced_view() { # git object -> kernel block then rules index
  git -C "$ROOT" show "$1" 2>/dev/null | tr -d '\r' | awk '
    /<!-- KERNEL:BEGIN -->/ {k=1}
    k {print}
    /<!-- KERNEL:END -->/ {k=0}
    /^## Rules index/ {r=1; print; next}
    /^## / {r=0}
    r'
}

# The synced set is read once per run into SET_G / SET_P (group and path):
# list_set runs in a subshell, and one per commit, or a here-document per set
# line, made the range scan take seconds on Windows.
SET_G=()
SET_P=()

load_set() {
  local g p
  SET_G=(); SET_P=()
  while read -r g p; do
    [[ -n "$g" ]] || continue
    SET_G+=("$g"); SET_P+=("$p")
  done < <(list_set)
}

# commit_kind <sha> <file>...: sets KIND to the kind of the commit, or "" when
# it changes nothing projects receive. No subshell: it runs once per commit.
commit_kind() {
  local sha="$1" g p f a b i core=0 header=0 agents=0 catalog=0
  shift
  KIND=""
  for f in "$@"; do
    [[ -n "$f" ]] || continue
    for i in "${!SET_G[@]}"; do
      g="${SET_G[$i]}"; p="${SET_P[$i]}"
      case "$g" in
        core|catalog)
          case "$p" in
            */) [[ "$f" == "$p"* ]] || continue ;;
            *) [[ "$f" == "$p" ]] || continue ;;
          esac
          if [[ "$g" == core ]]; then core=1; else catalog=1; fi ;;
        header)
          if [[ "$f" == "$p" && $header -eq 0 ]]; then
            if git -C "$ROOT" cat-file -e "$sha^:$p" 2>/dev/null; then
              a="P$(git -C "$ROOT" show "$sha^:$p" | sed -n "1,${HEADER_LINES}p")"
            else a=absent; fi
            if git -C "$ROOT" cat-file -e "$sha:$p" 2>/dev/null; then
              b="P$(git -C "$ROOT" show "$sha:$p" | sed -n "1,${HEADER_LINES}p")"
            else b=absent; fi
            [[ "$a" != "$b" ]] && header=1
          fi ;;
        agents)
          if [[ "$f" == "$p" && $agents -eq 0 ]] && [[ "$(agents_synced_view "$sha^:$p")" != "$(agents_synced_view "$sha:$p")" ]]; then
            agents=1
          fi ;;
      esac
    done
  done
  if [[ $agents -eq 1 ]]; then KIND=agents
  elif [[ $core -eq 1 ]]; then KIND=core
  elif [[ $header -eq 1 ]]; then KIND=header
  elif [[ $catalog -eq 1 ]]; then KIND=catalog
  fi
}

# One git log reads the whole range (marker line "TAB then the sha", then that
# commit's files; git quotes a path holding any control character whatever
# core.quotePath says, so no path line starts with a raw TAB); only commits that
# touch a header file or AGENTS.md pay for the git show comparisons inside
# commit_kind. --no-renames keeps one path per change, as diff-tree -r reported
# it. The marker was SOH (\001) until 2026-11-17: bash uses \001 internally as
# its quoting escape (CTLESC), so its survival through command substitution, an
# unquoted here-document and read -r rested on each bash version's handling of
# that byte; TAB is an ordinary character in all three, and IFS= keeps it.
synced_commits() {
  local range="$1" line sha="" out mark
  mark="$(printf '\t')"
  local files=()
  if ! out="$(git -C "$ROOT" -c core.quotePath=false -c log.showRoot=true log --no-merges --no-renames --format=%x09%H --name-only "$range" 2>/dev/null)"; then
    echo "template-sync: --synced-commits: cannot read the git range '$range' in $ROOT" >&2
    return 1
  fi
  load_set
  while IFS= read -r line; do
    if [[ "$line" == "$mark"* ]]; then
      if [[ -n "$sha" ]]; then
        commit_kind "$sha" ${files[@]+"${files[@]}"}
        if [[ -n "$KIND" ]]; then echo "$sha $KIND"; fi
      fi
      sha="${line#"$mark"}"; files=()
    elif [[ -n "$line" ]]; then
      files+=("$line")
    fi
  done <<LOG
$out
LOG
  if [[ -n "$sha" ]]; then
    commit_kind "$sha" ${files[@]+"${files[@]}"}
    if [[ -n "$KIND" ]]; then echo "$sha $KIND"; fi
  fi
  return 0
}

main() {
  local template="" ref="" dry=0 from_agents=0 default_tag="" resolved=0
  local baseline="" latest=0 mode=sync accept=0
  while (( $# )); do
    case "$1" in
      -h|--help) usage_text; exit 0 ;;
      --list-set) list_set; exit 0 ;;
      --synced-commits) [[ $# -ge 2 ]] || usage; synced_commits "$2"; exit $? ;;
      --template) [[ $# -ge 2 ]] || usage; template="$2"; shift 2 ;;
      --ref) [[ $# -ge 2 ]] || usage; ref="$2"; shift 2 ;;
      --baseline) [[ $# -ge 2 ]] || usage; baseline="$2"; shift 2 ;;
      --latest) latest=1; shift ;;
      --latest-tag) mode=latest-tag; shift ;;
      --status) mode=status; shift ;;
      --suggest-baseline) mode=suggest; shift ;;
      --dry-run) dry=1; shift ;;
      --resolved) resolved=1; shift ;;
      --accept-kernel) accept=1; shift ;;
      *) usage ;;
    esac
  done
  if (( latest )) && [[ -n "$ref" ]]; then
    echo "template-sync: --latest and --ref cannot be combined" >&2
    exit 2
  fi
  command -v git >/dev/null 2>&1 || { echo "template-sync: git not found" >&2; exit 1; }
  cd "$ROOT"

  if [[ "$mode" == status ]]; then
    status_check; exit $?
  fi

  if [[ -z "$template" ]]; then
    local at
    at="$(agents_template)"
    if [[ -z "$at" ]]; then
      echo "template-sync: no --template given and AGENTS.md has no '- Template: <url> <tag>' line under Project decisions" >&2
      exit 2
    fi
    template="${at%% *}"; default_tag="${at#* }"
    from_agents=1
    if [[ -z "$ref" && -n "$default_tag" ]] && (( ! latest )); then ref="$default_tag"; fi
  fi

  if [[ "$mode" == latest-tag ]]; then
    latest_remote_tag "$template"; exit $?
  fi

  # Guard: a real apply needs a clean tree on a working branch.
  if (( ! dry )) && [[ "$mode" == sync ]]; then
    local dirty branch
    dirty="$(git status --porcelain -- . ":(exclude)$OUTDIR" 2>/dev/null || true)"
    if [[ -n "$dirty" ]]; then
      echo "template-sync: refusing to apply: the working tree is not clean (git status --porcelain is not empty). Commit or stash first, or use --dry-run." >&2
      printf '%s\n' "$dirty" | sed -n '1,10s/^/  /p' >&2
      exit 2
    fi
    branch="$(git symbolic-ref --short -q HEAD 2>/dev/null || true)"
    if [[ -z "$branch" || "$branch" == main || "$branch" == master ]]; then
      echo "template-sync: refusing to apply on '${branch:-a detached HEAD}': switch to a working branch first (not main or master), or use --dry-run." >&2
      exit 2
    fi
  fi

  WORK="$(mktemp -d "${TMPDIR:-/tmp}/template-sync.XXXXXX")"
  trap 'case "$WORK" in */template-sync.*) rm -rf "$WORK" ;; esac' EXIT
  TPL="$WORK/tpl"
  git clone -q -- "$template" "$TPL" || { echo "template-sync: cannot clone $template" >&2; exit 1; }

  if [[ "$mode" == suggest ]]; then
    suggest_baseline; exit $?
  fi
  if (( latest )); then
    ref="$(git -C "$TPL" tag -l 'template-v*' | sort -V | tail -n 1)"
    [[ -n "$ref" ]] || { echo "template-sync: no template-v* tag in $template" >&2; exit 1; }
    echo "template-sync: newest template tag $ref (--latest)"
  fi

  local new_sha new_ref prev prev_sha="" old_dir=""
  new_sha="$(resolve_ref "${ref:-HEAD}")"
  [[ -n "$new_sha" ]] || { echo "template-sync: ref '${ref:-HEAD}' not found in $template" >&2; exit 1; }
  if [[ -n "$ref" ]] && git -C "$TPL" rev-parse -q --verify "refs/tags/$ref" >/dev/null 2>&1; then
    new_ref="$ref"
  else
    new_ref="$(git -C "$TPL" rev-parse --short "$new_sha")"
  fi
  export_tree "$new_sha" "$WORK/new"

  prev=""
  if [[ -n "$baseline" ]]; then
    prev="$baseline"
    if [[ -z "$(resolve_ref "$baseline")" ]]; then
      echo "template-sync: baseline '$baseline' not found in $template" >&2
      exit 1
    fi
  elif [[ -f "$LOG" ]]; then
    prev="$(grep '^template-sync: ' "$LOG" | tr -d '\r' | tail -n 1 | awk '{print $2}' || true)"
  fi
  if [[ -n "$prev" ]]; then
    prev_sha="$(resolve_ref "$prev")"
    if [[ -n "$prev_sha" ]]; then
      export_tree "$prev_sha" "$WORK/old"
      old_dir="$WORK/old"
    fi
  fi

  local adopted_list
  adopted_list="$(adopted_profiles)" || exit 1
  ADOPTED="$(printf '%s\n' "$adopted_list" | grep . | tr '\n' ' ' || true)"
  read_ledger || exit 2
  rm -rf "$OUTDIR"
  mkdir -p "$OUTDIR"
  echo "template-sync: template $template at $new_ref"
  if (( from_agents )); then echo "template-sync: template and default ref taken from AGENTS.md"; fi
  if [[ -n "$old_dir" && -n "$baseline" ]]; then
    echo "template-sync: previous version $prev from --baseline (three-way comparison)"
  elif [[ -n "$old_dir" ]]; then
    echo "template-sync: previous sync $prev (three-way comparison)"
  elif [[ -n "$prev" ]]; then
    echo "template-sync: previous sync $prev is not in the template; no previous version, differing files are listed only"
  else
    echo "template-sync: no previous sync recorded; no previous version, differing files are listed only"
  fi
  if [[ -n "${ADOPTED// /}" ]]; then
    echo "template-sync: adopted profiles (reported as DIFF, never applied): $ADOPTED"
  else
    echo "template-sync: no adopted profiles listed"
  fi
  local cd_
  for cd_ in "${CATALOG_DIRS[@]}"; do
    if [[ -d "$WORK/new/$cd_" && ! -d "$cd_" ]]; then
      echo "template-sync: $cd_/ is not carried by this project; not synced (copy it from the template to opt in)"
    fi
  done
  if (( ${#LED_DST[@]} )); then
    echo "template-sync: ${#LED_DST[@]} installed item(s) in $LEDGER, each compared with its template source"
  fi

  # An installed item's path may sit in the core set (.claude/agents/); the
  # ledger decides its template side, so the core walk skips it.
  local paths p t n_f o_f p_f vn vo vp led_list=""
  if (( ${#LED_DST[@]} )); then led_list="$(printf '%s\n' "${LED_DST[@]}")"; fi
  paths="$( { list_core "$WORK/new"; if [[ -n "$old_dir" ]]; then list_core "$old_dir"; fi; } \
            | grep -Ev "$EXCLUDE_RE" | grep -Ev "$PROJECT_OWNED_RE" \
            | { if [[ -n "$led_list" ]]; then grep -vxF -- "$led_list"; else cat; fi; } | sort -u || true)"
  if [[ -n "$led_list" ]]; then paths="$(printf '%s\n%s\n' "$paths" "$led_list" | grep . || true)"; fi

  local updates=() adds=() conflicts=() diffs=() deleted=() removed=()
  local unchanged=0 owned=0
  while IFS= read -r p; do
    [[ -n "$p" ]] || continue
    if uncarried_profile "$p" && ! adopted_profile_of "$p"; then continue; fi
    if uncarried_catalog "$p"; then continue; fi
    n_f=0; o_f=0; p_f=0
    t="$(tpl_path "$p")"
    [[ -f "$WORK/new/$t" ]] && n_f=1
    [[ -n "$old_dir" && -f "$old_dir/$t" ]] && o_f=1
    [[ -f "$p" ]] && p_f=1
    if (( n_f )) && never_apply "$p"; then
      if (( p_f )); then
        vn="$(view new "$WORK/new/$p" "$p")"; vp="$(view proj "$p" "$p")"
        if same "$vp" "$vn"; then unchanged=$((unchanged + 1)); continue; fi
        write_diff "$p" "$vp" "$vn"
      else
        write_diff "$p" /dev/null "$WORK/new/$p"
      fi
      diffs+=("$p")
      continue
    fi
    if (( n_f && p_f )); then
      vn="$(view new "$WORK/new/$t" "$p")"; vp="$(view proj "$p" "$p")"
      vo=""
      if (( o_f )); then vo="$(view old "$old_dir/$t" "$p")"; fi
      if same "$vp" "$vn"; then
        unchanged=$((unchanged + 1))
      elif (( o_f )) && same "$vn" "$vo"; then
        owned=$((owned + 1))
      elif (( o_f )) && same "$vp" "$vo"; then
        updates+=("$p")
      else
        conflicts+=("$p")
        write_diff "$p" "$vp" "$vn"
      fi
    elif (( n_f )); then
      if (( o_f )); then deleted+=("$p"); else adds+=("$p"); fi
    elif (( p_f )); then
      removed+=("$p")
    fi
  done <<< "$paths"

  local f
  if (( ${#updates[@]} )); then
    for f in "${updates[@]}"; do echo "UPDATE    $f  (project copy untouched since $prev; template changed)$(led_note "$f")"; done
  fi
  if (( ${#adds[@]} )); then
    for f in "${adds[@]}"; do echo "ADD       $f  (new in the template)$(led_note "$f")"; done
  fi
  if (( ${#conflicts[@]} )); then
    for f in "${conflicts[@]}"; do
      if (( resolved )); then echo "RESOLVED  $f  (project edited and template differs; hand merge attested with --resolved)$(led_note "$f")"
      else echo "CONFLICT  $f  (project edited and template differs; merge by hand, then rerun with --resolved)$(led_note "$f")"; fi
    done
  fi
  if (( ${#diffs[@]} )); then
    for f in "${diffs[@]}"; do echo "DIFF      $f  (never applied; see $OUTDIR/$f.diff)"; done
  fi
  if (( ${#deleted[@]} )); then
    for f in "${deleted[@]}"; do echo "DELETED   $f  (the project removed it; not restored)$(led_note "$f")"; done
  fi
  if (( ${#removed[@]} )); then
    for f in "${removed[@]}"; do echo "REMOVED   $f  (no longer in the template; review, then archive if unused)$(led_note "$f")"; done
  fi
  if (( ${#conflicts[@]} && ! resolved )); then
    for f in "${conflicts[@]}"; do
      echo
      echo "=== diff: $f (project -> template) ==="
      cat "$OUTDIR/$f.diff"
    done
    echo
  fi

  # AGENTS.md is never applied; its kernel and rules index are compared.
  local kernel_pending=0 do_accept=0
  if [[ -f AGENTS.md && -f "$WORK/new/AGENTS.md" ]]; then
    kernel_block AGENTS.md > "$WORK/k.proj"
    kernel_block "$WORK/new/AGENTS.md" > "$WORK/k.new"
    if [[ -s "$WORK/k.new" ]] && ! cmp -s "$WORK/k.proj" "$WORK/k.new"; then
      diff -u --label "project/AGENTS.md KERNEL" --label "template/AGENTS.md KERNEL" "$WORK/k.proj" "$WORK/k.new" > "$OUTDIR/AGENTS.kernel.diff" || true
      kernel_pending=1
      if (( accept && ! dry )); then
        # The release the project last recorded, not --baseline: the owner's
        # approval covers a kernel that is exactly that release's.
        local why="" log_ref="" log_sha="" kdir=""
        if [[ -f "$LOG" ]]; then log_ref="$(grep '^template-sync: ' "$LOG" | tr -d '\r' | tail -n 1 | awk '{print $2}' || true)"; fi
        if [[ -z "$log_ref" ]]; then why="no recorded sync line in $LOG"
        else
          log_sha="$(resolve_ref "$log_ref")"
          if [[ -z "$log_sha" ]]; then why="recorded ref $log_ref is missing from the template"
          else
            kdir="$WORK/oldlog"; export_tree "$log_sha" "$kdir"
            kernel_block "$kdir/AGENTS.md" > "$WORK/k.old" 2>/dev/null || true
            cmp -s "$WORK/k.old" "$WORK/k.proj" || why="project kernel differs from its recorded release $log_ref (customized)"
          fi
        fi
        if [[ -z "$why" ]]; then do_accept=1; kernel_pending=0
        else echo "KERNEL CHANGE: --accept-kernel refused: $why"; fi
      fi
      if (( ! do_accept )); then
        echo "KERNEL CHANGE: needs owner approval and scripts/kernel-hash.sh --update  (diff: $OUTDIR/AGENTS.kernel.diff)"
      fi
    fi
    rules_index AGENTS.md > "$WORK/r.proj"
    rules_index "$WORK/new/AGENTS.md" > "$WORK/r.new"
    if [[ -s "$WORK/r.new" ]] && ! cmp -s "$WORK/r.proj" "$WORK/r.new"; then
      diff -u --label "project/AGENTS.md Rules index" --label "template/AGENTS.md Rules index" "$WORK/r.proj" "$WORK/r.new" > "$OUTDIR/AGENTS.rules-index.diff" || true
      echo "RULES INDEX CHANGE: merge by hand into AGENTS.md  (diff: $OUTDIR/AGENTS.rules-index.diff)"
    fi
  fi

  # A core skill the new release drops from CORE_SKILLS while the project keeps
  # its folder becomes a project skill (ADR 0012) and may take the project over
  # its cap; name it so the owner sees why. The earlier core list is the
  # previous version's and the project's own lessons.sh (read before applying).
  local retired_skills=() s
  if [[ -f "$WORK/new/scripts/lessons.sh" ]]; then
    local new_core prior_core=""
    new_core="$(core_skills_of "$WORK/new/scripts/lessons.sh")"
    # A lessons.sh with no readable CORE_SKILLS line names no list, so it
    # retires nothing.
    if [[ -n "$new_core" ]]; then
      prior_core="$( { if [[ -n "$old_dir" ]]; then core_skills_of "$old_dir/scripts/lessons.sh"; fi; core_skills_of scripts/lessons.sh; } | sort -u)"
    fi
    while IFS= read -r s; do
      [[ -n "$s" && -d ".claude/skills/$s" ]] || continue
      grep -qx -- "$s" <<< "$new_core" && continue
      retired_skills+=("$s")
    done <<< "$prior_core"
  fi
  if (( ${#retired_skills[@]} )); then
    for s in "${retired_skills[@]}"; do
      echo "RETIRED CORE SKILL: $s  (.claude/skills/$s is kept but no longer a template core skill; it now counts as a project skill (ADR 0012): archive it or keep it in a project slot)"
    done
  fi

  echo "template-sync: summary: update=${#updates[@]} add=${#adds[@]} conflict=${#conflicts[@]} diff=${#diffs[@]} deleted-by-project=${#deleted[@]} removed-upstream=${#removed[@]} unchanged=$unchanged project-owned=$owned"

  local rc=0
  if (( (${#conflicts[@]} && ! resolved) || kernel_pending )); then rc=1; fi

  if (( dry )); then
    echo "template-sync: dry run; nothing was changed"
    return $rc
  fi

  local newsh=()
  if (( ${#updates[@]} )); then
    for f in "${updates[@]}"; do
      mkdir -p "$(dirname "$f")"
      if is_header_file "$f"; then
        { head -n "$HEADER_LINES" "$WORK/new/$f"; tail -n +"$((HEADER_LINES + 1))" "$f"; } > "$WORK/hdr.tmp"
        cat "$WORK/hdr.tmp" > "$f"
      else
        cp -p "$WORK/new/$(tpl_path "$f")" "$f"
      fi
    done
  fi
  if (( ${#adds[@]} )); then
    for f in "${adds[@]}"; do
      mkdir -p "$(dirname "$f")"; cp -p "$WORK/new/$(tpl_path "$f")" "$f"
      case "$f" in *.sh) newsh+=("$f") ;; esac
    done
  fi
  if (( ${#newsh[@]} )); then
    echo "template-sync: new scripts; keep them executable in git: git update-index --add --chmod=+x ${newsh[*]}"
  fi

  if (( do_accept )); then
    local cr=""
    if sed -n '/<!-- KERNEL:BEGIN -->/p' AGENTS.md | grep -q $'\r'; then cr=$'\r'; fi
    awk -v nf="$WORK/k.new" -v cr="$cr" '
      /<!-- KERNEL:BEGIN -->/ && !done { while ((getline l < nf) > 0) print l cr; skip = 1; done = 1 }
      skip { if (/<!-- KERNEL:END -->/) skip = 0; next }
      { print }' AGENTS.md > "$WORK/agents.tmp"
    cat "$WORK/agents.tmp" > AGENTS.md
    bash scripts/kernel-hash.sh --update >/dev/null
    echo "template-sync: kernel accepted verbatim from $new_ref under --accept-kernel"
  fi

  local recorded="the sync is recorded"
  if (( ${#conflicts[@]} && ! resolved )); then
    recorded="the sync is NOT recorded"
    echo "template-sync: sync NOT recorded: ${#conflicts[@]} conflict(s) remain and are reported on every run until merged by hand and attested with --resolved"
  elif (( kernel_pending )); then
    recorded="the sync is NOT recorded"
    echo "template-sync: sync NOT recorded: the kernel change is pending; the next run keeps ${prev:-no previous sync} as its base"
  else
    mkdir -p "$(dirname "$LOG")"
    echo "template-sync: $new_ref ${TEMPLATE_SYNC_TODAY:-$(date -u +%F)}" >> "$LOG"
  fi

  if [[ -x scripts/kernel-hash.sh ]]; then
    if ! ./scripts/kernel-hash.sh --verify; then
      echo "template-sync: kernel verification FAILED after the sync" >&2
      rc=1
    fi
  else
    echo "template-sync: scripts/kernel-hash.sh is not present or not executable; kernel not verified" >&2
    rc=1
  fi

  # A synced core skill can take the project over its kernel rule 10 skills
  # cap; the synced lessons.sh counts it, and a breach is the owner's call.
  # Exit 1 is a breach; any other failure (a lessons.sh without the skills
  # command, a crash) means the cap was not counted, which is no breach.
  if [[ -x scripts/lessons.sh ]]; then
    local cap_out cap_rc=0
    cap_out="$(./scripts/lessons.sh skills 2>&1)" || cap_rc=$?
    if (( cap_rc == 0 || cap_rc == 1 )); then
      printf '%s\n' "$cap_out" | sed -n '1s/^/template-sync: /p'
    fi
    if (( cap_rc == 1 )); then
      echo "ACTION: skills cap: $(printf '%s\n' "$cap_out" | sed -n 's/^lessons: //p'). Merge or archive a project skill (docs/procedures/maintain.md); $recorded."
      rc=1
    elif (( cap_rc )); then
      echo "template-sync: skills cap not checked: scripts/lessons.sh skills exited $cap_rc: $(printf '%s\n' "$cap_out" | sed -n 1p)" >&2
      rc=1
    fi
  fi
  return $rc
}

main "$@"; exit $?
