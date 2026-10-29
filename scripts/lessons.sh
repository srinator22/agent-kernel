#!/usr/bin/env bash
# lessons.sh - mechanizes the lesson caps and the forgetting rules (kernel
# rules 8, 9, 10; docs/procedures/maintain.md).
#   check          exit 1 on any cap or format violation (see below)
#   use <Lnnn>     increment used: and set last: to today for one lesson
#   expire         list lessons whose last: is older than 45 days or whose
#                  retire-when contains [met]; --apply archives them
#   stats          print counts
#
# INDEX.md line format (exactly as documented in docs/lessons/INDEX.md):
#   - [L001] <description> - <lesson> (used: 0, last: -, retire-when: <condition>)
# last: is YYYY-MM-DD or "-". A lesson with last: "-" has no age and never
# expires by age; set last: to the approval date when approving a lesson if you
# want the 45-day clock to run. Lines inside code fences and the documented
# format placeholder (description starting with "<") are not lessons.
#
# check enforces: <= 20 approved lessons; every one carries all three fields
# and a unique id; every PENDING.md entry carries its four fields; no
# QUARANTINE.md entry older than 30 days without an owner task; .claude/skills
# and .agents/skills identical; skill directories <= 8 + profile skill sets
# (the number of skills listed on the "Skills:" or "- Skills:" line of each
# docs/profiles/*/PROFILE.md, comma-separated; when AGENTS.md has a
# "- Profiles:" line naming profiles, only those count);
# every .claude/agents/<name>.md has a .codex/agents/<name>.toml or a line in
# docs/rules/models.md naming it with "no Codex counterpart"; the agent and
# skill sets under docs/profiles/*/, docs/library/ and docs/roster/ are well formed, and each
# profile's Skills: names equal its skills/ folders (shipped_set_errors);
# every docs/rules/*.md <= 40 lines; tests/quarantine.list entries (lines
# "<test path> # owner: <task> date: YYYY-MM-DD") carry an owner and a date and
# are at most 30 days old. Entries whose fields are all empty are the
# documented format placeholder and are ignored.
#
# Test hook: LESSONS_TODAY=YYYY-MM-DD overrides today's date.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

INDEX="docs/lessons/INDEX.md"
PENDING="docs/lessons/PENDING.md"
QUARANTINE="docs/lessons/QUARANTINE.md"
LOG="docs/lessons/MAINTENANCE.log"
MAX_LESSONS=20
MAX_RULE_LINES=40
EXPIRE_DAYS=45
QUARANTINE_DAYS=30
BASE_SKILLS=8
US=$'\037'

usage() {
  echo "usage: scripts/lessons.sh check | use <Lnnn> | expire [--apply] | stats" >&2
  exit 2
}

today() { echo "${LESSONS_TODAY:-$(date -u +%F)}"; }

valid_date() {
  [[ "$1" =~ ^([0-9]{4})-([0-9]{2})-([0-9]{2})$ ]] || return 1
  local m=$((10#${BASH_REMATCH[2]})) d=$((10#${BASH_REMATCH[3]}))
  (( m >= 1 && m <= 12 && d >= 1 && d <= 31 ))
}

# Days since 1970-01-01 for YYYY-MM-DD (civil-from-days algorithm; no GNU date).
day_number() {
  [[ "$1" =~ ^([0-9]{4})-([0-9]{2})-([0-9]{2})$ ]] || { echo 0; return; }
  local y=$((10#${BASH_REMATCH[1]})) m=$((10#${BASH_REMATCH[2]})) d=$((10#${BASH_REMATCH[3]}))
  local era yoe doy doe
  if (( m <= 2 )); then y=$((y - 1)); fi
  era=$(( (y >= 0 ? y : y - 399) / 400 ))
  yoe=$(( y - era * 400 ))
  doy=$(( (153 * (m > 2 ? m - 3 : m + 9) + 2) / 5 + d - 1 ))
  doe=$(( yoe * 365 + yoe / 4 - yoe / 100 + doy ))
  echo $(( era * 146097 + doe - 719468 ))
}

# Approved lesson lines as "lineno<US>line", skipping fenced blocks and the
# documented placeholder entry.
approved_lines() {
  [[ -f "$INDEX" ]] || return 0
  awk -v US="$US" '
    { sub(/\r$/, "") }
    /^```/ { fence = !fence; next }
    fence { next }
    /^- \[L[0-9]+\] / {
      rest = $0; sub(/^- \[L[0-9]+\] /, "", rest)
      if (rest ~ /^</) next
      printf "%d%s%s\n", NR, US, $0
    }' "$INDEX"
}

FIELD_RE='^-[[:space:]]\[(L[0-9]+)\][[:space:]](.*)\(used:[[:space:]]([0-9]+),[[:space:]]last:[[:space:]]([0-9]{4}-[0-9]{2}-[0-9]{2}|-),[[:space:]]retire-when:[[:space:]](.+)\)[[:space:]]*$'

# Entry blocks of PENDING/QUARANTINE: one line per entry,
# "start<US>p1<US>v1<US>p2<US>v2..." where p is 1 when the label is present.
# $1 = file, $2 = labels joined by "|"; the first label opens an entry.
entries() {
  local file="$1" labels="$2"
  [[ -f "$file" ]] || return 0
  awk -v US="$US" -v labels="$labels" '
    function flush(   i, s) {
      if (!open) return
      s = start
      for (i = 1; i <= n; i++) s = s US pres[i] US val[i]
      print s
      open = 0
    }
    BEGIN { n = split(labels, lab, "|") }
    { sub(/\r$/, "") }
    {
      hit = 0
      for (i = 1; i <= n; i++) {
        if ($0 ~ ("^- " lab[i] "( \\([^)]*\\))?:")) { hit = i; break }
      }
      if (hit) {
        if (hit == 1) flush()
        if (!open) {
          open = 1; start = NR
          for (i = 1; i <= n; i++) { pres[i] = 0; val[i] = "" }
        }
        v = $0; sub(/^- [^:]*:[ \t]*/, "", v); sub(/[ \t]+$/, "", v)
        pres[hit] = 1; val[hit] = v; cur = hit
        next
      }
      if (open && cur && $0 ~ /^[ \t]+[^ \t]/) {
        v = $0; sub(/^[ \t]+/, "", v); sub(/[ \t]+$/, "", v)
        val[cur] = (val[cur] == "" ? v : val[cur] " " v)
        next
      }
      cur = 0
    }
    END { flush() }' "$file"
}

PENDING_LABELS="what happened|what check should have caught it|what was added|retire-when"
QUARANTINE_LABELS="test path|observed flake behavior|date quarantined|owner task"

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

# The Skills: value of a profile, "Skills:" or "- Skills:" at line start. A value
# that ends in a comma continues on the next line.
profile_skills_value() {
  awk '
    { sub(/\r$/, "") }
    !found && /^(- )?Skills:/ { found = 1; v = $0; sub(/^(- )?Skills:[ \t]*/, "", v); next }
    found && v ~ /,[ \t]*$/ { t = $0; sub(/^[ \t]+/, "", t); v = v " " t; next }
    found { exit }
    END { if (found) print v }' "$1"
}

# Skill names one profile declares, one per line: the comma-separated names in
# its Skills: value ("none", "-", "n/a" and the "the core set" wording of the
# software profile declare none). Parentheticals, backticks and trailing
# sentence punctuation are dropped; only tokens shaped like a skill name count.
profile_skill_names() {
  local value lower item
  value="$(profile_skills_value "$1")"
  [[ -n "$value" ]] || return 0
  lower="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//')"
  if [[ "$lower" =~ ^(none|-|n/a)([^a-z0-9]|$) ]]; then return 0; fi
  if [[ "$lower" =~ ^(the[[:space:]]+)?core([^a-z0-9]|$) ]]; then return 0; fi
  value="$(printf '%s' "$value" | sed -e 's/([^)]*)//g' -e 's/`//g' -e 's/[[:space:]]*[.;:][[:space:]]*$//')"
  local IFS=','
  for item in $value; do
    item="$(printf '%s' "$item" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    [[ "$item" =~ ^[a-z0-9][a-z0-9-]*$ ]] && echo "$item"
  done
  return 0
}

profile_skill_count() {
  local n
  n="$(profile_skill_names "$1" | grep -c . || true)"
  echo $((n + 0))
}

# frontmatter_field FILE KEY: the value of KEY: inside the leading --- block
# only (a body line that happens to read "name: x" does not count); CRLF-safe.
frontmatter_field() {
  awk -v key="$2" '
    { sub(/\r$/, "") }
    NR == 1 { if ($0 != "---") exit; next }
    $0 == "---" { exit }
    index($0, key ":") == 1 { v = substr($0, length(key) + 2); sub(/^[ \t]+/, "", v); print v; exit }' "$1"
}

# Printed last by shipped_set_errors; a caller that does not see it knows the
# function stopped early (it runs in a process substitution, whose failure
# would otherwise look like "no problems").
SHIPPED_DONE="shipped-set-check-complete"

# shipped_set_errors DIR [PROFILE.md]: one problem per line for the agents and
# skills a profile (or docs/library) ships for start to install, then the
# SHIPPED_DONE line. Every agents/<name>.md has frontmatter whose name: is
# <name>, a description:, and an agents/<name>.toml Codex twin; every .toml
# carries name, description and developer_instructions; every
# skills/<name>/SKILL.md has frontmatter whose name: is <name> and a
# description:. With a PROFILE.md, its Skills: names and the skills/ folders
# are the same set, so the cap of kernel rule 10 counts exactly what start
# installs.
shipped_set_errors() {
  local dir="$1" profile="${2:-}" f name declared shipped
  for f in "$dir"/agents/*.md "$dir"/skills/*/SKILL.md; do
    [[ -f "$f" ]] || continue
    if [[ "$f" == */SKILL.md ]]; then name="$(basename "$(dirname "$f")")"; else name="$(basename "$f" .md)"; fi
    if ! head -n 1 "$f" | tr -d '\r' | grep -qx -- '---'; then
      echo "$f: frontmatter must open with ---"
      continue
    fi
    [[ -n "$(frontmatter_field "$f" description)" ]] || echo "$f: frontmatter missing description"
    [[ "$(frontmatter_field "$f" name)" == "$name" ]] || echo "$f: frontmatter name: must be $name"
    if [[ "$f" != */SKILL.md && ! -f "$dir/agents/$name.toml" ]]; then
      echo "$f: no Codex twin $dir/agents/$name.toml"
    fi
  done
  for f in "$dir"/agents/*.toml; do
    [[ -f "$f" ]] || continue
    grep -q '^name = ' "$f" || echo "$f: missing name field"
    grep -q '^description = ' "$f" || echo "$f: missing description field"
    grep -q '^developer_instructions = ' "$f" || echo "$f: missing developer_instructions field"
  done
  for f in "$dir"/skills/*/; do
    [[ -d "$f" ]] || continue
    [[ -f "$f/SKILL.md" ]] || echo "${f%/}: skill folder has no SKILL.md"
  done
  if [[ "$dir" == docs/roster ]]; then
    roster_twin_errors "$dir"
    handoff_errors "$dir"
  fi
  if [[ -n "$profile" ]]; then
    declared="$(profile_skill_names "$profile" | sort -u)"
    # A missing skills/ folder must not end this function under set -e.
    shipped="$(for f in "$dir"/skills/*/; do if [[ -d "$f" ]]; then basename "$f"; fi; done | sort -u)"
    while IFS= read -r name; do
      [[ -n "$name" ]] || continue
      printf '%s\n' "$shipped" | grep -qx -- "$name" || echo "$profile: Skills: lists $name but $dir/skills/$name/SKILL.md does not exist"
    done <<< "$declared"
    while IFS= read -r name; do
      [[ -n "$name" ]] || continue
      printf '%s\n' "$declared" | grep -qx -- "$name" || echo "$dir/skills/$name ships but $profile does not list it on its Skills: line"
    done <<< "$shipped"
  fi
  echo "$SHIPPED_DONE"
}

# trim_blank_edges: drop leading and trailing blank lines and CRs from stdin.
trim_blank_edges() {
  awk '{ sub(/\r$/, ""); lines[NR] = $0 }
    END { s = 1; while (s <= NR && lines[s] ~ /^[ \t]*$/) s++
          e = NR; while (e >= s && lines[e] ~ /^[ \t]*$/) e--
          for (i = s; i <= e; i++) print lines[i] }'
}

# roster_twin_errors DIR: a roster agent's Codex developer_instructions is its
# .md body, unchanged except that a hard-rule line "- Read-only." may read
# "- Your sandbox is read-only." (Codex enforces it with sandbox_mode); both
# forms ship today. Twins drifted silently before this check existed.
roster_twin_errors() {
  local dir="$1" md toml
  for md in "$dir"/agents/*.md; do
    [[ -f "$md" ]] || continue
    toml="${md%.md}.toml"
    [[ -f "$toml" ]] || continue
    if ! diff -q \
      <(awk '{ sub(/\r$/, "") } NR == 1 && $0 == "---" { f = 1; next } f == 1 && $0 == "---" { f = 2; next } f == 2' "$md" \
          | trim_blank_edges) \
      <(awk '{ sub(/\r$/, "") } /^developer_instructions = """/ { f = 1; next } f && $0 == "\"\"\"" { exit } f' "$toml" \
          | sed 's/^- Your sandbox is read-only\./- Read-only./' | trim_blank_edges) \
      >/dev/null; then
      echo "$toml: developer_instructions differ from the body of $md (regenerate the twin from the .md)"
    fi
  done
}

# handoff_errors DIR: every backticked lowercase-hyphenated name in an agent's
# "## Hand-offs" section is an agent that ships in this template (core, library,
# profiles or roster), so a hand-off never points at a role that does not exist.
handoff_errors() {
  local dir="$1" md known name
  known="$(for f in .claude/agents/*.md .codex/agents/*.toml docs/library/agents/*.md docs/library/agents/*.toml docs/profiles/*/agents/*.md docs/roster/agents/*.md; do
    [[ -f "$f" ]] && basename "$f" | sed 's/\.[a-z]*$//'
  done | sort -u)"
  for md in "$dir"/agents/*.md; do
    [[ -f "$md" ]] || continue
    while IFS= read -r name; do
      [[ -n "$name" ]] || continue
      printf '%s\n' "$known" | grep -qx -- "$name" || echo "$md: Hand-offs names \`$name\`, which is not an agent in this template"
    done < <(awk '{ sub(/\r$/, "") } /^## / { f = ($0 == "## Hand-offs"); next } f' "$md" \
      | grep -o '`[a-z][a-z0-9]*\(-[a-z0-9]\+\)\+`' | tr -d '`' | sort -u)
  done
}

# shipped_set_check DIR [PROFILE.md]: problems from shipped_set_errors, plus one
# when the function did not run to completion.
shipped_set_check() {
  local out
  out="$(shipped_set_errors "$@" || true)"
  printf '%s\n' "$out" | grep -vx -- "$SHIPPED_DONE" | grep . || true
  printf '%s\n' "$out" | grep -qx -- "$SHIPPED_DONE" || echo "shipped-set check of $1 stopped before completing"
}

# Total profile skills over the adopted profiles (all profiles when AGENTS.md
# names none).
profile_skill_sets() {
  local adopted f name total=0 n
  adopted="$(adopted_profiles)"
  for f in docs/profiles/*/PROFILE.md; do
    [[ -f "$f" ]] || continue
    name="$(basename "$(dirname "$f")")"
    if [[ -n "$adopted" ]] && ! printf '%s\n' "$adopted" | grep -qx -- "$name"; then
      continue
    fi
    n="$(profile_skill_count "$f")"
    total=$((total + n))
  done
  echo "$total"
}

skill_dir_count() {
  [[ -d .claude/skills ]] || { echo 0; return; }
  local n
  n="$(find .claude/skills -mindepth 1 -maxdepth 1 -type d | wc -l)"
  echo $((n + 0))
}

file_lines() { awk 'END { print NR }' "$1"; }

# An entry is the documented placeholder when every label is present and every
# value is empty.
is_placeholder() { [[ "$1$3$5$7" == "1111" && -z "$2$4$6$8" ]]; }

cmd_check() {
  local errs=() approved_count=0 line lineno id seen=" "

  # Approved lessons: cap, fields, unique ids.
  while IFS="$US" read -r lineno line; do
    [[ -n "$lineno" ]] || continue
    approved_count=$((approved_count + 1))
    if [[ "$line" =~ $FIELD_RE ]]; then
      id="${BASH_REMATCH[1]}"
      local last="${BASH_REMATCH[4]}" retire="${BASH_REMATCH[5]}"
      if [[ "$seen" == *" $id "* ]]; then errs+=("INDEX.md line $lineno: duplicate lesson id $id"); fi
      seen="$seen$id "
      if [[ -z "${retire//[[:space:]]/}" ]]; then errs+=("INDEX.md line $lineno: $id has an empty retire-when"); fi
      if [[ "$last" != "-" ]] && ! valid_date "$last"; then errs+=("INDEX.md line $lineno: $id has an invalid last: date '$last'"); fi
    else
      id="$(printf '%s' "$line" | sed -n 's/^- \[\(L[0-9]*\)\].*/\1/p')"
      errs+=("INDEX.md line $lineno: approved lesson ${id:-?} lacks the (used: N, last: ..., retire-when: ...) fields")
    fi
  done < <(approved_lines)
  if (( approved_count > MAX_LESSONS )); then
    errs+=("INDEX.md has $approved_count approved lessons; the hard cap is $MAX_LESSONS (kernel rule 10). Run: scripts/lessons.sh expire")
  fi

  # PENDING entries: all four fields, non-empty.
  local start p1 v1 p2 v2 p3 v3 p4 v4 missing
  while IFS="$US" read -r start p1 v1 p2 v2 p3 v3 p4 v4; do
    [[ -n "$start" ]] || continue
    if is_placeholder "$p1" "$v1" "$p2" "$v2" "$p3" "$v3" "$p4" "$v4"; then continue; fi
    missing=""
    [[ "$p1" == 1 && -n "$v1" ]] || missing="$missing 'what happened'"
    [[ "$p2" == 1 && -n "$v2" ]] || missing="$missing 'what check should have caught it'"
    [[ "$p3" == 1 && -n "$v3" ]] || missing="$missing 'what was added'"
    [[ "$p4" == 1 && -n "$v4" ]] || missing="$missing 'retire-when'"
    [[ -z "$missing" ]] || errs+=("PENDING.md entry at line $start is missing or has empty:$missing")
  done < <(entries "$PENDING" "$PENDING_LABELS")

  # QUARANTINE entries: an owner task is required once older than 30 days.
  local now_dn owner_lc age
  now_dn="$(day_number "$(today)")"
  while IFS="$US" read -r start p1 v1 p2 v2 p3 v3 p4 v4; do
    [[ -n "$start" ]] || continue
    if is_placeholder "$p1" "$v1" "$p2" "$v2" "$p3" "$v3" "$p4" "$v4"; then continue; fi
    if [[ -z "$v1" ]]; then errs+=("QUARANTINE.md entry at line $start has no test path"); fi
    owner_lc="$(printf '%s' "$v4" | tr '[:upper:]' '[:lower:]')"
    if [[ -z "$owner_lc" || "$owner_lc" == "none" || "$owner_lc" == "n/a" || "$owner_lc" == "-" ]]; then
      if valid_date "$v3"; then
        age=$(( now_dn - $(day_number "$v3") ))
        if (( age > QUARANTINE_DAYS )); then
          errs+=("QUARANTINE.md entry at line $start is $age days old (> $QUARANTINE_DAYS) with no owner task")
        fi
      else
        errs+=("QUARANTINE.md entry at line $start has no owner task and no valid 'date quarantined'")
      fi
    fi
  done < <(entries "$QUARANTINE" "$QUARANTINE_LABELS")

  # tests/quarantine.list (when present): one line per quarantined test,
  #   <test path> # owner: <task> date: YYYY-MM-DD
  # Blank lines and lines starting with "#" are ignored. Every entry needs an
  # owner and a valid date, and none may be older than 30 days.
  local ql qpath qmeta qowner qdate qn=0 qage
  if [[ -f tests/quarantine.list ]]; then
    while IFS= read -r ql || [[ -n "$ql" ]]; do
      ql="${ql%$'
'}"
      [[ "$ql" =~ ^[[:space:]]*(#|$) ]] && continue
      qn=$((qn + 1))
      qpath="${ql%%#*}"
      qpath="${qpath%"${qpath##*[![:space:]]}"}"
      qmeta=""
      if [[ "$ql" == *"#"* ]]; then qmeta="${ql#*#}"; fi
      qowner=""; qdate=""
      if [[ "$qmeta" =~ owner:[[:space:]]*([^[:space:]]*) ]]; then
        qowner="${BASH_REMATCH[1]}"
        if [[ "$qowner" == date:* ]]; then qowner=""; fi
      fi
      if [[ "$qmeta" =~ date:[[:space:]]*([0-9]{4}-[0-9]{2}-[0-9]{2}) ]]; then qdate="${BASH_REMATCH[1]}"; fi
      if [[ -z "$qpath" ]]; then errs+=("tests/quarantine.list entry '$ql' has no test path"); fi
      if [[ -z "$qowner" ]]; then errs+=("tests/quarantine.list entry '${qpath:-?}' has no owner (format: <test path> # owner: <task> date: YYYY-MM-DD)"); fi
      if [[ -z "$qdate" ]] || ! valid_date "$qdate"; then
        errs+=("tests/quarantine.list entry '${qpath:-?}' has no valid date (format: <test path> # owner: <task> date: YYYY-MM-DD)")
      else
        qage=$(( now_dn - $(day_number "$qdate") ))
        if (( qage > QUARANTINE_DAYS )); then
          errs+=("tests/quarantine.list entry '${qpath:-?}' is $qage days old (> $QUARANTINE_DAYS); fix or delete the test")
        fi
      fi
    done < tests/quarantine.list
  fi

  # Skills mirror and cap.
  if [[ -d .claude/skills || -d .agents/skills ]]; then
    if [[ ! -d .claude/skills || ! -d .agents/skills ]]; then
      errs+=(".claude/skills and .agents/skills must both exist")
    else
      # The substitution can fail (diff exits 1 on a difference); under set -e a
      # failing substitution inside an assignment would end the script silently.
      drift="$(diff -rq .claude/skills .agents/skills 2>&1 | head -3 | tr '\n' ';' || true)"
      if [[ -n "$drift" ]]; then
        errs+=(".claude/skills and .agents/skills differ: $drift")
      fi
    fi
    local skills cap sets
    skills="$(skill_dir_count)"
    sets="$(profile_skill_sets)"
    cap=$((BASE_SKILLS + sets))
    if (( skills > cap )); then
      errs+=(".claude/skills has $skills skills; the cap is $cap ($BASE_SKILLS core + $sets skills listed by the adopted profiles = $cap; kernel rule 10)")
    fi
  fi

  # Every Claude agent has a Codex twin, or models.md names the exception on a
  # line containing "no Codex counterpart".
  local ag agname
  if [[ -d .claude/agents ]]; then
    for ag in .claude/agents/*.md; do
      [[ -f "$ag" ]] || continue
      agname="$(basename "$ag" .md)"
      [[ -f ".codex/agents/$agname.toml" ]] && continue
      if [[ -f docs/rules/models.md ]] && grep -i 'no Codex counterpart' docs/rules/models.md | grep -qw -- "$agname"; then
        continue
      fi
      errs+=(".claude/agents/$agname.md has no .codex/agents/$agname.toml and docs/rules/models.md has no line naming '$agname' with 'no Codex counterpart'")
    done
  fi

  # Agent and skill sets shipped by profiles and the library are well formed
  # and match what each profile declares.
  local pf msg
  for pf in docs/profiles/*/PROFILE.md; do
    [[ -f "$pf" ]] || continue
    while IFS= read -r msg; do
      if [[ -n "$msg" ]]; then errs+=("$msg"); fi
    done < <(shipped_set_check "$(dirname "$pf")" "$pf")
  done
  local optdir
  for optdir in docs/library docs/roster; do
    [[ -d "$optdir" ]] || continue
    while IFS= read -r msg; do
      if [[ -n "$msg" ]]; then errs+=("$msg"); fi
    done < <(shipped_set_check "$optdir")
  done

  # Rules files stay small enough to read whole.
  local f n
  for f in docs/rules/*.md; do
    [[ -f "$f" ]] || continue
    n="$(file_lines "$f")"
    if (( n > MAX_RULE_LINES )); then errs+=("$f has $n lines; the cap is $MAX_RULE_LINES"); fi
  done

  if (( ${#errs[@]} > 0 )); then
    local e
    for e in "${errs[@]}"; do echo "lessons: $e" >&2; done
    echo "lessons: check FAILED (${#errs[@]} problem(s))" >&2
    exit 1
  fi
  echo "lessons: OK ($approved_count/$MAX_LESSONS approved lessons, $(skill_dir_count) skills, rules files <= $MAX_RULE_LINES lines)"
}

# rewrite_line FILE LINENO [NEWTEXT]: replace the line, or delete it when no
# text argument is given. Text travels through ENVIRON so backslashes survive.
rewrite_line() {
  local file="$1" n="$2" tmp
  tmp="$(mktemp)"
  if [[ $# -ge 3 ]]; then
    NEWLINE="$3" awk -v n="$n" 'NR == n { print ENVIRON["NEWLINE"]; next } { print }' "$file" > "$tmp"
  else
    awk -v n="$n" 'NR != n { print }' "$file" > "$tmp"
  fi
  cat "$tmp" > "$file"
  rm -f "$tmp"
}

cmd_use() {
  local want="${1:-}"
  [[ "$want" =~ ^L[0-9]+$ ]] || { echo "usage: scripts/lessons.sh use <Lnnn>" >&2; exit 2; }
  local lineno line used last retire trimmed tail head now
  while IFS="$US" read -r lineno line; do
    [[ -n "$lineno" ]] || continue
    if [[ "$line" =~ $FIELD_RE ]] && [[ "${BASH_REMATCH[1]}" == "$want" ]]; then
      used="${BASH_REMATCH[3]}"; last="${BASH_REMATCH[4]}"; retire="${BASH_REMATCH[5]}"
      trimmed="${line%"${line##*[![:space:]]}"}"
      tail="(used: $used, last: $last, retire-when: $retire)"
      head="${trimmed%"$tail"}"
      now="$(today)"
      rewrite_line "$INDEX" "$lineno" "${head}(used: $((used + 1)), last: $now, retire-when: $retire)"
      echo "lessons: $want used: $((used + 1)), last: $now"
      return 0
    fi
  done < <(approved_lines)
  echo "lessons: $want not found in $INDEX (or its fields are malformed; run check)" >&2
  exit 1
}

cmd_expire() {
  local apply=0
  case "${1:-}" in
    "") ;;
    --apply) apply=1 ;;
    *) usage ;;
  esac
  local now now_dn lineno line found=0 never="" id last retire reason age
  now="$(today)"
  now_dn="$(day_number "$now")"
  # Collect first, apply bottom-up so line numbers stay valid.
  local hits=()
  while IFS="$US" read -r lineno line; do
    [[ -n "$lineno" ]] || continue
    [[ "$line" =~ $FIELD_RE ]] || continue
    id="${BASH_REMATCH[1]}"; last="${BASH_REMATCH[4]}"; retire="${BASH_REMATCH[5]}"; reason=""
    if [[ "$last" != "-" ]] && valid_date "$last"; then
      age=$(( now_dn - $(day_number "$last") ))
      if (( age > EXPIRE_DAYS )); then reason="last used $age days ago (> $EXPIRE_DAYS)"; fi
    else
      never="$never $id"
    fi
    if [[ "$retire" == *"[met]"* ]]; then
      reason="${reason:+$reason; }retire-when marked [met]"
    fi
    if [[ -n "$reason" ]]; then
      hits+=("$lineno$US$id$US$reason$US$line")
      echo "expire: $id - $reason"
      found=$((found + 1))
    fi
  done < <(approved_lines)
  if (( found == 0 )); then echo "expire: nothing to expire"; fi
  if [[ -n "$never" ]]; then echo "expire: note - never used (last: -, no age):$never"; fi
  if (( ! apply )); then
    if (( found )); then echo "expire: dry run; re-run with --apply to archive"; fi
    return 0
  fi
  (( found )) || return 0

  mkdir -p .archive/lessons
  local i h hl hid hreason hline dest
  for (( i = ${#hits[@]} - 1; i >= 0; i-- )); do
    h="${hits[$i]}"
    IFS="$US" read -r hl hid hreason hline <<< "$h"
    dest=".archive/lessons/$hid.md"
    [[ ! -e "$dest" ]] || dest=".archive/lessons/$hid-$now.md"
    {
      echo "# $hid archived $now"
      echo
      echo "reason: $hreason"
      echo
      echo "$hline"
    } > "$dest"
    rewrite_line "$INDEX" "$hl"
    echo "$now expire: $hid archived to $dest - $hreason" >> "$LOG"
    echo "expire: archived $hid -> $dest"
  done
}

cmd_stats() {
  local approved=0 unused=0 lineno line
  while IFS="$US" read -r lineno line; do
    [[ -n "$lineno" ]] || continue
    approved=$((approved + 1))
    if [[ "$line" =~ $FIELD_RE ]] && [[ "${BASH_REMATCH[3]}" == "0" ]]; then unused=$((unused + 1)); fi
  done < <(approved_lines)
  local pending=0 quarantine=0 start p1 v1 p2 v2 p3 v3 p4 v4
  while IFS="$US" read -r start p1 v1 p2 v2 p3 v3 p4 v4; do
    [[ -n "$start" ]] || continue
    if is_placeholder "$p1" "$v1" "$p2" "$v2" "$p3" "$v3" "$p4" "$v4"; then continue; fi
    pending=$((pending + 1))
  done < <(entries "$PENDING" "$PENDING_LABELS")
  while IFS="$US" read -r start p1 v1 p2 v2 p3 v3 p4 v4; do
    [[ -n "$start" ]] || continue
    if is_placeholder "$p1" "$v1" "$p2" "$v2" "$p3" "$v3" "$p4" "$v4"; then continue; fi
    quarantine=$((quarantine + 1))
  done < <(entries "$QUARANTINE" "$QUARANTINE_LABELS")
  local sets rules=0 maxlines=0 f n
  sets="$(profile_skill_sets)"
  for f in docs/rules/*.md; do
    [[ -f "$f" ]] || continue
    rules=$((rules + 1))
    n="$(file_lines "$f")"
    if (( n > maxlines )); then maxlines="$n"; fi
  done
  echo "approved lessons: $approved/$MAX_LESSONS (never used: $unused)"
  echo "pending entries: $pending"
  echo "quarantined tests: $quarantine"
  echo "skills: $(skill_dir_count) (cap $((BASE_SKILLS + sets)) = $BASE_SKILLS core + $sets skills listed by the adopted profiles)"
  echo "rules files: $rules (longest $maxlines/$MAX_RULE_LINES lines)"
}

case "${1:-}" in
  check) cmd_check ;;
  use) shift; cmd_use "$@" ;;
  expire) shift; cmd_expire "$@" ;;
  stats) cmd_stats ;;
  *) usage ;;
esac
