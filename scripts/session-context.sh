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

if [[ -f .work/TASK.md ]] && ! grep -q '{{title}}' .work/TASK.md; then
  echo "[session-context] In-progress task state (.work/TASK.md):"
  cat .work/TASK.md
fi
