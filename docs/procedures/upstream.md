# Upstream - lessons flow back to the template; projects stay in sync

Four flows: a project's process lessons go up to the template; the template
cuts versioned releases; releases come down to each project; and the
template is adopted into an existing project. The template repository is
the shared source of the process; a project's AGENTS.md "Project decisions"
section is never overwritten by it.

## Core file set

One list. The sync script prints it with its --list-set option and a test
keeps this section equal to that output.

- `AGENTS.md`: the kernel block and the rules index only, shown as diffs,
  never applied
- `CLAUDE.md`, `CONTRIBUTING.md`, `manifest.md`, `cliff.toml`
- `docs/BLUEPRINT.md`, `docs/DEFECT_MEMORY.md`
- `docs/procedures/`, `docs/rules/`, `docs/profiles/`
- `docs/lessons/INDEX.md`, `docs/lessons/PENDING.md`,
  `docs/lessons/QUARANTINE.md`, `docs/lessons/UPSTREAM.md`: the format
  header only, never the entries
- `scripts/`, `tests/template/` (ships with the scripts)
- `.claude/`, `.agents/`, `.codex/`
- `.github/workflows/ci.yml`: shown as a diff, never applied
- Catalogs, synced only in a project that carries the folder: `docs/library/`,
  `docs/roster/`

Adopted profiles, the AGENTS.md kernel block and the rules index are NEVER
applied automatically: they are shown as diffs for the human. The rest of the
set applies only when the project's copy is untouched since the last sync.
Never touched: the project's own truth files, BACKLOG.md, docs/decisions/,
.work/, the kernel hash, any file named *.local.*, and scripts/stack-check.sh,
which holds the project's own stack steps (start writes it; check.sh runs it
last), so check.sh itself stays the template's and syncs cleanly.

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

## Template releases

3. Projects sync to tags, never to a moving branch. In the template,
   `scripts/template-release.sh` proposes the next `template-vMAJOR.MINOR.PATCH`
   (minor by default; `--major` is suggested when the kernel block changed,
   because projects then need owner approval to take it) and prints the
   notes grouped as synced to projects, library and roster, and not synced.
   `--tag` creates the annotated tag on a clean main equal to origin/main and
   prints the push command; pushing the tag is an owner approval (kernel
   rule 15). At session start the template prints how many synced-set commits
   wait since the newest tag.
4. `scripts/fleet.sh` lists the local projects named in `fleet.local.list`
   (one absolute path per line, gitignored because project paths are
   private) with their Template line, last sync, synced-set commits behind
   the newest tag, uncommitted files, branch, waiting upstream lessons and a
   status: OK, BEHIND, NO-BASE, BAD-LINE or MISSING. It is read-only.

## Template sync (down)

5. A project records its template as exactly `- Template: <url> <ref>` under
   Project decisions, and every recorded sync appends
   `template-sync: <ref> <date>` to `docs/lessons/MAINTENANCE.log`.
   `scripts/template-sync.sh --status` (run by check.sh) fails when the line
   is missing, carries anything else, or names a ref other than the last
   recorded sync.
6. At session start a project prints `Template update available` when the
   newest template tag (checked in the background at most once a day;
   `TEMPLATE_UPDATE_CHECK=0` turns it off) is newer than its last sync. The
   `template-update` skill then runs these steps:
   1. Stop if the working tree is not clean; the owner commits or stashes
      first.
   2. Branch `chore/template-sync-<tag>` from the default branch.
   3. Dry run: `scripts/template-sync.sh --latest --dry-run`. When the
      project has no usable sync record (NO-BASE, or a recorded base that is
      wrong), run `--suggest-baseline`, pick the merge-base or the best match
      with the owner, and pass it as `--baseline <ref>` from here on.
   4. Apply: `scripts/template-sync.sh --latest` (plus `--baseline` when
      used). UPDATE and ADD entries are applied by the script.
   5. Merge each CONFLICT by hand, keeping the project's customizations and
      taking the template's improvements. A conflict on check.sh is usually
      the project's stack steps: move them into scripts/stack-check.sh once
      and take the template's check.sh.
   6. KERNEL CHANGE: stop and ask the owner; an approved kernel goes in with
      `scripts/kernel-hash.sh --update` in the same commit. Merge the rules
      index diff by hand. DIFF entries (adopted profiles, ci.yml) are read
      and merged only where the project wants them.
   7. Set `- Template: <url> <tag>` to the new tag. With no conflicts, step 4
      already recorded the sync. When conflicts were merged by hand, commit
      the work so far on the branch (a real apply refuses a dirty tree), then
      rerun step 4 with the same flags plus `--resolved` so the sync is
      recorded, and commit again.
   8. Run `./scripts/check.sh` until green, then ship per
      `docs/procedures/ship.md` with a commit body listing what the sync
      applied, merged and left.

   The script never touches the Project decisions section, re-verifies the
   kernel hash after applying, and refuses a real apply on main or on a
   dirty tree. A conflict (the project edited the file and the template
   changed it too) is reported with its diff on every run until merged and
   attested with `--resolved`.

## Adopting the template into an existing project

7. Paste-ready prompt (one canonical text; the README quotes it verbatim):
   "Adopt the project template from <TEMPLATE URL> at tag <TAG> into this
   repository. Read its AGENTS.md and docs/procedures/upstream.md. First list
   every file you would add or change and stop for my approval. Then copy the
   core file set without overwriting existing files, run
   docs/procedures/discover.md and docs/procedures/start.md in
   existing-project mode with one batched interview, wire
   scripts/stack-check.sh to this project's existing commands, quarantine any
   test that already fails with an owner task, and record the adoption as an
   ADR with the template tag. Do not touch CI, branch protection or tags
   without asking."
8. Steps behind the prompt:
   1. List every file to add or change; stop for approval.
   2. Copy the core file set. An existing AGENTS.md or CLAUDE.md is merged
      by hand, never replaced; keep its project content under Project
      decisions. Add the `.gitignore` additions.
   3. Run `discover.md` and `start.md` in existing-project mode as one
      batched interview: start reads the code, build files and CI to fill
      the decisions it would otherwise ask about, and asks only what remains.
   4. Write the project's existing commands into `scripts/stack-check.sh`;
      `./scripts/check.sh` must pass on the unmodified code before anything
      else changes. Record failures that already exist in BACKLOG.md;
      quarantine failing tests in `tests/quarantine.list` with an owner task
      (tests.md); fix neither here.
   5. Record `- Template: <url> <tag>` and the first sync line in
      `docs/lessons/MAINTENANCE.log`, then the adoption as an ADR (what was
      copied, what was merged, what was deferred, the template tag adopted).
