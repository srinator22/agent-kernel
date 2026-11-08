# 0008 - Template releases reach projects through tags, a notice and a skill

Date: 2026-11-07
Status: accepted

## Context

Five local projects started from this template (survey of C:\dev,
2026-11-07) and none had synced since start. The template had no tag after
template-v0.2.1 while 59 commits landed, so projects pinned bare commits
(bab43ac, 90cf73a). A dry-run sync of each project to template main showed
why syncing stalled: every project had customized `scripts/check.sh` (117 to
408 changed lines), so every template change to it conflicts; three
"- Template:" line formats were in use and one project had none; one
project's recorded base was wrong (5 conflicts from template-v0.2.1, 0 from
its real base bab43ac); the Profiles parser read prose as profile names; and
`docs/library/` and `docs/roster/`, where 31 of the changes since the tag
landed, were outside the synced set.

Considered and rejected: a scheduled GitHub Action in each project that opens
update PRs (needs CI write permissions, pull requests opened with the Actions
token do not trigger CI, one project has no remote, and conflicts need
judgment anyway); syncing to the template's main branch (no stable point to
compare against or to name in a project); copying the library into every
project (it is an opt-in catalog, and two of the five projects never took
it).

## Decision

The template cuts `template-vMAJOR.MINOR.PATCH` tags with
`scripts/template-release.sh` (minor by default, major suggested when the
kernel changed; each tag push is an owner approval). A project learns at
session start that a newer tag exists (cached ls-remote, at most once a day,
in the background) and the `template-update` skill runs the sync on a branch
and ships it as a PR. The project's stack steps move out of check.sh into the
project-owned `scripts/stack-check.sh`, which the sync never touches, so
check.sh stays template-owned. The "- Template: <url> <ref>" line is exact
and checked against the last recorded sync. `--baseline` and
`--suggest-baseline` repair a missing or wrong sync record. The catalogs sync
only where a project carries them. `scripts/fleet.sh` shows every local
project's state from a gitignored list.

## Consequences

Projects get template improvements as reviewable PRs instead of never. Each
project pays a one-time move of its stack steps into stack-check.sh in its
first sync PR, and fixes its Template line there. Tagging becomes a release
step the template owner must run; session start in the template reports
unreleased synced-set commits so it is not forgotten. Library items a project
copied into its own folders still do not update (BACKLOG), and a hook
dispatcher for `.claude/settings.json`, the other file every project edits,
is deferred (BACKLOG).
