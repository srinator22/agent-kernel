#!/usr/bin/env bash
# Exercises check-project-readmes.sh against isolated pass and fail fixtures.
# Run: bash docs/library/tools/tests/test_check_project_readmes.sh
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$HERE/../check-project-readmes.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

fail() { echo "PROJECT README TEST FAILED: $*" >&2; exit 1; }
expect() { # expect CODE DESCRIPTION [stderr-substring] -- command...
  local want="$1" what="$2" needle="" got=0
  shift 2
  if [[ "$1" != "--" ]]; then needle="$1"; shift; fi
  shift
  "$@" >"$work/out.txt" 2>&1 || got=$?
  [[ "$got" == "$want" ]] || { cat "$work/out.txt" >&2; fail "$what: expected exit $want, got $got"; }
  [[ -z "$needle" ]] || grep -Fq -- "$needle" "$work/out.txt" || { cat "$work/out.txt" >&2; fail "$what: output lacks '$needle'"; }
}

full_readme() { # full_readme FILE [FENCE]  - eleven headings, optionally all inside a fence
  local file="$1" fence="${2:-}"
  {
    echo '# Example'
    [[ -z "$fence" ]] || echo "${fence}markdown"
    printf '%s\n' '## What it does' '## Requirements' '## Install' '## Verify installation' '## Use' \
      '## Update' '## Uninstall' '## Troubleshooting' '## Versioning and changelog' '## Known limitations' \
      '## Development and verification'
    [[ -z "$fence" ]] || echo "$fence"
  } > "$file"
}

# 1. A complete README passes.
ok="$work/ok"; mkdir -p "$ok/projects/example"
full_readme "$ok/projects/example/README.md"
expect 0 "complete README" "project-readmes: OK (1 project(s))" -- bash "$CHECK" "$ok"

# 2. Headings only inside a fenced block do not count, for both fence characters.
fenced="$work/fenced"; mkdir -p "$fenced/projects/fenced-example"
for fence in '```' '~~~'; do
  full_readme "$fenced/projects/fenced-example/README.md" "$fence"
  expect 1 "fenced fake headings ($fence)" "missing required section: ## What it does" -- bash "$CHECK" "$fenced"
done

# 3. A line that merely starts with the fence characters plus text does not close the fence.
for fence in '```' '~~~'; do
  {
    echo '# Pseudo-closer'; echo "${fence}markdown"; echo "${fence}not-a-commonmark-close"
    printf '%s\n' '## What it does' '## Requirements' '## Install' '## Verify installation' '## Use' \
      '## Update' '## Uninstall' '## Troubleshooting' '## Versioning and changelog' '## Known limitations' \
      '## Development and verification'
    echo "$fence"
  } > "$fenced/projects/fenced-example/README.md"
  expect 1 "pseudo-closer ($fence)" "missing required section: ## What it does" -- bash "$CHECK" "$fenced"
done

# 4. A missing section is named.
sed -i '/^## Use$/d' "$ok/projects/example/README.md"
expect 1 "missing section" "missing required section: ## Use" -- bash "$CHECK" "$ok"

# 5. A project folder without a README fails and is named.
full_readme "$ok/projects/example/README.md"; mkdir -p "$ok/projects/norm"
expect 1 "missing README" "norm is missing README.md" -- bash "$CHECK" "$ok"

# 6. CRLF line endings still pass.
crlf="$work/crlf"; mkdir -p "$crlf/projects/p"
full_readme "$crlf/projects/p/README.md"; sed -i 's/$/\r/' "$crlf/projects/p/README.md"
expect 0 "CRLF README" -- bash "$CHECK" "$crlf"

# 7. A custom projects folder and a custom section list (comments and blanks ignored).
custom="$work/custom"; mkdir -p "$custom/tools/a"
printf '%s\n' '# Tool' '## Purpose' '## Usage' > "$custom/tools/a/README.md"
printf '%s\n' '#! required headings' '## Purpose' '' '## Usage' > "$work/sections.txt"
expect 0 "custom folder and sections" -- bash "$CHECK" "$custom" --projects-dir tools --sections "$work/sections.txt"
printf '%s\n' '## Purpose' '## Limits' > "$work/sections2.txt"
expect 1 "custom section missing" "missing required section: ## Limits" -- bash "$CHECK" "$custom" --projects-dir tools --sections "$work/sections2.txt"

# 8. Could-not-run cases exit 2.
expect 2 "no projects folder" "does not exist" -- bash "$CHECK" "$work/empty-root"
mkdir -p "$work/noprojects/projects"
expect 2 "no project directories" "no project directories" -- bash "$CHECK" "$work/noprojects"
: > "$work/blank.txt"
expect 2 "empty section list" "lists no headings" -- bash "$CHECK" "$custom" --projects-dir tools --sections "$work/blank.txt"
expect 2 "unknown option" "unknown option" -- bash "$CHECK" "$custom" --bogus
expect 0 "help" -- bash "$CHECK" --help

echo "project-readme-test: OK"
