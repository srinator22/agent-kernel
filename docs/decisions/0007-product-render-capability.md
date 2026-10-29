# 0007 - Product render, animation and film capability as roster roles and library items

Date: 2026-10-29
Status: Accepted

## Context

The owner asked on 2026-10-29 for an opt-in capability that takes a
product from CAD to photoreal stills, turntables, exploded views, mechanism
demos, simulation shots (liquid, cloth, paper) and one-shot product films,
with the rigour the template applies to code and hardware. The evidence
comes from one prior project: a still-render set and a one-shot film of a
transparent plastic product with a liquid-pour demo, rendered with a
portable Blender and Cycles on one GPU. Phase 1 research on the same day
(`docs/research/2026-10-29-*.md`, merged in
`docs/research/2026-10-29-render-recommendations.md`) checked versions,
add-ons, outside tools, techniques, scale-out and tool gaps with sources.

The library admits items with one-project evidence; a profile needs two
(`docs/library/README.md`). The roster admits new roles with no evidence
(ADR 0005).

## Decision

- No `product-render` profile yet. Its outline is a BACKLOG item and the
  graduation target once a second project has used the items.
- Roles go in the roster: four leads (`render-technical-director`,
  `render-research-lead`, `animation-adversarial-reviewer`, `cold-viewer`)
  and seven specialists (`blender-operator`, `cad-asset-preparer`,
  `lookdev-artist`, `cinematographer`, `animator`, `fx-simulation-artist`,
  `render-wrangler`), each with a Codex twin and an Evidence line saying
  whether it carries the prior project's evidence. Five creative roles
  (`art-director`, `storyboard-specialist`, `video-direction-reviewer`,
  `senior-video-editor`, `industrial-designer`) gain the CG additions.
  Brand and typography stay with `art-director`; no sound role until a film
  with audio; music licences are recorded by `senior-video-editor`.
- The staged pipeline (brief to delivery, four hold points, a technical
  director GO with a measured estimate before any preview or final) is a
  library procedure and skill, `product-render`. Its tools are library
  tools with stdlib cores (a small PNG codec; Pillow and numpy only as
  optional fast paths that must agree with the stdlib path), so every tool
  test runs in CI with no new dependency (kernel rule 13). Blender-side
  code is limited to thin extractors and shims; GPU and Blender checks are
  gates the skill runs and records, never no-ops in `check.sh`.
- Defaults taken from the research: Blender 5.2 LTS pinned per project and
  ported only through the compat layer and a check render; video verified
  by a pure-Python MP4 parser, with ffprobe as a cross-check only when
  already installed; CAD import by a FreeCAD round trip, because the STEP
  importer extension depends on a third-party prebuilt binary (an owner
  exception is needed to use it); the render seed stated by each preset
  and decided by a measured flicker comparison, since the Cycles manual and
  the prior lesson disagree.
- Render job state lives in `.work/jobs/render/` (the longjob procedure),
  frames and videos outside the repo and outside cloud-synced folders.
- `scripts/lessons.sh check` now requires roster twins to match their
  `.md` body (only the read-only line may use the sandbox wording) and
  every backticked agent name in a roster Hand-offs section to exist.

## Consequences

- A project picks the render roles and the skill at start or by hand; the
  roles hand work to each other by exact name, checked mechanically.
- Every item is plausible, not proven general: the first project that uses
  it revises it and records what it caught. Lessons that the research
  could not source (sample doubling for transparent materials, a 1.75 px
  filter width, the seed setting) ship as defaults to measure, not rules.
- Outside tools, rented GPUs and farms are researched with dated prices
  but deferred; any use needs an owner decision (kernel rule 15).
