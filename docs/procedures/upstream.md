# Upstream - lessons flow back to the template; projects stay in sync

Three flows: a project's process lessons go up to the template; template
updates come down to the project; and the template is adopted into an
existing project. The template repository is the shared source of the
process; a project's AGENTS.md "Project decisions" section is never
overwritten by it.

## Core file set

One list, used by adoption and by `scripts/template-sync.sh` (the script
reads the same list):

- `AGENTS.md` (kernel block and rules index only, as a diff)
- `CLAUDE.md`, `CONTRIBUTING.md`, `manifest.md`, `cliff.toml`
- `docs/BLUEPRINT.md`, `docs/DEFECT_MEMORY.md`
- `docs/procedures/`, `docs/rules/`, `docs/profiles/`
- `docs/lessons/INDEX.md`, `PENDING.md`, `QUARANTINE.md`, `UPSTREAM.md`
  (format only, never the entries)
- `scripts/`, `tests/template/` (ships with the scripts)
- `.claude/`, `.agents/`, `.codex/`
- `.github/workflows/ci.yml` (as a diff)

Adopted profiles, the AGENTS.md kernel block and the rules index are NEVER
applied automatically: they are shown as diffs for the human. The rest of the
set applies only when the project's copy is untouched since the last sync.

## Lessons up

1. A retro lesson about the process itself (how work is run, not what the
   product does) is written to `docs/lessons/UPSTREAM.md` in the project,
   in the four-field format of `docs/lessons/PENDING.md` (what happened /
   what check should have caught it / what was added / retire-when) plus
   a fifth field, `applies to:` `core` or a named profile. Product
   lessons stay in PENDING.md.
2. At maintenance (`docs/procedures/maintain.md`) the owner opens an issue
   or PR on the template repository carrying the UPSTREAM.md entries,
   then marks them sent with the link. The template's own retro and the
   human approval gate decide acceptance (kernel rule 9); nothing lands
   in the template unreviewed.

## Template sync (down)

3. `scripts/template-sync.sh`:
   - fetches the template repository at a given tag
   - diffs the core file set above against the project
   - applies non-conflicting updates to files the project never changed
   - never touches the AGENTS.md "Project decisions" section
   - shows adopted profiles, the kernel block and the rules index as a
     diff, never applied
   - re-verifies the kernel hash after applying
   - appends `template-sync: <tag> <date>` to `docs/lessons/MAINTENANCE.log`
     when no conflict remains (the counts are printed, not logged)
   Guards: run it on a branch with a clean working tree; `tests/template`
   ships with `scripts/` so the synced scripts keep their selftests. Review
   the diff, run `./scripts/check.sh`, commit. A conflict (the project edited
   the file and the template changed it too) is reported with its diff and
   left for the advisor to merge by hand; a file the project customizes, such
   as `scripts/check.sh` after start, conflicts on every template change. After
   the hand merge, rerun with `--resolved` to record the sync; until then it is
   reported on every run and nothing is recorded.

## Adopting the template into an existing project

4. Paste-ready prompt (one canonical text; the README quotes it verbatim):
   "Adopt the project template from <TEMPLATE URL> at tag <TAG> into this
   repository. Read its AGENTS.md and docs/procedures/upstream.md. First list
   every file you would add or change and stop for my approval. Then copy the
   core file set without overwriting existing files, run
   docs/procedures/discover.md and docs/procedures/start.md in
   existing-project mode with one batched interview, wire scripts/check.sh to
   this project's existing commands, quarantine any test that already fails
   with an owner task, and record the adoption as an ADR with the template
   tag. Do not touch CI, branch protection or tags without asking."
5. Steps behind the prompt:
   1. List every file to add or change; stop for approval.
   2. Copy the core file set. An existing AGENTS.md or CLAUDE.md is merged
      by hand, never replaced; keep its project content under Project
      decisions. Add the `.gitignore` additions.
   3. Run `discover.md` and `start.md` in existing-project mode as one
      batched interview: start reads the code, build files and CI to fill
      the decisions it would otherwise ask about, and asks only what remains.
   4. Wire `scripts/check.sh` to the project's existing commands; it must
      pass on the unmodified code before anything else changes. Record
      failures that already exist in BACKLOG.md; quarantine failing tests
      in `tests/quarantine.list` with an owner task (tests.md); fix neither
      here.
   5. Record the adoption as an ADR (what was copied, what was merged,
      what was deferred, the template tag adopted).
