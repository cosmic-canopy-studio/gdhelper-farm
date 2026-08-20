"""CC5 Character Bake Pipeline — Blender Headless Script.

Imports a CC5 FBX via cc_blender_tools, bakes textures for Godot using
cc_blender_bake, and exports the result as GLB.

Usage:
    blender --background --python cc5_bake.py -- --input char.fbx --output char.glb
    blender --background --python cc5_bake.py -- --input char.fbx --output char.glb --resolution 2048

Arguments (after --):
    --input       Path to CC5 FBX file (required)
    --output      Path for output GLB file (required)
    --resolution  Bake texture resolution in pixels (default: 2048)
    --gpu         Enable GPU baking via OptiX/CUDA (default: true)

Requires Blender add-ons:
    - cc_blender_tools (v2.4.3+)
"""
import sys
import os
import time

import bpy


def parse_args():
    """Parse arguments after the -- separator."""
    argv = sys.argv
    if "--" in argv:
        args = argv[argv.index("--") + 1:]
    else:
        args = []

    config = {
        "input": None,
        "output": None,
        "resolution": 2048,
        "gpu": True,
    }

    i = 0
    while i < len(args):
        if args[i] == "--input" and i + 1 < len(args):
            config["input"] = args[i + 1]
            i += 2
        elif args[i] == "--output" and i + 1 < len(args):
            config["output"] = args[i + 1]
            i += 2
        elif args[i] == "--resolution" and i + 1 < len(args):
            config["resolution"] = int(args[i + 1])
            i += 2
        elif args[i] == "--no-gpu":
            config["gpu"] = False
            i += 1
        else:
            i += 1

    return config


def enable_gpu():
    """Enable GPU compute for Cycles baking (OptiX preferred, CUDA fallback)."""
    prefs = bpy.context.preferences
    cycles_prefs = prefs.addons.get("cycles")
    if not cycles_prefs:
        print("[WARN] Cycles addon not found, using CPU")
        return False

    cprefs = cycles_prefs.preferences

    # Try backends in priority order
    for backend in ("OPTIX", "CUDA", "HIP"):
        try:
            cprefs.compute_device_type = backend
            cprefs.get_devices()
            devices = cprefs.devices
            gpu_found = False
            for device in devices:
                if device.type != "CPU":
                    device.use = True
                    gpu_found = True
                    print(f"[OK] Enabled {backend} device: {device.name}")
                else:
                    device.use = False
            if gpu_found:
                return True
        except Exception:
            continue

    print("[WARN] No GPU backend available, falling back to CPU")
    return False


def setup_scene_for_bake(resolution):
    """Configure scene for Cycles baking."""
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "GPU"
    scene.cycles.samples = 64
    scene.cycles.use_denoising = False

    bake = scene.render.bake
    bake.margin = 16
    bake.margin_type = "EXTEND"
    bake.use_clear = True
    bake.target = "IMAGE_TEXTURES"


def import_cc5_fbx(filepath):
    """Import CC5 FBX using cc_blender_tools if available, else standard FBX import."""
    print(f"[INFO] Importing: {filepath}")

    # Try cc_blender_tools import (reconstructs CC materials properly)
    try:
        bpy.ops.cc3.importer(filepath=filepath, param="IMPORT_QUALITY")
        print("[OK] Imported via cc_blender_tools")
        return True
    except Exception as e:
        print(f"[WARN] cc_blender_tools import failed ({e}), trying standard FBX")

    # Fallback: standard FBX import
    bpy.ops.import_scene.fbx(filepath=filepath)
    print("[OK] Imported via standard FBX importer")
    return False


def run_bake_godot():
    """Run cc_blender_bake with Godot target if available."""
    try:
        # cc_blender_bake operator for Godot target
        bpy.ops.cc3.bake(target="GODOT")
        print("[OK] Baked via cc_blender_bake (Godot target)")
        return True
    except Exception as e:
        print(f"[WARN] cc_blender_bake not available ({e})")
        return False


def manual_bake_diffuse(resolution):
    """Fallback: manually bake diffuse textures if cc_blender_bake unavailable."""
    print("[INFO] Running manual diffuse bake (fallback)")

    mesh_objects = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    if not mesh_objects:
        print("[ERR] No mesh objects found")
        return False

    for obj in mesh_objects:
        bpy.context.view_layer.objects.active = obj
        obj.select_set(True)

        for slot in obj.material_slots:
            mat = slot.material
            if not mat or not mat.use_nodes:
                continue

            # Create bake target image
            img_name = f"{obj.name}_{mat.name}_bake"
            img = bpy.data.images.new(img_name, resolution, resolution)

            # Add image texture node and make active
            nodes = mat.node_tree.nodes
            bake_node = nodes.new("ShaderNodeTexImage")
            bake_node.image = img
            for n in nodes:
                n.select = False
            bake_node.select = True
            nodes.active = bake_node

        # Bake diffuse
        try:
            bpy.ops.object.bake(type="DIFFUSE", pass_filter={"COLOR"})
        except Exception as e:
            print(f"[WARN] Bake failed for {obj.name}: {e}")

        obj.select_set(False)

    return True


def export_glb(output_path):
    """Export scene as GLB."""
    print(f"[INFO] Exporting GLB: {output_path}")

    os.makedirs(os.path.dirname(output_path), exist_ok=True)

    bpy.ops.export_scene.gltf(
        filepath=output_path,
        export_format="GLB",
        export_texcoords=True,
        export_normals=True,
        export_materials="EXPORT",
        export_colors=True,
        export_animations=True,
        export_skins=True,
    )
    print(f"[OK] Exported: {output_path}")


def main():
    config = parse_args()

    if not config["input"]:
        print("[FATAL] --input is required")
        sys.exit(1)
    if not config["output"]:
        print("[FATAL] --output is required")
        sys.exit(1)
    if not os.path.exists(config["input"]):
        print(f"[FATAL] Input file not found: {config['input']}")
        sys.exit(1)

    print(f"\n{'='*60}")
    print(f"  CC5 Bake Pipeline")
    print(f"  Input:      {config['input']}")
    print(f"  Output:     {config['output']}")
    print(f"  Resolution: {config['resolution']}px")
    print(f"  GPU:        {config['gpu']}")
    print(f"{'='*60}\n")

    start = time.time()

    # Clean default scene
    bpy.ops.wm.read_factory_settings(use_empty=True)

    # Enable GPU
    if config["gpu"]:
        enable_gpu()

    # Setup scene
    setup_scene_for_bake(config["resolution"])

    # Import CC5 character
    cc_imported = import_cc5_fbx(config["input"])

    # Bake
    if cc_imported:
        baked = run_bake_godot()
    else:
        baked = False

    if not baked:
        manual_bake_diffuse(config["resolution"])

    # Export
    export_glb(config["output"])

    elapsed = time.time() - start
    print(f"\n[DONE] Completed in {elapsed:.1f}s")


if __name__ == "__main__":
    main()
