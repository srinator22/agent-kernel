# Task: product-render
Mode: standard
Branch: task/product-render
Date: 2026-10-29

## Goal
Give the template a complete, opt-in capability for photoreal product stills,
turntables, exploded views, mechanism demos, simulation shots (liquid, cloth,
paper) and one-shot product films, from CAD to an approved, verified video,
with the rigour the template already applies to code and hardware. It ships
as roster agents (new render roles plus revised creative roles, each with a
Codex twin), a library procedure and skill for a staged pipeline with hold
points, library tools with tests (CI runs every test that needs no GPU), and
a worked demonstration on a primitive-only sample scene. Source: the owner's
brief `C:\dev\work\prompts\product-render-capability.md` (2026-10-29) and the
Phase 1 research in `docs/research/2026-10-29-*.md`.

## Non-goals
- No kernel edit (AGENTS.md kernel block and `.kernel.hash` unchanged).
- No `docs/profiles/product-render/` profile: evidence is from one project
  (see Decisions D1); its outline goes to BACKLOG as the graduation target.
- No rendering of any real product, no committed renders, frames, caches or
  videos; sample-scene output lives outside the repo and outside cloud-synced
  folders.
- Nothing installed, bought, rented, uploaded or published (kernel rule 15):
  no ffmpeg install, no add-on install or build, no cloud GPU or farm test,
  no vendor contact.
- No change to the in-progress `kb-adaptations` task in the main checkout
  (`C:\dev\work\New Project`, its uncommitted `.work/TASK.md` is untouched);
  this task runs in the worktree `C:\dev\work\New-Project-product-render`.
- No audio tools (no audio in the evidence project; BACKLOG), no paper
  simulation builder, no Flamenco or farm integration (all DEFER in the
  recommendations).
- Library, profile and core agent twins outside `docs/roster/` keep their
  current harness wording (they use a shortened Codex style); only roster
  twins get the strict parity check.

## Budget
- Wall-clock: 16 hours of active work over several sessions, plus one
  overnight window for the sample-scene final if needed.
- Subagents / workflow runs: 30 (6 research reports and 1 merge already used).
- GPU time: sample scene only, under 2 GPU-hours total, measured and logged.
- Retries per failing step: 2
- Escalate to human when: budget exhausted | criteria unreachable | scope exceeds Non-goals | a hold point is reached (D3)

## Decisions for the owner (answer before building)
<!-- recommended option first; the advisor's default applies only once confirmed -->
- D1 Profile: one-project evidence only (one still set and one film of the
  same transparent product), so no profile. (a) outline in BACKLOG as the
  graduation target, items in roster and library [recommended]; (b) draft
  `docs/profiles/product-render/PROFILE.md` anyway (bends the
  library rule; needs an explicit override recorded in an ADR).
- D2 Tool runtime: CI installs no Python packages. (a) stdlib cores with a
  small stdlib PNG codec, Pillow and numpy as optional fast paths, tests run
  both paths where present and assert equal results, CI runs the stdlib path
  [recommended; no new dependency, kernel rule 13]; (b) add Pillow and numpy
  to CI with a pinned lock file; (c) skip image tests in CI (the merge
  pass's suggestion; rejected by the advisor because a skipped test never
  runs there).
- D3 Sample-scene hold points (animatic, check stills, preview, final
  review): (a) a standing approval for the primitive-only sample scene,
  recorded in Project decisions of this task only, every hold record still
  written with its verdict [recommended]; (b) stop for you at each of the
  four holds.
- D4 Video verification without ffprobe: (a) pure-Python MP4 box parser
  always, ffprobe used only when already on PATH, demo records "ffprobe could
  not run here" [recommended]; (b) you install an ffmpeg build yourself
  (ffmpeg.org links only third-party Windows builds, so it is an exception to
  the official-source rule you would record).
- D5 Seed policy: the Cycles manual recommends Animated Seed for animation,
  the prior lesson says off. (a) presets state the seed explicitly, default
  off labelled "unmeasured", and the demo runs a measured A/B with
  flicker_metric that decides the default [recommended]; (b) animated on
  now; (c) off as a rule.
- D6 Pinned Blender: (a) 5.2.3 LTS (current LTS patch, already present
  portable on this machine, maintained to July 2028) [recommended]; (b) 5.3
  at release (dispersion only).
- D7 CAD import: the STEP Importer extension needs the Cascadio prebuilt
  wheel. (a) FreeCAD round trip as the documented default, STEP Importer
  listed as "needs owner exception" [recommended]; (b) treat
  extensions.blender.org as an official publisher.
- D8 Roster twin parity: five roster `.toml` twins have drifted from their
  `.md` (backticks and headings stripped). (a) add a parity check for
  `docs/roster/` that allows only the sandbox-line wording difference, and
  regenerate the five drifted twins from their `.md` as repair (kernel rule 3)
  [recommended]; (b) check only the new and revised render twins.
- D9 Extra roles from the brief: (a) add `cold-viewer` (lead, standard
  tier); fold brand and typography into `art-director`; no sound agent until
  a film with audio, music licences recorded by `senior-video-editor`
  [recommended]; (b) add all three.
- Outside-tool and spend items need no answer now (all DEFER or AVOID in
  `docs/research/2026-10-29-render-recommendations.md` section 3, items 5-9).

## Assumptions
<!-- one line per assumption the work rests on: [confirmed] the human said so,
     [verified] -> evidence (a command or file), [open] not yet settled. -->
- [verified] Machine: NVIDIA RTX 4080 SUPER 16376 MiB, driver 610.88; Blender 5.2.3 portable under the user profile (path kept in the render output root lock file, outside the repo); Python 3.13.5 with Pillow 12.2.0 and numpy 2.3.1; no ffmpeg or ffprobe on PATH -> `nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv` and `blender --help` run 2026-10-29
- [verified] CI installs no packages, and `tests/template/test_profile_tools.sh` runs every `docs/library/tools/tests/test_*.py` with `python -I` -> .github/workflows/ci.yml, tests/template/test_profile_tools.sh
- [verified] Library skills are not counted against the kernel rule 10 cap until adopted into `.claude/skills/` -> scripts/lessons.sh
- [verified] Before this task no check verified hand-off names or md/toml body parity; 43 twin pairs, 24 differing, 7 in the roster -> parity script run 2026-10-29 (recorded in this file), scripts/lessons.sh
- [confirmed] The owner approved the spec and option (a) for every decision D1 to D9 on 2026-10-29 ("Approve all"). D3: standing approval for the four hold points of the primitive-only sample scene only; it does not extend to any real product or later project.
- [verified] Merge order with `task/kb-adaptations`: that task merged to main first; this branch merged origin/main on 2026-10-29, resolved BACKLOG.md, docs/BLUEPRINT.md and .work/TASK.md, and renumbered its ADR to 0007 because main added ADR 0006 -> docs/decisions/0007-product-render-capability.md
- [verified] `--python-exit-code 1` makes a `-P` script exception exit non-zero on 5.2.3 -> `blender_run.py --self-test` exit 0, "failure detected (returncode, script-error, traceback) rc=1" (docs/library/examples/product-render-sample/RECORD.md)

## Acceptance criteria
- [x] A1 Research: six reports and the merged recommendation table under `docs/research/2026-10-29-*.md`, every version, licence and price with a source, evidence level and `VERIFY 2026-10-29`; one cited item per report spot-checked by the advisor -> judgment: done in Phase 1, spot checks listed in the recommendations file
- [x] A2 Revised roster agents (`art-director`, `storyboard-specialist`, `video-direction-reviewer`, `senior-video-editor`, `industrial-designer`) carry the brief's CG additions (honest render labels, reference board, look locked by style frames, preview resolution stated; TO RENDER status, waypoint camera paths with lens, timing, easing, mechanism state per beat, required animatic; finishing with labels, end title hold, encode, platform versions, ffprobe or parser verification; CMF hand-off with material, finish, colour values, reference photos) -> judgment: reviewer reads each against the brief list
- [x] A3 New roster agents with Codex twins: leads `render-technical-director`, `render-research-lead`, `animation-adversarial-reviewer`, `cold-viewer` (read-only tools, read-only sandbox); specialists `blender-operator` (`render/scenes/`), `cad-asset-preparer` (`render/assets/`), `lookdev-artist` (`render/lookdev/`), `cinematographer` (`render/layout/`), `animator` (`render/anim/`), `fx-simulation-artist` (`render/fx/`), `render-wrangler` (`.work/jobs/render/`, gitignored: the longjob procedure keeps STATE files in `.work/jobs/`, so the brief's `render/jobs/` moved there); tiers by name; each states whether it carries project evidence -> tests/template/test_lessons.sh
- [x] A4 Hand-offs resolve: every backticked agent name in a roster `## Hand-offs` section names an agent that ships in the template (roster, library, profiles or core); claims shown in a film go to `engineering-reviewer` -> tests/template/test_lessons.sh (new cases)
- [x] A5 Roster twin parity: each `docs/roster/agents/*.toml` `developer_instructions` equals its `.md` body except the documented sandbox line; the five drifted twins regenerated -> tests/template/test_lessons.sh (new cases)
- [x] A6 `docs/library/procedures/product-render.md` and `docs/library/skills/product-render/SKILL.md`: stages 0 to 9 with owners, inputs, outputs, records and the four HOLD points; GO / NO-GO with time and cost estimate before any preview or final; long renders and bakes via `scripts/bg.sh` with STATE in `.work/jobs/`; delivery to a local folder with a bundle -> scripts/lessons.sh check, judgment: reviewer
- [x] A7 Library tools, each with `--help` and exit codes 0 pass / 1 check failed / 2 could not run, a module header (purpose, inputs, outputs, dependencies, origin "a product film project" or new), tests in `docs/library/tools/tests/`: phase 1 `blender_run`, `render_chunks`, `frame_audit`, `render_sheets`, `render_encode` (inside Blender), `encode_verify`, `render_estimate` (no shipped prices), `render_bundle`; phase 2 `color_check`, `motion_check` with `camera_path`, `scene_lint`, `blender_compat`; phase 3 `flicker_metric`, `sim_validate`, `render_overlay` (label track, side consistency, safe area, end title hold), `fit_check`; one Blender-side extractor `blender_extract` -> docs/library/tools/tests/test_*.py via tests/template/test_profile_tools.sh
- [x] A8 Tests cover empty, malformed, extreme, duplicate, partial and missing inputs on synthetic data (frames, curves, STATE files, MP4 boxes, sim volume series); stdlib and fast paths agree where both exist (D2); no test needs a GPU or Blender -> docs/library/tools/tests/
- [x] A9 GPU and Blender gates (blender_run self-test, extractor runs, renders, encode) are documented in the procedure as gates run by the skill and recorded, never wired into check.sh as no-ops -> judgment: reviewer reads check.sh and the procedure
- [x] A10 Lessons map: every lesson in the brief appears in the procedure's lessons table as a rule, a gate or a tool check (tool and test named), or as prose with the reason it cannot be mechanised; the reworded and default-to-measure items from the recommendations section 2 are carried as such -> judgment: reviewer checks the table against the brief
- [x] A11 Demonstration in `docs/library/examples/product-render-sample/`: primitive-only scene script, presets (check, preview, final), brief, storyboard and shot spec, and stage records for brief, storyboard, animatic, check stills, preview, final, frame QC, encode and verify, with measured seconds per frame, frame counts and tool outputs; frames and video outside the repo at the recorded path; any stage that could not run says so with the reason -> judgment: reviewer reads the records; tool exit codes quoted verbatim
- [x] A12 Wiring: `docs/library/README.md` (layout, tools table, items with origin), `docs/roster/README.md` (render department table, evidence status), ADR 0007, BACKLOG (profile outline, deferred items), `.gitignore` for `render/jobs/` and render outputs, BLUEPRINT tree and README lists where the self-tests require them; no private names, no em or en dashes -> ./scripts/check.sh
- [ ] A13 `./scripts/check.sh` green, `scripts/lessons.sh check` green, independent reviewer PASS recorded here, CI green on the pushed SHA (monitor agent) -> scripts/check.sh

## Plan
<!-- task graph: one node per row; nodes that can run in the same wave must
     own disjoint files. Validate: scripts/taskgraph.sh check -->
| node | depends on | owner files | worker tier | status |
|---|---|---|---|---|
| R1 research | - | docs/research/2026-10-29-blender-versions-api.md, docs/research/2026-10-29-blender-addons.md, docs/research/2026-10-29-outside-tools.md, docs/research/2026-10-29-render-techniques.md, docs/research/2026-10-29-render-scale-out.md, docs/research/2026-10-29-render-tool-gaps.md | standard | done |
| R2 merge | R1 | docs/research/2026-10-29-render-recommendations.md | strong then advisor | done |
| N1 adr | R2 | docs/decisions/0007-product-render-capability.md, BACKLOG.md | advisor | done |
| N2 revise | R2 | docs/roster/agents/art-director.md, docs/roster/agents/art-director.toml, docs/roster/agents/storyboard-specialist.md, docs/roster/agents/storyboard-specialist.toml, docs/roster/agents/video-direction-reviewer.md, docs/roster/agents/video-direction-reviewer.toml, docs/roster/agents/senior-video-editor.md, docs/roster/agents/senior-video-editor.toml, docs/roster/agents/industrial-designer.md, docs/roster/agents/industrial-designer.toml | strong | done |
| N3 leads | R2 | docs/roster/agents/render-technical-director.md, docs/roster/agents/render-technical-director.toml, docs/roster/agents/render-research-lead.md, docs/roster/agents/render-research-lead.toml, docs/roster/agents/animation-adversarial-reviewer.md, docs/roster/agents/animation-adversarial-reviewer.toml, docs/roster/agents/cold-viewer.md, docs/roster/agents/cold-viewer.toml | strong | done |
| N4 specialists | R2 | docs/roster/agents/blender-operator.md, docs/roster/agents/blender-operator.toml, docs/roster/agents/cad-asset-preparer.md, docs/roster/agents/cad-asset-preparer.toml, docs/roster/agents/lookdev-artist.md, docs/roster/agents/lookdev-artist.toml, docs/roster/agents/cinematographer.md, docs/roster/agents/cinematographer.toml, docs/roster/agents/animator.md, docs/roster/agents/animator.toml, docs/roster/agents/fx-simulation-artist.md, docs/roster/agents/fx-simulation-artist.toml, docs/roster/agents/render-wrangler.md, docs/roster/agents/render-wrangler.toml | strong | done |
| N5 checks | R2 | scripts/lessons.sh, tests/template/test_lessons.sh, docs/roster/agents/component-selection-engineer.toml, docs/roster/agents/firmware-lead.toml, docs/roster/agents/mechatronics-integration-lead.toml, docs/roster/agents/senior-pcb-designer.toml, docs/roster/agents/sourcing-lead.toml | advisor | done |
| N6a tools-img | R2 | docs/library/tools/render_common.py, docs/library/tools/frame_audit.py, docs/library/tools/render_sheets.py, docs/library/tools/tests/test_render_common.py, docs/library/tools/tests/test_frame_audit.py, docs/library/tools/tests/test_render_sheets.py | standard then advisor | done |
| N6b tools-run | R2 | docs/library/tools/blender_run.py, docs/library/tools/render_chunks.py, docs/library/tools/encode_verify.py, docs/library/tools/render_estimate.py, docs/library/tools/render_bundle.py, docs/library/tools/tests/test_blender_run.py, docs/library/tools/tests/test_render_chunks.py, docs/library/tools/tests/test_encode_verify.py, docs/library/tools/tests/test_render_estimate.py, docs/library/tools/tests/test_render_bundle.py | standard then advisor | doing |
| N7 tools-2 | N6a, N6b | docs/library/tools/render_encode.py, docs/library/tools/blender_extract.py, docs/library/tools/camera_path.py, docs/library/tools/motion_check.py, docs/library/tools/scene_lint.py, docs/library/tools/blender_compat.py, docs/library/tools/color_check.py, docs/library/tools/tests/test_render_encode.py, docs/library/tools/tests/test_camera_path.py, docs/library/tools/tests/test_motion_check.py, docs/library/tools/tests/test_scene_lint.py, docs/library/tools/tests/test_blender_compat.py, docs/library/tools/tests/test_color_check.py | standard then advisor | done |
| N8 tools-3 | N6a, N6b | docs/library/tools/flicker_metric.py, docs/library/tools/sim_validate.py, docs/library/tools/render_overlay.py, docs/library/tools/fit_check.py, docs/library/tools/tests/test_flicker_metric.py, docs/library/tools/tests/test_sim_validate.py, docs/library/tools/tests/test_render_overlay.py, docs/library/tools/tests/test_fit_check.py | standard then advisor | done |
| N9 procedure | N2, N3, N4, N7, N8 | docs/library/procedures/product-render.md, docs/library/skills/product-render/SKILL.md | advisor | done |
| N10 demo | N9 | docs/library/examples/product-render-sample/** | advisor | done |
| N11 wiring | N1, N5, N10 | docs/library/README.md, docs/roster/README.md, .gitignore, docs/BLUEPRINT.md, README.md, docs/procedures/start.md | advisor | done |
| N12 review | N11 | .work/TASK.md | reviewer | todo |
| N13 ship | N12 | none | advisor then cheap | todo |

Node notes (pitfalls the workers get in their briefs):
- N2 to N4: agent body follows the roster shape (Read first, Checks with the
  failure each prevents, Hard rules, Hand-offs with backticked names,
  Output, Verdict for leads); toml twin is the md body with the one
  sandbox-line substitution; no private names, plain hyphens.
- N6 to N8: stdlib core first (D2); Blender-side code only in
  `render_encode`, `blender_extract`, `blender_compat`, guarded so the module
  imports without `bpy` for tests; absolute output paths enforced; never
  write inside the repo or a cloud-synced folder by default.
- N10: GPU renders run through `render_chunks` under `scripts/bg.sh` with
  STATE in `.work/jobs/`; TD GO recorded with the estimate before preview
  and final; output under `C:\dev\work\_render\product-render-sample\`.

## Progress log
- 2026-10-29 worktree `C:\dev\work\New-Project-product-render` on `task/product-render` from origin/main 076ab5c; main checkout and its kb-adaptations TASK.md left untouched.
- 2026-10-29 R1: six researcher reports written (standard tier, parallel); hygiene scan clean (no private names, ASCII only).
- 2026-10-29 R2: merge pass (strong tier, read-only) saved with advisor corrections; six spot checks, all match.
- 2026-10-29 spec written; stopped for owner approval of the spec and D1 to D9.
- 2026-10-29 owner approved the spec and D1 to D9 option (a); build starts at wave 3.
- 2026-10-29 graph refined before wave 3: N6 split into N6a (image tools) and N6b (run tools), disjoint files; render_encode moved to N7 (needs blender_compat); wrangler state moved to `.work/jobs/render/` (longjob rule).
- 2026-10-29 incident: the N6a worker ran `taskkill /F /IM python.exe` to stop its own hung test and killed three python processes machine-wide (possibly the N6b worker or other sessions). Cause fixed in render_sheets (size check before thumbnail work). Later briefs: stop only by PID or task id, never by image name (docs/rules/destructive-actions.md).
- 2026-10-29 08:33 GPU busy with another session's film render until about 09:30 (message from the parent session; nvidia-smi 94 percent). Demo plan: workbench animatic and extract, lint and fit stages now; every Cycles stage waits for the GPU so the whole sample shot uses one device class (procedure rule 4). No Blender process this task did not start is touched.
- 2026-10-29 09:10 stopped at the usage limit. Done: N1-N9; N11 wiring drafted (READMEs, BLUEPRINT amendment, .gitignore). N10 demo: brief v2 approved, stage 2-3 checks pass, storyboard v3 owed (art-director APPROVE WITH CHANGES in RECORD.md). Resume: storyboard v3 + waypoints W4-W5 reframe + focus on HingePin; render_overlay advisory should test projected object size, not anchor points (art-director finding); then animatic (render_chunks plan in .work/jobs/render/animatic.json), check stills, seed A/B, preview, final, QC, encode, verify, bundle per run.md - GPU only when the other session's film job (blender PID 49692) has exited; then check.sh, reviewer, push, monitor.
- 2026-10-29 17:00 N10 demo complete: animatic, check stills (3 sets), seed A/B, preview (2 runs), final, QC, encode, verify, bundle; verdicts art-director HOLD -> APPROVE WITH CHANGES -> HOLD -> APPROVE (look locked), technical director NO-GO -> GO -> GO (final), animation-adversarial APPROVE WITH CHANGES -> APPROVE (preview) -> APPROVE (final), video-direction APPROVE WITH CHANGES (all done), cold-viewer message matches. Running the demo found 10 tool defects, each fixed with a failing-first regression test (RECORD.md lists them). A1-A12 ticked; A13 waits for check.sh, review and CI.

## Review verdict
<!-- written ONLY by the independent reviewer -->

## Retro
<!-- filled by docs/procedures/retro.md -->
