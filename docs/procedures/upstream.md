# Upstream - lessons flow back to the template; projects stay in sync

Four flows: lessons up; versioned releases; releases down to projects;
adoption into an existing project. The template is the shared source of the
process; a project's AGENTS.md "Project decisions"
section is never overwritten by it.

## Core file set

One list. The sync script prints it with its --list-set option and a test
keeps this section equal to that output.

- `AGENTS.md`: the kernel block and the rules index only, shown as diffs,
  never applied
- `CLAUDE.md`, `CONTRIBUTING.md`, `manifest.md`, `cliff.toml`
- `docs/BLUEPRINT.md`, `docs/DEFECT_MEMORY.md`
- `docs/preferences/README.md`: the register format; the other files there
  are project-owned
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
   in the format of `docs/lessons/PENDING.md` plus
   a fifth field, `applies to:` `core` or a named profile. Product
   lessons stay in PENDING.md.
2. At maintenance (`docs/procedures/maintain.md`) the owner opens an issue
   or PR on the template repository carrying the UPSTREAM.md entries,
   then marks them sent with the link. Acceptance follows kernel rule 9;
   nothing lands in the template unreviewed.

## Template releases

3. Projects sync to tags, never to a moving branch. In the template,
   `scripts/template-release.sh` proposes the next `template-vMAJOR.MINOR.PATCH`
   (minor by default; `--major` is suggested when the kernel block changed)
   and prints the notes grouped as synced, library and roster, not synced.
   `--tag` creates the annotated tag on a clean main equal to origin/main and
   prints the push command; pushing the tag is an owner approval (kernel
   rule 15).
4. `scripts/fleet.sh` lists the local projects named in `fleet.local.list`
   (one path per line, gitignored) with Template line, last
   sync, commits behind the newest tag and a
   status: OK, BEHIND, NO-BASE, BAD-LINE or MISSING. It is read-only. A
   commit counts as synced-set when it touches a core or catalog path, changes
   the first 12 lines of a lessons file, or changes the AGENTS.md kernel block
   or rules index. The sync script's --synced-commits option prints one
   "<sha> <kind>" line per such commit.
   `scripts/fleet-status.sh [--tsv]` is the short form: read-only, offline,
   exit 0 even when projects lag.
   `scripts/rating.sh [--offline]` prints the numbers behind a template
   rating.

## Template sync (down)

5. A project records its template as exactly `- Template: <url> <ref>` under
   Project decisions, and every recorded sync appends
   `template-sync: <ref> <date>` to `docs/lessons/MAINTENANCE.log`.
   `scripts/template-sync.sh --status` (run by check.sh) fails when the line
   is missing, carries anything else, or names a ref other than the last
   sync.
6. At session start a project prints `Template update available` when the
   newest template tag (checked in the background at most once a day;
   `TEMPLATE_UPDATE_CHECK=0` turns it off) is newer than its last sync. The
   `template-update` skill then runs these steps:
   1. Stop if the working tree is not clean.
   2. Branch `chore/template-sync-<tag>` from the default branch. Bootstrap:
      when `scripts/template-sync.sh --help` does not list `--latest` (the
      script predates template-v0.3.0), first replace it with the newest
      tag's copy and commit that alone.
   3. Dry run: `scripts/template-sync.sh --latest --dry-run`. When the
      project has no usable sync record (NO-BASE or a wrong base),
      run `--suggest-baseline`, pick the best match with the owner, and
      pass `--baseline <ref>` from here on.
   4. Apply: `scripts/template-sync.sh --latest` (plus `--baseline` when
      used). UPDATE and ADD entries are applied by the script.
   5. Merge each CONFLICT by hand, keeping the project's customizations.
      A conflict on check.sh is usually
      stack steps: move them into scripts/stack-check.sh once
      and take the template's check.sh.
   6. KERNEL CHANGE: stop and ask the owner about the kernel only (ADR 0020):
      every other file is already applied, and the sync stays unrecorded, so
      the next run keeps the old ref as its base. On the owner's word rerun
      with `scripts/template-sync.sh --accept-kernel`: it copies the template
      kernel verbatim and updates the hash only when the project kernel equals
      its last recorded release's; otherwise merge it by hand with
      `scripts/kernel-hash.sh --update` in the same commit. Standing approval:
      a Standing overrides line with "template kernel accepted verbatim",
      recorded only by the human; `scripts/fleet-sync.sh` then passes the
      flag for that project. Merge the rules
      index diff by hand. DIFF entries (adopted profiles, ci.yml) are read
      and merged only where the project wants them.
   7. Set `- Template: <url> <tag>` to the new tag. With no conflicts and no kernel pending, step 4
      already recorded the sync. After hand-merged conflicts, commit
      the work so far (a real apply refuses a dirty tree), then
      rerun step 4 with the same flags plus `--resolved` so the sync is
      recorded, and commit again.
   8. Run `./scripts/check.sh` until green, then ship per
      `docs/procedures/ship.md`, the commit body listing what the sync
      applied, merged and left.
   9. Drop workarounds the new release makes unnecessary (since v0.3.0):
      - take the template's `scripts/selftest.sh` and `scripts/new-task.sh`
        over a local fix;
      - drop quarantine entries for
        `tests/template/test_blueprint_parity.sh` and `test_check_always.sh`
        once they pass;
      - reword "direct-to-main on master" to "direct-to-main, on master"
        (new-task.sh misreads it as gated);
      - drop a ruff exclusion of `docs/profiles` or `docs/library`;
      - when `.claude/settings.json` conflicts, merge the `UserPromptSubmit`
        entry that runs `scripts/feedback-log.sh` (with `"timeout": 5`) by
        hand; session-context warns until it is wired;
      - after a sync that brings `.codex/hooks.json`, open the project in
        Codex once and trust it and its five hooks (template ADR 0014).

   RETIRED CORE SKILL names a skill the new release dropped from
   `CORE_SKILLS` whose folder the project keeps: it counts as a project
   skill (template ADR 0012); archive it or keep it.

   Verify skill upgrade (a sync that brings software profile rule SW-15,
   template ADR 0016): check.sh then fails project mode until
   `.claude/skills/verify/SKILL.md` exists with no `{{` left. Take the
   template from the new ref
   (`git show <ref>:docs/profiles/software/skills/verify/SKILL.md`),
   fill its `{{VERIFY_...}}` wiring as start.md step 4 describes, install it
   in `.claude/skills/verify/` and `.agents/skills/verify/`, merge
   the profile's `Skills: verify` line into PROFILE.md
   (so it counts as the profile's skill, not a project slot), run it once
   and record the `verify:` line.

   The script never touches the Project decisions section, re-verifies the
   kernel hash after applying, and refuses a real apply on main or on
   a dirty tree. A conflict is reported until merged and
   attested with `--resolved`.

## Installed items

A library, roster or profile file copied into the project
(start step 4, or by hand) is recorded in `docs/installed.list`, one line per
file: `<project path> <template path>`; `#` starts a
comment. The ledger is project-owned and never synced. The template path is
under `docs/library/`, `docs/roster/` or `docs/profiles/`.
Each sync compares the installed copy with its template path (UPDATE, ADD,
CONFLICT, REMOVED, each marked `[installed from <template path>]`).
A malformed line stops the sync with exit 2 and names the line.

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
      by hand, never replaced; its project content goes under Project
      decisions. Add the `.gitignore` additions.
   3. Run `discover.md` and `start.md` in existing-project mode as one
      batched interview.
   4. Write the project's existing commands into `scripts/stack-check.sh`;
      `./scripts/check.sh` must pass on the unmodified code before anything
      else changes. Record existing failures in BACKLOG.md; quarantine
      failing tests in `tests/quarantine.list` with an owner task
      (tests.md); fix neither here.
   5. Record `- Template: <url> <tag>` and the first sync line in
      `docs/lessons/MAINTENANCE.log`, then the adoption as an ADR (what was
      copied, merged, deferred; the tag).
   6. A long existing agent file (`CLAUDE.md` or `AGENTS.md` over the
      180-line cap) moves whole, unedited, to a long-form memory file such
      as `docs/memory/<name>-long-form.md`. The new `AGENTS.md` keeps a
      routing table (topic, when to read, section) and links to it;
      the long-form file links back.
   7. Older ADRs are normalized to the template header and nothing else:
      a title line (`# NNNN - Title`), a `Date: YYYY-MM-DD` line from the
      commit that first added the file, and a `Status:` line. Find the date
      with
      `git log --diff-filter=A --follow --format=%as -- docs/decisions/<file>.md`
      (the last line printed). Body text is untouched.
   8. A project may keep `.claude/skills/<name>/SKILL.md` as a pointer to a
      canonical skill file elsewhere. `scripts/lessons.sh check` accepts it
      when the pointer is the
      only file in its folder, its body (at most 4 non-blank lines) names
      exactly one repo-relative `SKILL.md` path, that file exists, and its
      frontmatter `name:` and `description:` equal the pointer's. A pointer
      with a different name or description, or naming a missing file, fails.
