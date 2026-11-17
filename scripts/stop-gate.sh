#!/usr/bin/env bash
# stop-gate.sh - Stop hook body (Claude Code; Codex runs it too through
# .codex/hooks.json): the agent cannot end a turn on a broken task state, and
# cannot call a task finished while the quick gate is red. Mechanizes part of
# kernel rule 5 ("done is layered"); other harnesses keep the prose rule and
# the ship procedure.
# Input: the Stop hook payload (JSON) on stdin.
# Behaviour, in order:
#   1. "stop_hook_active": true (this turn already continued once because of a
#      Stop hook) -> allow, so a red state that is intended (a failing test
#      written first, a question for the human) never loops.
#   2. No live task (.work/TASK.md missing or still the pristine template with
#      {{title}}): the work is done. When scripts/dream.sh says a dream is
#      due and records the offer ("due --offer", at most once a day for the
#      same state), block once so Claude asks the human whether to start
#      dreaming (docs/procedures/dream.md); otherwise allow.
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
# The quick gate runs detached (see the comment above its launch): this hook
# never waits for it, and a failed run blocks a later stop once.
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
# No live task: offer a dream when one is due, then allow.
offer_dream() {
  local msg
  [[ -f scripts/dream.sh ]] || exit 0
  msg="$(bash scripts/dream.sh due --offer 2>/dev/null)" || exit 0
  msg="${msg#dream: due (}"
  msg="${msg%)}"
  {
    echo "stop-gate: work is done and a dream is due (${msg})."
    echo "Ask the user: \"Start dreaming?\" (docs/procedures/dream.md). If they decline, stop; it is not offered again today."
  } >&2
  exit 2
}
[[ -f "$TASK" ]] || offer_dream
grep -q '{{title}}' "$TASK" && offer_dream

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

# The quick gate can take many minutes. A Stop hook that waits for it holds the
# chat in "processing" and queues the user's next message, so the gate runs
# detached and a later stop reads its result:
#   stop-gate.result   "<tree key> <exit code>" of the last finished run
#   stop-gate.running  "<pid> <start epoch>" while a run is going
#   stop-gate.log      output of the last run
JOBS=".work/jobs"
RES="$JOBS/stop-gate.result"
RUN="$JOBS/stop-gate.running"
LOG="$JOBS/stop-gate.log"
mkdir -p "$JOBS"

if [[ -f "$RES" ]]; then
  rkey="" rrc=""
  read -r rkey rrc < "$RES" || true
  if [[ "$rrc" == "0" ]]; then
    if [[ -n "$key" && "$rkey" == "$key" ]]; then
      printf '%s\n' "$key" > "$GREEN"
      rm -f "$RES"
      exit 0
    fi
    rm -f "$RES"   # passed, but for an older tree: run again below
  else
    # A failed run is reported once, even if the tree has moved on since.
    mv -f "$RES" "$RES.reported"
    block "every acceptance criterion is ticked but scripts/quickgate.sh failed (exit ${rrc:-?}) in the background run" "$(tail -n 40 "$LOG" 2>/dev/null)"
  fi
fi

if [[ -f "$RUN" ]]; then
  rpid="" rstart=0
  read -r rpid rstart < "$RUN" || true
  if [[ -n "$rpid" ]] && kill -0 "$rpid" 2>/dev/null && (( $(date +%s) - ${rstart:-0} < 3600 )); then
    exit 0   # a run is still going: let the turn end
  fi
  rm -f "$RUN"
fi

[[ -n "$key" ]] || exit 0
(
  rc=0
  bash scripts/quickgate.sh > "$LOG" 2>&1 || rc=$?
  printf '%s %s\n' "$key" "$rc" > "$RES"
  rm -f "$RUN"
) < /dev/null > /dev/null 2>&1 &
printf '%s %s\n' "$!" "$(date +%s)" > "$RUN"
disown 2>/dev/null || true
exit 0
