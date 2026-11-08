---
name: product-render
description: Run the staged CAD-to-film pipeline for product stills, turntables, exploded views, mechanism demos, simulation shots and one-shot product films in Blender, with hold points and verified output. Use when a render, animation or product video is planned, previewed, rendered, finished or delivered, or when the human runs /product-render. Do not use to publish or upload, to install or buy software, or to start a preview or final render without a recorded technical director GO.
---

Follow docs/procedures/product-render.md exactly. Write the stage record
after every stage; stop at each HOLD (animatic, check stills, preview, final
review) until the human approves; run every render, bake and encode as a
long job through `scripts/bg.sh` with its STATE file in `.work/jobs/render/`;
quote every tool's output verbatim in the record; report preview, final and
delivered separately, with resolution, samples and measured seconds per
frame.

Adopting this skill: copy `docs/library/procedures/product-render.md` to
`docs/procedures/`, the render tools from `docs/library/tools/` to
`tools/render/` (with their tests), and the render roles from
`docs/roster/agents/` with their Codex twins. Record the pinned Blender,
render output root, delivery root and presets in Project decisions. Until
the procedure is copied, read it from
`docs/library/procedures/product-render.md`.
