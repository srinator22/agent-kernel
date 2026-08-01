#!/usr/bin/env bash
# check.sh - the single gauntlet. CI runs this exact script, so local and CI
# cannot diverge. Usage: ./scripts/check.sh [--full-mutation]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

FULL_MUTATION=0
for arg in "$@"; do
  case "$arg" in
    --full-mutation) FULL_MUTATION=1 ;;
    *) echo "unknown flag: $arg (supported: --full-mutation)" >&2; exit 2 ;;
  esac
done

fail() { echo "CHECK FAILED: $*" >&2; exit 1; }

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

# Step 4: template-mode gate. Before start runs there is no stack to
# check, so the gauntlet checks the template itself: a green badge means
# the template is intact, not merely that nothing executed.
if [[ ! -f .start-done ]]; then
  echo "TEMPLATE MODE - start has not run; running the template self-test."
  tfail=0
  terr() { echo "TEMPLATE SELF-TEST FAILED: $*" >&2; tfail=1; }

  # 4a. Shell syntax of every script.
  for s in scripts/*.sh; do
    bash -n "$s" || terr "bash -n: $s"
  done

  # 4b. Every shipped template file exists (the blueprint tree, mechanized).
  required=(
    AGENTS.md CLAUDE.md README.md BACKLOG.md BUILD_NOTES.md CONTRIBUTING.md
    SECURITY.md LICENSE manifest.md cliff.toml .kernel.hash .gitignore
    .editorconfig .gitattributes
    .github/workflows/ci.yml
    .github/pull_request_template.md
    .github/ISSUE_TEMPLATE/bug_report.yml
    docs/BLUEPRINT.md docs/ARCHITECTURE.md docs/operations.md
    docs/decisions/0001-template-architecture.md
    docs/procedures/start.md docs/procedures/ship.md docs/procedures/retro.md
    docs/procedures/maintain.md docs/procedures/bugfix.md
    docs/procedures/audit.md docs/procedures/longjob.md
    docs/rules/architecture.md docs/rules/security.md
    docs/rules/data-provenance.md docs/rules/scientific-integrity.md
    docs/rules/destructive-actions.md docs/rules/ci-baseline.md
    docs/lessons/INDEX.md docs/lessons/PENDING.md docs/lessons/QUARANTINE.md
    scripts/check.sh scripts/check.ps1 scripts/check.cmd
    scripts/kernel-hash.sh scripts/ci-watch.sh scripts/new-task.sh
    scripts/bg.sh
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
  )
  for f in "${required[@]}"; do
    [[ -f "$f" ]] || terr "required template file missing: $f"
  done

  # 4c. CLAUDE.md is exactly the one-line import.
  [[ "$(cat CLAUDE.md)" == "@AGENTS.md" ]] || terr "CLAUDE.md must be exactly '@AGENTS.md'"

  # 4d. Template placeholders intact; nothing pretends to be started.
  grep -q '{{FILLED_BY_START}}' AGENTS.md || terr "AGENTS.md lost its {{FILLED_BY_START}} placeholders"
  grep -q 'Status: TEMPLATE' AGENTS.md || terr "AGENTS.md lost its template status line"
  # Escaped regex so this line cannot match itself, only the real placeholder.
  grep -Eq '\{\{FORMAT_CHECK_FILLED_BY_START\}\}' scripts/check.sh || terr "check.sh lost its stack placeholders"
  grep -q '{{title}}' .work/TASK.md || terr ".work/TASK.md is not the pristine template"

  # 4e. Agent and skill frontmatter is structurally sound.
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

  # 4f. settings.json parses as JSON (python3 exists in CI; degrades locally).
  PY=""
  command -v python3 >/dev/null 2>&1 && PY=python3
  [[ -n "$PY" ]] || { command -v python >/dev/null 2>&1 && PY=python; } || true
  if [[ -n "$PY" ]]; then
    "$PY" -c 'import json; json.load(open(".claude/settings.json"))' \
      || terr ".claude/settings.json is not valid JSON"
  else
    echo "WARNING: python not found; settings.json not validated here (CI validates it)."
  fi

  # 4g. Shell scripts keep their executable bit in the git index.
  nonexec="$(git ls-files -s scripts/ | awk '$1 != "100755" && $4 ~ /\.sh$/ {print $4}')"
  [[ -z "$nonexec" ]] || terr "scripts lost the executable bit: $nonexec"

  # 4h. Style: plain hyphens only (kernel rule 20). Tracked files only.
  # Needs grep with PCRE (GNU); where unavailable this defers to CI.
  rc=0
  dashes="$(git grep -IPn '[\x{2013}\x{2014}]' 2>/dev/null)" || rc=$?
  if (( rc == 0 )); then
    printf '%s\n' "$dashes" | head -20
    terr "em or en dash found; plain hyphens only"
  elif (( rc > 1 )); then
    echo "WARNING: git grep -P unavailable; dash check deferred to CI."
  fi

  if (( tfail )); then
    fail "template self-test found the problems listed above"
  fi
  echo "template self-test: OK (${#required[@]} required files, script syntax, frontmatter, placeholders, style)"
  exit 0
fi

# Steps 5+: stack gauntlet. The start procedure (docs/procedures/start.md,
# step 3) replaces this block with real commands from the stack reference
# table in docs/BLUEPRINT.md section 4. Every role is filled or the gap is
# logged in START_REPORT.md with a reason. FULL_MUTATION=1 selects the full
# mutation run instead of changed-files-only.
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
