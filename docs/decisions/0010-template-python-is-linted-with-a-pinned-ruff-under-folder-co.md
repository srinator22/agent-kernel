# 0010 - Template Python is linted with a pinned ruff under folder configs

Date: 2026-11-08
Status: accepted

## Context

The template ships Python in docs/library, docs/profiles and scripts/dream.
A started project's own ruff gate reads every tracked .py, so the first syncs
to template-v0.3.0 (2026-11-08) failed on the template's files: under ruff's
default rules they had 49 findings, and two projects excluded docs/profiles
from ruff to get green. Adopted-profile files reach a project only as DIFF
reports, while a folder ruff.toml in the core set is applied, so whatever the
template asks of its own Python must be a contract every project can meet.

Considered and rejected: no lint for template Python (the next finding breaks
projects again at sync); linting with the project's own config (the template
cannot know it, and stricter project rules would fail on every sync); more
than ruff's default rules, or ruff format, in the folder configs (projects
with other styles would fail); ruff unpinned (rule sets and defaults change
between minor releases, and the template has no lockfile to hold a version).

## Decision

Each folder that holds template Python carries its own ruff.toml: ruff's
default rules (E4, E7, E9, F) at target py311, with its .py files excluded
from ruff format. A folder config overrides a project's root config for the
files under it. In template mode, check.sh step 5k fails on any tracked .py
outside such a folder, runs ruff 0.16.10 (pinned in RUFF_PIN) check and
format --check on those folders, and runs both again from a scratch root
that selects every rule, to prove the folder config wins. The runner is ruff
on PATH at exactly that version, else uvx, else pipx. Self-tests use a fake
runner and never reach the network.

## Consequences

A project's ruff gate passes on template files without an exclusion, and a
new template .py outside a configured folder fails the template's own check.
The template repository needs ruff 0.16.10 through PATH, uvx or pipx, with
network on first use; started projects need nothing. Moving the pin is a
deliberate edit of RUFF_PIN with the findings of the new version fixed in
the same change. Template Python stays at the default rule set, so stricter
style is a project's choice for its own code only.
