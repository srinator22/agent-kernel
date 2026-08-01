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

# Step 4: template-mode gate.
if [[ ! -f .start-done ]]; then
  echo "TEMPLATE MODE - start has not run; stack checks inactive."
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
