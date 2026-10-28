#!/usr/bin/env python3
"""Blender Python API shims for 4.x to 5.x, by feature detection (no version tuples).

Purpose: Blender's Python API breaks between releases (slotted actions, the compositor node group, the
sequencer rename, the EEVEE engine id, the video output media type, dict-style property access). A scene
script that calls these shims instead of the raw API keeps working on both sides of each break. The break
table (BREAKS) lists every break found in the research report and names the shim, if any.
Inputs: Blender objects passed in by the caller (a scene, an action, an Animation Data block, a preferences
object). The functions use hasattr and duck typing only, so tests drive them with small fake classes that
mimic the old and the new API shape. `bpy` is never imported at module level.
Outputs: return values of the functions; `python blender_compat.py --list` prints the break table.
Exit codes: 0 for --help and --list (library module; argparse errors exit 2).
Dependencies: Python 3.10+ standard library; runs inside Blender for real use.
Assumptions: break facts come from docs/research/2026-10-29-blender-versions-api.md (sources S5 to S25 are
named per row). Rows marked unverified there stay unverified here; the real-API check of each shim is
run by the procedure with blender_run on the pinned Blender, not by CI.
Origin: generic port of the compat shim of a product film project, extended from the research break table.
"""

from __future__ import annotations

import argparse
import math
import sys

TOOL = "blender_compat"
SOURCE_DOC = "docs/research/2026-10-29-blender-versions-api.md"
VERIFY = "VERIFY 2026-10-29"

# (since, area, old, new, shim, source). "-" in shim means no shim: the script must use the new form.
_ROWS = [
    ("4.1", "mesh", "Mesh.use_auto_smooth, auto_smooth_angle", "removed; sharp edges by angle (set_sharp_from_angle)", "auto_smooth", "S9"),
    ("4.1", "mesh", "create/calc/free_normals_split()", "removed; Mesh.corner_normals, normals_split_custom_set", "-", "S9"),
    ("4.1", "python", "Python 3.10 (not stated)", "Python 3.11", "-", "S9"),
    ("4.2", "eevee", "engine id of legacy EEVEE (not stated)", "BLENDER_EEVEE_NEXT", "eevee_id", "S10"),
    ("4.2", "eevee", "scene.eevee.motion_blur_shutter/_position, scene.cycles.motion_blur_position", "scene.render.motion_blur_shutter/_position", "-", "S10"),
    ("4.2", "material", "Material.blend_method; light.cycles.cast_shadow", "Material.surface_render_method; light.use_shadow", "-", "S10"),
    ("4.2", "eevee", "scene.eevee.use_bloom, bloom_*", "deprecated", "-", "S10"),
    ("4.2", "light probe", "types CUBEMAP/PLANAR/GRID", "SPHERE/PLANE/VOLUME", "-", "S9"),
    ("4.2", "idprops", "loosely typed IDProperties", "statically typed; assignment converts or fails", "-", "S10"),
    ("4.2", "sequencer", "SequenceTransform.filter SUBSAMPLING_3x3", "BOX", "-", "S9"),
    ("4.2", "compositor", "Box/Ellipse Mask width/height", "mask_width/mask_height", "-", "S10"),
    ("4.4", "compositor", "use_new_cpu_compositor settings", "removed; new CPU compositor always used", "-", "S7"),
    ("4.4", "animation", "Action = flat F-curve list", "slotted actions: layers, strips, slots, channelbags", "action_fcurves", "S13 S7"),
    ("4.4", "animation", "anim_data.action = act animates the datablock", "assignment may leave no slot; set action_slot", "assign_action", "S7"),
    ("4.4", "animation", "action.fcurves, action.groups, action.id_root (deprecated)", "channelbag.fcurves/.groups, slot.target_id_type", "action_fcurves", "S7"),
    ("4.4", "sequencer", "Sequence, *Sequence types", "Strip, *Strip types", "-", "S7"),
    ("4.4", "sequencer", "SequenceEditor.sequences/.sequences_all, context.sequences", ".strips/.strips_all, context.strips", "vse_strips", "S7"),
    ("4.4", "sequencer", "text strip align_x/align_y", "anchor_x/anchor_y", "-", "S7"),
    ("4.5", "sequencer", "strips.new_effect(seq1=, seq2=)", "input1=, input2=", "-", "S11"),
    ("5.0", "animation", "action.fcurves, .groups, .id_root (removed)", "channelbag.fcurves/.groups, action_slot.target_id_type", "action_fcurves", "S6"),
    ("5.0", "animation", "fcurves.new(..., action_group=)", "channelbag.fcurves.new(..., group_name=), .ensure(...)", "ensure_fcurve", "S6"),
    ("5.0", "animation", "keyframe_insert INSERTKEY_XYZ_TO_RGB flag", "removed", "-", "S6"),
    ("5.0", "animation", "driver_add added an F-curve modifier", "creates two keyframes instead", "-", "S12"),
    ("5.0", "compositor", "scene.node_tree", "scene.compositing_node_group (node group, CompositorNodeTree)", "compositor_tree", "S6"),
    ("5.0", "nodes", "scene/material/world.use_nodes = True", "deprecated, always True, setting does nothing", "compositor_tree", "S6"),
    ("5.0", "compositor", "Composite node", "removed; Group Output", "-", "S12"),
    ("5.0", "compositor", "File Output: base_path, file_slots, layer_slots", "directory, file_name, file_output_items", "-", "S6 S12"),
    ("5.0", "compositor", "CompositorNodeGamma and similar; RGBA socket; Z Combine", "ShaderNodeGamma etc.; Color; Depth Combine", "-", "S6 S12"),
    ("5.0", "passes", "pass names DiffCol, IndexMA, Z", "Diffuse Color, Material Index, Depth", "-", "S6"),
    ("5.0", "eevee", "BLENDER_EEVEE_NEXT; scene.eevee.gtao_*", "BLENDER_EEVEE; view_layer.eevee.ambient_occlusion_distance", "eevee_id", "S6 S12"),
    ("5.0", "idprops", "scene['cycles'], obj['prop'] dict-style access to bpy.props storage", "attribute access (scene.cycles); property_unset", "cycles", "S6"),
    ("5.0", "render", "image_settings.file_format = 'FFMPEG' alone", "set media_type = 'VIDEO' first", "set_video_output", "S6"),
    ("5.0", "gpu", "BGL module, Image.bindcode", "removed", "-", "S6"),
    ("5.0", "math", "mathutils.Vector float64 buffer", "float32 buffer", "-", "S6"),
    ("5.0", "mesh", "UV selection per UV map, BMLoopUV.select", "removed; shared uv_select_vert/edge/face", "-", "S6"),
    ("5.0", "modeling", "boolean solver FAST", "FLOAT", "-", "S6"),
    ("5.0", "io", "USD export_textures, visible_objects_only; Scene.alembic_export", "removed (export_textures_mode)", "-", "S6"),
    ("5.0", "python", "bundled helper modules bl_*, rna_info", "made private", "-", "S6"),
    ("5.0", "logging", "log output format, background render progress text", "changed; log parsers may need updating", "-", "S6"),
    ("5.0", "sequencer", "context.scene as the sequencer scene", "context.sequencer_scene / workspace.sequencer_scene", "sequencer_scene", "S6"),
    ("5.0", "sequencer", "image/effect strips end_frame", "length", "-", "S6"),
    ("5.2.3", "sequencer", "render(scene=other) animated that scene's strips at its own frame", "still renders show strips frozen at frame 1 unless the scene is the window scene (seen on 5.2.3)", "activate_scene", "real-API run, not in the research table"),
    ("5.0", "cycles", "NVIDIA GPUs below sm_50 supported", "dropped", "-", "S12 S21"),
    ("5.1", "sequencer", "frame_final_duration/start/end, frame_offset_*, frame_duration, frame_start (deprecated)", "duration, left_handle, right_handle, content_* names", "-", "S8"),
    ("5.1", "python", "Python 3.11", "Python 3.13", "-", "S8 S20"),
    ("5.2", "geometry nodes", "modifier['Socket_2'] input access", "modifier.properties.inputs.<identifier>.value", "-", "S5"),
    ("5.2", "preferences", "active_asset_library index == asset_libraries index", "no longer matches", "-", "S5"),
    ("5.2", "idprops", "IDProperties nesting unlimited", "limit 1024 levels", "-", "S5"),
    ("5.2 branch", "cycles gpu", "CyclesPreferences.get_devices()", "refresh_devices() (get_devices marked deprecated)", "pin_gpu", "S17"),
]

BREAKS = [{"since": r[0], "area": r[1], "old": r[2], "new": r[3], "shim": r[4],
           "source": f"{r[5]} {VERIFY}"} for r in _ROWS]


def break_lines() -> list:
    return [f"{b['since']} | {b['area']} | old: {b['old']} | new: {b['new']} | shim: {b['shim']} | "
            f"{b['source']}" for b in BREAKS]


# ------------------------------------------------------------------------------------- animation
def _channelbags(action, strip, slot):
    if slot is not None:
        if hasattr(strip, "channelbag"):
            bag = strip.channelbag(slot)
            return [bag] if bag is not None else []
        return [b for b in getattr(strip, "channelbags", ()) if getattr(b, "slot", None) == slot]
    if hasattr(strip, "channelbags"):
        return list(strip.channelbags)
    if hasattr(strip, "channelbag"):
        bags = [strip.channelbag(s) for s in getattr(action, "slots", ())]
        return [b for b in bags if b is not None]
    return []


def action_fcurves(action, slot=None) -> list:
    """The F-curves of an action as a list: layered actions (4.4+) via layers/strips/channelbags, else the
    legacy flat `action.fcurves`. `slot` limits the result to one slot; None means every slot."""
    if action is None:
        return []
    layers = getattr(action, "layers", None)
    if layers is not None and len(layers) > 0:
        out = []
        for layer in layers:
            for strip in getattr(layer, "strips", ()):
                for bag in _channelbags(action, strip, slot):
                    out.extend(bag.fcurves)
        return out
    if hasattr(action, "fcurves"):
        return list(action.fcurves)
    return []


def ensure_fcurve(action, datablock, data_path, index=0):
    """Return the F-curve for data_path[index], creating it (and the slot or channelbag) when missing."""
    if hasattr(action, "fcurve_ensure_for_datablock"):
        return action.fcurve_ensure_for_datablock(datablock, data_path, index=index)
    found = action.fcurves.find(data_path, index=index)
    return found if found is not None else action.fcurves.new(data_path, index=index)


def assign_action(anim_data, action):
    """Set anim_data.action and, where slots exist, make sure a slot is assigned. Returns the slot or None."""
    anim_data.action = action
    if action is None or not hasattr(anim_data, "action_slot"):
        return None
    if getattr(anim_data, "action_slot", None) is not None:
        return anim_data.action_slot
    suitable = getattr(anim_data, "action_suitable_slots", None)
    slots = list(suitable) if suitable is not None else list(getattr(action, "slots", ()))
    if not slots:
        return None
    anim_data.action_slot = slots[0]
    return slots[0]


# --------------------------------------------------------------------------------- scene and nodes
def compositor_tree(scene, bpy=None):
    """The compositor node tree: `scene.compositing_node_group` (5.0+, created when None and `bpy` is
    given) else `scene.use_nodes = True; scene.node_tree`. May return None on 5.x when bpy is not given."""
    if hasattr(scene, "compositing_node_group"):
        tree = scene.compositing_node_group
        if tree is None and bpy is not None:
            tree = bpy.data.node_groups.new("Compositing", "CompositorNodeTree")
            scene.compositing_node_group = tree
        return tree
    scene.use_nodes = True
    return scene.node_tree


def vse_strips(scene):
    """The strip collection of the scene's sequence editor (created when missing): `.strips` else `.sequences`."""
    ed = scene.sequence_editor
    if ed is None:
        scene.sequence_editor_create()
        ed = scene.sequence_editor
    return ed.strips if hasattr(ed, "strips") else ed.sequences


def sequencer_scene(context, scene):
    """The scene that holds the sequencer: `context.sequencer_scene` (5.0+) when set, else `scene`."""
    return getattr(context, "sequencer_scene", None) or scene


def activate_scene(context, scene) -> bool:
    """Make `scene` the window scene. On 5.2.3 a still render (frame_set, then render write_still) of a scene
    that is not the window scene showed its sequencer frozen at the first frame; an animation render of the
    same scene was fine. Activate a new scene before any still render of its strips. Returns False when
    there is no window to switch (the caller must then reuse `context.scene`)."""
    win = getattr(context, "window", None)
    if win is None:
        wins = list(getattr(getattr(context, "window_manager", None), "windows", None) or ())
        win = wins[0] if wins else None
    if win is None:
        return False
    win.scene = scene
    return True


def eevee_id(engine_enum_items) -> str:
    """EEVEE's engine id: BLENDER_EEVEE when the enum offers it (4.1 and 5.0+), else BLENDER_EEVEE_NEXT.
    `engine_enum_items` holds identifiers or objects with .identifier (e.g. rna_type.properties['engine'].enum_items)."""
    ids = {getattr(i, "identifier", i) for i in engine_enum_items}
    if "BLENDER_EEVEE" in ids:
        return "BLENDER_EEVEE"
    if "BLENDER_EEVEE_NEXT" in ids:
        return "BLENDER_EEVEE_NEXT"
    raise RuntimeError(f"no EEVEE engine id among {sorted(ids)}")


def set_video_output(image_settings, ffmpeg, container="MPEG4", codec="H264", crf="HIGH", preset=None):
    """Configure H.264-style video output. media_type is set first where it exists (5.0+)."""
    if hasattr(image_settings, "media_type"):
        image_settings.media_type = "VIDEO"
    image_settings.file_format = "FFMPEG"
    ffmpeg.format = container
    ffmpeg.codec = codec
    ffmpeg.constant_rate_factor = crf
    if preset is not None:
        ffmpeg.ffmpeg_preset = preset


def cycles(scene):
    """Cycles scene settings by attribute (`scene['cycles']` dict access was removed in 5.0)."""
    if not hasattr(scene, "cycles"):
        raise AttributeError("scene has no 'cycles' attribute (is the Cycles add-on enabled?)")
    return scene.cycles


def auto_smooth(mesh, degrees):
    """Smooth shading with sharp edges above `degrees` (4.1+ set_sharp_from_angle, else use_auto_smooth)."""
    if hasattr(mesh, "shade_smooth"):
        mesh.shade_smooth()
    else:
        for p in mesh.polygons:
            p.use_smooth = True
    if hasattr(mesh, "set_sharp_from_angle"):
        mesh.set_sharp_from_angle(angle=math.radians(degrees))
    else:
        mesh.use_auto_smooth = True
        mesh.auto_smooth_angle = math.radians(degrees)


# ------------------------------------------------------------------------------------------- GPU
def pin_gpu(cycles_prefs, device_type, device_id=None) -> list:
    """Enable exactly one device class entry for Cycles and switch every other device (CPU included) off.
    Matches devices of `device_type` (CUDA, OPTIX, HIP, METAL, ONEAPI) whose `id` equals `device_id`, or the
    first such device when device_id is None. Returns the enabled ids; raises RuntimeError when the type is not
    offered or no device matched,
    so a render never silently falls back to the CPU."""
    try:
        cycles_prefs.compute_device_type = device_type
    except (TypeError, ValueError) as e:  # the enum only offers what this build supports (seen on 5.2.3)
        raise RuntimeError(f"compute device type {device_type!r} is not offered by this Blender build: {e}")
    if hasattr(cycles_prefs, "refresh_devices"):
        cycles_prefs.refresh_devices()
    elif hasattr(cycles_prefs, "get_devices"):
        cycles_prefs.get_devices()
    devices = list(cycles_prefs.devices)
    want = str(device_type).upper()
    target = None
    for d in devices:
        if str(d.type).upper() == want and (device_id is None or d.id == device_id):
            target = d
            break
    if target is None:
        seen = ", ".join(f"{d.type}:{d.id}" for d in devices) or "none"
        raise RuntimeError(f"no {device_type} device with id {device_id!r} (devices seen: {seen}); "
                           "refusing to render on the CPU")
    for d in devices:
        d.use = d is target
    return [target.id]


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(
        prog="blender_compat.py",
        description="Blender 4.x to 5.x API shims by feature detection. This is a library module that runs "
                    "inside Blender; run with --list (or read the table below) for the break table.",
        epilog=f"Break table from {SOURCE_DOC}:\n" + "\n".join(break_lines()),
        formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--list", action="store_true", help="print the break table, one break per line")
    args = ap.parse_args(argv)
    if args.list:
        print("\n".join(break_lines()))
        print(f"{TOOL}: PASS {len(BREAKS)} break(s) listed from {SOURCE_DOC}")
        return 0
    ap.print_usage(sys.stderr)
    print(f"{TOOL}: ERROR nothing to do: library module (try --list)", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
