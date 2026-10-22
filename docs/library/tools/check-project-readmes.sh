#!/usr/bin/env bash
# check-project-readmes.sh - every project folder has a README.md with the required section headings.
#
# Purpose: a minimum operator-documentation contract for a repository that holds several small projects
# (macros, add-ins, scripts, tools), so each one says what it does, how to install, verify, use, update and
# remove it, what breaks, and its known limits. Only real headings count: a heading inside a fenced code block
# (``` or ~~~, CommonMark closing rules, up to three spaces of indent) does not.
# Usage: check-project-readmes.sh [ROOT] [--projects-dir NAME] [--sections FILE]
#   ROOT            repository root (default: the folder above this script's folder)
#   --projects-dir  the folder under ROOT whose immediate subfolders are the projects (default: projects)
#   --sections      a file listing the required headings, one per line exactly as written in the README
#                   (for example '## Install'). Blank lines and lines starting with '#!' (comments) are
#                   ignored. The default list is the eleven headings set in the script body.
# Output: 'project-readmes: OK (N project(s))' or 'PROJECT README FAILED: <cause>' on stderr.
# Exit: 0 pass, 1 a README or section is missing, 2 could not run (no projects folder, no projects, bad list).
# Dependencies: bash, awk, find, sort.
# Assumptions: README headings are ATX style ('## Title'), written flush left or with up to three spaces.
# Validation source: ported from a script run in CI over a multi-project repository, with its fenced-heading
# and pseudo-closing-fence cases kept in the test.
set -euo pipefail

PROJECTS_DIR="projects"
SECTIONS_FILE=""
ROOT=""
while (( $# )); do
  case "$1" in
    --projects-dir) [[ $# -ge 2 ]] || { echo "PROJECT README FAILED: --projects-dir needs a value" >&2; exit 2; }; PROJECTS_DIR="$2"; shift 2 ;;
    --sections) [[ $# -ge 2 ]] || { echo "PROJECT README FAILED: --sections needs a value" >&2; exit 2; }; SECTIONS_FILE="$2"; shift 2 ;;
    -h|--help) sed -n '2,/^set -euo/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "PROJECT README FAILED: unknown option $1" >&2; exit 2 ;;
    *) [[ -z "$ROOT" ]] || { echo "PROJECT README FAILED: more than one ROOT given" >&2; exit 2; }; ROOT="$1"; shift ;;
  esac
done
[[ -n "$ROOT" ]] || ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
projects_root="$ROOT/$PROJECTS_DIR"

fail() { echo "PROJECT README FAILED: $*" >&2; exit 1; }
cannot() { echo "PROJECT README FAILED: $*" >&2; exit 2; }

[[ -d "$projects_root" ]] || cannot "$projects_root does not exist"

required_sections=()
if [[ -n "$SECTIONS_FILE" ]]; then
  [[ -f "$SECTIONS_FILE" ]] || cannot "$SECTIONS_FILE does not exist"
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    [[ -n "${line//[[:space:]]/}" ]] || continue
    [[ "$line" == '#!'* ]] && continue
    required_sections+=("$line")
  done < "$SECTIONS_FILE"
  (( ${#required_sections[@]} > 0 )) || cannot "$SECTIONS_FILE lists no headings"
else
  required_sections=(
    "## What it does"
    "## Requirements"
    "## Install"
    "## Verify installation"
    "## Use"
    "## Update"
    "## Uninstall"
    "## Troubleshooting"
    "## Versioning and changelog"
    "## Known limitations"
    "## Development and verification"
  )
fi

project_count=0
while IFS= read -r project_dir; do
  project_count=$((project_count + 1))
  readme="$project_dir/README.md"
  [[ -f "$readme" ]] || fail "$project_dir is missing README.md"

  for section in "${required_sections[@]}"; do
    awk -v required="$section" '
      { sub(/\r$/, "") }

      function trim_markdown_indent(line, count) {
        if (substr(line, 1, 1) == "\t") {
          return ""
        }

        count = 0
        while (count < 3 && substr(line, 1, 1) == " ") {
          line = substr(line, 2)
          count++
        }

        return substr(line, 1, 1) == " " ? "" : line
      }

      function fence_character(line, normalized, marker, count) {
        normalized = trim_markdown_indent(line)
        marker = substr(normalized, 1, 1)
        if (marker != "`" && marker != "~") {
          return ""
        }

        count = 0
        while (substr(normalized, count + 1, 1) == marker) {
          count++
        }

        return count >= 3 ? marker : ""
      }

      function fence_length(line, normalized, marker, count) {
        normalized = trim_markdown_indent(line)
        marker = substr(normalized, 1, 1)
        count = 0
        while (substr(normalized, count + 1, 1) == marker) {
          count++
        }

        return count
      }

      function fence_remainder(line, normalized, marker, count) {
        normalized = trim_markdown_indent(line)
        marker = substr(normalized, 1, 1)
        count = fence_length(line)
        return substr(normalized, count + 1)
      }

      {
        marker = fence_character($0)
        marker_length = marker == "" ? 0 : fence_length($0)
        marker_remainder = marker == "" ? "" : fence_remainder($0)
        if (open_fence != "") {
          if (marker == open_fence && marker_length >= open_fence_length && marker_remainder !~ /[^ \t]/) {
            open_fence = ""
            open_fence_length = 0
          }
          next
        }

        if (marker != "") {
          if (marker != "`" || index(marker_remainder, "`") == 0) {
            open_fence = marker
            open_fence_length = marker_length
            next
          }
        }

        if (trim_markdown_indent($0) == required) {
          found = 1
          exit
        }
      }

      END { exit found ? 0 : 1 }
    ' "$readme" \
      || fail "$readme is missing required section: $section"
  done
done < <(find "$projects_root" -mindepth 1 -maxdepth 1 -type d -print | sort)

(( project_count > 0 )) || cannot "$projects_root contains no project directories"
echo "project-readmes: OK ($project_count project(s))"
