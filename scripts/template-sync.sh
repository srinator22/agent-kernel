#!/usr/bin/env bash
# template-sync.sh - bring a project's template-owned files up to date with the
# template without clobbering what the project changed (docs/procedures/upstream.md).
# Usage: scripts/template-sync.sh [--template <git url or path>] [--ref <tag>] [--dry-run]
#        scripts/template-sync.sh --help | -h
#
# --template is optional: when omitted it is read from the project's AGENTS.md
# Project decisions line "- Template: <url> <tag>" (the url, and the tag as the
# default --ref). With neither, the script stops with exit 2.
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
# docs/BLUEPRINT.md, docs/DEFECT_MEMORY.md, docs/procedures/, docs/rules/,
# docs/profiles/, scripts/, tests/template/, .claude/, .agents/, .codex/,
# .github/workflows/ci.yml, and the format headers (first 12 lines only) of
# docs/lessons/INDEX.md, PENDING.md, QUARANTINE.md and UPSTREAM.md; the rest of
# those four files is project data and is never touched. Never touched at all:
# the project's own truth files, BACKLOG.md, docs/decisions/, .work/, the kernel
# hash and any *.local.* file.
#
# Outcomes (compared without regard to CR line endings):
#   PROJ == NEW                              unchanged
#   NEW == OLD                               project-owned, nothing to bring
#   PROJ == OLD, NEW differs                 UPDATE: applied (project never touched it)
#   PROJ differs from OLD, NEW differs       CONFLICT: listed as a diff, never applied
#   missing in project, absent from OLD      ADD: applied
#   missing in project, present in OLD       the project deleted it: listed, not restored
#   present in project, absent from NEW      removed upstream: listed, never deleted here
# Never applied, always reported as DIFF (the unified diff is written to
# .work/template-sync/<path>.diff): .github/workflows/ci.yml and every file of an
# adopted profile (docs/profiles/<name>/ for the names on the AGENTS.md
# "- Profiles:" line). A DIFF is information, not a conflict: it does not change
# the exit code. A profile the project does not carry is skipped.
#
# AGENTS.md is never applied. The KERNEL block (KERNEL:BEGIN through KERNEL:END)
# and the "## Rules index" section of both versions are compared; when they
# differ the diffs are written to .work/template-sync/AGENTS.kernel.diff and
# AGENTS.rules-index.diff, a kernel difference prints "KERNEL CHANGE: needs owner
# approval and scripts/kernel-hash.sh --update", and the project's .kernel.hash
# is never touched. After applying, the script re-runs
# scripts/kernel-hash.sh --verify.
#
# Exit: 0 clean or applied, 1 conflicts or a kernel change pending (or a failed
# clone, ref or kernel verification), 2 usage or guard failure.
#
# Test hook: TEMPLATE_SYNC_TODAY=YYYY-MM-DD overrides today's date.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG="docs/lessons/MAINTENANCE.log"
OUTDIR=".work/template-sync"
CORE_DIRS=(scripts docs/procedures docs/rules docs/profiles tests/template .claude .agents .codex)
CORE_FILES=(CLAUDE.md CONTRIBUTING.md manifest.md cliff.toml docs/BLUEPRINT.md docs/DEFECT_MEMORY.md .github/workflows/ci.yml)
HEADER_FILES=(docs/lessons/INDEX.md docs/lessons/PENDING.md docs/lessons/QUARANTINE.md docs/lessons/UPSTREAM.md)
HEADER_LINES=12
EXCLUDE_RE='(^|/)[^/]*\.local\.[^/]*$'

usage_text() {
  echo "usage: scripts/template-sync.sh [--template <git url or path>] [--ref <tag>] [--dry-run] [--resolved]"
  echo "       scripts/template-sync.sh --help"
  echo "  --template defaults to the '- Template: <url> <tag>' line of AGENTS.md (tag = default --ref)."
  echo "  A real apply needs a clean working tree and a branch other than main or master."
  echo "  --resolved: the conflicts reported by the previous run were merged by hand; record the sync with them"
  echo "  exit: 0 clean or applied, 1 conflicts or kernel change pending, 2 usage or guard failure"
}
usage() { usage_text >&2; exit 2; }

adopted_profiles() {
  [[ -f AGENTS.md ]] || return 0
  local line tok
  line="$(grep -m1 -E '^- Profiles:' AGENTS.md 2>/dev/null || true)"
  line="${line#- Profiles:}"
  line="${line//\`/ }"
  line="${line//,/ }"
  [[ "$line" == *"{{"* ]] && return 0
  for tok in $line; do
    [[ "$tok" =~ ^[a-z0-9][a-z0-9-]*$ ]] || continue
    case "$tok" in none|and|n) continue ;; esac
    echo "$tok"
  done
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
  for d in "${CORE_DIRS[@]}"; do
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

kernel_block() { awk '/<!-- KERNEL:BEGIN -->/{f=1} f{print} /<!-- KERNEL:END -->/{exit}' "$1" | tr -d '\r'; }
rules_index() { awk '/^## Rules index/{f=1; print; next} f && /^## /{exit} f{print}' "$1" | tr -d '\r'; }

main() {
  local template="" ref="" dry=0 from_agents=0 default_tag="" resolved=0
  while (( $# )); do
    case "$1" in
      -h|--help) usage_text; exit 0 ;;
      --template) [[ $# -ge 2 ]] || usage; template="$2"; shift 2 ;;
      --ref) [[ $# -ge 2 ]] || usage; ref="$2"; shift 2 ;;
      --dry-run) dry=1; shift ;;
      --resolved) resolved=1; shift ;;
      *) usage ;;
    esac
  done
  command -v git >/dev/null 2>&1 || { echo "template-sync: git not found" >&2; exit 1; }
  cd "$ROOT"

  if [[ -z "$template" ]]; then
    local at
    at="$(agents_template)"
    if [[ -z "$at" ]]; then
      echo "template-sync: no --template given and AGENTS.md has no '- Template: <url> <tag>' line under Project decisions" >&2
      exit 2
    fi
    template="${at%% *}"; default_tag="${at#* }"
    from_agents=1
    if [[ -z "$ref" && -n "$default_tag" ]]; then ref="$default_tag"; fi
  fi

  # Guard: a real apply needs a clean tree on a working branch.
  if (( ! dry )); then
    local dirty branch
    dirty="$(git status --porcelain -- . ":(exclude)$OUTDIR" 2>/dev/null || true)"
    if [[ -n "$dirty" ]]; then
      echo "template-sync: refusing to apply: the working tree is not clean (git status --porcelain is not empty). Commit or stash first, or use --dry-run." >&2
      printf '%s\n' "$dirty" | head -10 | sed 's/^/  /' >&2
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
  if [[ -f "$LOG" ]]; then prev="$(grep '^template-sync: ' "$LOG" | tail -n 1 | awk '{print $2}' || true)"; fi
  if [[ -n "$prev" ]]; then
    prev_sha="$(resolve_ref "$prev")"
    if [[ -n "$prev_sha" ]]; then
      export_tree "$prev_sha" "$WORK/old"
      old_dir="$WORK/old"
    fi
  fi

  ADOPTED="$(adopted_profiles | tr '\n' ' ')"
  rm -rf "$OUTDIR"
  mkdir -p "$OUTDIR"
  echo "template-sync: template $template at $new_ref"
  if (( from_agents )); then echo "template-sync: template and default ref taken from AGENTS.md"; fi
  if [[ -n "$old_dir" ]]; then
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

  local paths p n_f o_f p_f vn vo vp
  paths="$( { list_core "$WORK/new"; if [[ -n "$old_dir" ]]; then list_core "$old_dir"; fi; } \
            | grep -Ev "$EXCLUDE_RE" | sort -u || true)"

  local updates=() adds=() conflicts=() diffs=() deleted=() removed=()
  local unchanged=0 owned=0
  while IFS= read -r p; do
    [[ -n "$p" ]] || continue
    if uncarried_profile "$p" && ! adopted_profile_of "$p"; then continue; fi
    n_f=0; o_f=0; p_f=0
    [[ -f "$WORK/new/$p" ]] && n_f=1
    [[ -n "$old_dir" && -f "$old_dir/$p" ]] && o_f=1
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
      vn="$(view new "$WORK/new/$p" "$p")"; vp="$(view proj "$p" "$p")"
      vo=""
      if (( o_f )); then vo="$(view old "$old_dir/$p" "$p")"; fi
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
    for f in "${updates[@]}"; do echo "UPDATE    $f  (project copy untouched since $prev; template changed)"; done
  fi
  if (( ${#adds[@]} )); then
    for f in "${adds[@]}"; do echo "ADD       $f  (new in the template)"; done
  fi
  if (( ${#conflicts[@]} )); then
    for f in "${conflicts[@]}"; do
      if (( resolved )); then echo "RESOLVED  $f  (project edited and template differs; hand merge attested with --resolved)"
      else echo "CONFLICT  $f  (project edited and template differs; merge by hand, then rerun with --resolved)"; fi
    done
  fi
  if (( ${#diffs[@]} )); then
    for f in "${diffs[@]}"; do echo "DIFF      $f  (never applied; see $OUTDIR/$f.diff)"; done
  fi
  if (( ${#deleted[@]} )); then
    for f in "${deleted[@]}"; do echo "DELETED   $f  (the project removed it; not restored)"; done
  fi
  if (( ${#removed[@]} )); then
    for f in "${removed[@]}"; do echo "REMOVED   $f  (no longer in the template; review, then archive if unused)"; done
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
  local kernel_pending=0
  if [[ -f AGENTS.md && -f "$WORK/new/AGENTS.md" ]]; then
    kernel_block AGENTS.md > "$WORK/k.proj"
    kernel_block "$WORK/new/AGENTS.md" > "$WORK/k.new"
    if [[ -s "$WORK/k.new" ]] && ! cmp -s "$WORK/k.proj" "$WORK/k.new"; then
      diff -u --label "project/AGENTS.md KERNEL" --label "template/AGENTS.md KERNEL" "$WORK/k.proj" "$WORK/k.new" > "$OUTDIR/AGENTS.kernel.diff" || true
      echo "KERNEL CHANGE: needs owner approval and scripts/kernel-hash.sh --update  (diff: $OUTDIR/AGENTS.kernel.diff)"
      kernel_pending=1
    fi
    rules_index AGENTS.md > "$WORK/r.proj"
    rules_index "$WORK/new/AGENTS.md" > "$WORK/r.new"
    if [[ -s "$WORK/r.new" ]] && ! cmp -s "$WORK/r.proj" "$WORK/r.new"; then
      diff -u --label "project/AGENTS.md Rules index" --label "template/AGENTS.md Rules index" "$WORK/r.proj" "$WORK/r.new" > "$OUTDIR/AGENTS.rules-index.diff" || true
      echo "RULES INDEX CHANGE: merge by hand into AGENTS.md  (diff: $OUTDIR/AGENTS.rules-index.diff)"
    fi
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
        cp -p "$WORK/new/$f" "$f"
      fi
    done
  fi
  if (( ${#adds[@]} )); then
    for f in "${adds[@]}"; do
      mkdir -p "$(dirname "$f")"; cp -p "$WORK/new/$f" "$f"
      case "$f" in *.sh) newsh+=("$f") ;; esac
    done
  fi
  if (( ${#newsh[@]} )); then
    echo "template-sync: new scripts; keep them executable in git: git update-index --add --chmod=+x ${newsh[*]}"
  fi

  if (( ${#conflicts[@]} && ! resolved )); then
    echo "template-sync: sync NOT recorded: ${#conflicts[@]} conflict(s) remain and are reported on every run until merged by hand and attested with --resolved"
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
  return $rc
}

main "$@"; exit $?
