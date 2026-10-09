#!/usr/bin/env bash
# taskgraph.sh - validates and queries the task graph in .work/TASK.md (kernel
# rule 16; docs/rules/orchestration.md). The Plan section holds a table:
#   | node | depends on | owner files | worker tier | status |
# Usage:
#   scripts/taskgraph.sh check              validate (exit 1 on any problem)
#   scripts/taskgraph.sh ready              todo nodes whose dependencies are all done
#   scripts/taskgraph.sh waves              topological waves (nodes that may run together)
#   scripts/taskgraph.sh set <node> <status>   edit one status cell
# Set TASKGRAPH_FILE to read another file (default .work/TASK.md).
#
# Conventions the parser accepts:
#   node          first word is the id ("G1 profiles" -> G1)
#   depends on    ids separated by commas, or "-" for none
#   owner files   paths separated by "," or ";". A wildcard path is compared by
#                 its directory prefix ("docs/profiles/**" owns docs/profiles).
#                 A bare file name inherits the directory of the path before it
#                 in the same ";" group ("docs/rules/a.md, b.md" -> docs/rules/b.md);
#                 only the first word of an item is the path, so trailing prose
#                 is ignored. Write full paths when in doubt.
#   worker tier   cheap|standard|strong|inherit|advisor|reviewer, or a "then" sequence
#                 of them ("reviewer then advisor")
#   status        todo|doing|done|blocked
# A row whose node cell starts with "{{" is the unfilled template row of the
# blueprint and is skipped.
# Two nodes where neither depends on the other (directly or transitively) must
# not own overlapping paths. A Plan without the table (the old flat numbered
# list) passes check with a note so old tasks keep working.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
FILE="${TASKGRAPH_FILE:-.work/TASK.md}"

usage() {
  echo "usage: scripts/taskgraph.sh check | ready | waves | set <node> <todo|doing|done|blocked>" >&2
  exit 2
}

# Shared awk: parse the table, then act according to mode. Output lines:
#   NOTABLE            no task-graph table in the Plan section
#   SERR: <msg>        structural error (parse, duplicate, unknown dependency, cycle)
#   RERR: <msg>        rule error (tier, status, overlapping owner files)
#   READY: <node>      (mode ready)   WAVE: <n> <ids>   (mode waves)   SUMMARY: <nodes> <waves>
analyze() {
  awk -v mode="$1" '
function trim(s) { sub(/^[ \t\r]+/, "", s); sub(/[ \t\r]+$/, "", s); return s }
function firsttok(s) { s = trim(s); sub(/[ \t].*$/, "", s); return s }
function inset(v, list,   a, k, m) {
  m = split(list, a, " ")
  for (k = 1; k <= m; k++) if (a[k] == v) return 1
  return 0
}
function normalize(p,   pre) {
  gsub(/`/, "", p)
  sub(/^\.\//, "", p)
  if (match(p, /[*?\[]/)) {
    pre = substr(p, 1, RSTART - 1)
    sub(/[^\/]*$/, "", pre)
    p = pre
  }
  sub(/\/+$/, "", p)
  return p
}
function overlap(a, b) {
  if (a == "" || b == "") return 1
  if (a == b) return 1
  if (index(a, b "/") == 1) return 1
  if (index(b, a "/") == 1) return 1
  return 0
}
function addowner(i, p) { no[i]++; own[i, no[i]] = p }
BEGIN { n = 0; hdr = 0; tdone = 0; inplan = 0; nstruct = 0; ntpl = 0 }
{ sub(/\r$/, "") }
/^## / { inplan = ($0 ~ /^## Plan[ \t]*$/); next }
inplan && !tdone && /^[ \t]*\|/ {
  line = trim($0); sub(/^\|/, "", line); sub(/\|$/, "", line)
  nc = split(line, c, "|")
  for (i = 1; i <= nc; i++) c[i] = trim(c[i])
  if (!hdr) {
    if (nc == 5 && tolower(c[1]) == "node" && tolower(c[2]) == "depends on" && \
        tolower(c[3]) == "owner files" && tolower(c[4]) == "worker tier" && tolower(c[5]) == "status") hdr = 1
    next
  }
  sep = 1
  for (i = 1; i <= nc; i++) if (c[i] !~ /^:?-+:?$/) sep = 0
  if (sep) next
  if (c[1] ~ /^\{\{/) { ntpl++; next }
  if (nc != 5) { print "SERR: line " NR ": row has " nc " cells, expected 5"; nstruct++; next }
  id = firsttok(c[1])
  if (id == "") { print "SERR: line " NR ": empty node id"; nstruct++; next }
  if (id in idx) { print "SERR: line " NR ": duplicate node " id; nstruct++; next }
  n++; idx[id] = n; ids[n] = id; label[n] = c[1]; stat[n] = tolower(c[5]); tier[n] = c[4]
  nd[n] = 0
  m = split(c[2], dp, ",")
  for (j = 1; j <= m; j++) {
    t = firsttok(dp[j])
    if (t == "" || t == "-" || tolower(t) == "none") continue
    nd[n]++; dep[n, nd[n]] = t
  }
  m = split(c[3], grp, ";")
  for (g = 1; g <= m; g++) {
    k = split(grp[g], it, ","); prevdir = ""
    for (q = 1; q <= k; q++) {
      tok = firsttok(it[q]); gsub(/`/, "", tok)
      if (tok == "" || tok == "-") continue
      sub(/^\.\//, "", tok)
      wild = (tok ~ /[*?\[]/)
      if (index(tok, "/") == 0 && !wild && prevdir != "") tok = prevdir "/" tok
      if (index(tok, "/") > 0 && !wild) { prevdir = tok; sub(/\/[^\/]*$/, "", prevdir) }
      else if (wild) prevdir = ""
      addowner(n, normalize(tok))
    }
  }
  next
}
inplan && hdr && !/^[ \t]*\|/ { tdone = 1 }
END {
  if (!hdr) { print "NOTABLE"; exit 0 }
  if (n == 0 && ntpl > 0) { print "SUMMARY: 0 0"; exit 0 }
  if (n == 0) { print "SERR: the task-graph table has no rows"; exit 0 }
  # unknown dependencies and direct reachability
  for (i = 1; i <= n; i++) for (m = 1; m <= nd[i]; m++) {
    d = dep[i, m]
    if (!(d in idx)) { print "SERR: node " ids[i] " depends on unknown node " d; continue }
    reach[i, idx[d]] = 1
  }
  for (k = 1; k <= n; k++) for (i = 1; i <= n; i++) if (reach[i, k]) for (j = 1; j <= n; j++)
    if (reach[k, j]) reach[i, j] = 1
  cyc = 0
  for (i = 1; i <= n; i++) if (reach[i, i]) { print "SERR: dependency cycle involving node " ids[i]; cyc = 1 }
  # rule errors
  for (i = 1; i <= n; i++) {
    if (!inset(stat[i], "todo doing done blocked"))
      print "RERR: node " ids[i] " has status \"" stat[i] "\"; use todo, doing, done or blocked"
    t = tolower(tier[i]); gsub(/ then |\/|,/, ",", t)
    m = split(t, tp, ",")
    for (j = 1; j <= m; j++) {
      x = trim(tp[j])
      if (!inset(x, "cheap standard strong inherit advisor reviewer"))
        print "RERR: node " ids[i] " has worker tier \"" tier[i] "\"; use cheap, standard, strong, inherit, advisor or reviewer"
    }
  }
  for (i = 1; i <= n; i++) for (j = i + 1; j <= n; j++) {
    if (reach[i, j] || reach[j, i]) continue
    for (a = 1; a <= no[i]; a++) for (b = 1; b <= no[j]; b++)
      if (overlap(own[i, a], own[j, b]))
        print "RERR: nodes " ids[i] " and " ids[j] " can run in the same wave but both own " \
              (own[i, a] == "" ? "(everything)" : own[i, a]) " and " (own[j, b] == "" ? "(everything)" : own[j, b])
  }
  # waves (only on an acyclic, fully resolved graph)
  nw = 0
  if (!cyc) {
    left = n
    while (left > 0) {
      cnt = 0
      for (i = 1; i <= n; i++) {
        if (wave[i]) continue
        ok = 1
        for (m = 1; m <= nd[i]; m++) {
          if (!(dep[i, m] in idx)) continue
          w = wave[idx[dep[i, m]]]
          if (!w || w > nw) { ok = 0; break }
        }
        if (ok) { pick[++cnt] = i }
      }
      if (cnt == 0) break
      nw++
      s = ""
      for (c2 = 1; c2 <= cnt; c2++) { wave[pick[c2]] = nw; s = s (s == "" ? "" : " ") ids[pick[c2]] }
      wlist[nw] = s
      left -= cnt
    }
  }
  if (mode == "waves") for (w = 1; w <= nw; w++) print "WAVE: " w " " wlist[w]
  if (mode == "ready") for (i = 1; i <= n; i++) {
    if (stat[i] != "todo") continue
    ok = 1
    for (m = 1; m <= nd[i]; m++) {
      d = dep[i, m]
      if (!(d in idx) || stat[idx[d]] != "done") { ok = 0; break }
    }
    if (ok) print "READY: " label[i]
  }
  print "SUMMARY: " n " " nw
}' "$FILE"
}

cmd_check() {
  local out line serr=0 rerr=0 summary=""
  out="$(analyze check)"
  if [[ "$out" == "NOTABLE" ]]; then
    echo "taskgraph: no task-graph table in the Plan of $FILE (flat plan); nothing to check"
    return 0
  fi
  while IFS= read -r line; do
    case "$line" in
      SERR:*) echo "taskgraph: ${line#SERR: }" >&2; serr=$((serr + 1)) ;;
      RERR:*) echo "taskgraph: ${line#RERR: }" >&2; rerr=$((rerr + 1)) ;;
      SUMMARY:*) summary="${line#SUMMARY: }" ;;
    esac
  done <<< "$out"
  if (( serr + rerr > 0 )); then
    echo "taskgraph: check FAILED ($((serr + rerr)) problem(s))" >&2
    exit 1
  fi
  set -- $summary
  echo "taskgraph: OK ($1 nodes, $2 waves)"
}

# ready and waves fail only on structural errors; rule errors belong to check.
cmd_list() {
  local mode="$1" out line serr=0
  out="$(analyze "$mode")"
  if [[ "$out" == "NOTABLE" ]]; then
    echo "taskgraph: no task-graph table in the Plan of $FILE; '$mode' needs one" >&2
    exit 1
  fi
  while IFS= read -r line; do
    case "$line" in
      SERR:*) echo "taskgraph: ${line#SERR: }" >&2; serr=$((serr + 1)) ;;
    esac
  done <<< "$out"
  (( serr == 0 )) || exit 1
  while IFS= read -r line; do
    case "$line" in
      READY:*) echo "${line#READY: }" ;;
      WAVE:*) line="${line#WAVE: }"; echo "wave ${line%% *}: ${line#* }" ;;
    esac
  done <<< "$out"
}

cmd_set() {
  local node="${1:-}" status="${2:-}" tmp rc=0
  [[ -n "$node" && -n "$status" ]] || usage
  case "$status" in
    todo|doing|done|blocked) ;;
    *) echo "taskgraph: status must be todo, doing, done or blocked" >&2; exit 2 ;;
  esac
  tmp="$(mktemp)"
  awk -v node="$node" -v st="$status" '
function trim(s) { sub(/^[ \t\r]+/, "", s); sub(/[ \t\r]+$/, "", s); return s }
function firsttok(s) { s = trim(s); sub(/[ \t].*$/, "", s); return s }
BEGIN { hdr = 0; tdone = 0; inplan = 0; found = 0 }
/^## / { inplan = ($0 ~ /^## Plan[ \t\r]*$/) }
inplan && !tdone && /^[ \t]*\|/ {
  line = trim($0); sub(/\r$/, "", line); sub(/^\|/, "", line); sub(/\|$/, "", line)
  nc = split(line, c, "|")
  for (i = 1; i <= nc; i++) c[i] = trim(c[i])
  if (!hdr) {
    if (nc == 5 && tolower(c[1]) == "node" && tolower(c[2]) == "depends on" && \
        tolower(c[3]) == "owner files" && tolower(c[4]) == "worker tier" && tolower(c[5]) == "status") hdr = 1
    print; next
  }
  if (nc == 5 && firsttok(c[1]) == node && !found) {
    nr = split($0, r, "|")
    if (nr >= 6) {
      r[6] = " " st " "
      out = r[1]
      for (i = 2; i <= nr; i++) out = out "|" r[i]
      print out; found = 1; next
    }
  }
  print; next
}
inplan && hdr && !/^[ \t]*\|/ { tdone = 1 }
{ print }
END { if (!found) exit 3 }' "$FILE" > "$tmp" || rc=$?
  if (( rc == 3 )); then
    rm -f "$tmp"
    echo "taskgraph: node $node not found in the task-graph table of $FILE" >&2
    exit 1
  elif (( rc != 0 )); then
    rm -f "$tmp"
    exit "$rc"
  fi
  cat "$tmp" > "$FILE"
  rm -f "$tmp"
  echo "taskgraph: $node -> $status"
}

case "${1:-}" in
  check|ready|waves|set) [[ -f "$FILE" ]] || { echo "taskgraph: $FILE not found" >&2; exit 1; } ;;
esac

case "${1:-}" in
  check) cmd_check ;;
  ready) cmd_list ready ;;
  waves) cmd_list waves ;;
  set) shift; cmd_set "$@" ;;
  *) usage ;;
esac
