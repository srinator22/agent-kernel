#!/usr/bin/env bash
# check.sh - the single gauntlet. CI runs this exact script, so local and CI
# cannot diverge. Usage: ./scripts/check.sh [--full-mutation] [--quick]
# --quick is the working lane: the wired stack block skips mutation and the
# production build when QUICK=1; the always section (step 4) never skips.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

FULL_MUTATION=0
QUICK=0
for arg in "$@"; do
  case "$arg" in
    --full-mutation) FULL_MUTATION=1 ;;
    --quick) QUICK=1 ;;
    *) echo "unknown flag: $arg (supported: --full-mutation, --quick)" >&2; exit 2 ;;
  esac
done
export QUICK

fail() { echo "CHECK FAILED: $*" >&2; exit 1; }

# BEGIN blueprint-parity
# blueprint_parity BLUEPRINT FILE...: print one problem per line. The tree in
# section 2 of the blueprint lists files indented under their directories; the
# full path of each entry is built by walking the indentation (two spaces per
# level). Forward: every FILE must appear in the tree by its full path, or sit
# under a directory the tree lists as a summary entry (a directory with no
# children listed, such as .codex/agents/). Reverse: every file the tree lists
# must exist in the repository.
blueprint_parity() {
  local bp="$1" f entry kind path anc ok tree
  shift
  tree="$(awk '
    function flush(   i, k, ind, isdir, nxt) {
      for (i = 1; i <= n; i++) {
        ind = lvl[i]
        nxt = (i < n) ? lvl[i + 1] : -1
        if (isd[i]) print ((nxt > ind) ? "D " : "L ") pth[i]
        else print "F " pth[i]
      }
    }
    /^## 2\./ { sec = 1; next }
    /^## / { sec = 0; fence = 0; next }
    !sec { next }
    /^```/ { fence = !fence; next }
    !fence { next }
    {
      sub(/\r$/, "")
      line = $0
      sub(/[ \t]+#.*$/, "", line)
      if (line ~ /^[ \t]*$/) next
      match(line, /^ */); ind = RLENGTH
      name = line; sub(/^ +/, "", name); sub(/[ \t].*$/, "", name)
      lv = int(ind / 2)
      pre = (lv > 0) ? stack[lv - 1] : ""
      full = pre name
      n++; lvl[n] = lv; pth[n] = full; isd[n] = (name ~ /\/$/)
      if (isd[n]) stack[lv] = full
    }
    END { flush() }' "$bp")"
  for f in "$@"; do
    ok=0
    if printf '%s\n' "$tree" | grep -qxF -- "F $f"; then ok=1
    else
      anc="$f"
      while [[ "$anc" == */* ]]; do
        anc="${anc%/*}"
        if printf '%s\n' "$tree" | grep -qxF -- "L $anc/"; then ok=1; break; fi
      done
    fi
    (( ok )) || echo "$bp section 2 does not list $f by its full path"
  done
  while IFS= read -r entry; do
    kind="${entry%% *}"; path="${entry#* }"
    [[ "$kind" == F ]] || continue
    [[ -e "$path" ]] || echo "$bp section 2 lists $path but it does not exist in the repository"
  done <<< "$tree"
}
# END blueprint-parity

# Step 1 (always): kernel integrity.
./scripts/kernel-hash.sh --verify

# Step 2 (always): AGENTS.md hard line budget.
lines="$(wc -l < AGENTS.md)"
if (( lines > 180 )); then
  fail "AGENTS.md is $lines lines; the hard budget is 180. Move detail to docs/rules/ or archive lessons."
fi
echo "line-budget: OK (AGENTS.md = $lines/180)"

# Step 3 (always, non-fatal): untracked-files report. New modules that pass
# locally while never being staged are a known CI-breaker.
untracked="$(git status --porcelain | grep '^??' || true)"
if [[ -n "$untracked" ]]; then
  echo "------------------------------------------------------------------"
  echo "WARNING: untracked files exist. Resolve each one deliberately:"
  echo "stage it or ignore it, never leave it ambiguous."
  echo "$untracked" | sed 's/^?? /  /'
  echo "------------------------------------------------------------------"
fi

# Step 4 (always, both modes): the checks that are valid before and after
# start. Nothing here is skipped by --quick: they are fast and they are the
# ones that protect the memory caps and the style rule in every project.
gfail=0
gerr() { echo "CHECK FAILED: $*" >&2; gfail=1; }

# 4a. Style: plain hyphens only (kernel rule 20). Tracked files only.
# Needs grep with PCRE (GNU); where unavailable this defers to CI.
rc=0
dashes="$(git grep -IPn '[\x{2013}\x{2014}]' 2>/dev/null)" || rc=$?
if (( rc == 0 )); then
  printf '%s\n' "$dashes" | head -20
  gerr "em or en dash found; plain hyphens only"
elif (( rc > 1 )); then
  echo "WARNING: git grep -P unavailable; dash check deferred to CI."
fi

# 4b. Memory caps and mirror parity are mechanized (kernel rules 8 to 10):
# lesson count, entry fields, quarantine age, quarantine list, skills cap,
# .claude and .agents skill trees identical, rules files at most 40 lines.
./scripts/lessons.sh check || gerr "scripts/lessons.sh check failed"

# 4c. The task plan is a valid graph (docs/rules/orchestration.md).
./scripts/taskgraph.sh check || gerr "scripts/taskgraph.sh check failed"

# 4d. The template's own scripts are tested (docs/procedures/tests.md), in
# every mode, whenever the tests exist.
if [[ -d tests/template ]]; then
  ./scripts/selftest.sh || gerr "scripts/selftest.sh failed"
fi

# Step 5: template-mode gate. Before start runs there is no stack to
# check, so the gauntlet checks the template itself: a green badge means
# the template is intact, not merely that nothing executed.
if [[ ! -f .start-done ]]; then
  echo "TEMPLATE MODE - start has not run; running the template self-test."
  tfail=0
  terr() { echo "TEMPLATE SELF-TEST FAILED: $*" >&2; tfail=1; }

  # 5a. Shell syntax of every script.
  for s in scripts/*.sh; do
    bash -n "$s" || terr "bash -n: $s"
  done

  # 5b. Every shipped template file exists (the blueprint tree, mechanized).
  required=(
    AGENTS.md CLAUDE.md README.md BACKLOG.md BUILD_NOTES.md CONTRIBUTING.md
    SECURITY.md LICENSE manifest.md cliff.toml .kernel.hash .gitignore
    .editorconfig .gitattributes
    .github/workflows/ci.yml
    .github/pull_request_template.md
    .github/ISSUE_TEMPLATE/bug_report.yml
    docs/BLUEPRINT.md docs/ARCHITECTURE.md docs/operations.md
    docs/decisions/0001-template-architecture.md
    docs/decisions/0002-complexity-budgets-and-workflow-delegation.md
    docs/procedures/start.md docs/procedures/ship.md docs/procedures/retro.md
    docs/procedures/maintain.md docs/procedures/bugfix.md
    docs/procedures/audit.md docs/procedures/longjob.md
    docs/rules/architecture.md docs/rules/security.md
    docs/rules/data-provenance.md docs/rules/scientific-integrity.md
    docs/rules/destructive-actions.md docs/rules/ci-baseline.md
    docs/lessons/INDEX.md docs/lessons/PENDING.md docs/lessons/QUARANTINE.md
    docs/lessons/UPSTREAM.md
    scripts/check.sh scripts/check.ps1 scripts/check.cmd
    scripts/kernel-hash.sh scripts/ci-watch.sh scripts/new-task.sh
    scripts/bg.sh scripts/session-context.sh
    .work/TASK.md .work/done/.gitkeep .work/jobs/.gitkeep
    .claude/settings.json
    .claude/agents/reviewer.md .claude/agents/explore.md
    .claude/agents/worker.md .claude/agents/monitor.md
    .claude/skills/start/SKILL.md .claude/skills/ship/SKILL.md
    .claude/skills/retro/SKILL.md .claude/skills/maintain/SKILL.md
    .agents/skills/start/SKILL.md .agents/skills/ship/SKILL.md
    .agents/skills/retro/SKILL.md .agents/skills/maintain/SKILL.md
    .codex/agents/reviewer.toml .codex/agents/worker.toml
    .codex/agents/monitor.toml
    .archive/README.md
    docs/decisions/0003-self-improving-template.md
    docs/procedures/discover.md docs/procedures/bughunt.md
    docs/procedures/upstream.md docs/procedures/tests.md
    docs/rules/orchestration.md docs/rules/models.md
    docs/DEFECT_MEMORY.md
    docs/profiles/README.md docs/profiles/software/PROFILE.md
    docs/profiles/scientific/PROFILE.md
    docs/profiles/embedded-firmware/PROFILE.md
    docs/profiles/hardware-pcb/PROFILE.md
    docs/profiles/hardware-pcb/LAYOUT_PROCESS.md
    docs/profiles/hardware-pcb/CHECKS.md
    docs/profiles/data-analysis/PROFILE.md
    scripts/lessons.sh scripts/taskgraph.sh scripts/template-sync.sh
    scripts/quickgate.sh scripts/selftest.sh
    tests/template/lib.sh tests/template/test_kernel_hash.sh
    tests/template/test_new_task.sh tests/template/test_lessons.sh
    tests/template/test_taskgraph.sh tests/template/test_template_sync.sh
    tests/template/test_quickgate.sh tests/template/test_check_always.sh
    tests/template/test_blueprint_parity.sh tests/template/fixtures/check.sh
  )
  for f in "${required[@]}"; do
    [[ -f "$f" ]] || terr "required template file missing: $f"
  done

  # 5c. CLAUDE.md is exactly the one-line import.
  [[ "$(cat CLAUDE.md)" == "@AGENTS.md" ]] || terr "CLAUDE.md must be exactly '@AGENTS.md'"

  # 5d. Template placeholders intact; nothing pretends to be started.
  grep -q '{{FILLED_BY_START}}' AGENTS.md || terr "AGENTS.md lost its {{FILLED_BY_START}} placeholders"
  grep -q 'Status: TEMPLATE' AGENTS.md || terr "AGENTS.md lost its template status line"
  # Escaped regex so this line cannot match itself, only the real placeholder.
  grep -Eq '\{\{FORMAT_CHECK_FILLED_BY_START\}\}' scripts/check.sh || terr "check.sh lost its stack placeholders"
  # TASK.md is valid in two states: the pristine template, or a live
  # in-progress task file. Both must carry a declared Budget (ADR-0002).
  grep -q '^## Budget' .work/TASK.md || terr ".work/TASK.md lost its Budget section"
  if ! grep -q '{{title}}' .work/TASK.md && ! grep -q '^# Task: ' .work/TASK.md; then
    terr ".work/TASK.md is neither the pristine template nor an in-progress task"
  fi

  # 5e. Agent and skill frontmatter is structurally sound.
  for f in .claude/agents/*.md .claude/skills/*/SKILL.md .agents/skills/*/SKILL.md; do
    head -n 1 "$f" | grep -qx -- '---' || terr "frontmatter must open with ---: $f"
    grep -q '^name:' "$f" || terr "frontmatter missing name: $f"
    grep -q '^description:' "$f" || terr "frontmatter missing description: $f"
  done
  for f in .codex/agents/*.toml; do
    grep -q '^name = ' "$f" || terr "missing name field: $f"
    grep -q '^description = ' "$f" || terr "missing description field: $f"
    grep -q '^developer_instructions = ' "$f" || terr "missing developer_instructions field: $f"
  done

  # 5f. settings.json parses as JSON (python3 exists in CI; degrades locally).
  PY=""
  command -v python3 >/dev/null 2>&1 && PY=python3
  [[ -n "$PY" ]] || { command -v python >/dev/null 2>&1 && PY=python; } || true
  if [[ -n "$PY" ]]; then
    "$PY" -c 'import json; json.load(open(".claude/settings.json"))' \
      || terr ".claude/settings.json is not valid JSON"
  else
    echo "WARNING: python not found; settings.json not validated here (CI validates it)."
  fi

  # 5g. Shell scripts keep their executable bit in the git index.
  nonexec="$(git ls-files -s scripts/ | awk '$1 != "100755" && $4 ~ /\.sh$/ {print $4}')"
  [[ -z "$nonexec" ]] || terr "scripts lost the executable bit: $nonexec"

  # 5h. Every ADR a procedure or rule cites exists.
  for ref in $(grep -ohE 'docs/decisions/[0-9]{4}' docs/procedures/*.md docs/rules/*.md docs/profiles/*/*.md 2>/dev/null | sort -u); do
    n="${ref##*/}"
    ls docs/decisions/"$n"-*.md >/dev/null 2>&1 || terr "cited ADR does not exist: $ref"
  done

  # 5i. The pristine check.sh fixture the self-tests run against is this file.
  # After start wires the stack, the fixture keeps the template version.
  cmp -s scripts/check.sh tests/template/fixtures/check.sh \
    || terr "tests/template/fixtures/check.sh is not identical to scripts/check.sh (cp scripts/check.sh tests/template/fixtures/check.sh)"

  # 5j. The blueprint tree and the required list agree in both directions
  # (BLUEPRINT drift): every required file is in the section 2 tree by full
  # path, and every file the tree lists exists.
  while IFS= read -r msg; do
    if [[ -n "$msg" ]]; then terr "$msg"; fi
  done < <(blueprint_parity docs/BLUEPRINT.md "${required[@]}")

  if (( tfail || gfail )); then
    fail "template self-test found the problems listed above"
  fi
  echo "template self-test: OK (${#required[@]} required files, script syntax, frontmatter, placeholders, ADR refs, check.sh fixture, blueprint parity; always section: style, memory caps, task graph, selftest)"
  exit 0
fi

# Project mode: the always section decides before the stack block runs.
if (( gfail )); then
  fail "the always checks found the problems listed above"
fi

# Stack gauntlet. The start procedure (docs/procedures/start.md,
# step 3) replaces this block with real commands from the stack reference
# table in docs/BLUEPRINT.md section 4. Every role is filled or the gap is
# logged in START_REPORT.md with a reason. FULL_MUTATION=1 selects the full
# mutation run instead of changed-files-only; QUICK=1 (the --quick lane) skips
# steps 10 and 11 and must be honoured by the filled block. The start
# procedure also deletes the final fail line below once the block is wired.
#
#  5. Format check           {{FORMAT_CHECK_FILLED_BY_START}}
#  6. Typecheck              {{TYPECHECK_FILLED_BY_START}}
#  7. Lint + boundary rules  {{LINT_FILLED_BY_START}}
#  8. Tests                  {{TESTS_FILLED_BY_START}}
#  9. Secret scan (gitleaks) {{GITLEAKS_FILLED_BY_START}}
# 10. Production build       {{BUILD_FILLED_BY_START, or remove if no build}}
# 11. Mutation testing       {{MUTATION_FILLED_BY_START, honor FULL_MUTATION}}
# 12. CHANGELOG freshness    {{CHANGELOG_FRESHNESS_FILLED_BY_START:
#     regenerate with git-cliff to a temp path and diff; fail on drift}}

fail ".start-done exists but the stack gauntlet is not wired. Complete docs/procedures/start.md step 3, or remove .start-done."
