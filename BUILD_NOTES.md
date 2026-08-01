# Build notes - gaps and uncertainties hit while building

Build date: 2026-08-01. Built from docs/BLUEPRINT.md into
github.com/srinator22/New-Project per the owner's instruction.

- (VERIFY) settings attribution keys: verified against current Claude
  Code docs. `attribution.commit` and `attribution.pr` (empty string
  disables) are the documented keys; `.claude/settings.json` uses them.
- (VERIFY) subagent tool syntax: verified. Frontmatter `tools` /
  `disallowedTools` accept whole tool names only, so Bash-subcommand
  denial cannot be expressed there. The documented mechanism for that is
  a per-agent `PreToolUse` hook ("Conditional rules with hooks" in the
  subagents docs); worker.md uses it, and the hook was tested during the
  build (blocks "git commit"/"git push" with exit 2, passes other
  commands). The matcher is substring-based on purpose and over-blocks
  Bash commands merely containing those strings. On a Windows-only
  environment without bash on PATH, the docs recommend PowerShell hooks
  (shell: powershell); there the hook degrades to a non-blocking error
  and the prose rule plus advisor review carry the constraint.
- ci.yml: PyYAML was unavailable on the build machine, so YAML validity
  is confirmed by GitHub Actions itself parsing and running the workflow
  for the pushed SHA (a parse failure surfaces as a workflow error, not
  a run).
- cliff.toml: validated as TOML; git-cliff is not installed on the build
  machine, so the template renders on first per-project use. gitleaks is
  also not installed locally; both are per-project gauntlet tools that
  start wires and CI runs.
- scripts/ci-watch.sh uses bash 4 associative arrays: fine on ubuntu CI
  and Git Bash; stock macOS bash 3.2 would need a newer bash.
- Superpowers plugin install command: deliberately left as VERIFY at
  start time in manifest.md, per the blueprint.
- The remote repository's root commit ("Initial commit", from GitHub repo
  creation) predates this build and is not Conventional; history from the
  blueprint import onward is Conventional Commits.
