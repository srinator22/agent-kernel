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
