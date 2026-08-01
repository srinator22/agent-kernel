#!/usr/bin/env bash
# bg.sh - minimal background-job wrapper for long work. Jobs MUST checkpoint
# their own progress after every small unit so a kill resumes exactly where it
# stopped; this wrapper only supervises (log, pidfile, exit marker). See
# docs/procedures/longjob.md for the STATE-file protocol that goes with it.
# Usage:
#   scripts/bg.sh start <name> -- <command...>
#   scripts/bg.sh status [name]
#   scripts/bg.sh tail <name> [lines]
#   scripts/bg.sh stop <name>
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JOBS="$ROOT/.work/jobs"
mkdir -p "$JOBS"

usage() {
  sed -n '6,10p' "${BASH_SOURCE[0]}" | sed 's/^# //' >&2
}

cmd="${1:-}"
shift || true

case "$cmd" in
  start)
    NAME="${1:?usage: bg.sh start <name> -- <command...>}"
    shift
    [[ "${1:-}" == "--" ]] || { echo "ERROR: separate name and command with --" >&2; exit 2; }
    shift
    if (( $# == 0 )); then echo "ERROR: no command given" >&2; exit 2; fi
    LOG="$JOBS/$NAME.log"; PIDF="$JOBS/$NAME.pid"; MARKER="$JOBS/$NAME.exit"
    if [[ -f "$PIDF" ]] && kill -0 "$(cat "$PIDF")" 2>/dev/null; then
      echo "ERROR: job $NAME is already running (pid $(cat "$PIDF"))" >&2
      exit 1
    fi
    rm -f "$MARKER"
    printf 'started_at=%s\ncommand=%s\n' "$(date -u +%FT%TZ)" "$*" > "$JOBS/$NAME.meta"
    MARKER="$MARKER" nohup bash -c \
      'set +e; "$@"; code=$?; printf "exit_code=%s\nfinished_at=%s\n" "$code" "$(date -u +%FT%TZ)" > "$MARKER"; exit "$code"' \
      bash "$@" >> "$LOG" 2>&1 &
    echo "$!" > "$PIDF"
    echo "bg: started $NAME (pid $(cat "$PIDF")); log: $LOG"
    ;;
  status)
    shopt -s nullglob
    if [[ -n "${1:-}" ]]; then metas=("$JOBS/$1.meta"); else metas=("$JOBS"/*.meta); fi
    if (( ${#metas[@]} == 0 )); then echo "bg: no jobs"; exit 0; fi
    for meta in "${metas[@]}"; do
      name="$(basename "$meta" .meta)"
      if [[ ! -f "$meta" ]]; then echo "bg: no such job: $name"; continue; fi
      if [[ -f "$JOBS/$name.exit" ]]; then
        echo "$name: FINISHED ($(tr '\n' ' ' < "$JOBS/$name.exit"))"
      elif [[ -f "$JOBS/$name.pid" ]] && kill -0 "$(cat "$JOBS/$name.pid")" 2>/dev/null; then
        echo "$name: RUNNING (pid $(cat "$JOBS/$name.pid"))"
      else
        echo "$name: DEAD without an exit marker - inspect $JOBS/$name.log"
      fi
    done
    ;;
  tail)
    NAME="${1:?usage: bg.sh tail <name> [lines]}"
    LINES="${2:-50}"
    if [[ ! -f "$JOBS/$NAME.log" ]]; then echo "ERROR: no log for $NAME" >&2; exit 1; fi
    tail -n "$LINES" "$JOBS/$NAME.log"
    ;;
  stop)
    NAME="${1:?usage: bg.sh stop <name>}"
    PIDF="$JOBS/$NAME.pid"
    if [[ ! -f "$PIDF" ]]; then echo "ERROR: no pidfile for $NAME" >&2; exit 1; fi
    pid="$(cat "$PIDF")"
    if kill -0 "$pid" 2>/dev/null; then
      kill "$pid"
      echo "bg: sent TERM to $NAME (pid $pid). A checkpointed job resumes where it stopped when restarted."
    else
      echo "bg: $NAME (pid $pid) is not running"
    fi
    ;;
  *)
    usage
    exit 2
    ;;
esac
