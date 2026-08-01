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

Post-build review round (2026-08-01), items verified before acting:

- Codex conventions confirmed against developers.openai.com/codex (which
  redirects to learn.chatgpt.com): project skills live in
  .agents/skills/<name>/SKILL.md with the same name/description
  frontmatter; custom agents are .codex/agents/*.toml with required
  name, description, and developer_instructions fields; project agents
  override the built-ins (default, worker, explorer), so worker.toml
  deliberately overrides Codex's built-in worker. Codex offers no
  per-command hook, so the Codex-side commit/push denial is prose plus
  the advisor gate; the Codex reviewer is mechanically read-only via
  sandbox_mode = "read-only".
- Hook shell resolution confirmed in the hooks docs: hook commands run
  under sh on unix and under Git Bash on Windows when Git Bash is
  installed (bash on the PowerShell PATH is not required); PowerShell is
  the default only when Git Bash is absent - and a machine without Git
  Bash cannot run scripts/check.sh at all. The bash-syntax worker hook
  therefore stands; where it cannot run it degrades to a non-blocking
  error plus the prose rule and the advisor gate.
- scripts/check.ps1 added: native Windows shells (bash not on PATH there
  on the build machine, reproduced) get a wrapper that locates Git Bash
  and forwards to the canonical check.sh. One gauntlet, two entry doors.
- check.sh template mode now runs a template self-test (script syntax,
  required-file tree, placeholders, frontmatter, settings.json validity,
  executable bits, dash scan on tracked files) so the green badge attests
  template integrity rather than inactivity.

Second review round (2026-08-01):

- Private vulnerability reporting was disabled while SECURITY.md pointed
  to it; enabled via the GitHub API and verified (enabled: true), so the
  shipped instructions are now truthful.
- Windows execution policy Restricted reproduced: powershell -File
  refuses unsigned scripts on default machines. scripts\check.cmd added
  as the one-command Windows entry (per-invocation ExecutionPolicy
  Bypass -> check.ps1 -> Git Bash -> check.sh). Batch files need CRLF;
  .gitattributes pins *.cmd and *.bat to eol=crlf.
- Worker-hook runtime status, stated precisely: the hook command's
  block/pass behavior was tested in-session (exit 2 on git commit/push
  input, 0 otherwise), and the wiring follows the documented per-agent
  PreToolUse pattern; an end-to-end firing test requires running the
  worker under Claude Code, which the external reviewer could not do
  (no Claude CLI on their side). Docs confirm hook commands resolve Git
  Bash on Windows independently of the PowerShell PATH.
