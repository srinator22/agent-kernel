#!/usr/bin/env bash
# stop-gate.sh - Claude Code Stop hook body: the agent cannot end a turn on a
# broken task state, and cannot call a task finished while the quick gate is
# red. Mechanizes part of kernel rule 5 ("done is layered") for Claude Code;
# other harnesses keep the prose rule and the ship procedure.
# Input: the Stop hook payload (JSON) on stdin.
# Behaviour, in order:
#   1. "stop_hook_active": true (this turn already continued once because of a
#      Stop hook) -> allow, so a red state that is intended (a failing test
#      written first, a question for the human) never loops.
#   2. No live task (.work/TASK.md missing or still the pristine template with
#      {{title}}) -> allow.
#   3. Fast task-state checks on every stop: scripts/taskgraph.sh check and
#      scripts/tasklint.sh check (each skipped when the script is absent).
#      Any failure -> block.
#   4. Only when every acceptance criterion is ticked (the task claims to be
#      finished): scripts/quickgate.sh. The full quick lane runs minutes in a
#      repository with template self-tests, too slow for every turn end, so it
#      runs at the claimed finish only, and a green run is cached against the
#      exact working-tree state (a git tree id that includes untracked files)
#      in .work/jobs/stop-gate.green. No quick lane wired (no --quick in
#      scripts/check.sh, quickgate's own test) -> allow without running it.
#      Any nonzero exit of a wired lane -> block with the tail of its output;
#      exit 2 is not trusted to mean "not wired", because a wired stack step
#      (make, pytest) can exit 2 on a real failure.
# Exit: 0 allow; 2 block, with the reason on stderr (Claude reads it and keeps
# working). The hook's timeout is set in .claude/settings.json; a timed-out
# hook renders no decision, so the stop is allowed (VERIFY 2026-10-29,
# code.claude.com/docs/en/hooks.md).
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 0
TASK=".work/TASK.md"
GREEN=".work/jobs/stop-gate.green"

block() { # what output
  {
    echo "stop-gate: $1 while the task in $TASK is in progress."
    printf '%s\n' "$2" | tail -n 40
    echo "Fix it before ending the turn. If the red state is intended (a failing test written first, a question for the human), say so in your reply and stop again; this gate does not block twice in a row."
  } >&2
  exit 2
}

payload="$(cat)"
if [[ "$payload" =~ \"stop_hook_active\"[[:space:]]*:[[:space:]]*true ]]; then
  exit 0
fi
[[ -f "$TASK" ]] || exit 0
grep -q '{{title}}' "$TASK" && exit 0

out=""
failed=0
for s in taskgraph tasklint; do
  [[ -f "scripts/$s.sh" ]] || continue
  o="$(bash "scripts/$s.sh" check 2>&1)" || { failed=1; out+="$o"$'\n'; }
done
(( failed )) && block "the task-state checks failed" "$out"

# Count ticked and unticked criteria in the Acceptance criteria section,
# ignoring HTML comments (the template's example lines live in comments).
read -r ticked unticked < <(awk '
  { sub(/\r$/, "") }
  incomment { if ($0 ~ /-->/) incomment = 0; next }
  /<!--/ { if ($0 !~ /-->/) incomment = 1; next }
  /^## / { insec = ($0 ~ /^## Acceptance criteria[ \t]*$/); next }
  insec && /^[ \t]*- \[[xX]\]/ { t++ }
  insec && /^[ \t]*- \[ \]/ { u++ }
  END { print t + 0, u + 0 }' "$TASK")
(( ticked > 0 && unticked == 0 )) || exit 0
[[ -f scripts/quickgate.sh ]] || exit 0
[[ -f scripts/check.sh ]] && grep -q -e '--quick' scripts/check.sh || exit 0

# Tree id of the whole working tree, untracked files included, through a
# throwaway index so the real index is never touched.
tree_key() {
  local idx
  idx="$(mktemp)" || return 1
  rm -f "$idx"
  GIT_INDEX_FILE="$idx" git add -A . >/dev/null 2>&1 && GIT_INDEX_FILE="$idx" git write-tree 2>/dev/null
  local rc=$?
  rm -f "$idx"
  return $rc
}

key="$(tree_key)" || key=""
if [[ -n "$key" && -f "$GREEN" && "$(cat "$GREEN")" == "$key" ]]; then
  exit 0
fi

rc=0
qout="$(bash scripts/quickgate.sh 2>&1)" || rc=$?
case "$rc" in
  0)
    if [[ -n "$key" ]]; then mkdir -p .work/jobs && printf '%s\n' "$key" > "$GREEN"; fi
    exit 0
    ;;
  *) block "every acceptance criterion is ticked but scripts/quickgate.sh failed (exit $rc)" "$qout" ;;
esac
