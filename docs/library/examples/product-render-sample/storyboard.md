# Storyboard and shot spec: sample scene

Version 3, 2026-10-29. One shot, no cuts (stage 1). Status: TO RENDER.
24 fps, frames 1 to 120. Camera waypoints are in `waypoints.json`,
interpolated by `camera_path` (monotone pchip: no overshoot between
waypoints). Lens 90 mm full-frame, f/5.6. Focus follows a keyed target: the ball
through frame 50, moving to the hinge pin by frame 62 and held there. No engineering
claim is shown, so there is nothing for `engineering-reviewer`.

Easing: camera pchip through the waypoints (eases into the closing hold at
W4); lid Bezier keyframe ease in and out; label fades smoothstep over 6 frames
(in 50-56, out 74-80, full opacity 56-74, 0.79 s);
title cut in at frame 84 with no fade and held to the last frame.

| Beat | Frames | Camera (waypoint) | Mechanism state | On screen | Risky frames |
|---|---|---|---|---|---|
| 1 Reveal | 1-30 | W1 to W2: slow arc from front left at about 35 degrees elevation, so the ball reads through the lid over the front wall | lid closed | - | 1 (first frame), 30 |
| 2 Open | 30-60 | W2 to W3: continuous push toward the hinge side | lid rotates 0 to 70 degrees about the rear pin | "HINGE" fades in from frame 50 (after the fastest lid motion) | 45 (fastest lid motion, transparency over the ball) |
| 3 Detail | 60-84 | W3 to W4: direct push to about 0.38 m from the pin, narrow swing, never stopping | lid open, still | "HINGE" right of the pin until frame 80, fading out 74-80 | 70 (label next to the clear lid) |
| 4 Title | 84-120 | W4 to W5: hold (declared, the only stop), framed so the ball (y 178-429 px) and the pin (y 47-98 px) are fully in frame | lid open | "SAMPLE SCENE" in the lower third (y 433-467 px), over the matte black front wall of the box | 84 (title in, camera arrives), 100 (title text) |

Waypoints: W1 frame 1, W2 frame 30, W3 frame 60, W4 frame 84, W5 frame 120
(W4 and W5 equal: the closing hold). The animatic (workbench, 480 x 270,
real timing, real camera) is required before lookdev; ball visibility is
confirmed on animatic frames 1, 30, 84 and 100. Screen positions above come
from `blender_extract` screen boxes (box level, so slightly larger than the
objects).

Check frames for stages 4 and 5: 1, 45, 70, 84, 100 (frame 45 at stage 5 is
rendered with motion blur on, at the preview preset). Seed A/B window:
frames 92 to 103 (camera held, subject still).
