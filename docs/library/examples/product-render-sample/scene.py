"""Sample scene for the product-render pipeline: build, apply a preset, render.

Purpose: a primitive-only scene (open box, clear lid on a hinge pin, ball,
dark studio) that exercises every stage of
docs/library/procedures/product-render.md without any real product.
Inputs (after `--`): --preset PRESET.json --out ABS_DIR [--first N --last M |
--frames 1,45,70] [--device-type OPTIX|CUDA] [--device-id ID]
[--seed-mode fixed|animated] [--save ABS.blend] [--no-render].
Outputs: frame_####.png in --out (absolute, outside the repo), optional .blend.
Dependencies: Blender 5.2 LTS (bpy, mathutils), docs/library/tools/
blender_compat.py and camera_path.py (sibling tools folder).
Assumptions: run through blender_run with --factory-startup; metric units,
metres; the scene is rebuilt from nothing on every run so no .blend is kept
in git. Origin: new (primitive shapes only).
"""
import argparse
import json
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.path.abspath(os.path.join(HERE, "..", "..", "tools"))
if not os.path.isdir(TOOLS):  # adopted layout: tools/render next to the example
    TOOLS = os.path.abspath(os.path.join(HERE, "..", "..", "..", "tools", "render"))
sys.path.insert(0, TOOLS)

import bmesh  # noqa: E402
import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402

import blender_compat as bc  # noqa: E402
import camera_path  # noqa: E402

FPS = 24
FRAME_START, FRAME_END = 1, 120
LID_OPEN = (30, 60, -70.0)  # start frame, end frame, degrees about X


def parse(argv):
    argv = argv[argv.index("--") + 1:] if "--" in argv else []
    p = argparse.ArgumentParser(prog="scene.py")
    p.add_argument("--preset", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--first", type=int)
    p.add_argument("--last", type=int)
    p.add_argument("--frames")
    p.add_argument("--device-type", default="OPTIX")
    p.add_argument("--device-id")
    p.add_argument("--seed-mode", choices=["fixed", "animated"])
    p.add_argument("--save")
    p.add_argument("--no-render", action="store_true")
    a = p.parse_args(argv)
    if not os.path.isabs(a.out):
        raise SystemExit("scene.py: --out must be an absolute path")
    return a


def material(name, **kw):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    inputs = {
        "base": "Base Color", "rough": "Roughness", "metal": "Metallic",
        "trans": "Transmission Weight", "ior": "IOR", "aniso": "Anisotropic",
        "sheen": "Sheen Weight", "spec": "Specular IOR Level",
    }
    for key, value in kw.items():
        if key == "absorb":
            continue
        sock = bsdf.inputs.get(inputs[key])
        if sock is None:
            raise RuntimeError(f"Principled BSDF has no input {inputs[key]!r}")
        sock.default_value = (*value, 1.0) if key == "base" else value
    if "absorb" in kw:  # tint by volume absorption on a closed solid
        vol = m.node_tree.nodes.new("ShaderNodeVolumeAbsorption")
        vol.inputs["Color"].default_value = (*kw["absorb"][0], 1.0)
        vol.inputs["Density"].default_value = kw["absorb"][1]
        out = m.node_tree.nodes["Material Output"]
        m.node_tree.links.new(vol.outputs["Volume"], out.inputs["Volume"])
    return m


def bevel(obj, width, segments=2):
    mod = obj.modifiers.new("Bevel", "BEVEL")
    mod.width = width
    mod.segments = segments
    mod.limit_method = "ANGLE"


def box(name, size, loc):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = size
    bpy.ops.object.transform_apply(scale=True)
    return obj


def build():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0
    scene.render.fps = FPS
    scene.frame_start, scene.frame_end = FRAME_START, FRAME_END

    mats = {
        "black": material("MatteBlack", base=(0.02, 0.02, 0.022), rough=0.55, sheen=0.0, spec=0.4),
        "clear": material("ClearAcrylic", base=(1, 1, 1), rough=0.02, trans=1.0, ior=1.49,
                          absorb=((0.93, 0.98, 0.99), 3.0)),
        "edge": material("SatinCutEdge", base=(1, 1, 1), rough=0.35, trans=1.0, ior=1.49,
                         absorb=((0.93, 0.98, 0.99), 3.0)),
        "metal": material("BrushedPin", base=(0.8, 0.8, 0.82), rough=0.25, metal=1.0, aniso=0.6),
        "ball": material("Ball", base=(0.8, 0.25, 0.1), rough=0.35),
        "floor": material("Floor", base=(0.03, 0.03, 0.035), rough=0.4),
    }

    # Open box: a cube without its top face, given wall thickness.
    base = box("Base", (0.12, 0.08, 0.04), (0, 0, 0.02))
    bm = bmesh.new()
    bm.from_mesh(base.data)
    bm.normal_update()
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.normal.z > 0.9], context="FACES_ONLY")
    bm.to_mesh(base.data)
    bm.free()
    solid = base.modifiers.new("Walls", "SOLIDIFY")
    solid.thickness = 0.004
    solid.offset = -1.0
    bevel(base, 0.0008)
    base.data.materials.append(mats["black"])

    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.015, location=(0.0, -0.005, 0.004 + 0.015))
    ball = bpy.context.active_object
    ball.name = "Ball"
    # Deliberate cheat, recorded in RECORD.md: in the open lid the ball's internal reflection (the ray leaves
    # the acrylic as a transmission ray) read as a second ball (adversarial review of the preview). The ball
    # stays visible through the closed lid, then is hidden from transmission rays from frame 50, when the lid
    # is open and the ball is seen directly; frame 50 shows no reflection, so the switch is not visible.
    for frame, seen in ((49, True), (50, False)):
        ball.visible_transmission = ball.visible_glossy = seen
        ball.keyframe_insert("visible_transmission", frame=frame)
        ball.keyframe_insert("visible_glossy", frame=frame)
    bpy.ops.object.shade_smooth()
    ball.data.materials.append(mats["ball"])

    # Hinge: pin along X at the rear top edge; the lid pivots about it.
    pin_y, pin_z, pin_r = 0.042, 0.043, 0.002
    bpy.ops.mesh.primitive_cylinder_add(radius=pin_r, depth=0.03, location=(0, pin_y, pin_z),
                                        rotation=(0, math.radians(90), 0))
    pin = bpy.context.active_object
    pin.name = "HingePin"
    pin["label"] = "HINGE"
    bpy.ops.object.shade_smooth()
    pin.data.materials.append(mats["metal"])

    pivot = bpy.data.objects.new("LidPivot", None)
    scene.collection.objects.link(pivot)
    pivot.location = (0, pin_y, pin_z)

    lid = box("Lid", (0.12, 0.08, 0.004), (0, pin_y - pin_r - 0.04, pin_z))
    lid.data.materials.append(mats["clear"])
    lid.data.materials.append(mats["edge"])
    for poly in lid.data.polygons:  # cut edges get their own satin slot
        poly.material_index = 1 if abs(poly.normal.z) < 0.5 else 0
    bevel(lid, 0.0005)
    lid.parent = pivot
    lid.matrix_parent_inverse = pivot.matrix_world.inverted()

    start, end, angle = LID_OPEN
    for frame, value in ((start, 0.0), (end, math.radians(angle))):
        pivot.rotation_euler.x = value
        pivot.keyframe_insert("rotation_euler", index=0, frame=frame)

    bpy.ops.mesh.primitive_plane_add(size=3.0, location=(0, 0, 0))
    floor = bpy.context.active_object
    floor.name = "Floor"
    floor.data.materials.append(mats["floor"])

    world = bpy.data.worlds.new("World")
    scene.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.01, 0.01, 0.012, 1)

    def area(name, size, loc, energy, spread_deg, glossy=True, transmission=True, diffuse=True):
        data = bpy.data.lights.new(name, "AREA")
        data.shape = "RECTANGLE"
        data.size, data.size_y = size
        data.energy = energy
        data.spread = math.radians(spread_deg)  # grid / honeycomb emulation
        obj = bpy.data.objects.new(name, data)
        scene.collection.objects.link(obj)
        obj.location = loc
        obj.rotation_euler = (Vector((0, 0, 0.03)) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
        obj.visible_camera = False
        obj.visible_glossy = glossy
        obj.visible_transmission = transmission
        obj.visible_diffuse = diffuse
        return obj

    area("Key", (0.6, 0.3), (-0.6, -0.5, 0.7), 3.0, 60.0)
    area("Fill", (0.5, 0.5), (0.7, -0.3, 0.4), 0.8, 90.0)
    # Rim strip: never visible in glossy or transmission on clear parts.
    area("Rim", (1.0, 0.15), (0.0, 0.5, 0.6), 2.0, 45.0, glossy=False, transmission=False)
    # Reflection card: a soft panel at the camera's mirror angle, seen only in glossy reflections, so the
    # closed clear lid shows a reflection band (it lights nothing and never shows through the lid).
    area("ReflectionCard", (1.6, 0.12), (0.30, 0.75, 0.70), 3.0, 180.0, transmission=False, diffuse=False)

    cam_data = bpy.data.cameras.new("Camera")
    cam_data.lens = 90.0
    cam_data.sensor_width = 36.0
    cam_data.clip_start = 0.01
    # Focus follows the story: the ball in beats 1-2, the hinge pin from beat 3 on.
    focus = bpy.data.objects.new("FocusTarget", None)
    scene.collection.objects.link(focus)
    for frame, where in ((50, ball.location), (62, pin.location)):
        focus.location = where
        focus.keyframe_insert("location", frame=frame)
    cam_data.dof.use_dof = True
    cam_data.dof.focus_object = focus
    cam_data.dof.aperture_fstop = 5.6
    cam = bpy.data.objects.new("Camera", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    with open(os.path.join(HERE, "waypoints.json"), encoding="utf-8") as f:
        waypoints = json.load(f)
    for s in camera_path.sample_path(waypoints, FPS):
        cam.location = s["pos"]
        cam.rotation_euler = (Vector(s["target"]) - Vector(s["pos"])).to_track_quat("-Z", "Y").to_euler()
        cam_data.lens = s["lens"]
        cam.keyframe_insert("location", frame=s["frame"])
        cam.keyframe_insert("rotation_euler", frame=s["frame"])
        cam_data.keyframe_insert("lens", frame=s["frame"])
    return scene


def apply_preset(scene, preset, args):
    engine = preset.get("settings", {}).get("scene.engine", "CYCLES")
    scene.render.engine = engine
    scene.render.resolution_percentage = 100
    img = scene.render.image_settings
    if hasattr(img, "media_type"):
        img.media_type = "IMAGE"
    img.file_format, img.color_mode, img.color_depth = "PNG", "RGB", "8"
    for key, value in preset.get("settings", {}).items():
        if key == "scene.resolution":
            scene.render.resolution_x, scene.render.resolution_y = value
        elif key == "scene.engine":
            scene.render.engine = value
        elif key == "scene.view_transform":
            scene.view_settings.view_transform = value
        elif key == "scene.motion_blur":
            scene.render.use_motion_blur = value
        elif key.startswith("scene.cycles."):
            setattr(bc.cycles(scene), key.split(".", 2)[2], value)
        else:
            raise SystemExit(f"scene.py: preset key {key!r} is not supported")
    if engine == "CYCLES":
        if args.seed_mode:
            bc.cycles(scene).use_animated_seed = args.seed_mode == "animated"
        prefs = bpy.context.preferences.addons["cycles"].preferences
        prefs.compute_device_type = args.device_type
        enabled = bc.pin_gpu(prefs, args.device_type, args.device_id)
        bc.cycles(scene).device = "GPU"
        print("scene.py: GPU devices enabled:", enabled)
    elif engine == "BLENDER_WORKBENCH":
        scene.display.shading.light = "STUDIO"
        scene.display.shading.color_type = "MATERIAL"


def main():
    args = parse(sys.argv)
    with open(args.preset, encoding="utf-8") as f:
        preset = json.load(f)
    scene = build()
    apply_preset(scene, preset, args)
    if args.frames:
        frames = [int(x) for x in args.frames.split(",")]
    else:
        frames = list(range(args.first or FRAME_START, (args.last or FRAME_END) + 1))
    os.makedirs(args.out, exist_ok=True)
    if args.save:
        bpy.ops.wm.save_as_mainfile(filepath=args.save, copy=True)
    if args.no_render:
        return
    for frame in frames:
        scene.frame_set(frame)
        scene.render.filepath = os.path.join(args.out, f"frame_{frame:04d}.png")
        bpy.ops.render.render(write_still=True)
        print(f"scene.py: wrote frame {frame}")


main()
