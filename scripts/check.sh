#!/usr/bin/env bash
# check.sh - the single gauntlet. CI runs this exact script, so local and CI
# cannot diverge. Usage: ./scripts/check.sh [--full-mutation] [--quick]
# --quick is the working lane: the wired stack block skips mutation and the
# production build when QUICK=1; the always section (step 4) never skips,
# except the ship-readiness half of the task lint (4e), which is full-gate only.
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
  # Whole-line matches on the newline-framed tree, not printf | grep -q: an
  # early-exit reader can end the writer with SIGPIPE under pipefail once the
  # tree outgrows the pipe buffer ("printf: write error: Broken pipe").
  local nl=$'\n'
  for f in "$@"; do
    ok=0
    case "$nl$tree$nl" in *"${nl}F $f${nl}"*) ok=1 ;; esac
    if (( ! ok )); then
      anc="$f"
      while [[ "$anc" == */* ]]; do
        anc="${anc%/*}"
        case "$nl$tree$nl" in *"${nl}L $anc/${nl}"*) ok=1; break ;; esac
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

# 4a. Style: plain hyphens only (kernel rule 20), and no typographic or
# mis-encoded characters. Tracked files only.
# Needs grep with PCRE (GNU); where unavailable this defers to CI.
# The first 20 matches are printed with sed, which reads all its input: a
# pipe into head ends the writer with SIGPIPE under pipefail (exit 141) once
# the list outgrows the pipe buffer.
rc=0
dashes="$(git grep -IPn '[\x{2013}\x{2014}]' 2>/dev/null)" || rc=$?
if (( rc == 0 )); then
  printf '%s\n' "$dashes" | sed -n '1,20p'
  gerr "em or en dash found; plain hyphens only"
elif (( rc > 1 )); then
  echo "WARNING: git grep -P unavailable; dash check deferred to CI."
fi
# Typographic and mis-encoded characters: curly quotes, the ellipsis
# character, non-breaking space, the replacement character, and UTF-8 that
# was decoded as Latin-1 or Windows-1252 (an A-tilde or a-circumflex-euro
# pair). They break greps and diffs and usually mean pasted or mangled text.
rc=0
chars="$(git grep -IPn '[\x{2018}\x{2019}\x{201C}\x{201D}\x{2026}\x{00A0}\x{FFFD}]|\x{00C3}[\x{0080}-\x{00BF}]|\x{00E2}\x{20AC}' 2>/dev/null)" || rc=$?
if (( rc == 0 )); then
  printf '%s\n' "$chars" | sed -n '1,20p'
  gerr "typographic or mis-encoded character found (curly quote, ellipsis, non-breaking space, replacement character or mojibake); use plain ASCII punctuation"
elif (( rc > 1 )); then
  echo "WARNING: git grep -P unavailable; character check deferred to CI."
fi

# 4b. Memory caps and mirror parity are mechanized (kernel rules 8 to 10):
# lesson count, entry fields, quarantine age, quarantine list, skills cap,
# .claude and .agents skill trees identical, rules files at most 40 lines.
./scripts/lessons.sh check || gerr "scripts/lessons.sh check failed"

# 4c. The task plan is a valid graph (docs/rules/orchestration.md).
./scripts/taskgraph.sh check || gerr "scripts/taskgraph.sh check failed"

# 4d. Decision records are numbered and formatted (docs/procedures/adr.md).
./scripts/adr.sh check || gerr "scripts/adr.sh check failed"

# 4e. Task state: ticked criteria name evidence, assumptions carry a status,
# an autopilot task that started has a plan verdict. The full gate (not
# --quick) also requires every assumption settled: an open one means the task
# is not ready to ship.
./scripts/tasklint.sh check || gerr "scripts/tasklint.sh check failed"
if (( ! QUICK )); then
  ./scripts/tasklint.sh ship || gerr "scripts/tasklint.sh ship failed (settle open assumptions; autopilot needs a PASS plan verdict)"
fi

# 4f. The documentation question set is well formed and its sources exist
# (docs/procedures/doc-eval.md).
./scripts/doc-eval.sh check || gerr "scripts/doc-eval.sh check failed"

# 4g. The template's own scripts are tested (docs/procedures/tests.md), in
# every mode, whenever the tests exist.
if [[ -d tests/template ]]; then
  ./scripts/selftest.sh || gerr "scripts/selftest.sh failed"
fi

# 4h. The "- Template: <url> <ref>" line names the last recorded template
# sync (docs/procedures/upstream.md). Offline; nothing to check in template
# mode; skipped where the project does not carry the sync script.
if [[ -f scripts/template-sync.sh ]]; then
  ./scripts/template-sync.sh --status || gerr "scripts/template-sync.sh --status failed (fix the - Template: line in AGENTS.md)"
fi

# 4i. The preference registers (docs/preferences/*.md) are well formed: every
# rule has a source date and a named check or Review, references exist, IDs
# are unique, baselines resolve. Warnings (an unwired feedback hook) are
# printed by the script and do not fail. Skipped where the project does not
# carry the script (docs/procedures/preferences.md).
if [[ -f scripts/preferences.sh ]]; then
  bash scripts/preferences.sh check || gerr "scripts/preferences.sh check failed (docs/preferences/README.md has the format)"
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
    scripts/template-release.sh scripts/fleet.sh
    .claude/skills/template-update/SKILL.md .agents/skills/template-update/SKILL.md
    tests/template/test_template_release.sh tests/template/test_fleet.sh
    scripts/dream.sh scripts/dream/dream.py scripts/dream/ruff.toml
    tests/template/test_dream.sh docs/procedures/dream.md
    docs/library/ruff.toml docs/profiles/ruff.toml
    tests/template/test_selftest.sh tests/template/fixtures/fake-ruff.sh
    .claude/agents/dreamer.md .codex/agents/dreamer.toml
    scripts/dream/taste.py tests/template/test_taste.sh
    .claude/agents/taste-dreamer.md .codex/agents/taste-dreamer.toml
    .claude/skills/dream/SKILL.md .agents/skills/dream/SKILL.md
    scripts/quickgate.sh scripts/selftest.sh
    tests/template/lib.sh tests/template/test_kernel_hash.sh
    tests/template/test_new_task.sh tests/template/test_lessons.sh
    tests/template/test_taskgraph.sh tests/template/test_template_sync.sh
    tests/template/test_quickgate.sh tests/template/test_check_always.sh
    tests/template/test_blueprint_parity.sh tests/template/fixtures/check.sh
    docs/decisions/0004-profile-agent-sets.md docs/library/README.md
    tests/template/test_profile_tools.sh
    docs/decisions/0005-department-agent-roster.md docs/roster/README.md
    docs/decisions/0006-claude-code-hooks-enforce-the-destructive-action-rule-and-th.md
    docs/procedures/adr.md scripts/adr.sh scripts/worker-git-guard.sh
    .claude/skills/adr/SKILL.md .agents/skills/adr/SKILL.md
    tests/template/test_adr.sh tests/template/test_ci_watch.sh
    tests/template/test_worker_git_guard.sh
    scripts/destructive-guard.sh scripts/stop-gate.sh scripts/tasklint.sh
    scripts/doc-eval.sh docs/procedures/doc-eval.md tests/docs/questions.md
    tests/template/test_destructive_guard.sh tests/template/test_stop_gate.sh
    tests/template/test_tasklint.sh tests/template/test_doc_eval.sh
    tests/template/test_session_context.sh tests/template/test_test_files.sh
    scripts/feedback-log.sh scripts/preferences.sh scripts/find-python.sh
    scripts/dream/feedback.py scripts/dream/preferences.py
    docs/preferences/README.md docs/procedures/preferences.md
    tests/template/test_feedback.sh tests/template/test_preferences.sh
    tests/template/test_find_python.sh tests/template/test_taste_project.sh
    scripts/doctor.sh tests/template/test_doctor.sh
    .codex/hooks.json scripts/codex-hook.cmd tests/template/test_codex_hooks.sh
  )
  for f in "${required[@]}"; do
    [[ -f "$f" ]] || terr "required template file missing: $f"
  done

  # 5c. CLAUDE.md is exactly the one-line import.
  [[ "$(cat CLAUDE.md)" == "@AGENTS.md" ]] || terr "CLAUDE.md must be exactly '@AGENTS.md'"

  # 5d. Template placeholders intact; nothing pretends to be started.
  grep -q '{{FILLED_BY_START}}' AGENTS.md || terr "AGENTS.md lost its {{FILLED_BY_START}} placeholders"
  grep -q 'Status: TEMPLATE' AGENTS.md || terr "AGENTS.md lost its template status line"
  # The stack steps belong to each project's own scripts/stack-check.sh, so
  # the template carries the hand-off and never a stack-check.sh of its own.
  grep -q '\./scripts/stack-check\.sh ' scripts/check.sh || terr "check.sh lost its hand-off to scripts/stack-check.sh"
  [[ ! -e scripts/stack-check.sh ]] || terr "scripts/stack-check.sh is project-owned; the template must not ship one"
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

  # 5f. settings.json parses as JSON (Python exists in CI; degrades locally).
  # A subshell, so a missing or odd helper cannot end this script under set -e.
  PY="$(bash -c '. scripts/find-python.sh 2>/dev/null; printf %s "${PY:-}"')"
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

  # 5k. Template Python carries its own ruff contract. Projects that run
  # "ruff check ." or "ruff format --check ." with stricter rules must not
  # fail on synced template files, so every tracked .py lies under a folder
  # below the root with its own ruff.toml (ruff uses the closest config; a
  # root config is never synced), and the pinned ruff passes check and
  # format --check there. format --check guards the folders' format exclusion.
  # The same two runs repeat from a scratch root whose config selects every
  # rule, so the folder config must win over a strict project config.
  # Runner: ruff on PATH at exactly RUFF_PIN, else uvx, else pipx (network on
  # first use; pinned by exact version since the template has no lockfile).
  # Test hook: TEMPLATE_RUFF names the ruff command (the self-tests' fake).
  RUFF_PIN="0.16.10"
  ruff_dirs=()
  while IFS= read -r f; do ruff_dirs+=("${f%/ruff.toml}"); done < <(git ls-files -- '*/ruff.toml')
  while IFS= read -r p; do
    covered=0
    for d in "${ruff_dirs[@]+"${ruff_dirs[@]}"}"; do
      if [[ "$p" == "$d/"* ]]; then covered=1; break; fi
    done
    (( covered )) || terr "$p is template Python outside a folder with its own ruff.toml; projects would lint it with their own rules (move it under such a folder)"
  done < <(git ls-files -- '*.py')
  if (( ${#ruff_dirs[@]} > 0 )); then
    ruff_cmd=(); ruff_via=""
    if [[ -n "${TEMPLATE_RUFF:-}" ]]; then
      ruff_cmd=("$TEMPLATE_RUFF"); ruff_via="TEMPLATE_RUFF ($TEMPLATE_RUFF)"
    elif command -v ruff >/dev/null 2>&1 && [[ "$(ruff --version 2>/dev/null || true)" == "ruff $RUFF_PIN" ]]; then
      ruff_cmd=(ruff); ruff_via="ruff on PATH"
    elif command -v uvx >/dev/null 2>&1; then
      ruff_cmd=(uvx "ruff@$RUFF_PIN"); ruff_via="uvx"
    elif command -v pipx >/dev/null 2>&1; then
      ruff_cmd=(pipx run "ruff==$RUFF_PIN"); ruff_via="pipx"
    fi
    if (( ${#ruff_cmd[@]} == 0 )); then
      terr "ruff $RUFF_PIN is needed for the template's Python (${ruff_dirs[*]}): install exactly that version, or uv (uvx) or pipx"
    elif ! ruff_ver="$("${ruff_cmd[@]}" --version 2>&1)"; then
      terr "could not run ruff $RUFF_PIN through $ruff_via: $ruff_ver"
    else
      echo "template ruff: $ruff_via, $ruff_ver"
      "${ruff_cmd[@]}" check --no-cache --quiet "${ruff_dirs[@]}" \
        || terr "ruff check failed on the template's Python (${ruff_dirs[*]})"
      "${ruff_cmd[@]}" format --no-cache --check --quiet "${ruff_dirs[@]}" \
        || terr "ruff format --check failed on the template's Python; keep the [format] exclude in each folder ruff.toml"
      scratch="$(mktemp -d "${TMPDIR:-/tmp}/template-ruff.XXXXXX")"
      printf '[tool.ruff]\nline-length = 40\n\n[tool.ruff.lint]\nselect = ["ALL"]\n' > "$scratch/pyproject.toml"
      while IFS= read -r f; do
        mkdir -p "$scratch/$(dirname "$f")" && cp "$f" "$scratch/$f"
      done < <(git ls-files -- '*/ruff.toml' '*.py')
      if ! (cd "$scratch" && "${ruff_cmd[@]}" check --no-cache --quiet "${ruff_dirs[@]}" \
            && "${ruff_cmd[@]}" format --no-cache --check --quiet "${ruff_dirs[@]}"); then
        terr "a strict project-root ruff config overrides a folder ruff.toml; projects would lint template Python with their own rules"
      fi
      case "$scratch" in */template-ruff.*) rm -rf -- "$scratch" ;; esac
    fi
  fi

  # 5l. No script pipes into head. Under pipefail the writer dies with
  # SIGPIPE (exit 141) once its output outlives head, which turned a long dash
  # list into a crash; use sed -n '1,Np', which reads all its input. Not
  # linted, same mechanism: an early-exit grep -q or grep -m on a pipe.
  heads="$(git grep -nE '\|[[:space:]]*head([[:space:]]|$)' -- 'scripts/*.sh' | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' || true)"
  if [[ -n "$heads" ]]; then
    printf '%s\n' "$heads"
    terr "a script pipes into head (exit 141 under pipefail on long output); use sed -n '1,Np'"
  fi

  # 5m. The template's skills are exactly the core list scripts/lessons.sh
  # counts apart from project skills (kernel rule 10, ADR 0012), so a core
  # skill added without its CORE_SKILLS entry cannot ship as a project skill.
  core_want="$(./scripts/lessons.sh core-skills | sort)"
  core_have="$(find .claude/skills -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort)"
  if [[ "$core_want" != "$core_have" ]]; then
    terr "the template's .claude/skills ($(echo $core_have)) differ from CORE_SKILLS in scripts/lessons.sh ($(echo $core_want))"
  fi

  if (( tfail || gfail )); then
    fail "template self-test found the problems listed above"
  fi
  echo "template self-test: OK (${#required[@]} required files, script syntax, frontmatter, placeholders, ADR refs, check.sh fixture, blueprint parity, template Python ruff contract, no pipe into head, core skills list; always section: style and characters, memory caps, task graph, task state, ADR format, doc questions, selftest, preference registers)"
  exit 0
fi

# Project mode: the always section decides before the stack block runs.
if (( gfail )); then
  fail "the always checks found the problems listed above"
fi

# Stack gauntlet. The project's own steps live in scripts/stack-check.sh,
# which the project owns and template-sync never touches, so this file stays
# the template's and syncs without conflicts. The start procedure
# (docs/procedures/start.md, step 3) writes stack-check.sh from the stack
# reference table in docs/BLUEPRINT.md section 4, one role per step below;
# every role is filled or its gap is logged in START_REPORT.md with a reason.
# It receives --full-mutation (the full mutation run instead of changed files
# only) and --quick (skip the build and the mutation run) and must honour
# both. It runs under bash, so it needs no executable bit: a bit set on a
# Windows checkout never reaches git, and CI would then refuse the file.
#
#   - Format check
#   - Typecheck
#   - Lint + boundary rules
#   - Tests (with each adopted profile's gates and each installed tool's tests)
#   - Secret scan (gitleaks)
#   - Production build (when the project has one)
#   - Mutation testing
#   - CHANGELOG freshness: regenerate with git-cliff to a temp path and diff;
#     fail on drift

if [[ ! -f scripts/stack-check.sh ]]; then
  fail ".start-done exists but scripts/stack-check.sh is missing. Write the stack steps there (docs/procedures/start.md step 3), or remove .start-done."
fi
stack_args=()
if (( FULL_MUTATION )); then stack_args+=(--full-mutation); fi
if (( QUICK )); then stack_args+=(--quick); fi
bash ./scripts/stack-check.sh ${stack_args[@]+"${stack_args[@]}"} || fail "scripts/stack-check.sh failed"
echo "check: OK (always section and scripts/stack-check.sh)"
