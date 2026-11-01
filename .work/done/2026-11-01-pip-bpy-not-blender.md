# Task: Tell a real Blender process from a pip-installed bpy module
Mode: standard
Branch: fix/pip-bpy-guard
Date: 2026-11-01

## Goal
`./scripts/check.sh` failed on the owner's workstation: a pip `bpy` 5.2.3 (pulled in by PyVista-Blender) imports in plain Python, so `blender_extract.py` and `render_encode.py` took "bpy imports" as "inside Blender". `blender_extract` then extracted the empty default scene and reported PASS. Fix the check at the shared layer so both tools exit 2 outside a Blender process, with or without a pip bpy.

## Non-goals
- Supporting the pip bpy module as a render backend.
- Changing blender_run or any other tool.

## Budget
- Wall-clock: 2 h
- Subagents / workflow runs: 0
- Retries per failing step: 2
- Escalate to human when: push or PR needed

## Assumptions
- [verified] pip bpy reports `bpy.app.binary_path == ''` -> `python -c "import bpy; print(repr(bpy.app.binary_path))"` printed `''`
- [verified] real Blender sets binary_path -> Blender 4.0 `-b --factory-startup` printed its blender.exe path, and `rc.require_blender()` returned bpy
- [verified] real Blender path still works -> `blender.exe -b --factory-startup -P blender_extract.py -- --out <scratch>` PASS, 250 frames

## Acceptance criteria
- [x] `rc.require_blender()` rejects no bpy and pip bpy, accepts a Blender process -> docs/library/tools/tests/test_render_common.py
- [x] blender_extract exits 2 and writes nothing with a pip bpy -> docs/library/tools/tests/test_blender_compat.py
- [x] render_encode exits 2 and writes nothing with a pip bpy -> docs/library/tools/tests/test_render_encode.py
- [x] `./scripts/check.sh` green on this machine -> judgment: exit 0, selftest 17 passed 0 failed, template self-test OK (log in session scratchpad check2.log)

## Plan
| node | depends on | owner files | worker tier | status |
|---|---|---|---|---|
| N1 | - | docs/library/tools/tests/test_render_common.py, docs/library/tools/tests/test_blender_compat.py, docs/library/tools/tests/test_render_encode.py | advisor | done |
| N2 | N1 | docs/library/tools/render_common.py, docs/library/tools/blender_extract.py, docs/library/tools/render_encode.py | advisor | done |

## Plan verdict

## Progress log
- 2026-11-01 reproduced: 2 failures in tools tests; failed run also wrote %TEMP%/never_written_extract.json (removed)
- 2026-11-01 regression tests red (7), fix applied, 7 green; check.sh exit 0
- 2026-11-01 reviewer FAIL on missing verify output only; header lines fixed (render_common.py, render_encode.py); targeted 7 ok, check.sh exit 0 again

## Review verdict
- 2026-11-01 reviewer agent, second pass: PASS. Evidence: targeted.log (7 ok), check2.log (17/17 selftest, template self-test OK, exit 0). Not blocking: pip bpy binary_path is writable, so code in the same process could set it; a fresh interpreter running the tool does not hit this.

## Retro
- Defect route (b), escaped past merge of PR #8: the tools tests passed in CI and on machines without a pip bpy; installing PyVista-Blender (pip bpy 5.2.3) on the workstation exposed it.
- Regression tests exist and failed before the fix (test_render_common.RequireBlender, the pip-bpy cases in test_blender_compat.py and test_render_encode.py), so the cause is a check now; no PENDING lesson.
- Repaired damage: the stale %TEMP%/never_written_extract.json the failing test wrote was removed.
- No lessons consulted; BACKLOG unchanged (no item covered this).
