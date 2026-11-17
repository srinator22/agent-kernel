#!/usr/bin/env bash
# lessons.sh - mechanizes the lesson caps and the forgetting rules (kernel
# rules 8, 9, 10; docs/procedures/maintain.md).
#   check          exit 1 on any cap or format violation (see below)
#   use <Lnnn>     increment used: and set last: to today for one lesson
#   expire         list lessons whose last: is older than 45 days or whose
#                  retire-when contains [met]; --apply archives them
#   archive <Lnnn> <reason>
#                  archive one lesson with a one-line reason (kernel rule 11)
#   stats          print counts
#   skills         print the skills count and cap; exit 1 when over the cap
#                  (scripts/template-sync.sh runs it after a sync)
#   core-skills    print the template core skill names, one per line
#   match <diff file> | match <git diff revisions>
#                  print the lessons whose trigger matches a changed path of a
#                  git diff (a file holding one) or of `git diff --name-status`
#                  over the given revisions (--staged and --cached allowed)
#
# INDEX.md line format (exactly as documented in docs/lessons/INDEX.md):
#   - [L001] <description> - <lesson> (used: 0, last: -, approved: YYYY-MM-DD, retire-when: <condition>)
# with an optional trigger as the last field (ADR 0017):
#   (used: 0, last: -, approved: YYYY-MM-DD, retire-when: <condition>, trigger: <token> <token>...)
# A token is <glob> or A:<glob>, M:<glob>, D:<glob>: a changed path matching the
# glob, for A only an added path (a rename or copy adds its new path), M only a
# modified one, D only a deleted one (a rename deletes its old path). The glob
# is a bash pattern over the whole repo-relative path, so * also crosses "/".
# last: is YYYY-MM-DD or "-". approved: is the YYYY-MM-DD date the lesson was
# approved; it measures the age of a lesson that was never used (last: "-"), so
# check and expire need it. Lines inside code fences and the documented
# format placeholder (description starting with "<") are not lessons.
#
# check enforces: <= 20 approved lessons; every one carries all four fields
# (a missing or malformed approved: date is an error) and a unique id; a lesson
# with used: 0 more than 45 days after its approved: date is an error (archive
# it with expire --apply or record a use); a retire-when carrying [met] prints a
# warning and does not fail; every PENDING.md entry carries its four fields; no
# QUARANTINE.md entry older than 30 days without an owner task; every
# UPSTREAM.md entry carries those four fields plus "applies to:" (core or a
# docs/profiles/ folder); every docs/profiles/*/PROFILE.md opening with
# "# Profile: " has 60 to 160 lines and exactly the ten README.md headings;
# .claude/skills and .agents/skills identical, except that a pointer SKILL.md
# (sole file, body names one canonical SKILL.md with the same name and
# description) may stand in one mirror; skill directories <= the template core skills
# present (CORE_SKILLS, at most 8) + 2 project skills + profile skill sets
# (the number of skills listed on the "Skills:" or "- Skills:" line of each
# docs/profiles/*/PROFILE.md, comma-separated; when AGENTS.md has a
# "- Profiles:" line naming profiles, only those count; with AGENTS.md but no
# such line, only software counts), so a core skill the
# template adds never takes a project's slot (ADR 0012);
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
# Kernel rule 10. CORE_SKILLS is the template's core set; this file syncs to
# every project, so the list travels with each release. In template mode,
# check.sh step 5m requires .claude/skills to hold exactly these names.
CORE_SKILLS=(adr dream maintain retro ship start template-update)
MAX_CORE_SKILLS=8
PROJECT_SKILLS=2
US=$'\037'

usage() {
  echo "usage: scripts/lessons.sh check | use <Lnnn> | expire [--apply] | archive <Lnnn> <reason> | stats | skills | core-skills | match <diff file | git revisions>" >&2
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

# split_retire TEXT: the retire-when capture of FIELD_RE may end with
# ", trigger: <spec>". Sets RW (retire-when alone), TRIG (the spec, trimmed) and
# HAS_TRIG (1 when the field is present, even empty).
split_retire() {
  RW="$1"; TRIG=""; HAS_TRIG=0
  if [[ "$1" == *", trigger:"* ]]; then
    RW="${1%, trigger:*}"
    TRIG="${1##*, trigger:}"
    HAS_TRIG=1
    TRIG="${TRIG#"${TRIG%%[![:space:]]*}"}"
    TRIG="${TRIG%"${TRIG##*[![:space:]]}"}"
  fi
}

# trigger_token_ok TOKEN: a glob with an optional A:, M: or D: prefix.
trigger_token_ok() {
  local g="$1"
  case "$g" in [AMD]:*) g="${g:2}" ;; esac
  [[ -n "$g" && "$g" != *:* ]]
}

# Groups: 1 id, 2 text, 3 used, 4 last, 5 the whole "approved: X, " clause (empty
# when absent, which check reports), 6 the approved value, 7 retire-when (with
# any trigger).
FIELD_RE='^-[[:space:]]\[(L[0-9]+)\][[:space:]](.*)\(used:[[:space:]]([0-9]+),[[:space:]]last:[[:space:]]([0-9]{4}-[0-9]{2}-[0-9]{2}|-),[[:space:]](approved:[[:space:]]*([^,]*),[[:space:]])?retire-when:[[:space:]](.+)\)[[:space:]]*$'

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

# The "- Profiles:" line is parsed by scripts/profiles.sh, the one parser
# template-sync.sh shares, so both adopt the same set.
adopted_profiles() {
  [[ -f AGENTS.md ]] || return 0
  bash "$ROOT/scripts/profiles.sh" adopted AGENTS.md
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
    if [[ "$(sed -n 1p "$f" | tr -d '\r')" != '---' ]]; then
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
  twin_errors "$dir/agents"
  handoff_errors "$dir"
  if [[ -n "$profile" ]]; then
    declared="$(profile_skill_names "$profile" | sort -u)"
    # A missing skills/ folder must not end this function under set -e.
    shipped="$(for f in "$dir"/skills/*/; do if [[ -d "$f" ]]; then basename "$f"; fi; done | sort -u)"
    while IFS= read -r name; do
      [[ -n "$name" ]] || continue
      grep -qx -- "$name" <<< "$shipped" || echo "$profile: Skills: lists $name but $dir/skills/$name/SKILL.md does not exist"
    done <<< "$declared"
    while IFS= read -r name; do
      [[ -n "$name" ]] || continue
      grep -qx -- "$name" <<< "$declared" || echo "$dir/skills/$name ships but $profile does not list it on its Skills: line"
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

# twin_errors MD_DIR [TOML_DIR]: an agent's Codex developer_instructions is its
# .md body, unchanged except that a hard-rule line "- Read-only." may read
# "- Your sandbox is read-only." (Codex enforces it with sandbox_mode); both
# forms ship today. TOML_DIR defaults to MD_DIR (library, profiles, roster);
# the core pair is .claude/agents and .codex/agents. Twins drifted silently
# before this check existed.
twin_errors() {
  local dir="$1" tomldir="${2:-$1}" md toml
  for md in "$dir"/*.md; do
    [[ -f "$md" ]] || continue
    toml="$tomldir/$(basename "$md" .md).toml"
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
    # "|| continue", not "&&": an unmatched last glob would end the loop with
    # status 1, and set -e then ends the function silently, losing every problem.
    [[ -f "$f" ]] || continue
    basename "$f" | sed 's/\.[a-z]*$//'
  done | sort -u)"
  for md in "$dir"/agents/*.md; do
    [[ -f "$md" ]] || continue
    while IFS= read -r name; do
      [[ -n "$name" ]] || continue
      grep -qx -- "$name" <<< "$known" || echo "$md: Hand-offs names \`$name\`, which is not an agent in this template"
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
  grep -qx -- "$SHIPPED_DONE" <<< "$out" || echo "shipped-set check of $1 stopped before completing"
}

# roster_inventory_errors: the roster README advertises its roles as table rows
# starting "| `<name>` |"; each advertised role ships agents/<name>.md and its
# .toml twin, and every shipped agent is advertised. Without this a deleted
# role still passes, because shipped_set_errors only judges files that exist.
roster_inventory_errors() {
  local readme=docs/roster/README.md listed shipped name f
  [[ -f "$readme" ]] || return 0
  listed="$(tr -d '\r' < "$readme" | sed -n 's/^| `\([a-z0-9][a-z0-9-]*\)` |.*/\1/p' | sort -u)"
  # Both halves count as shipped, so an orphan .toml is caught too.
  shipped="$(for f in docs/roster/agents/*.md docs/roster/agents/*.toml; do if [[ -f "$f" ]]; then f="${f##*/}"; echo "${f%.*}"; fi; done | sort -u)"
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    [[ -f "docs/roster/agents/$name.md" ]] || echo "$readme lists $name but docs/roster/agents/$name.md does not exist"
    [[ -f "docs/roster/agents/$name.toml" ]] || echo "$readme lists $name but docs/roster/agents/$name.toml does not exist"
  done <<< "$listed"
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    grep -qx -- "$name" <<< "$listed" || echo "docs/roster/agents/$name ships but $readme does not list it"
  done <<< "$shipped"
  return 0
}

# library_inventory_errors: docs/library/README.md lists its items in the
# "## Items" table as "| <name> | <kind ...> |"; each listed item exists where
# its kind lives (agent: agents/<name>.md or .toml, skill: skills/<name>/SKILL.md,
# procedure: procedures/<name>.md, hook: hooks/<name>.py, tool: tools/<name>.py
# or .sh), and every shipped item of those kinds is listed. Without this a
# deleted library item still passes.
library_inventory_errors() {
  local readme=docs/library/README.md lib=docs/library rows name kind f found
  [[ -f "$readme" ]] || return 0
  rows="$(tr -d '\r' < "$readme" | awk '
    /^## / { items = ($0 == "## Items"); next }
    items && /^\| / {
      n = split($0, c, "|"); name = c[2]; kind = c[3]
      gsub(/^[ \t`]+|[ \t`]+$/, "", name); gsub(/^[ \t]+/, "", kind)
      split(kind, k, /[ (]/)
      if (name ~ /^[a-z0-9][a-z0-9_-]*$/ && k[1] ~ /^(agent|skill|procedure|hook|tool)$/) print k[1] " " name
    }')"
  while read -r kind name; do
    [[ -n "$name" ]] || continue
    found=0
    case "$kind" in
      agent) [[ -f "$lib/agents/$name.md" || -f "$lib/agents/$name.toml" ]] && found=1 ;;
      skill) [[ -f "$lib/skills/$name/SKILL.md" ]] && found=1 ;;
      procedure) [[ -f "$lib/procedures/$name.md" ]] && found=1 ;;
      hook) [[ -f "$lib/hooks/$name.py" ]] && found=1 ;;
      tool) [[ -f "$lib/tools/$name.py" || -f "$lib/tools/$name.sh" ]] && found=1 ;;
    esac
    (( found )) || echo "$readme lists $kind $name but it does not exist under $lib/"
  done <<< "$rows"
  for f in "$lib"/agents/*.md "$lib"/agents/*.toml "$lib"/skills/*/SKILL.md "$lib"/procedures/*.md "$lib"/hooks/*.py "$lib"/tools/*.py "$lib"/tools/*.sh; do
    [[ -f "$f" ]] || continue
    case "$f" in
      "$lib"/agents/*) kind=agent; name="${f##*/}"; name="${name%.*}" ;;
      "$lib"/skills/*) kind=skill; name="${f%/SKILL.md}"; name="${name##*/}" ;;
      "$lib"/procedures/*) kind=procedure; name="${f##*/}"; name="${name%.md}" ;;
      "$lib"/hooks/*) kind=hook; name="${f##*/}"; name="${name%.py}" ;;
      *) kind=tool; name="${f##*/}"; name="${name%.*}" ;;
    esac
    grep -qx -- "$kind $name" <<< "$rows" || echo "$f ships but $readme does not list it as a $kind"
  done
  return 0
}

# Total profile skills over the adopted profiles (only software when AGENTS.md
# exists but names none; all profiles when there is no AGENTS.md).
profile_skill_sets() {
  local adopted f name total=0 n
  adopted="$(adopted_profiles)"
  for f in docs/profiles/*/PROFILE.md; do
    [[ -f "$f" ]] || continue
    name="$(basename "$(dirname "$f")")"
    if [[ -n "$adopted" ]] && ! grep -qx -- "$name" <<< "$adopted"; then
      continue
    fi
    # Template mode (AGENTS.md present, no usable Profiles line): software is
    # the one profile every project adopts, so only it counts. Without
    # AGENTS.md nothing says which profiles apply, so all count.
    if [[ -z "$adopted" && -f AGENTS.md && "$name" != software ]]; then
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

# Template core skills present in .claude/skills. A core skill the project
# removed frees no project slot.
core_dir_count() {
  local n=0 s
  for s in "${CORE_SKILLS[@]}"; do
    if [[ -d ".claude/skills/$s" ]]; then n=$((n + 1)); fi
  done
  echo "$n"
}

# skills_cap: the kernel rule 10 figures, the one place check, stats and skills
# take them from. Sets SK_COUNT (skill folders), SK_CAP and SK_FORMULA (the
# terms of the cap, for messages).
skills_cap() {
  local sets core
  sets="$(profile_skill_sets)"
  core="$(core_dir_count)"
  SK_COUNT="$(skill_dir_count)"
  SK_CAP=$((core + PROJECT_SKILLS + sets))
  SK_FORMULA="$core core + $PROJECT_SKILLS project + $sets skills listed by the adopted profiles"
}
skills_over_msg() { echo ".claude/skills has $SK_COUNT skills; the cap is $SK_CAP ($SK_FORMULA = $SK_CAP; kernel rule 10)"; }
skills_stats_line() { echo "skills: $SK_COUNT (cap $SK_CAP = $SK_FORMULA)"; }

file_lines() { awk 'END { print NR }' "$1"; }

# An entry is the documented placeholder when every label is present and every
# value is empty.
is_placeholder() { [[ "$1$3$5$7" == "1111" && -z "$2$4$6$8" ]]; }

# skills_pointer_target FILE: prints the canonical SKILL.md path and returns 0
# when FILE is a skills pointer (a SKILL.md with frontmatter and a body of at
# most 4 non-blank lines naming exactly one *SKILL.md path); returns 1 for a
# real skill. The path is repo-relative.
skills_pointer_target() {
  local body paths
  body="$(awk '
    { sub(/\r$/, "") }
    NR == 1 { if ($0 != "---") exit; next }
    fm == 0 { if ($0 == "---") fm = 1; next }
    $0 ~ /[^ \t]/ { print }' "$1" || true)"
  [[ -n "$body" ]] || return 1
  if (( $(printf '%s\n' "$body" | awk 'END { print NR }') > 4 )); then return 1; fi
  paths="$(printf '%s\n' "$body" | grep -oE '[A-Za-z0-9_./-]*SKILL\.md' | sort -u || true)"
  [[ -n "$paths" ]] || return 1
  if (( $(printf '%s\n' "$paths" | awk 'END { print NR }') != 1 )); then return 1; fi
  printf '%s\n' "${paths#./}"
}

# skills_pointer_errors FILE: one problem per line when a pointer FILE does not
# resolve to a canonical skill with the same name and description. Prints
# nothing for a real skill or a valid pointer.
skills_pointer_errors() {
  local f="$1" target pn pd cn cd
  target="$(skills_pointer_target "$f")" || return 0
  if [[ ! -f "$target" ]]; then
    echo "$f is a skills pointer naming $target, which does not exist"
    return 0
  fi
  pn="$(frontmatter_field "$f" name)"; pd="$(frontmatter_field "$f" description)"
  cn="$(frontmatter_field "$target" name)"; cd="$(frontmatter_field "$target" description)"
  if [[ -z "$pn" || -z "$pd" ]]; then
    echo "$f is a skills pointer without a name: and description: in its frontmatter"
  elif [[ "$pn" != "$cn" ]]; then
    echo "$f pointer name '$pn' differs from $target name '$cn'"
  elif [[ "$pd" != "$cd" ]]; then
    echo "$f pointer description differs from the description in $target"
  fi
}

# skills_mirror_errors: .claude/skills and .agents/skills must match entry by
# entry; the one accepted difference is a pointer SKILL.md (the only file of
# its folder) on one side whose counterpart is the canonical file it names.
# Pointer validity itself is checked by skills_pointer_errors.
skills_mirror_errors() {
  local n side other target rest="" d names
  names="$( { ls -A .claude/skills; ls -A .agents/skills; } | sort -u)"
  while IFS= read -r n; do
    [[ -n "$n" ]] || continue
    if diff -rq ".claude/skills/$n" ".agents/skills/$n" >/dev/null 2>&1; then continue; fi
    for side in .claude .agents; do
      other=".agents"; [[ "$side" == ".agents" ]] && other=".claude"
      [[ -f "$side/skills/$n/SKILL.md" ]] || continue
      [[ "$(find "$side/skills/$n" -type f | awk 'END { print NR }')" == "1" ]] || continue
      target="$(skills_pointer_target "$side/skills/$n/SKILL.md")" || continue
      if [[ "$target" == "$other/skills/$n/SKILL.md" ]]; then continue 2; fi
    done
    d="$(diff -rq ".claude/skills/$n" ".agents/skills/$n" 2>&1 | sed -n '1,3p' | tr '\n' ';' || true)"
    rest="$rest$d"
  done <<< "$names"
  if [[ -n "$rest" ]]; then echo "$rest"; fi
}

# profile_contract_errors PROFILE.md: the file contract of
# docs/profiles/README.md - 60 to 160 lines and exactly these level-2
# headings in this order (headings inside code fences are ignored).
PROFILE_HEADINGS="Purpose and risk|Rules|Gates|Tools|Playbooks|Agents and skills|Parameters and records|Done means|Lessons carried in|Sources"
profile_contract_errors() {
  local f="$1" n found first
  # Only a file that opens with the contract title line is held to the contract.
  first="$(sed -n 1p "$f")"
  [[ "$first" == "# Profile: "* ]] || return 0
  n="$(file_lines "$f")"
  if (( n < 60 || n > 160 )); then echo "$f has $n lines; a PROFILE.md is 60 to 160 lines (docs/profiles/README.md)"; fi
  found="$(awk '
    { sub(/\r$/, "") }
    /^```/ { fence = !fence; next }
    !fence && /^## / { sub(/^## /, ""); sub(/[ \t]+$/, ""); printf "%s%s", (c++ ? "|" : ""), $0 }' "$f")"
  if [[ "$found" != "$PROFILE_HEADINGS" ]]; then
    echo "$f level-2 headings are '$found'; expected exactly, in order: '$PROFILE_HEADINGS' (docs/profiles/README.md)"
  fi
}

UPSTREAM="docs/lessons/UPSTREAM.md"
UPSTREAM_LABELS="what happened|what check should have caught it|what was added|retire-when|applies to"

cmd_check() {
  local errs=() approved_count=0 line lineno id seen=" "

  # adopted_profiles runs inside command substitutions, where a missing
  # parser would read as "no profile adopted" and pass; name it here instead.
  if [[ -f AGENTS.md && ! -f "$ROOT/scripts/profiles.sh" ]]; then
    errs+=("scripts/profiles.sh is missing; lessons.sh reads the AGENTS.md Profiles line through it (a core file: restore it from the template)")
  fi

  # Approved lessons: cap, fields, unique ids.
  while IFS="$US" read -r lineno line; do
    [[ -n "$lineno" ]] || continue
    approved_count=$((approved_count + 1))
    if [[ "$line" =~ $FIELD_RE ]]; then
      id="${BASH_REMATCH[1]}"
      local used="${BASH_REMATCH[3]}" last="${BASH_REMATCH[4]}" aclause="${BASH_REMATCH[5]}" approved="${BASH_REMATCH[6]}" retire="${BASH_REMATCH[7]}"
      if [[ "$seen" == *" $id "* ]]; then errs+=("INDEX.md line $lineno: duplicate lesson id $id"); fi
      seen="$seen$id "
      split_retire "$retire"
      if [[ -z "${RW//[[:space:]]/}" ]]; then errs+=("INDEX.md line $lineno: $id has an empty retire-when"); fi
      if (( HAS_TRIG )); then
        if [[ -z "$TRIG" ]]; then errs+=("INDEX.md line $lineno: $id has an empty trigger (drop the field or name a glob)"); fi
        local tok toks=()
        # read -a splits without glob expansion; a bare $TRIG would expand *.sh here.
        read -r -a toks <<< "$TRIG"
        for tok in ${toks[@]+"${toks[@]}"}; do
          trigger_token_ok "$tok" || errs+=("INDEX.md line $lineno: $id trigger token '$tok' is malformed (expected <glob>, A:<glob>, M:<glob> or D:<glob>)")
        done
      fi
      if [[ "$last" != "-" ]] && ! valid_date "$last"; then errs+=("INDEX.md line $lineno: $id has an invalid last: date '$last'"); fi
      if [[ -z "$aclause" ]]; then
        errs+=("INDEX.md line $lineno: $id has no approved: YYYY-MM-DD field (put it right after last:)")
      elif ! valid_date "$approved"; then
        errs+=("INDEX.md line $lineno: $id has a malformed approved: date '$approved' (expected YYYY-MM-DD)")
      elif [[ "$used" == "0" ]]; then
        local age=$(( $(day_number "$(today)") - $(day_number "$approved") ))
        if (( age > EXPIRE_DAYS )); then
          errs+=("INDEX.md line $lineno: $id has used: 0 and was approved $age days ago (> $EXPIRE_DAYS); archive it in a maintain pass (scripts/lessons.sh expire --apply) or record a use (scripts/lessons.sh use $id)")
        fi
      fi
      if [[ "$retire" == *"[met]"* ]]; then
        echo "lessons: warning - $id retire-when is marked [met]; archive it in a maintain pass (scripts/lessons.sh expire --apply)"
      fi
    else
      id="$(printf '%s' "$line" | sed -n 's/^- \[\(L[0-9]*\)\].*/\1/p')"
      errs+=("INDEX.md line $lineno: approved lesson ${id:-?} lacks the (used: N, last: ..., approved: ..., retire-when: ...) fields")
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

  # UPSTREAM entries: the PENDING four fields plus "applies to:", which names
  # core or a profile folder under docs/profiles/ (docs/procedures/upstream.md).
  local p5 v5 applies
  while IFS="$US" read -r start p1 v1 p2 v2 p3 v3 p4 v4 p5 v5; do
    [[ -n "$start" ]] || continue
    # The documented format placeholder leaves the four fields empty.
    if is_placeholder "$p1" "$v1" "$p2" "$v2" "$p3" "$v3" "$p4" "$v4"; then continue; fi
    missing=""
    [[ "$p1" == 1 && -n "$v1" ]] || missing="$missing 'what happened'"
    [[ "$p2" == 1 && -n "$v2" ]] || missing="$missing 'what check should have caught it'"
    [[ "$p3" == 1 && -n "$v3" ]] || missing="$missing 'what was added'"
    [[ "$p4" == 1 && -n "$v4" ]] || missing="$missing 'retire-when'"
    [[ "$p5" == 1 && -n "$v5" ]] || missing="$missing 'applies to'"
    [[ -z "$missing" ]] || errs+=("UPSTREAM.md entry at line $start is missing or has empty:$missing")
    if [[ "$p5" == 1 && -n "$v5" ]]; then
      applies="${v5%%[[:space:]]*}"
      if [[ "$applies" != "core" && ! -d "docs/profiles/$applies" ]]; then
        errs+=("UPSTREAM.md entry at line $start: 'applies to' is '$v5'; expected core or a profile folder name under docs/profiles/")
      fi
    fi
  done < <(entries "$UPSTREAM" "$UPSTREAM_LABELS")

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
  if (( ${#CORE_SKILLS[@]} > MAX_CORE_SKILLS )); then
    errs+=("the template core set lists ${#CORE_SKILLS[@]} skills; the cap is $MAX_CORE_SKILLS (kernel rule 10)")
  fi
  if [[ -d .claude/skills || -d .agents/skills ]]; then
    if [[ ! -d .claude/skills || ! -d .agents/skills ]]; then
      errs+=(".claude/skills and .agents/skills must both exist")
    else
      # The substitution can fail (diff exits 1 on a difference); under set -e a
      # failing substitution inside an assignment would end the script silently.
      drift="$(skills_mirror_errors)"
      if [[ -n "$drift" ]]; then
        errs+=(".claude/skills and .agents/skills differ: $drift")
      fi
      local sk
      for sk in .claude/skills/*/SKILL.md .agents/skills/*/SKILL.md; do
        [[ -f "$sk" ]] || continue
        while IFS= read -r msg; do
          if [[ -n "$msg" ]]; then errs+=("$msg"); fi
        done < <(skills_pointer_errors "$sk")
      done
    fi
    skills_cap
    if (( SK_COUNT > SK_CAP )); then errs+=("$(skills_over_msg)"); fi
  fi

  # Every Claude agent has a Codex twin, or models.md names the exception on a
  # line containing "no Codex counterpart".
  local ag agname msg
  if [[ -d .claude/agents ]]; then
    for ag in .claude/agents/*.md; do
      [[ -f "$ag" ]] || continue
      agname="$(basename "$ag" .md)"
      [[ -f ".codex/agents/$agname.toml" ]] && continue
      if [[ -f docs/rules/models.md ]] && grep -i 'no Codex counterpart' docs/rules/models.md | grep -cw -- "$agname" >/dev/null; then
        continue
      fi
      errs+=(".claude/agents/$agname.md has no .codex/agents/$agname.toml and docs/rules/models.md has no line naming '$agname' with 'no Codex counterpart'")
    done
    while IFS= read -r msg; do
      if [[ -n "$msg" ]]; then errs+=("$msg"); fi
    done < <(twin_errors .claude/agents .codex/agents; handoff_errors .claude)
  fi

  # Agent and skill sets shipped by profiles and the library are well formed
  # and match what each profile declares.
  local pf msg
  for pf in docs/profiles/*/PROFILE.md; do
    [[ -f "$pf" ]] || continue
    while IFS= read -r msg; do
      if [[ -n "$msg" ]]; then errs+=("$msg"); fi
    done < <(shipped_set_check "$(dirname "$pf")" "$pf")
    while IFS= read -r msg; do
      if [[ -n "$msg" ]]; then errs+=("$msg"); fi
    done < <(profile_contract_errors "$pf")
  done
  local optdir
  for optdir in docs/library docs/roster; do
    [[ -d "$optdir" ]] || continue
    while IFS= read -r msg; do
      if [[ -n "$msg" ]]; then errs+=("$msg"); fi
    done < <(shipped_set_check "$optdir")
  done
  while IFS= read -r msg; do
    if [[ -n "$msg" ]]; then errs+=("$msg"); fi
  done < <(roster_inventory_errors || echo "roster inventory check stopped before completing")
  while IFS= read -r msg; do
    if [[ -n "$msg" ]]; then errs+=("$msg"); fi
  done < <(library_inventory_errors || echo "library inventory check stopped before completing")

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
  local lineno line used last aclause retire trimmed tail head now
  while IFS="$US" read -r lineno line; do
    [[ -n "$lineno" ]] || continue
    if [[ "$line" =~ $FIELD_RE ]] && [[ "${BASH_REMATCH[1]}" == "$want" ]]; then
      used="${BASH_REMATCH[3]}"; last="${BASH_REMATCH[4]}"; aclause="${BASH_REMATCH[5]}"; retire="${BASH_REMATCH[7]}"
      trimmed="${line%"${line##*[![:space:]]}"}"
      tail="(used: $used, last: $last, ${aclause}retire-when: $retire)"
      head="${trimmed%"$tail"}"
      now="$(today)"
      rewrite_line "$INDEX" "$lineno" "${head}(used: $((used + 1)), last: $now, ${aclause}retire-when: $retire)"
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
  local now now_dn lineno line found=0 never="" id last approved retire reason age used
  now="$(today)"
  now_dn="$(day_number "$now")"
  # Collect first, apply bottom-up so line numbers stay valid.
  local hits=()
  while IFS="$US" read -r lineno line; do
    [[ -n "$lineno" ]] || continue
    [[ "$line" =~ $FIELD_RE ]] || continue
    id="${BASH_REMATCH[1]}"; used="${BASH_REMATCH[3]}"; last="${BASH_REMATCH[4]}"; approved="${BASH_REMATCH[6]}"; retire="${BASH_REMATCH[7]}"; reason=""
    if [[ "$last" != "-" ]] && valid_date "$last"; then
      age=$(( now_dn - $(day_number "$last") ))
      if (( age > EXPIRE_DAYS )); then reason="last used $age days ago (> $EXPIRE_DAYS)"; fi
    else
      # Never used: the approval date is the only age there is.
      if [[ "$used" == "0" ]] && valid_date "$approved"; then
        age=$(( now_dn - $(day_number "$approved") ))
        if (( age > EXPIRE_DAYS )); then reason="never used, approved $age days ago (> $EXPIRE_DAYS)"; fi
      fi
      [[ -n "$reason" ]] || never="$never $id"
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

  local i h hl hid hreason hline
  for (( i = ${#hits[@]} - 1; i >= 0; i-- )); do
    h="${hits[$i]}"
    IFS="$US" read -r hl hid hreason hline <<< "$h"
    archive_line "$hl" "$hid" "$hreason" "$hline" expire
  done
}

# archive_line LINENO ID REASON LINE TAG: move one approved lesson to
# .archive/lessons/ with its one-line reason (kernel rule 11), drop it from
# INDEX.md and log it. A second archive of the same id gets a dated name.
archive_line() {
  local hl="$1" hid="$2" hreason="$3" hline="$4" tag="$5" now dest
  now="$(today)"
  mkdir -p .archive/lessons
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
  echo "$now $tag: $hid archived to $dest - $hreason" >> "$LOG"
  echo "$tag: archived $hid -> $dest"
}

# archive <Lnnn> <reason>: archive one lesson on evidence the retire-when
# marker cannot carry (for example its content now lives in a repo file).
cmd_archive() {
  local want="${1:-}" reason="${2:-}" lineno line
  if [[ ! "$want" =~ ^L[0-9]+$ || -z "${reason//[[:space:]]/}" || $# -ne 2 ]]; then
    echo "usage: scripts/lessons.sh archive <Lnnn> <one-line reason>" >&2; exit 2
  fi
  case "$reason" in *$'\n'*) echo "lessons: the reason must be one line" >&2; exit 2 ;; esac
  while IFS="$US" read -r lineno line; do
    [[ -n "$lineno" ]] || continue
    if [[ "$line" =~ ^-[[:space:]]\[($want)\][[:space:]] ]]; then
      archive_line "$lineno" "$want" "$reason" "$line" archive
      return 0
    fi
  done < <(approved_lines)
  echo "lessons: $want not found in $INDEX" >&2
  exit 1
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
  local rules=0 maxlines=0 f n
  skills_cap
  for f in docs/rules/*.md; do
    [[ -f "$f" ]] || continue
    rules=$((rules + 1))
    n="$(file_lines "$f")"
    if (( n > maxlines )); then maxlines="$n"; fi
  done
  echo "approved lessons: $approved/$MAX_LESSONS (never used: $unused)"
  echo "pending entries: $pending"
  echo "quarantined tests: $quarantine"
  skills_stats_line
  echo "rules files: $rules (longest $maxlines/$MAX_RULE_LINES lines)"
}

# changed_paths ARG...: "status<TAB>path" lines, status A, M or D. A rename or
# copy gives A for the new path (and D for the old one, for a rename).
changed_paths() {
  if [[ $# -eq 1 && -f "$1" ]]; then
    # A git diff: the header of each file block names its paths and status.
    awk '
      function emit(st, p) { if (p != "") printf "%s\t%s\n", st, p }
      function flush() {
        if (!open) return
        if (rto != "") { emit("A", rto); if (!copy) emit("D", rfrom) }
        else if (isnew) emit("A", (newp != "" ? newp : gitp))
        else if (isdel) emit("D", (oldp != "" ? oldp : gitp))
        else emit("M", (newp != "" ? newp : gitp))
        open = 0
      }
      { sub(/\r$/, "") }
      /^diff --git / {
        flush(); open = 1; isnew = 0; isdel = 0; copy = 0; rfrom = ""; rto = ""; oldp = ""; newp = ""; hunk = 0
        # "diff --git a/P b/P": both halves are equal unless renamed, so P has (len - 6) / 2 characters.
        h = substr($0, 12); gitp = substr(h, 3, (length(h) - 6) / 2)
        seen = 1; next
      }
      !open { next }
      /^@@ / { hunk = 1; next }
      hunk { next }
      /^new file mode/ { isnew = 1; next }
      /^deleted file mode/ { isdel = 1; next }
      /^rename from / { rfrom = substr($0, 13); next }
      /^rename to / { rto = substr($0, 11); next }
      /^copy from / { rfrom = substr($0, 11); copy = 1; next }
      /^copy to / { rto = substr($0, 9); copy = 1; next }
      /^--- / { p = substr($0, 5); sub(/\t.*$/, "", p); if (p != "/dev/null") { sub(/^a\//, "", p); oldp = p }; next }
      /^\+\+\+ / { p = substr($0, 5); sub(/\t.*$/, "", p); if (p != "/dev/null") { sub(/^b\//, "", p); newp = p }; next }
      END { flush(); if (!seen) exit 3 }
    ' "$1" || { echo "lessons: $1 holds no \"diff --git\" header; pass a git diff or git revisions" >&2; return 2; }
    return 0
  fi
  local a
  for a in "$@"; do
    case "$a" in
      --staged|--cached) ;;
      -*) echo "lessons: match takes a diff file or git revisions; option '$a' is not allowed" >&2; return 2 ;;
    esac
  done
  local out
  out="$(git diff --name-status -M "$@" 2>&1)" || { echo "lessons: git diff failed: $out" >&2; return 2; }
  [[ -n "$out" ]] || return 0
  printf '%s\n' "$out" | awk -F '\t' '
    $1 ~ /^R/ { printf "A\t%s\nD\t%s\n", $3, $2; next }
    $1 ~ /^C/ { printf "A\t%s\n", $3; next }
    $1 ~ /^[AMD]/ { printf "%s\t%s\n", substr($1, 1, 1), $2; next }
    { printf "M\t%s\n", $2 }'
}

# match: one line per lesson whose trigger matches a changed path, in INDEX
# order: "<id> <status> <first matching path> (trigger <token>)".
cmd_match() {
  [[ $# -ge 1 ]] || { echo "usage: scripts/lessons.sh match <diff file> | match <git diff revisions>" >&2; exit 2; }
  local paths rc=0
  paths="$(changed_paths "$@")" || rc=$?
  (( rc == 0 )) || exit 2
  local npaths=0 nhit=0 ntrig=0 lineno line id tok st glob want p hit toks=()
  if [[ -n "$paths" ]]; then npaths="$(printf '%s\n' "$paths" | awk 'END { print NR }')"; fi
  while IFS="$US" read -r lineno line; do
    [[ -n "$lineno" ]] || continue
    [[ "$line" =~ $FIELD_RE ]] || continue
    id="${BASH_REMATCH[1]}"
    split_retire "${BASH_REMATCH[7]}"
    [[ -n "$TRIG" ]] || continue
    ntrig=$((ntrig + 1))
    hit=""
    read -r -a toks <<< "$TRIG"
    for tok in "${toks[@]}"; do
      want=""; glob="$tok"
      case "$tok" in [AMD]:*) want="${tok:0:1}"; glob="${tok:2}" ;; esac
      while IFS=$'\t' read -r st p; do
        [[ -n "$p" ]] || continue
        [[ -z "$want" || "$st" == "$want" ]] || continue
        # shellcheck disable=SC2053 # the glob is a pattern on purpose
        if [[ "$p" == $glob ]]; then hit="$id $st $p (trigger $tok)"; break; fi
      done <<< "$paths"
      [[ -z "$hit" ]] || break
    done
    if [[ -n "$hit" ]]; then echo "$hit"; nhit=$((nhit + 1)); fi
  done < <(approved_lines)
  echo "lessons: $nhit of $ntrig lesson triggers match $npaths changed path(s)" >&2
}

cmd_skills() {
  skills_cap
  skills_stats_line
  if (( SK_COUNT > SK_CAP )); then
    echo "lessons: $(skills_over_msg)" >&2
    exit 1
  fi
}

case "${1:-}" in
  check) cmd_check ;;
  skills) cmd_skills ;;
  core-skills) printf '%s\n' "${CORE_SKILLS[@]}" ;;
  use) shift; cmd_use "$@" ;;
  expire) shift; cmd_expire "$@" ;;
  archive) shift; cmd_archive "$@" ;;
  stats) cmd_stats ;;
  match) shift; cmd_match "$@" ;;
  *) usage ;;
esac
