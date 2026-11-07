#!/usr/bin/env bash
# session-context.sh - SessionStart hook target: mechanizes kernel rule 7
# for Claude Code. Fires at startup, resume, clear, and after compaction
# (SessionStart source "compact"), so the rule-7 re-read happens by
# mechanism, not memory. stdout is injected into the session context:
# keep it small and stable. Other harnesses rely on the prose rule.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

if [[ -f .start-done ]]; then
  echo "[session-context] Project mode (start has run)."
else
  echo "[session-context] TEMPLATE MODE: start has not run. Placeholders {{...}} are filled only by docs/procedures/start.md."
fi

echo "[session-context] Kernel rule 7: read AGENTS.md, .work/TASK.md, and BACKLOG.md before acting; scan docs/lessons/INDEX.md before non-trivial work."

# Git state: commit bodies carry the why (kernel rule 6), so the last commits
# and the working-tree status are the cheapest memory to load. Capped so a
# large untracked tree cannot flood the context. Outside a git repository
# this block prints nothing.
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
  echo "[session-context] Branch: $branch"
  status="$(git status --short 2>/dev/null || true)"
  if [[ -z "$status" ]]; then
    echo "[session-context] Working tree: clean"
  else
    total="$(printf '%s\n' "$status" | wc -l | tr -d ' ')"
    echo "[session-context] Working tree ($total changed or untracked):"
    printf '%s\n' "$status" | head -n 20
    if (( total > 20 )); then echo "  ... $((total - 20)) more (git status --short)"; fi
  fi
  log="$(git log --oneline -10 2>/dev/null || true)"
  if [[ -n "$log" ]]; then
    echo "[session-context] Last commits (git log for bodies):"
    printf '%s\n' "$log"
  fi
fi

if [[ -f .work/TASK.md ]] && ! grep -q '{{title}}' .work/TASK.md; then
  echo "[session-context] In-progress task state (.work/TASK.md):"
  cat .work/TASK.md
fi

# Template update awareness. Project mode: tell the human when a newer
# template-v* tag exists than the last recorded sync. Template mode: tell the
# maintainer when synced-set commits have landed since the newest tag.
# Opt out with TEMPLATE_UPDATE_CHECK=0. Every command is guarded: this hook
# must print its other lines and exit 0 whatever happens here.
# Prints the AGENTS.md sections that sync to projects (the kernel block and
# the rules index) from stdin.
agents_synced_sections() {
  awk '
    /<!-- KERNEL:BEGIN -->/ {k=1}
    k {print}
    /<!-- KERNEL:END -->/ {k=0}
    /^## Rules index/ {r=1; print; next}
    /^## / {r=0}
    r {print}
  ' || true
}
template_update_block() {
  local line rest url ref last tag cache dir tmp lowest newest n paths p
  if [[ -f .start-done ]]; then
    line="$(grep -m1 -E '^- Template:' AGENTS.md 2>/dev/null | tr -d '\r' || true)"
    [[ -n "$line" ]] || return 0
    rest="${line#- Template:}"
    set -- $rest
    [[ $# -eq 2 ]] || return 0
    url="$1"; ref="$2"
    last="$(grep -E '^template-sync: ' docs/lessons/MAINTENANCE.log 2>/dev/null | tail -n 1 || true)"
    [[ -n "$last" ]] || return 0
    last="$(printf '%s\n' "$last" | awk '{print $2}' || true)"
    [[ -n "$last" ]] || return 0

    dir=".work/template-sync"
    cache="$dir/latest-tag"
    if [[ ! -f "$cache" ]] || [[ -n "$(find "$cache" -mmin +1440 2>/dev/null || true)" ]]; then
      mkdir -p "$dir" 2>/dev/null || true
      tmp="$dir/latest-tag.tmp.$$"
      # A SessionStart hook must not wait on the network, so the refresh runs
      # detached and lands in the cache for the next session. Tests set
      # TEMPLATE_UPDATE_SYNC=1 to run it in the foreground and avoid races.
      if [[ "${TEMPLATE_UPDATE_SYNC:-0}" == "1" ]]; then
        { bash scripts/template-sync.sh --latest-tag >"$tmp" 2>/dev/null && [[ -s "$tmp" ]] && mv -f "$tmp" "$cache"; } || rm -f "$tmp" 2>/dev/null || true
      else
        nohup bash -c 'bash scripts/template-sync.sh --latest-tag >"$1" 2>/dev/null && [ -s "$1" ] && mv -f "$1" "$2" || rm -f "$1"' _ "$tmp" "$cache" >/dev/null 2>&1 &
      fi
    fi

    tag="$(head -n 1 "$cache" 2>/dev/null | tr -d '\r' || true)"
    [[ -n "$tag" ]] || return 0
    [[ "$last" != "$tag" ]] || return 0
    if [[ "$last" != template-v* ]]; then
      echo "[session-context] Template update available: $tag (synced $last). Run /template-update."
      return 0
    fi
    lowest="$(printf '%s\n%s\n' "$last" "$tag" | sort -V | head -n 1 || true)"
    if [[ "$lowest" == "$last" ]]; then
      echo "[session-context] Template update available: $tag (synced $last). Run /template-update."
    fi
  else
    newest="$(git tag -l 'template-v*' 2>/dev/null | sort -V | tail -n 1 || true)"
    [[ -n "$newest" ]] || return 0
    # Only core and catalog paths count: lesson data and AGENTS.md Project
    # decisions change in every project and are not a release trigger.
    paths="$(bash scripts/template-sync.sh --list-set 2>/dev/null | awk '$1 == "core" || $1 == "catalog" {print $2}' || true)"
    n=0
    if [[ -n "$paths" ]]; then
      local args=()
      while IFS= read -r p; do
        [[ -n "$p" ]] && args+=("$p")
      done <<< "$paths"
      n="$(git rev-list --count "$newest..HEAD" -- "${args[@]}" 2>/dev/null || true)"
      [[ "$n" =~ ^[0-9]+$ ]] || n=0
    fi
    # AGENTS.md syncs only its kernel block and rules index; compare those.
    local differs=0 old_md new_md
    old_md="$(git show "$newest:AGENTS.md" 2>/dev/null | tr -d '\r' || true)"
    new_md="$(git show HEAD:AGENTS.md 2>/dev/null | tr -d '\r' || true)"
    if [[ -n "$old_md" && -n "$new_md" ]]; then
      if [[ "$(printf '%s\n' "$old_md" | agents_synced_sections)" != "$(printf '%s\n' "$new_md" | agents_synced_sections)" ]]; then
        differs=1
      fi
    fi
    if (( n > 0 || differs == 1 )); then
      rest="[session-context] Template release pending: $n synced-set commits since $newest. Cut one with scripts/template-release.sh."
      if (( differs == 1 )); then rest="$rest The kernel or rules index changed."; fi
      echo "$rest"
    fi
  fi
  return 0
}
if [[ "${TEMPLATE_UPDATE_CHECK:-1}" != "0" ]]; then
  template_update_block || true
fi
